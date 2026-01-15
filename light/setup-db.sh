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

-- Performance settings (optimized for 128GB RAM / 8 Core / 7GB+ DB)
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA cache_size = -20971520;     -- 20GB RAM Cache
PRAGMA mmap_size = 21474836480;    -- 20GB Memory-mapped I/O
PRAGMA temp_store = MEMORY;
PRAGMA page_size = 4096;

-- Verify
SELECT 'Tables: block_wildcard, block_hosts, block_ips';
SELECT 'Cache: 20GB | mmap: 20GB | Optimized for HP DL120 (7GB+ DB)';
EOF

echo "Done: $DB"
