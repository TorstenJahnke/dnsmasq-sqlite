#!/bin/bash
# Import regex patterns from file into SQLite database
# Usage: ./import-regex.sh [pattern-file] [database.db] [ipv4] [ipv6]

set -e

PATTERN_FILE="${1:-regex-patterns.txt}"
DB_FILE="${2:-blocklist.db}"
DEFAULT_IPV4="${3:-0.0.0.0}"
DEFAULT_IPV6="${4:-::}"
BATCH_SIZE="${BATCH_SIZE:-10000}"

if [ ! -f "$PATTERN_FILE" ]; then
    echo "❌ Error: Pattern file not found: $PATTERN_FILE"
    echo ""
    echo "Usage: $0 [pattern-file] [database.db] [ipv4] [ipv6]"
    echo ""
    echo "Example:"
    echo "  $0 my-patterns.txt blocklist.db 10.0.0.1 fd00::1"
    echo ""
    echo "Pattern file format (one pattern per line):"
    echo "  ^ads\\..*"
    echo "  .*\\.tracker\\.com$"
    echo "  ^(www|cdn)\\.(ads|tracker)\\."
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "❌ Error: Database not found: $DB_FILE"
    echo "Create it first: ./createdb-regex.sh $DB_FILE"
    exit 1
fi

echo "========================================"
echo "Regex Pattern Import"
echo "========================================"
echo "Pattern file: $PATTERN_FILE"
echo "Database:     $DB_FILE"
echo "IPv4:         $DEFAULT_IPV4"
echo "IPv6:         $DEFAULT_IPV6"
echo "Batch size:   $BATCH_SIZE"
echo ""

# Count patterns
total=$(wc -l < "$PATTERN_FILE")
echo "Total patterns: $total"
echo ""

if [ $total -gt 100000 ]; then
    echo "⚠️  WARNING: $total patterns will use significant RAM!"
    echo "   Each pattern is compiled with PCRE at runtime"
    echo "   Consider splitting into smaller files if you have issues"
    echo ""
fi

# Import with batch transactions
echo "Importing patterns..."
imported=0
skipped=0
batch=0

sqlite3 "$DB_FILE" <<EOF
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
BEGIN TRANSACTION;
EOF

while IFS= read -r pattern || [ -n "$pattern" ]; do
    # Skip empty lines and comments
    [[ -z "$pattern" ]] && continue
    [[ "$pattern" =~ ^[[:space:]]*# ]] && continue

    # Escape single quotes for SQL
    pattern_escaped="${pattern//\'/\'\'}"

    # Insert pattern
    sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO domain_regex (Pattern, IPv4, IPv6) VALUES ('$pattern_escaped', '$DEFAULT_IPV4', '$DEFAULT_IPV6');"

    ((imported++))
    ((batch++))

    # Commit and start new transaction every BATCH_SIZE patterns
    if [ $((batch % BATCH_SIZE)) -eq 0 ]; then
        sqlite3 "$DB_FILE" "COMMIT; BEGIN TRANSACTION;"
        echo "  Imported: $imported / $total patterns..."
    fi
done < "$PATTERN_FILE"

# Final commit
sqlite3 "$DB_FILE" "COMMIT;"

echo ""
echo "========================================"
echo "✅ Import completed!"
echo "========================================"
echo "Imported: $imported patterns"
echo ""

# Show statistics
sqlite3 "$DB_FILE" <<EOF
SELECT 'Total regex patterns: ' || COUNT(*) FROM domain_regex;
SELECT 'Total wildcard domains: ' || COUNT(*) FROM domain;
SELECT 'Total exact domains: ' || COUNT(*) FROM domain_exact;
EOF

echo ""
echo "Test with:"
echo "  dnsmasq -d -p 5353 --db-file=$DB_FILE --db-block-ipv4=$DEFAULT_IPV4 --db-block-ipv6=$DEFAULT_IPV6 --log-queries"
