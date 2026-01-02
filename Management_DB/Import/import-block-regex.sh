#!/bin/bash
# ============================================================================
# Import Script: block_regex (PCRE2 Patterns)
# ============================================================================
# Priority: 1 (HIGHEST)
# Target: IPSetTerminate (direct blocking)
# Usage: ./import-block-regex.sh <database> <input-file>
# Version: 4.3 - Added ANALYZE for query optimization
# ============================================================================

DB_FILE="${1}"
INPUT_FILE="${2}"

if [ -z "$DB_FILE" ] || [ -z "$INPUT_FILE" ]; then
    echo "Usage: $0 <database> <input-file>"
    echo ""
    echo "Example:"
    echo "  $0 blocklist.db patterns.txt"
    echo ""
    echo "Input file format (one pattern per line):"
    echo "  ^ad[sz]?[0-9]*\..*$"
    echo "  ^tracker[0-9]+\..*$"
    echo "  .*\.doubleclick\.net$"
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
echo "Import: block_regex"
echo "========================================="
echo "Database: $DB_FILE"
echo "Input:    $INPUT_FILE"
echo ""

# Count lines
TOTAL_LINES=$(wc -l < "$INPUT_FILE")
echo "Total patterns to import: $TOTAL_LINES"
echo ""

# Start import
START_TIME=$(date +%s)

# Pre-process: Remove empty lines and comments
echo "Pre-processing patterns..."
TEMP_FILE=$(mktemp)
# Trap to ensure temp file cleanup on error
trap "rm -f '$TEMP_FILE'" EXIT

sed 's/^[[:space:]]*//;s/[[:space:]]*$//' < "$INPUT_FILE" | \
    grep -v '^#' | \
    grep -v '^$' > "$TEMP_FILE"

sqlite3 "$DB_FILE" <<EOF
-- Use transaction for speed (100x faster!)
BEGIN TRANSACTION;

-- Import patterns
.mode list
.separator "\n"

-- CRITICAL FIX v4.1: Create temp table BEFORE import
CREATE TEMP TABLE temp_import_block_regex (Pattern TEXT);

-- Read from file and insert into temp table
.import '${TEMP_FILE}' temp_import_block_regex

-- Copy to actual table (ignore duplicates)
INSERT OR IGNORE INTO block_regex (Pattern)
SELECT DISTINCT TRIM(Pattern) FROM temp_import_block_regex
WHERE Pattern IS NOT NULL
  AND Pattern != ''
  AND LENGTH(TRIM(Pattern)) > 0;

-- Drop temp table
DROP TABLE temp_import_block_regex;

COMMIT;

-- Show statistics
SELECT 'Imported: ' || COUNT(*) || ' regex patterns' FROM block_regex;
EOF

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "Import completed in ${ELAPSED} seconds"
echo ""

# OPTIMIZATION v4.3: Run ANALYZE to update query statistics
echo "Updating query statistics (ANALYZE)..."
sqlite3 "$DB_FILE" "ANALYZE block_regex; PRAGMA optimize;"

# Show current count
CURRENT_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM block_regex;")
echo "Total patterns in block_regex: $CURRENT_COUNT"
echo ""
echo "Done!"
