#!/bin/bash
# ============================================================================
# Show database statistics (entry counts, sizes, etc.)
# ============================================================================
# Usage: ./search-statistics.sh <database>
# ============================================================================

DB_FILE="${1}"

if [ -z "$DB_FILE" ]; then
    echo "Usage: $0 <database>"
    echo ""
    echo "Example:"
    echo "  $0 blocklist.db"
    echo ""
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "❌ Error: Database '$DB_FILE' not found!"
    exit 1
fi

echo "========================================="
echo "Database Statistics"
echo "========================================="
echo "Database: $DB_FILE"
echo ""

# File size
DB_SIZE=$(stat -c%s "$DB_FILE" 2>/dev/null || stat -f%z "$DB_FILE" 2>/dev/null)
DB_SIZE_MB=$((DB_SIZE / 1024 / 1024))
DB_SIZE_GB=$((DB_SIZE / 1024 / 1024 / 1024))

if [ $DB_SIZE_GB -gt 0 ]; then
    echo "Database size: ${DB_SIZE_GB} GB"
else
    echo "Database size: ${DB_SIZE_MB} MB"
fi
echo ""

# Table counts
echo "Entry counts per table:"
echo "----------------------------------------"

sqlite3 "$DB_FILE" <<'EOF' | column -t -s '|'
.mode list
.separator '|'

SELECT 'block_regex', COUNT(*), 'Priority 1 (HIGHEST) → IPSetTerminate' FROM block_regex
UNION ALL
SELECT 'block_exact', COUNT(*), 'Priority 2 → IPSetTerminate' FROM block_exact
UNION ALL
SELECT 'block_wildcard', COUNT(*), 'Priority 3 → IPSetDNSBlock' FROM block_wildcard
UNION ALL
SELECT 'fqdn_dns_allow', COUNT(*), 'Priority 4 → IPSetDNSAllow (Whitelist)' FROM fqdn_dns_allow
UNION ALL
SELECT 'fqdn_dns_block', COUNT(*), 'Priority 5 → IPSetDNSBlock (Blacklist)' FROM fqdn_dns_block;
EOF

echo ""

# Total
TOTAL=$(sqlite3 "$DB_FILE" "SELECT
    (SELECT COUNT(*) FROM block_regex) +
    (SELECT COUNT(*) FROM block_exact) +
    (SELECT COUNT(*) FROM block_wildcard) +
    (SELECT COUNT(*) FROM fqdn_dns_allow) +
    (SELECT COUNT(*) FROM fqdn_dns_block);")

echo "Total entries: $TOTAL"
echo ""

# Index information
echo "Index statistics:"
echo "----------------------------------------"
INDEX_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%';")
echo "Total indexes: $INDEX_COUNT"
echo ""

# Show indexes
sqlite3 "$DB_FILE" <<'EOF'
.mode column
.headers on
.width 35 30

SELECT name as "Index Name", tbl_name as "Table"
FROM sqlite_master
WHERE type='index'
  AND name NOT LIKE 'sqlite_%'
ORDER BY tbl_name, name;
EOF

echo ""

# PRAGMA information
echo "SQLite configuration:"
echo "----------------------------------------"

sqlite3 "$DB_FILE" <<'EOF' | column -t -s '|'
.mode list
.separator '|'

SELECT 'journal_mode', (SELECT journal_mode FROM pragma_journal_mode)
UNION ALL
SELECT 'page_size', (SELECT page_size FROM pragma_page_size)
UNION ALL
SELECT 'cache_size', (SELECT cache_size FROM pragma_cache_size)
UNION ALL
SELECT 'synchronous', (SELECT synchronous FROM pragma_synchronous)
UNION ALL
SELECT 'locking_mode', (SELECT locking_mode FROM pragma_locking_mode)
UNION ALL
SELECT 'query_only', (SELECT query_only FROM pragma_query_only);
EOF

echo ""

# Schema version
echo "Schema information:"
echo "----------------------------------------"

sqlite3 "$DB_FILE" <<'EOF' | column -t -s '|'
.mode list
.separator '|'

SELECT key, value
FROM db_metadata
WHERE key IN ('schema_version', 'optimized', 'features')
ORDER BY key;
EOF

echo ""
echo "Done! 🚀"
