#!/bin/bash
# ============================================================================
# Search for potential duplicates across tables
# ============================================================================
# Finds domains/patterns that exist in multiple tables
# Usage: ./search-duplicates.sh <database>
# ============================================================================

DB_FILE="${1}"

if [ -z "$DB_FILE" ]; then
    echo "Usage: $0 <database>"
    echo ""
    echo "Example:"
    echo "  $0 blocklist.db"
    echo ""
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "❌ Error: Database '$DB_FILE' not found!"
    exit 1
fi

echo "========================================="
echo "Duplicate Detection"
echo "========================================="
echo "Database: $DB_FILE"
echo ""

echo "Checking for domains in multiple tables..."
echo ""

# Check for exact duplicates across domain tables
DUPLICATES=$(sqlite3 "$DB_FILE" <<'EOF'
-- Find domains in both block_exact and block_wildcard
SELECT 'block_exact + block_wildcard', Domain FROM block_exact
WHERE Domain IN (SELECT Domain FROM block_wildcard)
UNION ALL
-- Find domains in both block_exact and fqdn_dns_allow
SELECT 'block_exact + fqdn_dns_allow', Domain FROM block_exact
WHERE Domain IN (SELECT Domain FROM fqdn_dns_allow)
UNION ALL
-- Find domains in both block_exact and fqdn_dns_block
SELECT 'block_exact + fqdn_dns_block', Domain FROM block_exact
WHERE Domain IN (SELECT Domain FROM fqdn_dns_block)
UNION ALL
-- Find domains in both block_wildcard and fqdn_dns_allow
SELECT 'block_wildcard + fqdn_dns_allow', Domain FROM block_wildcard
WHERE Domain IN (SELECT Domain FROM fqdn_dns_allow)
UNION ALL
-- Find domains in both block_wildcard and fqdn_dns_block
SELECT 'block_wildcard + fqdn_dns_block', Domain FROM block_wildcard
WHERE Domain IN (SELECT Domain FROM fqdn_dns_block)
UNION ALL
-- Find domains in both fqdn_dns_allow and fqdn_dns_block
SELECT 'fqdn_dns_allow + fqdn_dns_block', Domain FROM fqdn_dns_allow
WHERE Domain IN (SELECT Domain FROM fqdn_dns_block);
EOF
)

if [ -z "$DUPLICATES" ]; then
    echo "✅ No duplicates found!"
    echo ""
    echo "All entries are unique across tables."
else
    echo "⚠️  Duplicates found:"
    echo ""
    echo "$DUPLICATES" | while IFS='|' read -r TABLES DOMAIN; do
        echo "  $DOMAIN → in [$TABLES]"
    done
    echo ""
    echo "Note: Duplicates may cause unexpected behavior!"
    echo "      Priority order determines which table is checked first."
fi

echo ""
echo "Done! 🚀"
