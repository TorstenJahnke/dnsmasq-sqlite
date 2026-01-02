#!/bin/sh
# Setup SQLite database for dnsmasq blocking v5.0
# Usage: ./setup-db.sh /path/to/database.db

DB="${1:-/usr/local/etc/dnsmasq/blocklist.db}"

echo "Creating database: $DB"

sqlite3 "$DB" <<'EOF'
-- Block wildcard: Base domain blocks all subdomains
-- Example: info.com blocks *.info.com
CREATE TABLE IF NOT EXISTS block_wildcard (
    Domain TEXT PRIMARY KEY NOT NULL
) WITHOUT ROWID;

-- Block hosts: Exact hostname match only
CREATE TABLE IF NOT EXISTS block_hosts (
    Domain TEXT PRIMARY KEY NOT NULL
) WITHOUT ROWID;

-- Block IPs: Rewrite IP addresses
CREATE TABLE IF NOT EXISTS block_ips (
    Source_IP TEXT PRIMARY KEY NOT NULL,
    Target_IP TEXT NOT NULL
) WITHOUT ROWID;

-- Performance settings
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;

-- Verify
SELECT 'Tables: block_wildcard, block_hosts, block_ips';
EOF

echo "Done: $DB"
