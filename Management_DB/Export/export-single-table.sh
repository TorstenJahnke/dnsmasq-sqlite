#!/bin/bash
# ============================================================================
# Export SINGLE table to file
# ============================================================================
# Usage: ./export-single-table.sh <database> <table-name> <output-file>
# Version: 4.1 - Added SQL injection protection
# ============================================================================

DB_FILE="${1}"
TABLE_NAME="${2}"
OUTPUT_FILE="${3}"

# Allowed table names (SQL injection protection)
ALLOWED_TABLES="block_regex block_exact block_wildcard fqdn_dns_allow fqdn_dns_block domain_alias ip_rewrite_v4 ip_rewrite_v6"

if [ -z "$DB_FILE" ] || [ -z "$TABLE_NAME" ] || [ -z "$OUTPUT_FILE" ]; then
    echo "Usage: $0 <database> <table-name> <output-file>"
    echo ""
    echo "Available tables:"
    echo "  block_regex"
    echo "  block_exact"
    echo "  block_wildcard"
    echo "  fqdn_dns_allow"
    echo "  fqdn_dns_block"
    echo "  domain_alias"
    echo "  ip_rewrite_v4"
    echo "  ip_rewrite_v6"
    echo ""
    echo "Example:"
    echo "  $0 blocklist.db block_exact exported-domains.txt"
    echo ""
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "Error: Database '$DB_FILE' not found!"
    exit 1
fi

# SECURITY FIX v4.1: Validate table name against whitelist (SQL injection protection)
TABLE_VALID=0
for allowed in $ALLOWED_TABLES; do
    if [ "$TABLE_NAME" = "$allowed" ]; then
        TABLE_VALID=1
        break
    fi
done

if [ "$TABLE_VALID" -eq 0 ]; then
    echo "Error: Invalid table name '$TABLE_NAME'!"
    echo "Allowed tables: $ALLOWED_TABLES"
    exit 1
fi

echo "========================================="
echo "Export Single Table"
echo "========================================="
echo "Database: $DB_FILE"
echo "Table:    $TABLE_NAME"
echo "Output:   $OUTPUT_FILE"
echo ""

# Check if table/view exists
TABLE_EXISTS=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sqlite_master WHERE (type='table' OR type='view') AND name='$TABLE_NAME';")

if [ "$TABLE_EXISTS" -eq 0 ]; then
    echo "Error: Table or view '$TABLE_NAME' does not exist!"
    exit 1
fi

# Get count
COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM $TABLE_NAME;")
echo "Exporting $COUNT entries..."
echo ""

# Export based on table type
case "$TABLE_NAME" in
    block_regex)
        sqlite3 "$DB_FILE" "SELECT Pattern FROM $TABLE_NAME ORDER BY Pattern;" > "$OUTPUT_FILE"
        ;;
    domain_alias)
        sqlite3 "$DB_FILE" "SELECT Source_Domain || ',' || Target_Domain FROM $TABLE_NAME ORDER BY Source_Domain;" > "$OUTPUT_FILE"
        ;;
    ip_rewrite_v4)
        sqlite3 "$DB_FILE" "SELECT Source_IPv4 || ',' || Target_IPv4 FROM $TABLE_NAME ORDER BY Source_IPv4;" > "$OUTPUT_FILE"
        ;;
    ip_rewrite_v6)
        sqlite3 "$DB_FILE" "SELECT Source_IPv6 || ',' || Target_IPv6 FROM $TABLE_NAME ORDER BY Source_IPv6;" > "$OUTPUT_FILE"
        ;;
    *)
        sqlite3 "$DB_FILE" "SELECT Domain FROM $TABLE_NAME ORDER BY Domain;" > "$OUTPUT_FILE"
        ;;
esac

echo "Export completed!"
echo ""
echo "File: $OUTPUT_FILE"
ls -lh "$OUTPUT_FILE"
echo ""
echo "Done!"
