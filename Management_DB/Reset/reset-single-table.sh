#!/bin/bash
# ============================================================================
# RESET (empty) a single table - DANGEROUS!
# ============================================================================
# Usage: ./reset-single-table.sh <database> <table-name>
# ============================================================================

DB_FILE="${1}"
TABLE_NAME="${2}"

if [ -z "$DB_FILE" ] || [ -z "$TABLE_NAME" ]; then
    echo "Usage: $0 <database> <table-name>"
    echo ""
    echo "Available tables:"
    echo "  block_regex"
    echo "  block_exact"
    echo "  block_wildcard"
    echo "  fqdn_dns_allow"
    echo "  fqdn_dns_block"
    echo ""
    echo "Example:"
    echo "  $0 blocklist.db block_exact"
    echo ""
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "❌ Error: Database '$DB_FILE' not found!"
    exit 1
fi

echo "========================================="
echo "⚠️  RESET TABLE (DELETE ALL ENTRIES)"
echo "========================================="
echo "Database: $DB_FILE"
echo "Table:    $TABLE_NAME"
echo ""

# Get current count
COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM $TABLE_NAME;" 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ Error: Table '$TABLE_NAME' not found!"
    exit 1
fi

echo "Current entries: $COUNT"
echo ""
echo "⚠️  WARNING: This will DELETE ALL $COUNT entries!"
echo "⚠️  This action CANNOT be undone!"
echo ""
read -p "Type the table name '$TABLE_NAME' to confirm: " CONFIRM

if [ "$CONFIRM" != "$TABLE_NAME" ]; then
    echo "Cancelled. (You typed: '$CONFIRM')"
    exit 0
fi

echo ""
echo "Deleting all entries from $TABLE_NAME..."

sqlite3 "$DB_FILE" "DELETE FROM $TABLE_NAME;"

echo ""
echo "✅ Table $TABLE_NAME reset successfully!"
echo ""

NEW_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM $TABLE_NAME;")
echo "Entries remaining: $NEW_COUNT"
echo ""
echo "Done! 🚀"
