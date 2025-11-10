#include "dnsmasq.h"
#ifdef HAVE_SQLITE

#ifdef HAVE_REGEX
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>
#endif

static sqlite3 *db = NULL;
static sqlite3_stmt *db_block_regex = NULL;      /* For regex pattern matching → IPSetTerminate */
static sqlite3_stmt *db_block_exact = NULL;      /* For exact matching → IPSetTerminate */
static sqlite3_stmt *db_block_wildcard = NULL;   /* For wildcard matching → IPSetDNSBlock */
static sqlite3_stmt *db_fqdn_dns_allow = NULL;   /* For DNS allow (whitelist) → IPSetDNSAllow */
static sqlite3_stmt *db_fqdn_dns_block = NULL;   /* For DNS block (blacklist) → IPSetDNSBlock */
static char *db_file = NULL;

/* IPSet configurations (comma-separated strings from config) */
static char *ipset_terminate_v4 = NULL;  /* IPv4 termination IPs (no port): "127.0.0.1,0.0.0.0" */
static char *ipset_terminate_v6 = NULL;  /* IPv6 termination IPs (no port): "::1,::" */
static char *ipset_dns_block = NULL;     /* DNS blocker servers (with port): "127.0.0.1#5353,[fd00::1]:5353" */
static char *ipset_dns_allow = NULL;     /* Real DNS servers (with port): "8.8.8.8,1.1.1.1#5353" */

#ifdef HAVE_REGEX
/* Regex pattern cache for performance (1-2 million patterns!)
 * Strategy: Load patterns on-demand, compile once, cache in memory
 * Using PCRE2 for better performance and modern API
 */
typedef struct regex_cache_entry {
  char *pattern;                /* Original regex pattern */
  pcre2_code *compiled;         /* Compiled PCRE2 regex */
  pcre2_match_data *match_data; /* Match data for PCRE2 */
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

  /* ========================================================================
   * PERFORMANCE OPTIMIZATION: Enterprise settings for 128 GB RAM server
   * Optimized for: 8 Core Intel + 128 GB RAM + NVMe SSD
   * Target: 1 Billion domains (~50 GB DB) with <2ms lookups
   * ======================================================================== */

  /* Memory-mapped I/O: 2 GB (SQLite maximum limit)
   * Benefit: OS manages pages, no read() syscalls = 30-50% faster reads
   * Note: 2 GB is SQLite's hardcoded max, even with more system RAM */
  sqlite3_exec(db, "PRAGMA mmap_size = 2147483648", NULL, NULL, NULL);

  /* Cache Size: 20,000,000 pages (~80 GB with 4KB pages)
   * Optimized for: 128 GB RAM server with 1 Billion domains
   * Benefit: Entire DB + indexes fit in RAM = 0.2-2 ms lookups!
   * Calculation: -20000000 = 20M pages * 4KB = 80 GB cache */
  sqlite3_exec(db, "PRAGMA cache_size = -20000000", NULL, NULL, NULL);

  /* Temp Store: MEMORY
   * Benefit: Temp tables in RAM instead of disk (for sorting/aggregation) */
  sqlite3_exec(db, "PRAGMA temp_store = MEMORY", NULL, NULL, NULL);

  /* Journal Mode: WAL (if not already set)
   * Benefit: Parallel reads while writing, no lock contention */
  sqlite3_exec(db, "PRAGMA journal_mode = WAL", NULL, NULL, NULL);

  /* Synchronous: NORMAL (safe with WAL mode)
   * Benefit: 50x faster than FULL, still crash-safe with WAL */
  sqlite3_exec(db, "PRAGMA synchronous = NORMAL", NULL, NULL, NULL);

  /* Threads: 8 (utilize all CPU cores)
   * Benefit: Parallel query execution on multi-core systems
   * Note: Requires SQLite 3.37+ compiled with SQLITE_MAX_WORKER_THREADS */
  sqlite3_exec(db, "PRAGMA threads = 8", NULL, NULL, NULL);

  /* Query Optimizer Hints (SQLite 3.46+)
   * Benefit: Better query plans for our specific access patterns */
  sqlite3_exec(db, "PRAGMA optimize", NULL, NULL, NULL);

  printf("SQLite ENTERPRISE optimizations enabled (128 GB RAM: mmap=2GB, cache=80GB, threads=8)\n");

  /* ========================================================================
   * NEW LOOKUP ORDER (Schema v4.0):
   * 1. block_regex      → IPSetTerminate (IPv4 + IPv6 direct response)
   * 2. block_exact      → IPSetTerminate (IPv4 + IPv6 direct response)
   * 3. block_wildcard   → IPSetDNSBlock (DNS Forward to blocker)
   * 4. fqdn_dns_allow   → IPSetDNSAllow (DNS Forward to real DNS)
   * 5. fqdn_dns_block   → IPSetDNSBlock (DNS Forward to blocker)
   *
   * Note: Tables now contain ONLY domains/patterns (no IPv4/IPv6 columns!)
   *       IP addresses are stored in IPSets (config file), not database.
   * ======================================================================== */

#ifdef HAVE_REGEX
  /* Step 1: block_regex (Pattern) → IPSetTerminate
   * PCRE2 pattern matching for complex blocking rules
   * Example: ^ad[sz]?[0-9]*\..*$ matches ads.example.com
   * Returns: Pattern (IPs come from IPSetTerminate config)
   */
  sqlite3_prepare(
    db,
    "SELECT Pattern FROM block_regex",
    -1,
    &db_block_regex,
    NULL
  );
#endif

  /* Step 2: block_exact (Domain) → IPSetTerminate
   * Exact domain match ONLY (no subdomains!)
   * Example: ads.example.com blocks ads.example.com (NOT www.ads.example.com)
   * Returns: Domain found (IPs come from IPSetTerminate config)
   */
  sqlite3_prepare(
    db,
    "SELECT Domain FROM block_exact WHERE Domain = ?",
    -1,
    &db_block_exact,
    NULL
  );

  /* Step 3: block_wildcard (Domain) → IPSetDNSBlock
   * Wildcard domain match (includes subdomains!)
   * Example: privacy.com blocks privacy.com AND *.privacy.com
   * Returns: Domain found (forward to IPSetDNSBlock servers)
   */
  if (sqlite3_prepare(
    db,
    "SELECT Domain FROM block_wildcard WHERE Domain = ? OR ? LIKE '%.' || Domain ORDER BY length(Domain) DESC LIMIT 1",
    -1,
    &db_block_wildcard,
    NULL
  ))
  {
    fprintf(stderr, "Can't prepare block_wildcard statement: %s\n", sqlite3_errmsg(db));
    exit(1);
  }

  /* Step 4: fqdn_dns_allow (Domain) → IPSetDNSAllow
   * DNS Allow (Whitelist) - Forward to real DNS servers
   * Example: trusted.xyz → forward to 8.8.8.8 (normal resolution)
   * Priority: Checked BEFORE fqdn_dns_block (whitelist overrides blacklist)
   */
  sqlite3_prepare(
    db,
    "SELECT Domain FROM fqdn_dns_allow WHERE Domain = ? OR ? LIKE '%.' || Domain ORDER BY length(Domain) DESC LIMIT 1",
    -1,
    &db_fqdn_dns_allow,
    NULL
  );

  /* Step 5: fqdn_dns_block (Domain) → IPSetDNSBlock
   * DNS Block (Blacklist) - Forward to blocker DNS servers
   * Example: *.xyz → forward to 127.0.0.1#5353 (blocker returns 0.0.0.0)
   * Priority: Checked AFTER fqdn_dns_allow (step 5 after step 4)
   */
  sqlite3_prepare(
    db,
    "SELECT Domain FROM fqdn_dns_block WHERE Domain = ? OR ? LIKE '%.' || Domain ORDER BY length(Domain) DESC LIMIT 1",
    -1,
    &db_fqdn_dns_block,
    NULL
  );
  /* Note: Ignore error if table doesn't exist - it's optional */

  printf("SQLite ready: DNS forwarding + blocker (exact/wildcard/regex + per-domain IPs)\n");
#else
  printf("SQLite ready: DNS forwarding + blocker (exact/wildcard + per-domain IPs)\n");
#endif
}

