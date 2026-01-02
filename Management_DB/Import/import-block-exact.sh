#!/bin/bash
# ============================================================================
# Import Script: block_exact (Exact Domain Match)
# ============================================================================
# Priority: 2
# Target: IPSetTerminate (direct blocking)
# Match: ONLY exact domain (NO subdomains!)
# Usage: ./import-block-exact.sh <database> <input-file>
# Version: 4.3 - Optimized for large imports (100M+ domains)
#
# PERFORMANCE NOTES:
# - Uses shell preprocessing (tr/sed) instead of SQL for 2-3x faster import
# - Single transaction is faster than chunked for SQLite (WAL mode)
# - For 100M+ domains, ensure sufficient RAM (2-4GB recommended)
# - Run ANALYZE after import: sqlite3 db.db "ANALYZE;"
# ============================================================================

DB_FILE="${1}"
INPUT_FILE="${2}"

if [ -z "$DB_FILE" ] || [ -z "$INPUT_FILE" ]; then
    echo "Usage: $0 <database> <input-file>"
    echo ""
    echo "Example:"
    echo "  $0 blocklist.db exact-domains.txt"
    echo ""
    echo "Input file format (one domain per line):"
    echo "  ads.example.com"
    echo "  tracker.badsite.net"
    echo "  analytics.evilcorp.com"
    echo ""
    echo "NOTE: Blocks ONLY exact domain, NOT subdomains!"
    echo "  ads.example.com -> BLOCKED"
    echo "  www.ads.example.com -> NOT BLOCKED (use block_wildcard for this)"
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
echo "Import: block_exact"
echo "========================================="
echo "Database: $DB_FILE"
echo "Input:    $INPUT_FILE"
echo ""

# Count lines
TOTAL_LINES=$(wc -l < "$INPUT_FILE")
echo "Total domains to import: $TOTAL_LINES"
echo ""

# Start import
START_TIME=$(date +%s)

# Pre-process: Lowercase and clean domains
echo "Pre-processing domains (lowercase, trim whitespace)..."
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

-- Import to temp table
CREATE TEMP TABLE temp_import_block_exact (Domain TEXT);
.import '${TEMP_FILE}' temp_import_block_exact

-- Insert with duplicate handling
INSERT OR IGNORE INTO block_exact (Domain)
SELECT DISTINCT LOWER(TRIM(Domain)) FROM temp_import_block_exact
WHERE Domain IS NOT NULL
  AND Domain != ''
  AND LENGTH(TRIM(Domain)) > 0
  AND Domain NOT LIKE '#%'  -- Skip comments
  AND Domain LIKE '%.%';    -- Must contain at least one dot

DROP TABLE temp_import_block_exact;

COMMIT;

-- Show statistics
SELECT 'Imported into block_exact: ' || COUNT(*) || ' domains' FROM block_exact;
EOF

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "Import completed in ${ELAPSED} seconds"
echo ""

# OPTIMIZATION v4.3: Run ANALYZE to update query statistics
echo "Updating query statistics (ANALYZE)..."
sqlite3 "$DB_FILE" "ANALYZE block_exact; PRAGMA optimize;"

# Show current count
CURRENT_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM block_exact;")
echo "Total domains in block_exact: $CURRENT_COUNT"
echo ""
echo "Done!"
