/* DNSMASQ-SQLITE Simple Blocking
 * Version: 5.0 - Simplified
 *
 * Tables:
 *   block_wildcard - Base domain blocks all subdomains (info.com → *.info.com)
 *   block_hosts    - Exact hostname match only
 *   block_ips      - IP address rewriting (Source_IP → Target_IP)
 *
 * Features:
 *   - 2nd-level TLD aware (co.uk, com.au handled correctly)
 *   - Case-insensitive matching (lowercase conversion)
 *   - Pre-prepared statements (fast!)
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

/* Block responses (returned for blocked domains) */
static char *block_ipv4 = NULL;  /* e.g., "0.0.0.0" */
static char *block_ipv6 = NULL;  /* e.g., "::" */
static char *block_txt = NULL;   /* e.g., "Privacy Protection Active." */
static char *block_mx = NULL;    /* e.g., "mx-protect.keweon.center." (with priority) */
static int block_mx_prio = 10;   /* MX priority */

/* Prepared statements */
static sqlite3_stmt *stmt_block_hosts = NULL;     /* Exact match */
static sqlite3_stmt *stmt_block_wildcard = NULL;  /* Base domain match */
static sqlite3_stmt *stmt_block_ips = NULL;       /* IP rewrite */

/* ============================================================================
 * 2nd-Level TLD Hash Set (co.uk, com.au, org.uk, etc.)
 * ============================================================================ */

#define TLD2_HASH_SIZE 16384  /* Power of 2 for fast modulo */

typedef struct tld2_entry {
  char *tld;
  struct tld2_entry *next;
} tld2_entry_t;

static tld2_entry_t *tld2_hash[TLD2_HASH_SIZE];
static int tld2_loaded = 0;

/* Simple hash function for TLDs */
static unsigned int tld2_hash_func(const char *s)
{
  unsigned int hash = 5381;
  while (*s)
    hash = ((hash << 5) + hash) ^ (unsigned char)(*s++);
  return hash & (TLD2_HASH_SIZE - 1);
}

/* Check if TLD is in 2nd-level list */
static int tld2_is_2nd_level(const char *tld)
{
  if (!tld2_loaded)
    return 0;

  unsigned int h = tld2_hash_func(tld);
  tld2_entry_t *e = tld2_hash[h];

  while (e) {
    if (strcmp(e->tld, tld) == 0)
      return 1;
    e = e->next;
  }
  return 0;
}

/* Add TLD to hash set */
static void tld2_add(const char *tld)
{
  unsigned int h = tld2_hash_func(tld);

  /* Check if already exists */
  tld2_entry_t *e = tld2_hash[h];
  while (e) {
    if (strcmp(e->tld, tld) == 0)
      return;  /* Already exists */
    e = e->next;
  }

  /* Add new entry */
  e = malloc(sizeof(tld2_entry_t));
  if (!e) return;

  e->tld = strdup(tld);
  if (!e->tld) {
    free(e);
    return;
  }

  e->next = tld2_hash[h];
  tld2_hash[h] = e;
}

/* Load 2nd-level TLD list from file */
static void tld2_load(const char *path)
{
  FILE *f = fopen(path, "r");
  if (!f) {
    fprintf(stderr, "Warning: Cannot open TLD2 list: %s\n", path);
    return;
  }

  char line[256];
  int count = 0;

  while (fgets(line, sizeof(line), f)) {
    /* Remove newline and whitespace */
    char *p = line;
    while (*p && *p != '\n' && *p != '\r' && *p != ' ' && *p != '\t')
      p++;
    *p = '\0';

    /* Skip empty lines and comments */
    if (line[0] == '\0' || line[0] == '#')
      continue;

    /* Convert to lowercase */
    for (p = line; *p; p++)
      *p = tolower((unsigned char)*p);

    tld2_add(line);
    count++;
  }

  fclose(f);
  tld2_loaded = 1;
  printf("SQLite: Loaded %d 2nd-level TLDs from %s\n", count, path);
}

/* Cleanup TLD hash set */
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

/* Convert string to lowercase in-place */
static void str_tolower(char *s)
{
  for (; *s; s++)
    *s = tolower((unsigned char)*s);
}

/* Get base domain using 2nd-level TLD awareness
 *
 * Examples:
 *   tracker.example.com    → example.com     (2 parts, .com is not 2nd-level)
 *   tracker.example.co.uk  → example.co.uk   (3 parts, co.uk IS 2nd-level)
 *   sub.domain.com.au      → domain.com.au   (3 parts, com.au IS 2nd-level)
 *
 * Returns pointer into the input string (no allocation)
 */
