/* DNSMASQ-SQLITE High-Performance Blocking
 * Version: 7.2 - Minimal (maximum performance, no overhead)
 *
 * Tables:
 *   block_wildcard - Base domain blocks all subdomains (info.com → *.info.com)
 *   block_hosts    - Exact hostname match only
 *   block_ips      - IP address rewriting (Source_IP → Target_IP)
 *                    Supports CIDR notation (192.168.0.0/16 → Target_IP)
 *
 * Performance Features:
 *   - CIDR rules loaded into RAM at startup
 *   - 2nd-level TLD aware (co.uk, com.au handled correctly)
 *   - IPv6 normalization (compressed ↔ expanded matching)
 *   - Aggressive SQLite settings for 128GB RAM
 */

#include "dnsmasq.h"

#ifdef HAVE_SQLITE
#include <sqlite3.h>
#include <ctype.h>
#include <string.h>
#include <stdlib.h>

/* ============================================================================
 * Configuration
 * ============================================================================ */

static sqlite3 *db = NULL;
static char *db_file = NULL;
static char *tld2_file = NULL;
static int db_init_attempted = 0;

/* Block responses */
static char *block_ipv4 = NULL;
static char *block_ipv6 = NULL;
static char *block_txt = NULL;
static char *block_mx = NULL;
static int block_mx_prio = 10;

/* Prepared statements */
static sqlite3_stmt *stmt_block_hosts = NULL;
static sqlite3_stmt *stmt_block_wildcard = NULL;
static sqlite3_stmt *stmt_block_ips = NULL;

/* ============================================================================
 * CIDR Rules in RAM (loaded at startup, no DB queries needed)
 * ============================================================================ */

typedef struct cidr_rule {
  struct in_addr net4;
  struct in6_addr net6;
  int prefix_len;
  int is_ipv6;
  char target[INET6_ADDRSTRLEN];
  struct cidr_rule *next;
} cidr_rule_t;

static cidr_rule_t *cidr_rules = NULL;
static int cidr_count = 0;

/* Parse CIDR notation */
static int parse_cidr(const char *cidr, struct in_addr *addr4, struct in6_addr *addr6, int *is_ipv6)
{
  char ip_part[INET6_ADDRSTRLEN];
  const char *slash = strchr(cidr, '/');
  int prefix_len;

  if (!slash) {
    if (strchr(cidr, ':')) {
      *is_ipv6 = 1;
      if (inet_pton(AF_INET6, cidr, addr6) != 1) return -1;
      return 128;
    } else {
      *is_ipv6 = 0;
      if (inet_pton(AF_INET, cidr, addr4) != 1) return -1;
      return 32;
    }
  }

  size_t ip_len = slash - cidr;
  if (ip_len >= sizeof(ip_part)) return -1;
  memcpy(ip_part, cidr, ip_len);
  ip_part[ip_len] = '\0';

  prefix_len = atoi(slash + 1);

  if (strchr(ip_part, ':')) {
    *is_ipv6 = 1;
    if (inet_pton(AF_INET6, ip_part, addr6) != 1) return -1;
    if (prefix_len < 0 || prefix_len > 128) return -1;
  } else {
    *is_ipv6 = 0;
    if (inet_pton(AF_INET, ip_part, addr4) != 1) return -1;
    if (prefix_len < 0 || prefix_len > 32) return -1;
  }

  return prefix_len;
}

/* Load all CIDR rules into RAM */
static void cidr_load(void)
{
  if (!db) return;

  sqlite3_stmt *stmt;
  if (sqlite3_prepare_v2(db,
      "SELECT Source_IP, Target_IP FROM block_ips WHERE Source_IP LIKE '%/%'",
      -1, &stmt, NULL) != SQLITE_OK) {
    return;
  }

  while (sqlite3_step(stmt) == SQLITE_ROW) {
    const char *cidr = (const char *)sqlite3_column_text(stmt, 0);
    const char *target = (const char *)sqlite3_column_text(stmt, 1);

    if (!cidr || !target) continue;

    cidr_rule_t *rule = malloc(sizeof(cidr_rule_t));
    if (!rule) continue;

    rule->prefix_len = parse_cidr(cidr, &rule->net4, &rule->net6, &rule->is_ipv6);
    if (rule->prefix_len < 0) {
      free(rule);
      continue;
    }

    strncpy(rule->target, target, sizeof(rule->target) - 1);
    rule->target[sizeof(rule->target) - 1] = '\0';

    rule->next = cidr_rules;
    cidr_rules = rule;
    cidr_count++;
  }

  sqlite3_finalize(stmt);
  if (cidr_count > 0)
    my_syslog(LOG_INFO, "SQLite: Loaded %d CIDR rules into RAM", cidr_count);
}

