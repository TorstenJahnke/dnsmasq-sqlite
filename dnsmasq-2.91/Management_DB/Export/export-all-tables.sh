#!/bin/bash
# ============================================================================
# Export ALL tables to separate files
# ============================================================================
# Usage: ./export-all-tables.sh <database> [output-dir]
# ============================================================================

DB_FILE="${1}"
OUTPUT_DIR="${2:-./exports}"

if [ -z "$DB_FILE" ]; then
    echo "Usage: $0 <database> [output-dir]"
    echo ""
    echo "Example:"
    echo "  $0 blocklist.db ./backup"
    echo ""
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "❌ Error: Database '$DB_FILE' not found!"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "========================================="
echo "Export All Tables"
echo "========================================="
echo "Database: $DB_FILE"
echo "Output:   $OUTPUT_DIR"
echo ""

# Export each table
for TABLE in block_regex block_exact block_wildcard fqdn_dns_allow fqdn_dns_block; do
    OUTPUT_FILE="$OUTPUT_DIR/${TABLE}.txt"
    COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM $TABLE;")

    echo "Exporting $TABLE ($COUNT entries)..."

    if [ "$TABLE" = "block_regex" ]; then
        sqlite3 "$DB_FILE" "SELECT Pattern FROM $TABLE ORDER BY Pattern;" > "$OUTPUT_FILE"
    else
        sqlite3 "$DB_FILE" "SELECT Domain FROM $TABLE ORDER BY Domain;" > "$OUTPUT_FILE"
    fi

    echo "  ✅ Saved to: $OUTPUT_FILE"
done

echo ""
echo "✅ Export completed!"
echo ""
echo "Files created:"
ls -lh "$OUTPUT_DIR"/*.txt
echo ""
echo "Done! 🚀"
