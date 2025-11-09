#include "dnsmasq.h"
#ifdef HAVE_SQLITE

#ifdef HAVE_REGEX
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>
#endif

static sqlite3 *db = NULL;
static sqlite3_stmt *db_domain_exact = NULL;     /* For exact-only matching (hosts-style) */
static sqlite3_stmt *db_domain_wildcard = NULL;  /* For wildcard matching (*.domain) */
static sqlite3_stmt *db_domain_regex = NULL;     /* For regex pattern matching */
static char *db_file = NULL;

/* Termination addresses for blocked domains */
static struct in_addr db_block_ipv4;
static struct in6_addr db_block_ipv6;
static int db_has_ipv4 = 0;
static int db_has_ipv6 = 0;

#ifdef HAVE_REGEX
/* Regex pattern cache for performance (1-2 million patterns!)
 * Strategy: Load patterns on-demand, compile once, cache in memory
 * Using PCRE2 for better performance and modern API
 */
typedef struct regex_cache_entry {
  char *pattern;                /* Original regex pattern */
  pcre2_code *compiled;         /* Compiled PCRE2 regex */
  pcre2_match_data *match_data; /* Match data for PCRE2 */
  char *ipv4;                   /* IPv4 termination address */
  char *ipv6;                   /* IPv6 termination address */
  struct regex_cache_entry *next;
} regex_cache_entry;

static regex_cache_entry *regex_cache = NULL;
static int regex_cache_loaded = 0;
static int regex_patterns_count = 0;

/* Load all regex patterns from DB into cache (called once) */
static void load_regex_cache(void);
static void free_regex_cache(void);
#endif

void db_init(void)
{
  if (!db_file || db)
  {
    return;
  }

  atexit(db_cleanup);
  printf("Opening database %s\n", db_file);

  if (sqlite3_open(db_file, &db))
  {
    fprintf(stderr, "Can't open database: %s\n", sqlite3_errmsg(db));
    exit(1);
  }

  /* Prepare statement for exact-only matching (hosts-style)
   * Table: domain_exact (Domain, IPv4, IPv6)
   * Blocks ONLY the exact domain, NOT subdomains
   * Returns IPv4 and IPv6 termination addresses
   */
  sqlite3_prepare(
    db,
    "SELECT IPv4, IPv6 FROM domain_exact WHERE Domain = ?",
    -1,
    &db_domain_exact,
    NULL
  );
  /* Note: Ignore error if table doesn't exist - it's optional */

  /* Prepare statement for wildcard matching
   * Table: domain (Domain, IPv4, IPv6)
   * Blocks domain AND all subdomains
   * Returns IPv4 and IPv6 for the longest matching domain (most specific)
   */
  if (sqlite3_prepare(
    db,
    "SELECT IPv4, IPv6 FROM domain WHERE Domain = ? OR ? LIKE '%.' || Domain ORDER BY length(Domain) DESC LIMIT 1",
    -1,
    &db_domain_wildcard,
    NULL
  ))
  {
    fprintf(stderr, "Can't prepare wildcard statement: %s\n", sqlite3_errmsg(db));
    exit(1);
  }

#ifdef HAVE_REGEX
  /* Prepare statement for regex pattern matching
   * Table: domain_regex (Pattern, IPv4, IPv6)
   * Matches domain against regex patterns
   * Returns IPv4 and IPv6 for the matching pattern
   */
  sqlite3_prepare(
    db,
    "SELECT Pattern, IPv4, IPv6 FROM domain_regex",
    -1,
    &db_domain_regex,
    NULL
  );
  /* Note: Ignore error if table doesn't exist - it's optional */

  printf("SQLite blocker ready: exact + wildcard + regex (per-domain termination IPs)\n");
#else
  printf("SQLite blocker ready: exact-match + wildcard support (per-domain termination IPs)\n");
#endif
}

void db_cleanup(void)
{
  printf("cleaning up database...\n");

  if (db_domain_exact)
  {
    sqlite3_finalize(db_domain_exact);
    db_domain_exact = NULL;
  }

  if (db_domain_wildcard)
  {
    sqlite3_finalize(db_domain_wildcard);
    db_domain_wildcard = NULL;
  }

#ifdef HAVE_REGEX
  if (db_domain_regex)
  {
    sqlite3_finalize(db_domain_regex);
    db_domain_regex = NULL;
  }

  free_regex_cache();
#endif

  if (db)
  {
    sqlite3_close(db);
    db = NULL;
  }

  if (db_file)
  {
    free(db_file);
    db_file = NULL;
  }
}

void db_set_file(char *path)
{
  if (db_file) {
    free(db_file);
    db_file = NULL;
  }

  db_file = path;
}

/* Check if domain should be blocked and get termination IPs
 * Supports two modes:
 * 1. Exact-only (hosts-style): domain_exact table
 *    - Blocks ONLY the exact domain
 * 2. Wildcard: domain table
 *    - Blocks domain AND all subdomains (*.domain)
 *
 * Returns:
 *   1 if blocked (ipv4_out and ipv6_out are set to IPs from DB, or NULL if not in DB)
 *   0 if not blocked
 *
 * Caller must free ipv4_out and ipv6_out if not NULL
 */
