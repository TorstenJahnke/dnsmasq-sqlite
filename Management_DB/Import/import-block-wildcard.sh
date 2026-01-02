#!/bin/bash
# ============================================================================
# Import Script: block_wildcard (Wildcard Domain Match)
# ============================================================================
# Priority: 3
# Target: IPSetDNSBlock (forward to DNS blocker)
# Match: Domain AND all subdomains!
# Usage: ./import-block-wildcard.sh <database> <input-file>
# Version: 4.3 - Added ANALYZE for query optimization
# ============================================================================

DB_FILE="${1}"
INPUT_FILE="${2}"

if [ -z "$DB_FILE" ] || [ -z "$INPUT_FILE" ]; then
    echo "Usage: $0 <database> <input-file>"
    echo ""
    echo "Example:"
    echo "  $0 blocklist.db wildcard-domains.txt"
    echo ""
    echo "Input file format (one domain per line):"
    echo "  privacy.com"
    echo "  telemetry.microsoft.com"
    echo "  tracking.company.net"
    echo ""
    echo "Wildcard matching (includes ALL subdomains!):"
    echo "  privacy.com -> privacy.com AND *.privacy.com BLOCKED"
    echo "  tracking.company.net -> tracking.company.net AND *.tracking.company.net BLOCKED"
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
echo "Import: block_wildcard"
echo "========================================="
echo "Database: $DB_FILE"
echo "Input:    $INPUT_FILE"
echo ""

TOTAL_LINES=$(wc -l < "$INPUT_FILE")
echo "Total wildcard domains to import: $TOTAL_LINES"
echo ""

START_TIME=$(date +%s)

# Pre-process
echo "Pre-processing domains..."
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

CREATE TEMP TABLE temp_import_block_wildcard (Domain TEXT);
.import '${TEMP_FILE}' temp_import_block_wildcard

INSERT OR IGNORE INTO block_wildcard (Domain)
SELECT DISTINCT LOWER(TRIM(Domain)) FROM temp_import_block_wildcard
WHERE Domain IS NOT NULL
  AND Domain != ''
  AND LENGTH(TRIM(Domain)) > 0
  AND Domain NOT LIKE '#%'
  AND Domain LIKE '%.%';

DROP TABLE temp_import_block_wildcard;

COMMIT;

SELECT 'Imported into block_wildcard: ' || COUNT(*) || ' domains' FROM block_wildcard;
EOF

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "Import completed in ${ELAPSED} seconds"
echo ""

# OPTIMIZATION v4.3: Run ANALYZE to update query statistics
echo "Updating query statistics (ANALYZE)..."
sqlite3 "$DB_FILE" "ANALYZE block_wildcard; PRAGMA optimize;"

CURRENT_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM block_wildcard;")
echo "Total wildcard domains: $CURRENT_COUNT"
echo ""
echo "Done!"
