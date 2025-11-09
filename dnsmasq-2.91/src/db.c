#include "dnsmasq.h"
#ifdef HAVE_SQLITE

static sqlite3 *db = NULL;
static sqlite3_stmt *db_domain_exact = NULL;     /* For exact-only matching (hosts-style) */
static sqlite3_stmt *db_domain_wildcard = NULL;  /* For wildcard matching (*.domain) */
static char *db_file = NULL;

/* Termination addresses for blocked domains */
static struct in_addr db_block_ipv4;
static struct in6_addr db_block_ipv6;
static int db_has_ipv4 = 0;
static int db_has_ipv6 = 0;

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

  printf("SQLite blocker ready: exact-match + wildcard support (per-domain termination IPs)\n");
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

#endif
