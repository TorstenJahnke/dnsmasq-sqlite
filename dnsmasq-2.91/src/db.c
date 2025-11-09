#include "dnsmasq.h"
#ifdef HAVE_SQLITE

static sqlite3 *db = NULL;
static sqlite3_stmt *db_domain_exists = NULL;
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

  /* Query checks both exact match AND parent domain match (wildcard)
   * Example: If "example.com" is in DB, it blocks:
   *   - example.com (exact match)
   *   - www.example.com (subdomain match)
   *   - mail.server.example.com (nested subdomain match)
   */
  if (sqlite3_prepare(
    db,
    "SELECT COUNT(*) FROM domain WHERE Domain = ? OR ? LIKE '%.' || Domain",
    -1,
    &db_domain_exists,
    NULL
  ))
  {
    fprintf(stderr, "Can't prepare statement: %s\n", sqlite3_errmsg(db));
    exit(1);
  }
}

void db_cleanup(void)
{
  printf("cleaning up database...\n");

  if (db_domain_exists)
  {
    sqlite3_finalize(db_domain_exists);
    db_domain_exists = NULL;
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

// FIXED: Umbenannt von db_check_allow zu db_check_block für klarere Semantik
// Wird zusammen mit der invertierten Logik in rfc1035.c verwendet
int db_check_block(const char *name)
{
  db_init();

  if (!db)
  {
    return 0;  // FIXED: Wenn keine DB → nicht blockieren (war 1)
  }

  sqlite3_reset(db_domain_exists);
  int row_exists = 0;

  /* Bind domain name to both parameters (exact match and wildcard match) */
  if (sqlite3_bind_text(db_domain_exists, 1, name, -1, SQLITE_TRANSIENT) ||
      sqlite3_bind_text(db_domain_exists, 2, name, -1, SQLITE_TRANSIENT))
  {
    fprintf(stderr, "Can't bind text parameter: %s\n", sqlite3_errmsg(db));
  }
  else if (sqlite3_step(db_domain_exists) == SQLITE_ROW)
  {
    row_exists = sqlite3_column_int(db_domain_exists, 0);
  }

  printf("block: %s %d\n", name, row_exists);  // FIXED: "block" statt "exists"
  return row_exists;
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
