#!/bin/bash
# ============================================================================
# Show top N domains/patterns from each table
# ============================================================================
# Usage: ./search-top-domains.sh <database> [limit]
# ============================================================================

DB_FILE="${1}"
LIMIT="${2:-10}"

if [ -z "$DB_FILE" ]; then
    echo "Usage: $0 <database> [limit]"
    echo ""
    echo "Example:"
    echo "  $0 blocklist.db 20"
    echo ""
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "❌ Error: Database '$DB_FILE' not found!"
    exit 1
fi

echo "========================================="
echo "Top $LIMIT Entries Per Table"
echo "========================================="
echo "Database: $DB_FILE"
echo ""

# block_regex
echo "Top $LIMIT patterns in block_regex:"
echo "----------------------------------------"
sqlite3 "$DB_FILE" "SELECT Pattern FROM block_regex ORDER BY Pattern LIMIT $LIMIT;" | sed 's/^/  /'
echo ""

# block_exact
echo "Top $LIMIT domains in block_exact:"
echo "----------------------------------------"
sqlite3 "$DB_FILE" "SELECT Domain FROM block_exact ORDER BY Domain LIMIT $LIMIT;" | sed 's/^/  /'
echo ""

# block_wildcard
echo "Top $LIMIT domains in block_wildcard:"
echo "----------------------------------------"
sqlite3 "$DB_FILE" "SELECT Domain FROM block_wildcard ORDER BY Domain LIMIT $LIMIT;" | sed 's/^/  /'
echo ""

# fqdn_dns_allow
echo "Top $LIMIT domains in fqdn_dns_allow:"
echo "----------------------------------------"
ALLOW_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM fqdn_dns_allow;")
if [ "$ALLOW_COUNT" -gt 0 ]; then
    sqlite3 "$DB_FILE" "SELECT Domain FROM fqdn_dns_allow ORDER BY Domain LIMIT $LIMIT;" | sed 's/^/  /'
else
    echo "  (empty)"
fi
echo ""

# fqdn_dns_block
echo "Top $LIMIT domains in fqdn_dns_block:"
echo "----------------------------------------"
BLOCK_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM fqdn_dns_block;")
if [ "$BLOCK_COUNT" -gt 0 ]; then
    sqlite3 "$DB_FILE" "SELECT Domain FROM fqdn_dns_block ORDER BY Domain LIMIT $LIMIT;" | sed 's/^/  /'
else
    echo "  (empty)"
fi
echo ""

echo "Done! 🚀"
