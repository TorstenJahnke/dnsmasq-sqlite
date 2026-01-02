#!/bin/sh
# Optimized blocklist import for 300M+ entries (v5.0)
# Usage: ./import-blocklist.sh /path/to/blacklist.txt [/path/to/output.db]

TXT="${1:-/opt/blacklist.txt}"
DB="${2:-/usr/local/etc/dnsmasq/blocklist.db}"

if [ ! -f "$TXT" ]; then
    echo "Error: $TXT not found"
    exit 1
fi

echo "=== SQLite Blocklist Import v5.0 ==="
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

-- block_wildcard: Base domain blocks all subdomains
CREATE TABLE block_wildcard (
    Domain TEXT PRIMARY KEY NOT NULL
) WITHOUT ROWID;

-- block_hosts: Exact hostname match only
CREATE TABLE block_hosts (
    Domain TEXT PRIMARY KEY NOT NULL
) WITHOUT ROWID;

-- block_ips: IP address rewriting
CREATE TABLE block_ips (
    Source_IP TEXT PRIMARY KEY NOT NULL,
    Target_IP TEXT NOT NULL
) WITHOUT ROWID;
SQL

echo "[2/4] Importing domains (this takes a while)..."
# Fast import using .import
sqlite3 "$DB" << SQL
PRAGMA synchronous = OFF;
PRAGMA journal_mode = OFF;
PRAGMA cache_size = -2097152;
.mode csv
.import '$TXT' block_wildcard
SQL

echo "[3/4] Optimizing database..."
sqlite3 "$DB" << 'SQL'
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
ANALYZE;
VACUUM;
SQL

echo "[4/4] Verifying..."
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM block_wildcard;")
SIZE=$(ls -lh "$DB" | awk '{print $5}')

echo ""
echo "=== Done ==="
echo "Domains: $COUNT"
echo "DB Size: $SIZE"
echo "Database: $DB"
