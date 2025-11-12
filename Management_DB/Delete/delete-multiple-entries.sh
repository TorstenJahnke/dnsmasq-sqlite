#!/bin/bash
# ============================================================================
# Delete MULTIPLE entries from a table (from file)
# ============================================================================
# Usage: ./delete-multiple-entries.sh <database> <table> <input-file>
# ============================================================================

DB_FILE="${1}"
TABLE_NAME="${2}"
INPUT_FILE="${3}"

if [ -z "$DB_FILE" ] || [ -z "$TABLE_NAME" ] || [ -z "$INPUT_FILE" ]; then
    echo "Usage: $0 <database> <table> <input-file>"
    echo ""
    echo "Available tables:"
    echo "  block_regex"
    echo "  block_exact"
    echo "  block_wildcard"
    echo "  fqdn_dns_allow"
    echo "  fqdn_dns_block"
    echo ""
    echo "Example:"
    echo "  $0 blocklist.db block_exact domains-to-delete.txt"
    echo ""
    echo "Input file format (one entry per line):"
    echo "  ads.example.com"
    echo "  tracker.badsite.net"
    echo ""
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "❌ Error: Database '$DB_FILE' not found!"
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "❌ Error: Input file '$INPUT_FILE' not found!"
    exit 1
fi

echo "========================================="
echo "Delete Multiple Entries"
echo "========================================="
echo "Database: $DB_FILE"
echo "Table:    $TABLE_NAME"
echo "Input:    $INPUT_FILE"
echo ""

TOTAL_LINES=$(wc -l < "$INPUT_FILE")
echo "Entries to delete: $TOTAL_LINES"
echo ""

read -p "Are you sure you want to delete these entries? Type 'yes': " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

# Determine column name
if [ "$TABLE_NAME" = "block_regex" ]; then
    COLUMN="Pattern"
else
    COLUMN="Domain"
fi

# Delete entries
DELETED=0
while IFS= read -r ENTRY; do
    # Skip empty lines and comments
    if [ -z "$ENTRY" ] || [[ "$ENTRY" =~ ^# ]]; then
        continue
    fi

    sqlite3 "$DB_FILE" "DELETE FROM $TABLE_NAME WHERE $COLUMN = '$ENTRY';" 2>/dev/null
    if [ $? -eq 0 ]; then
        DELETED=$((DELETED + 1))
    fi
done < "$INPUT_FILE"

echo ""
echo "✅ Deleted $DELETED entries"
echo ""

COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM $TABLE_NAME;")
echo "Remaining entries in $TABLE_NAME: $COUNT"
echo ""
echo "Done! 🚀"
