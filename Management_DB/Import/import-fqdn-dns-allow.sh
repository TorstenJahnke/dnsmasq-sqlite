#!/bin/bash
# ============================================================================
# Import Script: fqdn_dns_allow (DNS Whitelist)
# ============================================================================
# Priority: 4
# Target: IPSetDNSAllow (forward to real DNS servers)
# Use case: Whitelist domains that would otherwise be blocked
# Usage: ./import-fqdn-dns-allow.sh <database> <input-file>
# Version: 4.1 - Added temp file cleanup trap
# ============================================================================

DB_FILE="${1}"
INPUT_FILE="${2}"

if [ -z "$DB_FILE" ] || [ -z "$INPUT_FILE" ]; then
    echo "Usage: $0 <database> <input-file>"
    echo ""
    echo "Example:"
    echo "  $0 blocklist.db allow-domains.txt"
    echo ""
    echo "Input file format (one domain per line):"
    echo "  trusted.xyz"
    echo "  allowed-site.com"
    echo "  safe.tracking.com"
    echo ""
    echo "Use case - Whitelist override:"
    echo "  If *.xyz is blocked in fqdn_dns_block,"
    echo "  but trusted.xyz is in fqdn_dns_allow,"
    echo "  then trusted.xyz will be allowed!"
    echo ""
    echo "Priority: fqdn_dns_allow (step 4) is checked BEFORE fqdn_dns_block (step 5)"
    echo ""
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "Error: Database '$DB_FILE' not found!"
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found!"
    exit 1
fi

echo "========================================="
echo "Import: fqdn_dns_allow (Whitelist)"
echo "========================================="
echo "Database: $DB_FILE"
echo "Input:    $INPUT_FILE"
echo ""

TOTAL_LINES=$(wc -l < "$INPUT_FILE")
echo "Total whitelist domains to import: $TOTAL_LINES"
echo ""

START_TIME=$(date +%s)

TEMP_FILE=$(mktemp)
# CRITICAL FIX v4.1: Trap to ensure temp file cleanup on error
trap "rm -f '$TEMP_FILE'" EXIT

tr '[:upper:]' '[:lower:]' < "$INPUT_FILE" | \
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
    grep -v '^#' | \
    grep -v '^$' > "$TEMP_FILE"

sqlite3 "$DB_FILE" <<EOF
BEGIN TRANSACTION;

.mode list
.separator "\n"

CREATE TEMP TABLE temp_import_fqdn_dns_allow (Domain TEXT);
.import '${TEMP_FILE}' temp_import_fqdn_dns_allow

INSERT OR IGNORE INTO fqdn_dns_allow (Domain)
SELECT DISTINCT LOWER(TRIM(Domain)) FROM temp_import_fqdn_dns_allow
WHERE Domain IS NOT NULL
  AND Domain != ''
  AND LENGTH(TRIM(Domain)) > 0
  AND Domain NOT LIKE '#%'
  AND Domain LIKE '%.%';

DROP TABLE temp_import_fqdn_dns_allow;

COMMIT;

SELECT 'Imported into fqdn_dns_allow: ' || COUNT(*) || ' domains' FROM fqdn_dns_allow;
EOF

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "Import completed in ${ELAPSED} seconds"
echo ""

CURRENT_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM fqdn_dns_allow;")
echo "Total whitelisted domains: $CURRENT_COUNT"
echo ""
echo "Done!"