int db_get_block_ips(const char *name, char **ipv4_out, char **ipv6_out)
{
  db_init();

  if (!db)
  {
    return 0;  /* No DB → don't block */
  }

  /* Initialize outputs */
  if (ipv4_out) *ipv4_out = NULL;
  if (ipv6_out) *ipv6_out = NULL;

  const unsigned char *ipv4_text = NULL;
  const unsigned char *ipv6_text = NULL;

  /* Check 1: Exact-only table (hosts-style matching)
   * Example: "paypal-evil.de" in domain_exact blocks ONLY "paypal-evil.de"
   */
  if (db_domain_exact)
  {
    sqlite3_reset(db_domain_exact);
    if (sqlite3_bind_text(db_domain_exact, 1, name, -1, SQLITE_TRANSIENT) == SQLITE_OK)
    {
      if (sqlite3_step(db_domain_exact) == SQLITE_ROW)
      {
        /* Domain found in exact table */
        ipv4_text = sqlite3_column_text(db_domain_exact, 0);  /* IPv4 */
        ipv6_text = sqlite3_column_text(db_domain_exact, 1);  /* IPv6 */

        if (ipv4_out && ipv4_text)
          *ipv4_out = strdup((const char *)ipv4_text);
        if (ipv6_out && ipv6_text)
          *ipv6_out = strdup((const char *)ipv6_text);

        printf("block (exact): %s → IPv4=%s IPv6=%s\n", name,
               ipv4_text ? (const char *)ipv4_text : "(fallback)",
               ipv6_text ? (const char *)ipv6_text : "(fallback)");
        return 1;
      }
    }
  }

  /* Check 2: Wildcard table (subdomain matching)
   * Example: "paypal-evil.de" in domain blocks "paypal-evil.de" AND "*.paypal-evil.de"
   */
  if (db_domain_wildcard)
  {
    sqlite3_reset(db_domain_wildcard);
    if (sqlite3_bind_text(db_domain_wildcard, 1, name, -1, SQLITE_TRANSIENT) == SQLITE_OK &&
        sqlite3_bind_text(db_domain_wildcard, 2, name, -1, SQLITE_TRANSIENT) == SQLITE_OK)
    {
      if (sqlite3_step(db_domain_wildcard) == SQLITE_ROW)
      {
        /* Domain found in wildcard table */
        ipv4_text = sqlite3_column_text(db_domain_wildcard, 0);  /* IPv4 */
        ipv6_text = sqlite3_column_text(db_domain_wildcard, 1);  /* IPv6 */

        if (ipv4_out && ipv4_text)
          *ipv4_out = strdup((const char *)ipv4_text);
        if (ipv6_out && ipv6_text)
          *ipv6_out = strdup((const char *)ipv6_text);

        printf("block (wildcard): %s → IPv4=%s IPv6=%s\n", name,
               ipv4_text ? (const char *)ipv4_text : "(fallback)",
               ipv6_text ? (const char *)ipv6_text : "(fallback)");
        return 1;
      }
    }
  }

#ifdef HAVE_REGEX
  /* Check 3: Regex patterns (slowest, check last!)
   * Load patterns on first call, then cache compiled regex in memory
   * For 1-2 million patterns, this is the performance bottleneck
   */
  if (db_domain_regex)
  {
    /* Load patterns into cache on first use */
    if (!regex_cache_loaded)
      load_regex_cache();

    /* Iterate through cached patterns and test domain */
    regex_cache_entry *entry = regex_cache;
    while (entry)
    {
      int rc = pcre2_match(
        entry->compiled,        /* Compiled pattern */
        (PCRE2_SPTR)name,       /* Subject string */
        strlen(name),           /* Subject length */
        0,                      /* Start offset */
        0,                      /* Options */
        entry->match_data,      /* Match data block */
        NULL                    /* Match context */
      );

      if (rc >= 0)  /* Match found! */
      {
        if (ipv4_out && entry->ipv4)
          *ipv4_out = strdup(entry->ipv4);
        if (ipv6_out && entry->ipv6)
          *ipv6_out = strdup(entry->ipv6);

        printf("block (regex): %s matched pattern '%s' → IPv4=%s IPv6=%s\n", name, entry->pattern,
               entry->ipv4 ? entry->ipv4 : "(fallback)",
               entry->ipv6 ? entry->ipv6 : "(fallback)");
        return 1;
      }

      entry = entry->next;
    }
  }
#endif

  return 0;  /* Not blocked */
}

/* Legacy function for backwards compatibility */
int db_check_block(const char *name)
{
  return db_get_block_ips(name, NULL, NULL);
}

