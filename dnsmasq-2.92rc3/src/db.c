/* DNSMASQ-SQLITE: Simple DNS blocking with SQLite
 *
 * Features:
 * - Exact domain matching (block_exact table)
 * - Wildcard domain matching (block_wildcard_fast table)
 * - Configurable block IPs for IPv4 and IPv6
 *
 * Config options:
 *   sqlite-database=/path/to/db.sqlite
 *   sqlite-block-ipv4=1.2.3.4
 *   sqlite-block-ipv6=::1
 */

#include "dnsmasq.h"

#ifdef HAVE_SQLITE

#include <sqlite3.h>

/* Database connection and prepared statements */
static sqlite3 *db = NULL;
static sqlite3_stmt *stmt_block_exact = NULL;
static sqlite3_stmt *stmt_block_wildcard = NULL;
static char *db_file = NULL;

/* Block IPs from config */
static char *block_ipv4 = NULL;
static char *block_ipv6 = NULL;

/* Initialize database connection */
void db_init(void)
{
  if (!db_file || db)
    return;

  atexit(db_cleanup);
  printf("Opening database %s\n", db_file);

  if (sqlite3_open_v2(db_file, &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK)
  {
    fprintf(stderr, "Can't open database: %s\n", sqlite3_errmsg(db));
    db = NULL;
    return;
  }

  /* Prepare exact match statement */
  if (sqlite3_prepare_v2(db,
      "SELECT 1 FROM block_exact WHERE Domain = ? LIMIT 1",
      -1, &stmt_block_exact, NULL) != SQLITE_OK)
  {
    fprintf(stderr, "Warning: block_exact table not available\n");
    stmt_block_exact = NULL;
  }

  /* Prepare wildcard match statement */
  if (sqlite3_prepare_v2(db,
      "SELECT 1 FROM block_wildcard_fast WHERE Domain = ? LIMIT 1",
      -1, &stmt_block_wildcard, NULL) != SQLITE_OK)
  {
    fprintf(stderr, "Warning: block_wildcard_fast table not available\n");
    stmt_block_wildcard = NULL;
  }

  printf("SQLite ready: block_exact=%s, block_wildcard=%s\n",
         stmt_block_exact ? "yes" : "no",
         stmt_block_wildcard ? "yes" : "no");

  if (block_ipv4)
    printf("Block IPv4: %s\n", block_ipv4);
  if (block_ipv6)
    printf("Block IPv6: %s\n", block_ipv6);
}

/* Cleanup database connection */
void db_cleanup(void)
{
  if (stmt_block_exact)
  {
    sqlite3_finalize(stmt_block_exact);
    stmt_block_exact = NULL;
  }

  if (stmt_block_wildcard)
  {
    sqlite3_finalize(stmt_block_wildcard);
    stmt_block_wildcard = NULL;
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

  if (block_ipv4)
  {
    free(block_ipv4);
    block_ipv4 = NULL;
  }

  if (block_ipv6)
  {
    free(block_ipv6);
    block_ipv6 = NULL;
  }
}

/* Set database file path */
void db_set_file(char *path)
{
  if (db_file)
    free(db_file);
  db_file = path ? strdup(path) : NULL;
}

/* Set block IPv4 address */
void db_set_block_ipv4(char *ip)
{
  if (block_ipv4)
    free(block_ipv4);
  block_ipv4 = ip ? strdup(ip) : NULL;
}

/* Set block IPv6 address */
void db_set_block_ipv6(char *ip)
{
  if (block_ipv6)
    free(block_ipv6);
  block_ipv6 = ip ? strdup(ip) : NULL;
}

/* Check if domain matches exactly */
static int check_exact(const char *domain)
{
  if (!stmt_block_exact)
    return 0;

  sqlite3_reset(stmt_block_exact);

  if (sqlite3_bind_text(stmt_block_exact, 1, domain, -1, SQLITE_STATIC) != SQLITE_OK)
    return 0;

  return (sqlite3_step(stmt_block_exact) == SQLITE_ROW) ? 1 : 0;
}

/* Check if domain matches wildcard (checks all suffixes) */
static int check_wildcard(const char *domain)
{
  if (!stmt_block_wildcard || !domain)
    return 0;

  const char *p = domain;

  /* Check each suffix: www.example.com -> example.com -> com */
  while (p && *p)
  {
    sqlite3_reset(stmt_block_wildcard);

    if (sqlite3_bind_text(stmt_block_wildcard, 1, p, -1, SQLITE_STATIC) == SQLITE_OK)
    {
      if (sqlite3_step(stmt_block_wildcard) == SQLITE_ROW)
        return 1;  /* Found match! */
    }

    /* Move to next suffix */
    p = strchr(p, '.');
    if (p) p++;  /* Skip the dot */
  }

  return 0;
}

/* Main check function: returns 1 if domain should be blocked */
int db_check_block(const char *domain)
{
  db_init();

  if (!db)
    return 0;  /* No database = don't block */

  /* Check exact match first */
  if (check_exact(domain))
    return 1;

  /* Check wildcard match */
  if (check_wildcard(domain))
    return 1;

  return 0;  /* Not blocked */
}

/* Get block IPs (returns 1 if should block, fills in IPs) */
int db_get_block_ips(const char *domain, char **ipv4_out, char **ipv6_out)
{
  if (ipv4_out) *ipv4_out = NULL;
  if (ipv6_out) *ipv6_out = NULL;

  if (!db_check_block(domain))
    return 0;

  /* Domain is blocked - return configured IPs */
  if (ipv4_out && block_ipv4)
    *ipv4_out = block_ipv4;

  if (ipv6_out && block_ipv6)
    *ipv6_out = block_ipv6;

  return 1;
}

#endif /* HAVE_SQLITE */
