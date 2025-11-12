#!/bin/bash
# ============================================================================
# Delete SINGLE entry from a table
# ============================================================================
# Usage: ./delete-single-entry.sh <database> <table> <domain-or-pattern>
# ============================================================================

DB_FILE="${1}"
TABLE_NAME="${2}"
ENTRY="${3}"

if [ -z "$DB_FILE" ] || [ -z "$TABLE_NAME" ] || [ -z "$ENTRY" ]; then
    echo "Usage: $0 <database> <table> <domain-or-pattern>"
    echo ""
    echo "Available tables:"
    echo "  block_regex       (Pattern)"
    echo "  block_exact       (Domain)"
    echo "  block_wildcard    (Domain)"
    echo "  fqdn_dns_allow    (Domain)"
    echo "  fqdn_dns_block    (Domain)"
    echo ""
    echo "Examples:"
    echo "  $0 blocklist.db block_exact ads.example.com"
    echo "  $0 blocklist.db block_regex '^ad[sz].*$'"
    echo "  $0 blocklist.db block_wildcard privacy.com"
    echo ""
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "❌ Error: Database '$DB_FILE' not found!"
    exit 1
fi

echo "========================================="
echo "Delete Single Entry"
echo "========================================="
echo "Database: $DB_FILE"
echo "Table:    $TABLE_NAME"
echo "Entry:    $ENTRY"
echo ""

# Determine column name
if [ "$TABLE_NAME" = "block_regex" ]; then
    COLUMN="Pattern"
else
    COLUMN="Domain"
fi

# Check if exists
EXISTS=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM $TABLE_NAME WHERE $COLUMN = '$ENTRY';")

if [ "$EXISTS" -eq 0 ]; then
    echo "⚠️  Entry not found in $TABLE_NAME"
    echo ""
    exit 0
fi

echo "Found entry in $TABLE_NAME"
echo ""
echo "⚠️  Are you sure you want to delete?"
echo "Entry: $ENTRY"
echo ""
read -p "Type 'yes' to confirm: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

# Delete
sqlite3 "$DB_FILE" "DELETE FROM $TABLE_NAME WHERE $COLUMN = '$ENTRY';"

echo ""
echo "✅ Entry deleted successfully!"
echo ""

# Show new count
COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM $TABLE_NAME;")
echo "Remaining entries in $TABLE_NAME: $COUNT"
echo ""
echo "Done! 🚀"
