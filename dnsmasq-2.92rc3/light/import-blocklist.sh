#!/bin/sh
#
# Import blocklist into SQLite database
# Supports: plain domain lists, hosts format, adblock format
#

DB_PATH="${1:-/usr/local/etc/dnsmasq/aviontex.db}"
BLOCKLIST="$2"
TABLE="${3:-block_wildcard_fast}"

usage() {
    echo "Usage: $0 <database> <blocklist-file> [table]"
    echo ""
    echo "  database       Path to SQLite database"
    echo "  blocklist-file Text file with domains (one per line)"
    echo "  table          Target table: block_exact or block_wildcard_fast (default)"
    echo ""
    echo "Supported formats:"
    echo "  - Plain domain list (one domain per line)"
    echo "  - Hosts file format (0.0.0.0 domain or 127.0.0.1 domain)"
    echo "  - Comments starting with # are ignored"
    exit 1
}

if [ -z "$BLOCKLIST" ]; then
    usage
fi

if [ ! -f "$DB_PATH" ]; then
    echo "ERROR: Database not found: $DB_PATH"
    echo "Run setup-db.sh first"
    exit 1
fi

if [ ! -f "$BLOCKLIST" ]; then
    echo "ERROR: Blocklist not found: $BLOCKLIST"
    exit 1
fi

if [ "$TABLE" != "block_exact" ] && [ "$TABLE" != "block_wildcard_fast" ]; then
    echo "ERROR: Invalid table. Use 'block_exact' or 'block_wildcard_fast'"
    exit 1
fi

echo "Importing blocklist into $TABLE..."
echo "Source: $BLOCKLIST"
echo "Database: $DB_PATH"

# Count before
BEFORE=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM $TABLE;")

# Process blocklist and import
# - Remove comments
# - Handle hosts format (0.0.0.0 domain or 127.0.0.1 domain)
# - Remove empty lines
# - Convert to lowercase
# - Remove duplicates
cat "$BLOCKLIST" | \
    sed 's/#.*$//' | \
    sed 's/^0\.0\.0\.0[[:space:]]*//' | \
    sed 's/^127\.0\.0\.1[[:space:]]*//' | \
    sed 's/[[:space:]]*$//' | \
    tr '[:upper:]' '[:lower:]' | \
    grep -v '^$' | \
    grep -v '^localhost$' | \
    sort -u | \
while read domain; do
    echo "INSERT OR IGNORE INTO $TABLE (Domain) VALUES ('$domain');"
done | sqlite3 "$DB_PATH"

# Count after
AFTER=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM $TABLE;")
ADDED=$((AFTER - BEFORE))

echo ""
echo "Done!"
echo "  Before: $BEFORE domains"
echo "  After:  $AFTER domains"
echo "  Added:  $ADDED new domains"