static void cidr_cleanup(void)
{
  cidr_rule_t *r = cidr_rules;
  while (r) {
    cidr_rule_t *next = r->next;
    free(r);
    r = next;
  }
  cidr_rules = NULL;
  cidr_count = 0;
}

/* Check if IPv4 matches CIDR */
static inline int ipv4_in_cidr(const struct in_addr *addr, const struct in_addr *network, int prefix_len)
{
  if (prefix_len == 0) return 1;
  if (prefix_len == 32) return addr->s_addr == network->s_addr;
  uint32_t mask = htonl(~((1U << (32 - prefix_len)) - 1));
  return (addr->s_addr & mask) == (network->s_addr & mask);
}

/* Check if IPv6 matches CIDR */
static inline int ipv6_in_cidr(const struct in6_addr *addr, const struct in6_addr *network, int prefix_len)
{
  int full_bytes = prefix_len / 8;
  int remaining_bits = prefix_len % 8;

  if (full_bytes > 0 && memcmp(addr->s6_addr, network->s6_addr, full_bytes) != 0)
    return 0;

  if (remaining_bits > 0) {
    unsigned char mask = (0xFF << (8 - remaining_bits)) & 0xFF;
    if ((addr->s6_addr[full_bytes] & mask) != (network->s6_addr[full_bytes] & mask))
      return 0;
  }

  return 1;
}

/* Find matching CIDR rule in RAM */
static const char *cidr_find_match(const struct in_addr *addr4, const struct in6_addr *addr6, int is_ipv6)
{
  for (cidr_rule_t *r = cidr_rules; r; r = r->next) {
    if (r->is_ipv6 != is_ipv6) continue;

    int match = is_ipv6 ?
      ipv6_in_cidr(addr6, &r->net6, r->prefix_len) :
      ipv4_in_cidr(addr4, &r->net4, r->prefix_len);

    if (match)
      return r->target;
  }
  return NULL;
}

/* ============================================================================
 * 2nd-Level TLD Hash Set
 * ============================================================================ */

#define TLD2_HASH_SIZE 16384

typedef struct tld2_entry {
  char *tld;
  struct tld2_entry *next;
} tld2_entry_t;

static tld2_entry_t *tld2_hash[TLD2_HASH_SIZE];
static int tld2_loaded = 0;

static unsigned int tld2_hash_func(const char *s)
{
  unsigned int hash = 5381;
  while (*s)
    hash = ((hash << 5) + hash) ^ (unsigned char)(*s++);
  return hash & (TLD2_HASH_SIZE - 1);
}

static int tld2_is_2nd_level(const char *tld)
{
  if (!tld2_loaded) return 0;
  unsigned int h = tld2_hash_func(tld);
  for (tld2_entry_t *e = tld2_hash[h]; e; e = e->next)
    if (strcmp(e->tld, tld) == 0) return 1;
  return 0;
}

static void tld2_add(const char *tld)
{
  unsigned int h = tld2_hash_func(tld);
  for (tld2_entry_t *e = tld2_hash[h]; e; e = e->next)
    if (strcmp(e->tld, tld) == 0) return;

  tld2_entry_t *e = malloc(sizeof(tld2_entry_t));
  if (!e) return;
  e->tld = strdup(tld);
  if (!e->tld) { free(e); return; }
  e->next = tld2_hash[h];
  tld2_hash[h] = e;
}

static void tld2_load(const char *path)
{
  FILE *f = fopen(path, "r");
  if (!f) {
    my_syslog(LOG_WARNING, "SQLite: Cannot open TLD2 list: %s", path);
    return;
  }

  char line[256];
  int count = 0;

  while (fgets(line, sizeof(line), f)) {
    char *p = line;
    while (*p && *p != '\n' && *p != '\r' && *p != ' ' && *p != '\t') p++;
    *p = '\0';
    if (line[0] == '\0' || line[0] == '#') continue;
    for (p = line; *p; p++) *p = tolower((unsigned char)*p);
    tld2_add(line);
    count++;
  }

  fclose(f);
  tld2_loaded = 1;
  my_syslog(LOG_INFO, "SQLite: Loaded %d 2nd-level TLDs", count);
}

