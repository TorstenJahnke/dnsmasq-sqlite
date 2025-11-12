#!/bin/bash
# ============================================================================
# Search for a domain/pattern in ALL tables
# ============================================================================
# Usage: ./search-domain.sh <database> <search-term>
# ============================================================================

DB_FILE="${1}"
SEARCH_TERM="${2}"

if [ -z "$DB_FILE" ] || [ -z "$SEARCH_TERM" ]; then
    echo "Usage: $0 <database> <search-term>"
    echo ""
    echo "Examples:"
    echo "  $0 blocklist.db ads.example.com"
    echo "  $0 blocklist.db 'google%'           # Wildcard search"
    echo "  $0 blocklist.db '%tracking%'        # Contains search"
    echo ""
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "❌ Error: Database '$DB_FILE' not found!"
    exit 1
fi

echo "========================================="
echo "Search Domain/Pattern"
echo "========================================="
echo "Database: $DB_FILE"
echo "Search:   $SEARCH_TERM"
echo ""

FOUND=0

# Search in block_regex
echo "Searching in block_regex..."
RESULTS=$(sqlite3 "$DB_FILE" "SELECT Pattern FROM block_regex WHERE Pattern LIKE '$SEARCH_TERM';")
if [ -n "$RESULTS" ]; then
    echo "✅ Found in block_regex:"
    echo "$RESULTS" | sed 's/^/  /'
    echo ""
    FOUND=1
fi

# Search in block_exact
echo "Searching in block_exact..."
RESULTS=$(sqlite3 "$DB_FILE" "SELECT Domain FROM block_exact WHERE Domain LIKE '$SEARCH_TERM';")
if [ -n "$RESULTS" ]; then
    echo "✅ Found in block_exact:"
    echo "$RESULTS" | sed 's/^/  /'
    echo ""
    FOUND=1
fi

# Search in block_wildcard
echo "Searching in block_wildcard..."
RESULTS=$(sqlite3 "$DB_FILE" "SELECT Domain FROM block_wildcard WHERE Domain LIKE '$SEARCH_TERM';")
if [ -n "$RESULTS" ]; then
    echo "✅ Found in block_wildcard:"
    echo "$RESULTS" | sed 's/^/  /'
    echo ""
    FOUND=1
fi

# Search in fqdn_dns_allow
echo "Searching in fqdn_dns_allow..."
RESULTS=$(sqlite3 "$DB_FILE" "SELECT Domain FROM fqdn_dns_allow WHERE Domain LIKE '$SEARCH_TERM';")
if [ -n "$RESULTS" ]; then
    echo "✅ Found in fqdn_dns_allow:"
    echo "$RESULTS" | sed 's/^/  /'
    echo ""
    FOUND=1
fi

# Search in fqdn_dns_block
echo "Searching in fqdn_dns_block..."
RESULTS=$(sqlite3 "$DB_FILE" "SELECT Domain FROM fqdn_dns_block WHERE Domain LIKE '$SEARCH_TERM';")
if [ -n "$RESULTS" ]; then
    echo "✅ Found in fqdn_dns_block:"
    echo "$RESULTS" | sed 's/^/  /'
    echo ""
    FOUND=1
fi

if [ $FOUND -eq 0 ]; then
    echo "❌ No matches found for: $SEARCH_TERM"
    echo ""
    echo "Tip: Use wildcards for partial matches:"
    echo "  '%google%'  → matches anything containing 'google'"
    echo "  'google%'   → matches anything starting with 'google'"
    echo "  '%google'   → matches anything ending with 'google'"
fi

echo ""
echo "Done! 🚀"
