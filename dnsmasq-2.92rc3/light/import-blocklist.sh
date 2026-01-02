#!/bin/sh
# Optimized blocklist import for 660M+ entries
# Usage: ./import-blocklist.sh /path/to/blacklist.txt [/path/to/output.db]

TXT="${1:-/opt/blacklist.txt}"
DB="${2:-/usr/local/etc/dnsmasq/blocklist.db}"

if [ ! -f "$TXT" ]; then
    echo "Error: $TXT not found"
    exit 1
fi

echo "=== SQLite Blocklist Import ==="
echo "Input:  $TXT"
echo "Output: $DB"
echo "Lines:  $(wc -l < "$TXT")"
echo ""

# Remove old database
rm -f "$DB" "$DB-wal" "$DB-shm"

echo "[1/4] Creating database with optimal settings..."
sqlite3 "$DB" << 'SQL'
PRAGMA page_size = 4096;
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
PRAGMA cache_size = -2097152;
PRAGMA temp_store = MEMORY;

CREATE TABLE block_wildcard_fast (
    Domain TEXT PRIMARY KEY NOT NULL
) WITHOUT ROWID;

CREATE TABLE block_exact (
    Domain TEXT PRIMARY KEY NOT NULL
) WITHOUT ROWID;
SQL

echo "[2/4] Importing domains (this takes a while)..."
# Fast import using .import
sqlite3 "$DB" << SQL
PRAGMA synchronous = OFF;
PRAGMA journal_mode = OFF;
PRAGMA cache_size = -2097152;
.mode csv
.import '$TXT' block_wildcard_fast
SQL

echo "[3/4] Optimizing database..."
sqlite3 "$DB" << 'SQL'
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
ANALYZE;
VACUUM;
SQL

echo "[4/4] Verifying..."
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM block_wildcard_fast;")
SIZE=$(ls -lh "$DB" | awk '{print $5}')

echo ""
echo "=== Done ==="
echo "Domains: $COUNT"
echo "DB Size: $SIZE"
echo "Database: $DB"
