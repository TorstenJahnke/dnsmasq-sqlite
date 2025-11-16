#!/bin/bash
# ============================================================================
# Cleanup duplicate entries across tables with priority-based logic
# ============================================================================
# Usage: ./cleanup-duplicates.sh <database> [--auto]
#
# Priority order (highest to lowest):
#   1. fqdn_dns_allow (whitelist - most important)
#   2. block_exact (exact blocking)
#   3. block_wildcard (wildcard blocking)
#   4. fqdn_dns_block (blacklist)
#
# If a domain exists in multiple tables, it's kept in the highest priority
# table and removed from lower priority tables.
# ============================================================================

set -e

DB_FILE="${1}"
AUTO_MODE="${2}"

if [ -z "$DB_FILE" ]; then
    echo "Usage: $0 <database> [--auto]"
    echo ""
    echo "Example:"
    echo "  $0 blocklist.db           # Interactive mode (asks for confirmation)"
    echo "  $0 blocklist.db --auto    # Automatic mode (no confirmation)"
    echo ""
    echo "Priority order (highest to lowest):"
    echo "  1. fqdn_dns_allow    (whitelist - keeps this)"
    echo "  2. block_exact       (exact match)"
    echo "  3. block_wildcard    (wildcard)"
    echo "  4. fqdn_dns_block    (blacklist)"
    echo ""
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "❌ Error: Database '$DB_FILE' not found!"
    exit 1
fi

echo "========================================="
echo "Duplicate Cleanup (Priority-Based)"
echo "========================================="
echo "Database: $DB_FILE"
echo "Mode: $([ "$AUTO_MODE" = "--auto" ] && echo "Automatic" || echo "Interactive")"
echo ""

# First, find all duplicates
echo "Step 1: Scanning for duplicates..."
echo ""

DUPLICATES=$(sqlite3 "$DB_FILE" <<'EOF'
SELECT 'fqdn_dns_allow + block_exact', Domain FROM fqdn_dns_allow
WHERE Domain IN (SELECT Domain FROM block_exact)
UNION ALL
SELECT 'fqdn_dns_allow + block_wildcard', Domain FROM fqdn_dns_allow
WHERE Domain IN (SELECT Domain FROM block_wildcard)
UNION ALL
SELECT 'fqdn_dns_allow + fqdn_dns_block', Domain FROM fqdn_dns_allow
WHERE Domain IN (SELECT Domain FROM fqdn_dns_block)
UNION ALL
SELECT 'block_exact + block_wildcard', Domain FROM block_exact
WHERE Domain IN (SELECT Domain FROM block_wildcard)
UNION ALL
SELECT 'block_exact + fqdn_dns_block', Domain FROM block_exact
WHERE Domain IN (SELECT Domain FROM fqdn_dns_block)
UNION ALL
SELECT 'block_wildcard + fqdn_dns_block', Domain FROM block_wildcard
WHERE Domain IN (SELECT Domain FROM fqdn_dns_block);
EOF
)

if [ -z "$DUPLICATES" ]; then
    echo "✅ No duplicates found!"
    echo ""
    echo "Database is clean. No action needed."
    exit 0
fi

# Show duplicates
echo "⚠️  Found duplicates:"
echo ""
DUPLICATE_COUNT=$(echo "$DUPLICATES" | wc -l)
echo "$DUPLICATES" | while IFS='|' read -r TABLES DOMAIN; do
    echo "  $DOMAIN → in [$TABLES]"
done
echo ""
echo "Total: $DUPLICATE_COUNT duplicate(s)"
echo ""

# Ask for confirmation in interactive mode
if [ "$AUTO_MODE" != "--auto" ]; then
    echo "Cleanup strategy:"
    echo "  - Domains in fqdn_dns_allow (whitelist) → Remove from all block tables"
    echo "  - Domains in block_exact → Remove from block_wildcard and fqdn_dns_block"
    echo "  - Domains in block_wildcard → Remove from fqdn_dns_block"
    echo ""
    read -p "Proceed with cleanup? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi
    echo ""
fi

echo "Step 2: Cleaning up duplicates..."
echo ""

# Create SQL cleanup script
CLEANUP_SQL=$(mktemp)
trap "rm -f $CLEANUP_SQL" EXIT

cat > "$CLEANUP_SQL" <<'EOF'
BEGIN TRANSACTION;

-- Priority 1: Keep in fqdn_dns_allow, remove from all others
DELETE FROM block_exact WHERE Domain IN (SELECT Domain FROM fqdn_dns_allow);
DELETE FROM block_wildcard WHERE Domain IN (SELECT Domain FROM fqdn_dns_allow);
DELETE FROM fqdn_dns_block WHERE Domain IN (SELECT Domain FROM fqdn_dns_allow);

-- Priority 2: Keep in block_exact, remove from lower priority
DELETE FROM block_wildcard WHERE Domain IN (SELECT Domain FROM block_exact);
DELETE FROM fqdn_dns_block WHERE Domain IN (SELECT Domain FROM block_exact);

-- Priority 3: Keep in block_wildcard, remove from lowest priority
DELETE FROM fqdn_dns_block WHERE Domain IN (SELECT Domain FROM block_wildcard);

COMMIT;

-- Show statistics
SELECT 'Cleanup complete!' AS Status;
EOF

# Execute cleanup
sqlite3 "$DB_FILE" < "$CLEANUP_SQL"

echo "✅ Cleanup completed!"
echo ""

# Verify no duplicates remain
REMAINING=$(sqlite3 "$DB_FILE" <<'EOF'
SELECT COUNT(*) FROM (
    SELECT Domain FROM fqdn_dns_allow
    WHERE Domain IN (SELECT Domain FROM block_exact)
    UNION ALL
    SELECT Domain FROM fqdn_dns_allow
    WHERE Domain IN (SELECT Domain FROM block_wildcard)
    UNION ALL
    SELECT Domain FROM fqdn_dns_allow
    WHERE Domain IN (SELECT Domain FROM fqdn_dns_block)
    UNION ALL
    SELECT Domain FROM block_exact
    WHERE Domain IN (SELECT Domain FROM block_wildcard)
    UNION ALL
    SELECT Domain FROM block_exact
    WHERE Domain IN (SELECT Domain FROM fqdn_dns_block)
    UNION ALL
    SELECT Domain FROM block_wildcard
    WHERE Domain IN (SELECT Domain FROM fqdn_dns_block)
);
EOF
)

if [ "$REMAINING" = "0" ]; then
    echo "✅ Verification: No duplicates remaining!"
else
    echo "⚠️  Warning: $REMAINING duplicate(s) still present (manual review needed)"
fi

echo ""
echo "========================================="
echo "Summary"
echo "========================================="
echo "Cleaned: $DUPLICATE_COUNT duplicate(s)"
echo "Remaining: $REMAINING duplicate(s)"
echo ""
echo "Final table sizes:"
sqlite3 "$DB_FILE" <<'EOF'
.mode column
.headers on
SELECT
    'fqdn_dns_allow' AS Table_Name,
    COUNT(*) AS Entries
FROM fqdn_dns_allow
UNION ALL
SELECT 'block_exact', COUNT(*) FROM block_exact
UNION ALL
SELECT 'block_wildcard', COUNT(*) FROM block_wildcard
UNION ALL
SELECT 'fqdn_dns_block', COUNT(*) FROM fqdn_dns_block
UNION ALL
SELECT 'block_regex', COUNT(*) FROM block_regex;
EOF

echo ""
echo "Done! 🚀"
