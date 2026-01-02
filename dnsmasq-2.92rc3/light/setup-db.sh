#!/bin/sh
# Setup SQLite database for dnsmasq blocking
# Usage: ./setup-db.sh /path/to/database.db

DB="${1:-/usr/local/etc/dnsmasq/blocklist.db}"

echo "Creating database: $DB"

sqlite3 "$DB" <<'EOF'
-- Block wildcard domains (suffix matching)
CREATE TABLE IF NOT EXISTS block_wildcard_fast (
    Domain TEXT PRIMARY KEY NOT NULL
) WITHOUT ROWID;

-- Block exact domains (optional)
CREATE TABLE IF NOT EXISTS block_exact (
    Domain TEXT PRIMARY KEY NOT NULL
) WITHOUT ROWID;

-- Performance settings for large databases
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;

-- Verify
SELECT 'Tables created';
EOF

echo "Done: $DB"