static const char *get_base_domain(const char *name)
{
  const char *dots[4] = {NULL, NULL, NULL, NULL};  /* Last 4 dot positions */
  int dot_count = 0;

  /* Find all dots, keep track of last 4 */
  for (const char *p = name; *p; p++) {
    if (*p == '.') {
      dots[3] = dots[2];
      dots[2] = dots[1];
      dots[1] = dots[0];
      dots[0] = p;
      dot_count++;
    }
  }

  if (dot_count == 0)
    return name;  /* No dots, return as-is */

  if (dot_count == 1)
    return name;  /* Only one dot (e.g., "example.com"), return as-is */

  /* Extract last 2 parts to check if it's a 2nd-level TLD */
  const char *last2 = dots[0] + 1;  /* After last dot - but this is wrong */

  /* Actually need: for "sub.example.co.uk"
   * dots[0] = pointer to ".uk"
   * dots[1] = pointer to ".co"
   * dots[2] = pointer to ".example"
   * dots[3] = pointer to ".sub" (or NULL if not enough dots)
   *
   * last 2 parts = "co.uk" = dots[1] + 1
   * last 3 parts = "example.co.uk" = dots[2] + 1
   */

  if (dots[1]) {
    last2 = dots[1] + 1;  /* "co.uk" */

    if (tld2_is_2nd_level(last2)) {
      /* It's a 2nd-level TLD, return last 3 parts */
      if (dots[2])
        return dots[2] + 1;  /* "example.co.uk" */
      else
        return name;  /* Not enough parts, return whole name */
    }
  }

  /* Not a 2nd-level TLD, return last 2 parts */
  if (dots[1])
    return dots[1] + 1;

  return name;
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
  if (!mx) {
    if (block_mx) free(block_mx);
    block_mx = NULL;
    return;
  }

  /* Parse "priority hostname" format, e.g., "10 mx.example.com." */
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
  if (db)
    return;  /* Already initialized */

  if (!db_file) {
    char *env = getenv("DNSMASQ_SQLITE_DB");
    if (env && *env)
      db_file = strdup(env);
    else
      return;  /* No database configured */
  }

  printf("SQLite: Opening %s\n", db_file);

  if (sqlite3_open_v2(db_file, &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
    fprintf(stderr, "SQLite: Cannot open database: %s\n", sqlite3_errmsg(db));
    sqlite3_close(db);
    db = NULL;
    return;
  }

  /* Performance settings for read-only operation */
  sqlite3_exec(db, "PRAGMA cache_size = -1048576", NULL, NULL, NULL);  /* 1GB cache */
  sqlite3_exec(db, "PRAGMA mmap_size = 8589934592", NULL, NULL, NULL); /* 8GB mmap */
  sqlite3_exec(db, "PRAGMA temp_store = MEMORY", NULL, NULL, NULL);
  sqlite3_exec(db, "PRAGMA query_only = ON", NULL, NULL, NULL);

  /* Prepare statements */
  if (sqlite3_prepare_v2(db,
      "SELECT 1 FROM block_hosts WHERE Domain = ? LIMIT 1",
      -1, &stmt_block_hosts, NULL) != SQLITE_OK) {
    fprintf(stderr, "SQLite: block_hosts table not found (optional)\n");
  }

  if (sqlite3_prepare_v2(db,
      "SELECT 1 FROM block_wildcard WHERE Domain = ? LIMIT 1",
      -1, &stmt_block_wildcard, NULL) != SQLITE_OK) {
    fprintf(stderr, "SQLite: block_wildcard table not found (optional)\n");
  }

  if (sqlite3_prepare_v2(db,
      "SELECT Target_IP FROM block_ips WHERE Source_IP = ? LIMIT 1",
      -1, &stmt_block_ips, NULL) != SQLITE_OK) {
    fprintf(stderr, "SQLite: block_ips table not found (optional)\n");
  }

  /* Load 2nd-level TLD list */
  if (tld2_file)
    tld2_load(tld2_file);

  /* Count entries for info */
  sqlite3_stmt *count_stmt;
  int hosts_count = 0, wildcard_count = 0;

  if (sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM block_hosts", -1, &count_stmt, NULL) == SQLITE_OK) {
    if (sqlite3_step(count_stmt) == SQLITE_ROW)
      hosts_count = sqlite3_column_int(count_stmt, 0);
    sqlite3_finalize(count_stmt);
  }

  if (sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM block_wildcard", -1, &count_stmt, NULL) == SQLITE_OK) {
    if (sqlite3_step(count_stmt) == SQLITE_ROW)
      wildcard_count = sqlite3_column_int(count_stmt, 0);
    sqlite3_finalize(count_stmt);
  }

  printf("SQLite: Ready - block_hosts=%d, block_wildcard=%d\n", hosts_count, wildcard_count);
  printf("SQLite: Block IPs - IPv4=%s, IPv6=%s\n",
         block_ipv4 ? block_ipv4 : "(none)",
         block_ipv6 ? block_ipv6 : "(none)");
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

  tld2_cleanup();

  printf("SQLite: Cleanup complete\n");
}

/* ============================================================================
 * Blocking Functions
 * ============================================================================ */

/* Check if domain should be blocked
 * Returns: 1 if blocked, 0 if not
 */
int db_check_block(const char *name)
{
  if (!name || !*name)
    return 0;

  /* Lazy init after fork */
  db_init();

  if (!db)
    return 0;

  /* Convert to lowercase for case-insensitive matching */
  char name_lower[256];
  strncpy(name_lower, name, sizeof(name_lower) - 1);
  name_lower[sizeof(name_lower) - 1] = '\0';
  str_tolower(name_lower);

  /* Check 1: Exact match in block_hosts */
  if (stmt_block_hosts) {
    sqlite3_reset(stmt_block_hosts);
    sqlite3_bind_text(stmt_block_hosts, 1, name_lower, -1, SQLITE_STATIC);
    if (sqlite3_step(stmt_block_hosts) == SQLITE_ROW) {
      printf("SQLite: BLOCK exact %s\n", name_lower);
      return 1;
    }
  }

  /* Check 2: Base domain in block_wildcard */
  if (stmt_block_wildcard) {
    const char *base = get_base_domain(name_lower);

    sqlite3_reset(stmt_block_wildcard);
    sqlite3_bind_text(stmt_block_wildcard, 1, base, -1, SQLITE_STATIC);
    if (sqlite3_step(stmt_block_wildcard) == SQLITE_ROW) {
      printf("SQLite: BLOCK wildcard %s (base: %s)\n", name_lower, base);
      return 1;
    }
  }

  return 0;  /* Not blocked */
}

/* Get block IPs if domain is blocked
 * Returns: 1 if blocked (ipv4_out/ipv6_out set), 0 if not
 * Note: Returned pointers are to static strings, do NOT free!
 */
int db_get_block_ips(const char *name, char **ipv4_out, char **ipv6_out)
{
  if (ipv4_out) *ipv4_out = NULL;
  if (ipv6_out) *ipv6_out = NULL;

  if (!db_check_block(name))
    return 0;

  if (ipv4_out) *ipv4_out = block_ipv4;
  if (ipv6_out) *ipv6_out = block_ipv6;

  return 1;
}

/* Rewrite IP address if in block_ips table
 * Returns: Target IP (static buffer, do NOT free) or NULL
 */
static char ip_rewrite_buffer[64];

char *db_get_rewrite_ip(const char *source_ip)
{
  if (!source_ip || !db || !stmt_block_ips)
    return NULL;

  sqlite3_reset(stmt_block_ips);
  sqlite3_bind_text(stmt_block_ips, 1, source_ip, -1, SQLITE_STATIC);

  if (sqlite3_step(stmt_block_ips) == SQLITE_ROW) {
    const char *target = (const char *)sqlite3_column_text(stmt_block_ips, 0);
    if (target) {
      strncpy(ip_rewrite_buffer, target, sizeof(ip_rewrite_buffer) - 1);
      ip_rewrite_buffer[sizeof(ip_rewrite_buffer) - 1] = '\0';
      printf("SQLite: REWRITE IP %s → %s\n", source_ip, ip_rewrite_buffer);
      return ip_rewrite_buffer;
    }
  }

  return NULL;
}

/* Rewrite IPv4 address if rule exists
 * Returns: 1 if rewritten (addr modified), 0 if no rule
 */
int db_rewrite_ipv4(struct in_addr *addr)
{
  if (!addr || !db || !stmt_block_ips)
    return 0;

  char ip_str[INET_ADDRSTRLEN];
  if (!inet_ntop(AF_INET, addr, ip_str, sizeof(ip_str)))
    return 0;

  char *target = db_get_rewrite_ip(ip_str);
  if (target) {
    struct in_addr new_addr;
    if (inet_pton(AF_INET, target, &new_addr) == 1) {
      *addr = new_addr;
      return 1;
    }
  }
  return 0;
}

/* Rewrite IPv6 address if rule exists
 * Returns: 1 if rewritten (addr modified), 0 if no rule
 */
int db_rewrite_ipv6(struct in6_addr *addr)
{
  if (!addr || !db || !stmt_block_ips)
    return 0;

  char ip_str[INET6_ADDRSTRLEN];
  if (!inet_ntop(AF_INET6, addr, ip_str, sizeof(ip_str)))
    return 0;

  char *target = db_get_rewrite_ip(ip_str);
  if (target) {
    struct in6_addr new_addr;
    if (inet_pton(AF_INET6, target, &new_addr) == 1) {
      *addr = new_addr;
      return 1;
    }
  }
  return 0;
}

/* Legacy compatibility functions */
struct in_addr *db_get_block_ipv4(void)
{
  static struct in_addr addr;
  if (block_ipv4 && inet_pton(AF_INET, block_ipv4, &addr) == 1)
    return &addr;
  return NULL;
}

struct in6_addr *db_get_block_ipv6(void)
{
  static struct in6_addr addr;
  if (block_ipv6 && inet_pton(AF_INET6, block_ipv6, &addr) == 1)
    return &addr;
  return NULL;
}

#endif /* HAVE_SQLITE */