static void tld2_cleanup(void)
{
  for (int i = 0; i < TLD2_HASH_SIZE; i++) {
    tld2_entry_t *e = tld2_hash[i];
    while (e) {
      tld2_entry_t *next = e->next;
      free(e->tld);
      free(e);
      e = next;
    }
    tld2_hash[i] = NULL;
  }
  tld2_loaded = 0;
}

/* ============================================================================
 * Domain Helpers
 * ============================================================================ */

static inline void str_tolower(char *s)
{
  for (; *s; s++) *s = tolower((unsigned char)*s);
}

static const char *get_base_domain(const char *name)
{
  const char *dots[4] = {NULL, NULL, NULL, NULL};
  int dot_count = 0;

  for (const char *p = name; *p; p++) {
    if (*p == '.') {
      dots[3] = dots[2]; dots[2] = dots[1]; dots[1] = dots[0]; dots[0] = p;
      dot_count++;
    }
  }

  if (dot_count <= 1) return name;

  if (dots[1]) {
    const char *last2 = dots[1] + 1;
    if (tld2_is_2nd_level(last2)) {
      if (dots[2]) return dots[2] + 1;
      return name;
    }
  }

  return dots[1] ? dots[1] + 1 : name;
}

/* ============================================================================
 * IPv6 Normalization
 * ============================================================================ */

static void ipv6_normalize(const char *input, char *output, size_t outlen)
{
  struct in6_addr addr;
  if (inet_pton(AF_INET6, input, &addr) != 1) {
    strncpy(output, input, outlen - 1);
    output[outlen - 1] = '\0';
    return;
  }
  snprintf(output, outlen,
           "%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x",
           addr.s6_addr[0], addr.s6_addr[1], addr.s6_addr[2], addr.s6_addr[3],
           addr.s6_addr[4], addr.s6_addr[5], addr.s6_addr[6], addr.s6_addr[7],
           addr.s6_addr[8], addr.s6_addr[9], addr.s6_addr[10], addr.s6_addr[11],
           addr.s6_addr[12], addr.s6_addr[13], addr.s6_addr[14], addr.s6_addr[15]);
}

/* ============================================================================
 * Database Functions
 * ============================================================================ */

void db_set_file(char *path)
{
  if (db_file) free(db_file);
  db_file = path ? strdup(path) : NULL;
}

void db_set_tld2_file(char *path)
{
  if (tld2_file) free(tld2_file);
  tld2_file = path ? strdup(path) : NULL;
}

void db_set_block_ipv4(char *ip)
{
  if (block_ipv4) free(block_ipv4);
  block_ipv4 = ip ? strdup(ip) : NULL;
}

void db_set_block_ipv6(char *ip)
{
  if (block_ipv6) free(block_ipv6);
  block_ipv6 = ip ? strdup(ip) : NULL;
}

void db_set_block_txt(char *txt)
{
  if (block_txt) free(block_txt);
  block_txt = txt ? strdup(txt) : NULL;
}

void db_set_block_mx(char *mx)
{
  if (!mx) { if (block_mx) free(block_mx); block_mx = NULL; return; }
  char *space = strchr(mx, ' ');
  if (space) {
    block_mx_prio = atoi(mx);
    if (block_mx) free(block_mx);
    block_mx = strdup(space + 1);
  } else {
    block_mx_prio = 10;
    if (block_mx) free(block_mx);
    block_mx = strdup(mx);
  }
}

char *db_get_block_txt(void) { return block_txt; }
char *db_get_block_mx(void) { return block_mx; }
int db_get_block_mx_prio(void) { return block_mx_prio; }

