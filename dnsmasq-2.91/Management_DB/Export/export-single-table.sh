#!/bin/bash
# ============================================================================
# Export SINGLE table to file
# ============================================================================
# Usage: ./export-single-table.sh <database> <table-name> <output-file>
# ============================================================================

DB_FILE="${1}"
TABLE_NAME="${2}"
OUTPUT_FILE="${3}"

if [ -z "$DB_FILE" ] || [ -z "$TABLE_NAME" ] || [ -z "$OUTPUT_FILE" ]; then
    echo "Usage: $0 <database> <table-name> <output-file>"
    echo ""
    echo "Available tables:"
    echo "  block_regex"
    echo "  block_exact"
    echo "  block_wildcard"
    echo "  fqdn_dns_allow"
    echo "  fqdn_dns_block"
    echo ""
    echo "Example:"
    echo "  $0 blocklist.db block_exact exported-domains.txt"
    echo ""
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "❌ Error: Database '$DB_FILE' not found!"
    exit 1
fi

echo "========================================="
echo "Export Single Table"
echo "========================================="
echo "Database: $DB_FILE"
echo "Table:    $TABLE_NAME"
echo "Output:   $OUTPUT_FILE"
echo ""

# Check if table exists
TABLE_EXISTS=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$TABLE_NAME';")

if [ "$TABLE_EXISTS" -eq 0 ]; then
    echo "❌ Error: Table '$TABLE_NAME' does not exist!"
    exit 1
fi

# Get count
COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM $TABLE_NAME;")
echo "Exporting $COUNT entries..."
echo ""

# Export
if [ "$TABLE_NAME" = "block_regex" ]; then
    sqlite3 "$DB_FILE" "SELECT Pattern FROM $TABLE_NAME ORDER BY Pattern;" > "$OUTPUT_FILE"
else
    sqlite3 "$DB_FILE" "SELECT Domain FROM $TABLE_NAME ORDER BY Domain;" > "$OUTPUT_FILE"
fi

echo "✅ Export completed!"
echo ""
echo "File: $OUTPUT_FILE"
ls -lh "$OUTPUT_FILE"
echo ""
echo "Done! 🚀"