/* Set IPv4 termination address for blocked domains */
void db_set_block_ipv4(struct in_addr *addr)
{
  if (addr)
    {
      db_block_ipv4 = *addr;
      db_has_ipv4 = 1;

      char ip_str[INET_ADDRSTRLEN];
      inet_ntop(AF_INET, addr, ip_str, sizeof(ip_str));
      printf("SQLite blocker: IPv4 termination set to %s\n", ip_str);
    }
}

/* Set IPv6 termination address for blocked domains */
void db_set_block_ipv6(struct in6_addr *addr)
{
  if (addr)
    {
      db_block_ipv6 = *addr;
      db_has_ipv6 = 1;

      char ip_str[INET6_ADDRSTRLEN];
      inet_ntop(AF_INET6, addr, ip_str, sizeof(ip_str));
      printf("SQLite blocker: IPv6 termination set to %s\n", ip_str);
    }
}

/* Get IPv4 termination address (returns NULL if not set) */
struct in_addr *db_get_block_ipv4(void)
{
  return db_has_ipv4 ? &db_block_ipv4 : NULL;
}

/* Get IPv6 termination address (returns NULL if not set) */
struct in6_addr *db_get_block_ipv6(void)
{
  return db_has_ipv6 ? &db_block_ipv6 : NULL;
}

#ifdef HAVE_REGEX
/* Load all regex patterns from database into cache
 * This is called on first regex query to avoid startup delay
 * For 1-2 million patterns, this will take some time and RAM!
 */
static void load_regex_cache(void)
{
  if (regex_cache_loaded || !db || !db_domain_regex)
    return;

  printf("Loading regex patterns from database...\n");
  int loaded = 0;
  int failed = 0;

  sqlite3_reset(db_domain_regex);

  while (sqlite3_step(db_domain_regex) == SQLITE_ROW)
  {
    const unsigned char *pattern_text = sqlite3_column_text(db_domain_regex, 0);
    const unsigned char *ipv4_text = sqlite3_column_text(db_domain_regex, 1);
    const unsigned char *ipv6_text = sqlite3_column_text(db_domain_regex, 2);

    if (!pattern_text)
      continue;

    /* Compile regex pattern with PCRE2 */
    int errorcode;
    PCRE2_SIZE erroroffset;
    pcre2_code *compiled = pcre2_compile(
      (PCRE2_SPTR)pattern_text,     /* Pattern */
      PCRE2_ZERO_TERMINATED,         /* Length (zero-terminated) */
      0,                             /* Options */
      &errorcode,                    /* Error code */
      &erroroffset,                  /* Error offset */
      NULL                           /* Compile context */
    );

    if (!compiled)
    {
      PCRE2_UCHAR error_buffer[256];
      pcre2_get_error_message(errorcode, error_buffer, sizeof(error_buffer));
      fprintf(stderr, "Regex compile error at offset %zu: %s (pattern: %s)\n",
              erroroffset, error_buffer, pattern_text);
      failed++;
      continue;
    }

    /* Create match data for this pattern */
    pcre2_match_data *match_data = pcre2_match_data_create_from_pattern(compiled, NULL);
    if (!match_data)
    {
      pcre2_code_free(compiled);
      fprintf(stderr, "Failed to create match data for pattern: %s\n", pattern_text);
      failed++;
      continue;
    }

    /* Add to cache */
    regex_cache_entry *entry = malloc(sizeof(regex_cache_entry));
    if (!entry)
    {
      pcre2_code_free(compiled);
      pcre2_match_data_free(match_data);
      fprintf(stderr, "Out of memory loading regex cache!\n");
      break;
    }

    entry->pattern = strdup((const char *)pattern_text);
    entry->compiled = compiled;
    entry->match_data = match_data;
    entry->ipv4 = ipv4_text ? strdup((const char *)ipv4_text) : NULL;
    entry->ipv6 = ipv6_text ? strdup((const char *)ipv6_text) : NULL;
    entry->next = regex_cache;
    regex_cache = entry;

    loaded++;
  }

  regex_cache_loaded = 1;
  regex_patterns_count = loaded;

  printf("Regex cache loaded: %d patterns compiled", loaded);
  if (failed > 0)
    printf(" (%d failed)", failed);
  printf("\n");

  if (loaded > 100000)
    printf("WARNING: %d regex patterns loaded - this may use significant RAM and CPU!\n", loaded);
}

/* Free all regex cache entries */
static void free_regex_cache(void)
{
  regex_cache_entry *entry = regex_cache;
  int freed = 0;

  while (entry)
  {
    regex_cache_entry *next = entry->next;

    if (entry->pattern)
      free(entry->pattern);
    if (entry->compiled)
      pcre2_code_free(entry->compiled);
    if (entry->match_data)
      pcre2_match_data_free(entry->match_data);
    if (entry->ipv4)
      free(entry->ipv4);
    if (entry->ipv6)
      free(entry->ipv6);
    free(entry);

    entry = next;
    freed++;
  }

  regex_cache = NULL;
  regex_cache_loaded = 0;
  regex_patterns_count = 0;

  if (freed > 0)
    printf("Freed %d regex patterns from cache\n", freed);
}
#endif

#endif
