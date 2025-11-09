#!/bin/bash
# Simple script to add regex patterns to database
# Usage: ./add-regex-patterns.sh patterns.txt [database.db] [ipv4] [ipv6]

set -e

PATTERN_FILE="${1}"
DB_FILE="${2:-blocklist.db}"
IPV4="${3:-0.0.0.0}"
IPV6="${4:-::}"

if [ -z "$PATTERN_FILE" ]; then
    echo "Usage: $0 <patterns.txt> [database.db] [ipv4] [ipv6]"
    echo ""
    echo "Example:"
    echo "  $0 my-patterns.txt blocklist.db 10.0.1.1 fd00:1::1"
    echo ""
    echo "patterns.txt format (one regex per line):"
    echo "  ^ads\\..*"
    echo "  .*\\.tracker\\.com$"
    echo "  ^(www|cdn)\\.analytics\\."
    exit 1
fi

if [ ! -f "$PATTERN_FILE" ]; then
    echo "❌ Pattern file not found: $PATTERN_FILE"
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "❌ Database not found: $DB_FILE"
    echo "Create it first: ./createdb-regex.sh $DB_FILE"
    exit 1
fi

echo "========================================"
echo "Adding Regex Patterns"
echo "========================================"
echo "Patterns: $PATTERN_FILE"
echo "Database: $DB_FILE"
echo "IP-Set:   $IPV4 / $IPV6"
echo ""

# Count and import
added=0
skipped=0

while IFS= read -r pattern || [ -n "$pattern" ]; do
    # Skip empty lines
    [[ -z "$pattern" ]] && { ((skipped++)); continue; }

    # Skip comments
    [[ "$pattern" =~ ^[[:space:]]*# ]] && { ((skipped++)); continue; }

    # Escape single quotes for SQL
    pattern_escaped="${pattern//\'/\'\'}"
    ipv4_escaped="${IPV4//\'/\'\'}"
    ipv6_escaped="${IPV6//\'/\'\'}"

    # Insert into DB
    sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO domain_regex (Pattern, IPv4, IPv6) VALUES ('$pattern_escaped', '$ipv4_escaped', '$ipv6_escaped');" 2>/dev/null

    ((added++))
done < "$PATTERN_FILE"

echo "✅ Done!"
echo "   Added:   $added patterns"
echo "   Skipped: $skipped lines (empty/comments)"
echo ""

# Show what's in DB
total=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM domain_regex;")
echo "Total regex patterns in DB: $total"
