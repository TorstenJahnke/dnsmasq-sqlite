#!/bin/bash
# ============================================================================
# Import Script: block_regex (PCRE2 Patterns)
# ============================================================================
# Priority: 1 (HIGHEST)
# Target: IPSetTerminate (direct blocking)
# Usage: ./import-block-regex.sh <database> <input-file>
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
    echo "❌ Error: Database '$DB_FILE' not found!"
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "❌ Error: Input file '$INPUT_FILE' not found!"
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

sqlite3 "$DB_FILE" <<EOF
-- Use transaction for speed (100x faster!)
BEGIN TRANSACTION;

-- Import patterns
.mode list
.separator "\n"

-- Read from file and insert
-- INSERT OR IGNORE: Skip duplicates automatically (PRIMARY KEY prevents duplicates)
.import '${INPUT_FILE}' temp_import_block_regex

-- Copy to actual table (ignore duplicates)
INSERT OR IGNORE INTO block_regex (Pattern)
SELECT DISTINCT Pattern FROM temp_import_block_regex
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
echo "✅ Import completed in ${ELAPSED} seconds"
echo ""

# Show current count
CURRENT_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM block_regex;")
echo "Total patterns in block_regex: $CURRENT_COUNT"
echo ""
echo "Done! 🚀"
