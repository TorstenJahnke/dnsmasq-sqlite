#!/bin/sh
# Update PRAGMA settings on existing database
# Version: 5.0
#
# Usage: ./update-db.sh [database]
#        ./update-db.sh /path/to/database.db

DATABASE="${1:-/usr/local/etc/dnsmasq/aviontex.db}"

echo ""
echo "=========================================="
echo " Update Database Settings"
echo "=========================================="
echo ""

if [ ! -f "$DATABASE" ]; then
    echo "Error: $DATABASE not found"
    exit 1
fi

echo "Database: $DATABASE"
echo ""

sqlite3 "$DATABASE" <<'EOF'
-- Persistent settings (stored in DB)
PRAGMA journal_mode = WAL;
PRAGMA page_size = 4096;

-- Update statistics for query optimizer
ANALYZE;

-- Show current settings
SELECT 'journal_mode: ' || journal_mode FROM pragma_journal_mode;
SELECT 'page_size: ' || page_size FROM pragma_page_size;
SELECT 'Tables updated: block_wildcard, block_hosts, block_ips';
EOF

echo ""
echo "Done!"
echo ""
echo "Note: cache_size and mmap_size are session-based."
echo "They must be set by dnsmasq at connection time."
echo ""
