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
   * Table: domain_exact
   * Blocks ONLY the exact domain, NOT subdomains
   * Example: "paypal-evil.de" blocks ONLY "paypal-evil.de"
   */
  sqlite3_prepare(
    db,
    "SELECT COUNT(*) FROM domain_exact WHERE Domain = ?",
    -1,
    &db_domain_exact,
    NULL
  );
  /* Note: Ignore error if table doesn't exist - it's optional */

  /* Prepare statement for wildcard matching
   * Table: domain
   * Blocks domain AND all subdomains
   * Example: "paypal-evil.de" blocks "paypal-evil.de", "*.paypal-evil.de", etc.
   */
  if (sqlite3_prepare(
    db,
    "SELECT COUNT(*) FROM domain WHERE Domain = ? OR ? LIKE '%.' || Domain",
    -1,
    &db_domain_wildcard,
    NULL
  ))
  {
    fprintf(stderr, "Can't prepare wildcard statement: %s\n", sqlite3_errmsg(db));
    exit(1);
  }

  printf("SQLite blocker ready: exact-match + wildcard support\n");
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

/* Check if domain should be blocked
 * Supports two modes:
 * 1. Exact-only (hosts-style): domain_exact table
 *    - Blocks ONLY the exact domain
 * 2. Wildcard: domain table
 *    - Blocks domain AND all subdomains (*.domain)
 */
int db_check_block(const char *name)
{
  db_init();

  if (!db)
  {
    return 0;  /* No DB → don't block */
  }

  int blocked = 0;

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
        blocked = sqlite3_column_int(db_domain_exact, 0);
        if (blocked)
        {
          printf("block (exact): %s\n", name);
          return 1;
        }
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
        blocked = sqlite3_column_int(db_domain_wildcard, 0);
        if (blocked)
        {
          printf("block (wildcard): %s\n", name);
          return 1;
        }
      }
    }
  }

  return 0;  /* Not blocked */
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
