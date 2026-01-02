/* DNSMASQ-SQLITE: DNS blocking with SQLite
 * Based on mabrafoo's original implementation
 *
 * Tables:
 * - block_exact: Exact domain matches (needs INDEX on Domain)
 * - block_wildcard_fast: Wildcard domain matches (needs INDEX on Domain)
 *
 * Config:
 *   sqlite-database=/path/to/db.sqlite
 *   sqlite-block-ipv4=1.2.3.4
 *   sqlite-block-ipv6=::1
 */

#include "dnsmasq.h"

#ifdef HAVE_SQLITE

static sqlite3 *db = NULL;
static sqlite3_stmt *stmt_exact = NULL;
static sqlite3_stmt *stmt_wildcard = NULL;
static char *db_file = NULL;
static char *block_ipv4 = NULL;
static char *block_ipv6 = NULL;

void db_init(void)
{
  if (!db_file || db)
    return;

  atexit(db_cleanup);

  /* Open database read-only for safety and performance */
  int flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX;
  if (sqlite3_open_v2(db_file, &db, flags, NULL))
  {
    my_syslog(LOG_ERR, _("SQLite: Can't open database %s: %s"), db_file, sqlite3_errmsg(db));
    db = NULL;
    return;
  }

  /* Performance optimizations */
  sqlite3_exec(db, "PRAGMA cache_size = -65536", NULL, NULL, NULL);  /* 64MB cache */
  sqlite3_exec(db, "PRAGMA mmap_size = 268435456", NULL, NULL, NULL); /* 256MB mmap */

  /* Prepare exact match statement */
  if (sqlite3_prepare_v2(db,
      "SELECT 1 FROM block_exact WHERE Domain=? LIMIT 1",
      -1, &stmt_exact, NULL))
  {
    my_syslog(LOG_WARNING, _("SQLite: block_exact table not available"));
    stmt_exact = NULL;
  }

  /* Prepare wildcard match statement */
  if (sqlite3_prepare_v2(db,
      "SELECT 1 FROM block_wildcard_fast WHERE Domain=? LIMIT 1",
      -1, &stmt_wildcard, NULL))
  {
    my_syslog(LOG_WARNING, _("SQLite: block_wildcard_fast table not available"));
    stmt_wildcard = NULL;
  }

  my_syslog(LOG_INFO, _("SQLite: database %s opened (exact=%s, wildcard=%s)"),
            db_file,
            stmt_exact ? "yes" : "no",
            stmt_wildcard ? "yes" : "no");
}

void db_cleanup(void)
{
  if (stmt_exact)
  {
    sqlite3_finalize(stmt_exact);
    stmt_exact = NULL;
  }

  if (stmt_wildcard)
  {
    sqlite3_finalize(stmt_wildcard);
    stmt_wildcard = NULL;
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

void db_set_file(char *path)
{
  if (db_file)
    free(db_file);
  db_file = path;
}

void db_set_block_ipv4(char *ip)
{
  if (block_ipv4)
    free(block_ipv4);
  block_ipv4 = ip;
}

void db_set_block_ipv6(char *ip)
{
  if (block_ipv6)
    free(block_ipv6);
  block_ipv6 = ip;
}

/* Check if domain should be blocked - returns 1 if blocked */
int db_check_block(const char *name)
{
  const char *p;

  db_init();

  if (!db)
    return 0;

  /* Check exact match first */
  if (stmt_exact)
  {
    sqlite3_reset(stmt_exact);
    sqlite3_bind_text(stmt_exact, 1, name, -1, SQLITE_STATIC);
    if (sqlite3_step(stmt_exact) == SQLITE_ROW)
      return 1;
  }

  /* Check wildcard - try each suffix */
  if (stmt_wildcard)
  {
    p = name;
    while (p && *p)
    {
      sqlite3_reset(stmt_wildcard);
      sqlite3_bind_text(stmt_wildcard, 1, p, -1, SQLITE_STATIC);
      if (sqlite3_step(stmt_wildcard) == SQLITE_ROW)
        return 1;

      /* Move to next suffix */
      p = strchr(p, '.');
      if (p) p++;
    }
  }

  return 0;
}

/* Get block IPs */
char *db_get_block_ipv4(void)
{
  return block_ipv4;
}

char *db_get_block_ipv6(void)
{
  return block_ipv6;
}

#endif /* HAVE_SQLITE */