void db_cleanup(void)
{
  printf("cleaning up database...\n");

#ifdef HAVE_REGEX
  if (db_block_regex)
  {
    sqlite3_finalize(db_block_regex);
    db_block_regex = NULL;
  }
  free_regex_cache();
#endif

  if (db_block_exact)
  {
    sqlite3_finalize(db_block_exact);
    db_block_exact = NULL;
  }

  if (db_block_wildcard)
  {
    sqlite3_finalize(db_block_wildcard);
    db_block_wildcard = NULL;
  }

  if (db_fqdn_dns_allow)
  {
    sqlite3_finalize(db_fqdn_dns_allow);
    db_fqdn_dns_allow = NULL;
  }

  if (db_fqdn_dns_block)
  {
    sqlite3_finalize(db_fqdn_dns_block);
    db_fqdn_dns_block = NULL;
  }

  if (db)
  {
    /* Run PRAGMA optimize before closing (SQLite 3.46+ recommended)
     * This updates query statistics for better future query plans */
    sqlite3_exec(db, "PRAGMA optimize", NULL, NULL, NULL);

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

/* Check if domain should be forwarded to specific DNS server
 * Lookup order (whitelist before blacklist):
 * 1. domain_dns_allow (whitelist): Forward to real DNS (bypasses blocker)
 * 2. domain_dns_block (blacklist): Forward to blocker DNS
 *
 * Returns:
 *   DNS server string (e.g., "8.8.8.8" or "10.0.0.1#5353") if forwarding needed
 *   NULL if no forwarding (continue with normal processing)
 *
 * Caller must free returned string
 */
char *db_get_forward_server(const char *name)
{
  db_init();

  if (!db)
  {
    return NULL;  /* No DB → no forwarding */
  }

  const unsigned char *server_text = NULL;

  /* Check 1: DNS Allow (whitelist) - Forward to real DNS
   * Example: "trusted-ads.com" in domain_dns_allow → forward to 8.8.8.8
   * This bypasses the blocker for trusted domains
   */
  if (db_dns_allow)
  {
    sqlite3_reset(db_dns_allow);
    if (sqlite3_bind_text(db_dns_allow, 1, name, -1, SQLITE_TRANSIENT) == SQLITE_OK &&
        sqlite3_bind_text(db_dns_allow, 2, name, -1, SQLITE_TRANSIENT) == SQLITE_OK)
    {
      if (sqlite3_step(db_dns_allow) == SQLITE_ROW)
      {
        /* Domain found in allow list */
        server_text = sqlite3_column_text(db_dns_allow, 0);  /* Server */

        if (server_text)
        {
          printf("forward (allow): %s → %s\n", name, (const char *)server_text);
          return strdup((const char *)server_text);
        }
      }
    }
  }

  /* Check 2: DNS Block (blacklist) - Forward to blocker DNS
   * Example: "evil.xyz" in domain_dns_block → forward to 10.0.0.1 (blocker DNS)
   * The blocker DNS returns 0.0.0.0 for everything
   */
  if (db_dns_block)
  {
    sqlite3_reset(db_dns_block);
    if (sqlite3_bind_text(db_dns_block, 1, name, -1, SQLITE_TRANSIENT) == SQLITE_OK &&
        sqlite3_bind_text(db_dns_block, 2, name, -1, SQLITE_TRANSIENT) == SQLITE_OK)
    {
      if (sqlite3_step(db_dns_block) == SQLITE_ROW)
      {
        /* Domain found in block list */
        server_text = sqlite3_column_text(db_dns_block, 0);  /* Server */

        if (server_text)
        {
          printf("forward (block): %s → %s\n", name, (const char *)server_text);
          return strdup((const char *)server_text);
        }
      }
    }
  }

  /* Not in forwarding tables → continue with normal processing */
  return NULL;
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

/* ============================================================================
 * IPSet Configuration Setters (called from option.c)
 * ========================================================================== */

/* Set IPv4 termination addresses (comma-separated, no port)
 * Example: "127.0.0.1,0.0.0.0" */
void db_set_ipset_terminate_v4(char *addresses)
{
  if (ipset_terminate_v4)
    free(ipset_terminate_v4);
  ipset_terminate_v4 = addresses;
  if (addresses)
    printf("SQLite IPSet: Terminate IPv4 set to: %s\n", addresses);
}

/* Set IPv6 termination addresses (comma-separated, no port)
 * Example: "::1,::" */
void db_set_ipset_terminate_v6(char *addresses)
{
  if (ipset_terminate_v6)
    free(ipset_terminate_v6);
  ipset_terminate_v6 = addresses;
  if (addresses)
    printf("SQLite IPSet: Terminate IPv6 set to: %s\n", addresses);
}

/* Set DNS blocker servers (comma-separated, with port)
 * Example: "127.0.0.1#5353,[fd00::1]:5353" */
void db_set_ipset_dns_block(char *servers)
{
  if (ipset_dns_block)
    free(ipset_dns_block);
  ipset_dns_block = servers;
  if (servers)
    printf("SQLite IPSet: DNS Block set to: %s\n", servers);
}

/* Set real DNS servers (comma-separated, with port)
 * Example: "8.8.8.8,1.1.1.1#5353,[2001:4860:4860::8888]:53" */
void db_set_ipset_dns_allow(char *servers)
{
  if (ipset_dns_allow)
    free(ipset_dns_allow);
  ipset_dns_allow = servers;
  if (servers)
    printf("SQLite IPSet: DNS Allow set to: %s\n", servers);
}

/* Get IPSet configuration strings (for use in lookup logic) */
char *db_get_ipset_terminate_v4(void) { return ipset_terminate_v4; }
char *db_get_ipset_terminate_v6(void) { return ipset_terminate_v6; }
char *db_get_ipset_dns_block(void) { return ipset_dns_block; }
char *db_get_ipset_dns_allow(void) { return ipset_dns_allow; }

#ifdef HAVE_REGEX
/* Load all regex patterns from database into cache
 * This is called on first regex query to avoid startup delay
 * For 1-2 million patterns, this will take some time and RAM!
 */
static void load_regex_cache(void)
{
  if (regex_cache_loaded || !db || !db_block_regex)
    return;

  printf("Loading regex patterns from database...\n");
  int loaded = 0;
  int failed = 0;

  sqlite3_reset(db_block_regex);

  while (sqlite3_step(db_block_regex) == SQLITE_ROW)
  {
    const unsigned char *pattern_text = sqlite3_column_text(db_block_regex, 0);

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

    /* Add to cache (IPs come from IPSetTerminate, not database!) */
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
