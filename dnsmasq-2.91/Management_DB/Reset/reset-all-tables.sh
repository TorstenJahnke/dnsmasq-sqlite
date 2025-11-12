#!/bin/bash
# ============================================================================
# RESET ALL TABLES - EXTREMELY DANGEROUS!
# ============================================================================
# Deletes ALL entries from ALL tables
# Usage: ./reset-all-tables.sh <database>
# ============================================================================

DB_FILE="${1}"

if [ -z "$DB_FILE" ]; then
    echo "Usage: $0 <database>"
    echo ""
    echo "Example:"
    echo "  $0 blocklist.db"
    echo ""
    echo "⚠️  WARNING: This will delete ALL entries from ALL tables!"
    echo ""
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "❌ Error: Database '$DB_FILE' not found!"
    exit 1
fi

echo "========================================="
echo "⚠️  RESET ALL TABLES (NUCLEAR OPTION!)"
echo "========================================="
echo "Database: $DB_FILE"
echo ""

# Show current counts
echo "Current entries:"
for TABLE in block_regex block_exact block_wildcard fqdn_dns_allow fqdn_dns_block; do
    COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM $TABLE;")
    echo "  $TABLE: $COUNT"
done

TOTAL=$(sqlite3 "$DB_FILE" "SELECT
    (SELECT COUNT(*) FROM block_regex) +
    (SELECT COUNT(*) FROM block_exact) +
    (SELECT COUNT(*) FROM block_wildcard) +
    (SELECT COUNT(*) FROM fqdn_dns_allow) +
    (SELECT COUNT(*) FROM fqdn_dns_block);")

echo ""
echo "Total entries: $TOTAL"
echo ""
echo "⚠️  WARNING: This will DELETE ALL $TOTAL entries!"
echo "⚠️  This action CANNOT be undone!"
echo "⚠️  The database structure will remain, but all data will be lost!"
echo ""
read -p "Type 'DELETE EVERYTHING' to confirm: " CONFIRM

if [ "$CONFIRM" != "DELETE EVERYTHING" ]; then
    echo ""
    echo "Cancelled. (You typed: '$CONFIRM')"
    exit 0
fi

echo ""
echo "Deleting all entries from all tables..."
echo ""

sqlite3 "$DB_FILE" <<EOF
BEGIN TRANSACTION;

DELETE FROM block_regex;
DELETE FROM block_exact;
DELETE FROM block_wildcard;
DELETE FROM fqdn_dns_allow;
DELETE FROM fqdn_dns_block;

COMMIT;

-- Vacuum to reclaim space
VACUUM;
EOF

echo ""
echo "✅ All tables reset successfully!"
echo ""

# Show new counts
echo "New counts:"
for TABLE in block_regex block_exact block_wildcard fqdn_dns_allow fqdn_dns_block; do
    COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM $TABLE;")
    echo "  $TABLE: $COUNT"
done

echo ""
echo "Database is now empty and ready for fresh import."
echo ""
echo "Done! 🚀"
