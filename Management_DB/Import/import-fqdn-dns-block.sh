#!/bin/bash
# ============================================================================
# Import Script: fqdn_dns_block (DNS Blacklist)
# ============================================================================
# Priority: 5 (LOWEST)
# Target: IPSetDNSBlock (forward to DNS blocker)
# Use case: Block entire TLDs or domain patterns
# Usage: ./import-fqdn-dns-block.sh <database> <input-file>
# Version: 4.1 - Added temp file cleanup trap
# ============================================================================

DB_FILE="${1}"
INPUT_FILE="${2}"

if [ -z "$DB_FILE" ] || [ -z "$INPUT_FILE" ]; then
    echo "Usage: $0 <database> <input-file>"
    echo ""
    echo "Example:"
    echo "  $0 blocklist.db blacklist-domains.txt"
    echo ""
    echo "Input file format (one domain per line):"
    echo "  malware.com"
    echo "  suspicious-tld.xyz"
    echo "  phishing-site.tk"
    echo ""
    echo "Use case - TLD blocking:"
    echo "  *.xyz -> Blocks all .xyz domains"
    echo "  *.tk -> Blocks all .tk domains"
    echo ""
    echo "Priority: Checked AFTER fqdn_dns_allow (step 5 after step 4)"
    echo "  -> fqdn_dns_allow can override this table!"
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
echo "Import: fqdn_dns_block (Blacklist)"
echo "========================================="
echo "Database: $DB_FILE"
echo "Input:    $INPUT_FILE"
echo ""

TOTAL_LINES=$(wc -l < "$INPUT_FILE")
echo "Total blacklist domains to import: $TOTAL_LINES"
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

CREATE TEMP TABLE temp_import_fqdn_dns_block (Domain TEXT);
.import '${TEMP_FILE}' temp_import_fqdn_dns_block

INSERT OR IGNORE INTO fqdn_dns_block (Domain)
SELECT DISTINCT LOWER(TRIM(Domain)) FROM temp_import_fqdn_dns_block
WHERE Domain IS NOT NULL
  AND Domain != ''
  AND LENGTH(TRIM(Domain)) > 0
  AND Domain NOT LIKE '#%'
  AND Domain LIKE '%.%';

DROP TABLE temp_import_fqdn_dns_block;

COMMIT;

SELECT 'Imported into fqdn_dns_block: ' || COUNT(*) || ' domains' FROM fqdn_dns_block;
EOF

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "Import completed in ${ELAPSED} seconds"
echo ""

CURRENT_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM fqdn_dns_block;")
echo "Total blacklisted domains: $CURRENT_COUNT"
echo ""
echo "Done!"
