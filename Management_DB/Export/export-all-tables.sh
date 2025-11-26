#!/bin/bash
# ============================================================================
# Export ALL tables to separate files
# ============================================================================
# Usage: ./export-all-tables.sh <database> [output-dir]
# Version: 4.1 - Added domain_alias and ip_rewrite tables
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
    echo "Error: Database '$DB_FILE' not found!"
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

# Export each table/view
TABLES="block_regex block_exact block_wildcard fqdn_dns_allow fqdn_dns_block domain_alias ip_rewrite_v4 ip_rewrite_v6"

for TABLE in $TABLES; do
    OUTPUT_FILE="$OUTPUT_DIR/${TABLE}.txt"

    # Check if table/view exists
    EXISTS=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sqlite_master WHERE (type='table' OR type='view') AND name='$TABLE';")
    if [ "$EXISTS" -eq 0 ]; then
        echo "Skipping $TABLE (not found)"
        continue
    fi

    COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM $TABLE;")
    echo "Exporting $TABLE ($COUNT entries)..."

    case "$TABLE" in
        block_regex)
            sqlite3 "$DB_FILE" "SELECT Pattern FROM $TABLE ORDER BY Pattern;" > "$OUTPUT_FILE"
            ;;
        domain_alias)
            sqlite3 "$DB_FILE" "SELECT Source_Domain || ',' || Target_Domain FROM $TABLE ORDER BY Source_Domain;" > "$OUTPUT_FILE"
            ;;
        ip_rewrite_v4)
            sqlite3 "$DB_FILE" "SELECT Source_IPv4 || ',' || Target_IPv4 FROM $TABLE ORDER BY Source_IPv4;" > "$OUTPUT_FILE"
            ;;
        ip_rewrite_v6)
            sqlite3 "$DB_FILE" "SELECT Source_IPv6 || ',' || Target_IPv6 FROM $TABLE ORDER BY Source_IPv6;" > "$OUTPUT_FILE"
            ;;
        *)
            sqlite3 "$DB_FILE" "SELECT Domain FROM $TABLE ORDER BY Domain;" > "$OUTPUT_FILE"
            ;;
    esac

    echo "  Saved to: $OUTPUT_FILE"
done

echo ""
echo "Export completed!"
echo ""
echo "Files created:"
ls -lh "$OUTPUT_DIR"/*.txt 2>/dev/null || echo "  (no files)"
echo ""
echo "Done!"