void db_init(void)
{
  if (db) return;
  if (db_init_attempted) return;
  db_init_attempted = 1;

  if (!db_file) {
    char *env = getenv("DNSMASQ_SQLITE_DB");
    if (env && *env) db_file = strdup(env);
    else return;
  }

  my_syslog(LOG_INFO, "SQLite: Opening %s", db_file);

  if (sqlite3_open_v2(db_file, &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
    my_syslog(LOG_ERR, "SQLite: Cannot open database: %s", sqlite3_errmsg(db));
    sqlite3_close(db);
    db = NULL;
    return;
  }

  /* Performance settings - aggressive for 128GB RAM */
  sqlite3_exec(db, "PRAGMA cache_size = -2097152", NULL, NULL, NULL);   /* 2GB cache */
  sqlite3_exec(db, "PRAGMA mmap_size = 17179869184", NULL, NULL, NULL); /* 16GB mmap */
  sqlite3_exec(db, "PRAGMA temp_store = MEMORY", NULL, NULL, NULL);
  sqlite3_exec(db, "PRAGMA query_only = ON", NULL, NULL, NULL);

  /* Prepare statements */
  sqlite3_prepare_v2(db, "SELECT 1 FROM block_hosts WHERE Domain = ? LIMIT 1",
                     -1, &stmt_block_hosts, NULL);
  sqlite3_prepare_v2(db, "SELECT 1 FROM block_wildcard WHERE Domain = ? LIMIT 1",
                     -1, &stmt_block_wildcard, NULL);
  sqlite3_prepare_v2(db, "SELECT Target_IP FROM block_ips WHERE Source_IP = ? LIMIT 1",
                     -1, &stmt_block_ips, NULL);

  /* Load 2nd-level TLDs */
  if (tld2_file) tld2_load(tld2_file);

  /* Load CIDR rules into RAM */
  cidr_load();

  /* Count entries */
  sqlite3_stmt *count_stmt;
  int hosts_count = 0, wildcard_count = 0, ips_count = 0;

  if (sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM block_hosts", -1, &count_stmt, NULL) == SQLITE_OK) {
    if (sqlite3_step(count_stmt) == SQLITE_ROW) hosts_count = sqlite3_column_int(count_stmt, 0);
    sqlite3_finalize(count_stmt);
  }
  if (sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM block_wildcard", -1, &count_stmt, NULL) == SQLITE_OK) {
    if (sqlite3_step(count_stmt) == SQLITE_ROW) wildcard_count = sqlite3_column_int(count_stmt, 0);
    sqlite3_finalize(count_stmt);
  }
  if (sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM block_ips", -1, &count_stmt, NULL) == SQLITE_OK) {
    if (sqlite3_step(count_stmt) == SQLITE_ROW) ips_count = sqlite3_column_int(count_stmt, 0);
    sqlite3_finalize(count_stmt);
  }

  my_syslog(LOG_INFO, "SQLite: Ready - hosts=%d, wildcard=%d, ips=%d, cidr=%d",
            hosts_count, wildcard_count, ips_count, cidr_count);
}

void db_cleanup(void)
{
  if (stmt_block_hosts) { sqlite3_finalize(stmt_block_hosts); stmt_block_hosts = NULL; }
  if (stmt_block_wildcard) { sqlite3_finalize(stmt_block_wildcard); stmt_block_wildcard = NULL; }
  if (stmt_block_ips) { sqlite3_finalize(stmt_block_ips); stmt_block_ips = NULL; }

  if (db) { sqlite3_close(db); db = NULL; }
  if (db_file) { free(db_file); db_file = NULL; }
  if (tld2_file) { free(tld2_file); tld2_file = NULL; }
  if (block_ipv4) { free(block_ipv4); block_ipv4 = NULL; }
  if (block_ipv6) { free(block_ipv6); block_ipv6 = NULL; }

  cidr_cleanup();
  tld2_cleanup();

  my_syslog(LOG_INFO, "SQLite: Cleanup complete");
}

/* ============================================================================
 * Blocking Functions
 * ============================================================================ */

int db_check_block(const char *name)
{
  if (!name || !*name) return 0;

  db_init();
  if (!db) return 0;

  /* Convert to lowercase */
  char name_lower[256];
  strncpy(name_lower, name, sizeof(name_lower) - 1);
  name_lower[sizeof(name_lower) - 1] = '\0';
  str_tolower(name_lower);

  /* Check 1: Exact match in block_hosts */
  if (stmt_block_hosts) {
    sqlite3_reset(stmt_block_hosts);
    sqlite3_bind_text(stmt_block_hosts, 1, name_lower, -1, SQLITE_STATIC);
    if (sqlite3_step(stmt_block_hosts) == SQLITE_ROW)
      return 1;
  }

  /* Check 2: Base domain in block_wildcard */
  if (stmt_block_wildcard) {
    const char *base = get_base_domain(name_lower);
    sqlite3_reset(stmt_block_wildcard);
    sqlite3_bind_text(stmt_block_wildcard, 1, base, -1, SQLITE_STATIC);
    if (sqlite3_step(stmt_block_wildcard) == SQLITE_ROW)
      return 2;
  }

  return 0;
}

int db_get_block_ips(const char *name, char **ipv4_out, char **ipv6_out)
{
  if (ipv4_out) *ipv4_out = NULL;
  if (ipv6_out) *ipv6_out = NULL;
  if (!db_check_block(name)) return 0;
  if (ipv4_out) *ipv4_out = block_ipv4;
  if (ipv6_out) *ipv6_out = block_ipv6;
  return 1;
}

/* ============================================================================
 * IP Rewriting Functions (with RAM-based CIDR matching)
 * ============================================================================ */

static char ip_rewrite_buffer[INET6_ADDRSTRLEN + 1];

static char *db_get_rewrite_ip_internal(const char *source_ip, int is_ipv6)
{
  if (!source_ip || !db) return NULL;

  /* For IPv6, try normalized form too */
  char normalized_ip[48];
  if (is_ipv6) ipv6_normalize(source_ip, normalized_ip, sizeof(normalized_ip));

  /* Try exact match first */
  if (stmt_block_ips) {
    sqlite3_reset(stmt_block_ips);
    sqlite3_bind_text(stmt_block_ips, 1, source_ip, -1, SQLITE_STATIC);
    if (sqlite3_step(stmt_block_ips) == SQLITE_ROW) {
      const char *target = (const char *)sqlite3_column_text(stmt_block_ips, 0);
      if (target) {
        strncpy(ip_rewrite_buffer, target, sizeof(ip_rewrite_buffer) - 1);
        ip_rewrite_buffer[sizeof(ip_rewrite_buffer) - 1] = '\0';
        return ip_rewrite_buffer;
      }
    }

    /* IPv6 normalized form */
    if (is_ipv6 && strcmp(source_ip, normalized_ip) != 0) {
      sqlite3_reset(stmt_block_ips);
      sqlite3_bind_text(stmt_block_ips, 1, normalized_ip, -1, SQLITE_STATIC);
      if (sqlite3_step(stmt_block_ips) == SQLITE_ROW) {
        const char *target = (const char *)sqlite3_column_text(stmt_block_ips, 0);
        if (target) {
          strncpy(ip_rewrite_buffer, target, sizeof(ip_rewrite_buffer) - 1);
          ip_rewrite_buffer[sizeof(ip_rewrite_buffer) - 1] = '\0';
          return ip_rewrite_buffer;
        }
      }
    }
  }

  /* CIDR matching from RAM */
  struct in_addr addr4;
  struct in6_addr addr6;

  if (is_ipv6) {
    if (inet_pton(AF_INET6, source_ip, &addr6) != 1) return NULL;
  } else {
    if (inet_pton(AF_INET, source_ip, &addr4) != 1) return NULL;
  }

  const char *target = cidr_find_match(&addr4, &addr6, is_ipv6);
  if (target) {
    strncpy(ip_rewrite_buffer, target, sizeof(ip_rewrite_buffer) - 1);
    ip_rewrite_buffer[sizeof(ip_rewrite_buffer) - 1] = '\0';
    return ip_rewrite_buffer;
  }

  return NULL;
}

char *db_get_rewrite_ip(const char *source_ip)
{
  if (!source_ip) return NULL;
  return db_get_rewrite_ip_internal(source_ip, strchr(source_ip, ':') != NULL);
}

int db_rewrite_ipv4(struct in_addr *addr)
{
  if (!addr || !db) return 0;
  char ip_str[INET_ADDRSTRLEN];
  if (!inet_ntop(AF_INET, addr, ip_str, sizeof(ip_str))) return 0;

  char *target = db_get_rewrite_ip_internal(ip_str, 0);
  if (target) {
    struct in_addr new_addr;
    if (inet_pton(AF_INET, target, &new_addr) == 1) {
      *addr = new_addr;
      return 1;
    }
  }
  return 0;
}

int db_rewrite_ipv6(struct in6_addr *addr)
{
  if (!addr || !db) return 0;
  char ip_str[INET6_ADDRSTRLEN];
  if (!inet_ntop(AF_INET6, addr, ip_str, sizeof(ip_str))) return 0;

  char *target = db_get_rewrite_ip_internal(ip_str, 1);
  if (target) {
    struct in6_addr new_addr;
    if (inet_pton(AF_INET6, target, &new_addr) == 1) {
      *addr = new_addr;
      return 1;
    }
  }
  return 0;
}

/* Legacy compatibility */
struct in_addr *db_get_block_ipv4(void)
{
  static struct in_addr addr;
  if (block_ipv4 && inet_pton(AF_INET, block_ipv4, &addr) == 1) return &addr;
  return NULL;
}

struct in6_addr *db_get_block_ipv6(void)
{
  static struct in6_addr addr;
  if (block_ipv6 && inet_pton(AF_INET6, block_ipv6, &addr) == 1) return &addr;
  return NULL;
}

#endif /* HAVE_SQLITE */
