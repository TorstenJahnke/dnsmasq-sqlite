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

  /* Performance optimizations for large RAM systems */
  sqlite3_exec(db, "PRAGMA cache_size = -4194304", NULL, NULL, NULL);  /* 4GB cache */
  sqlite3_exec(db, "PRAGMA mmap_size = 34359738368", NULL, NULL, NULL); /* 32GB mmap */
  sqlite3_exec(db, "PRAGMA temp_store = MEMORY", NULL, NULL, NULL);

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

/* Convert string to lowercase in-place */
static void str_tolower(char *s)
{
  for (; *s; s++)
    if (*s >= 'A' && *s <= 'Z')
      *s += 32;
}

/* Extract base domain (last 2 parts): a.b.c.info.com -> info.com */
static const char *get_base_domain(const char *name)
{
  const char *p, *last_dot = NULL, *second_last_dot = NULL;

  for (p = name; *p; p++)
  {
    if (*p == '.')
    {
      second_last_dot = last_dot;
      last_dot = p;
    }
  }

  /* Return pointer after second-to-last dot, or original name */
  return second_last_dot ? second_last_dot + 1 : name;
}

/* Check if domain should be blocked - returns 1 if blocked */
int db_check_block(const char *name)
{
  const char *base;
  char name_lower[256];

  db_init();

  if (!db)
    return 0;

  /* Convert to lowercase for case-insensitive matching */
  strncpy(name_lower, name, sizeof(name_lower) - 1);
  name_lower[sizeof(name_lower) - 1] = '\0';
  str_tolower(name_lower);

  /* Get base domain (e.g., info.com from a.b.c.info.com) */
  base = get_base_domain(name_lower);

  /* Check wildcard first (base domain) */
  if (stmt_wildcard)
  {
    sqlite3_reset(stmt_wildcard);
    sqlite3_bind_text(stmt_wildcard, 1, base, -1, SQLITE_STATIC);
    if (sqlite3_step(stmt_wildcard) == SQLITE_ROW)
      return 1;
  }

  /* Check exact match (full domain) */
  if (stmt_exact)
  {
    sqlite3_reset(stmt_exact);
    sqlite3_bind_text(stmt_exact, 1, name_lower, -1, SQLITE_STATIC);
    if (sqlite3_step(stmt_exact) == SQLITE_ROW)
      return 1;
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
