#!/bin/bash
# Import regex patterns to SQLite - Schema v4.0
# Usage: ./add-regex.sh <database.db> <patterns.txt>
#
# Format of patterns.txt:
#   ^ad[sz]?[0-9]*\..*$
#   .*\.tracker\.com$
#   ^analytics?\..*
#
# IMPORTANT: Termination IPs are configured in dnsmasq.conf, NOT in database!
#            ipset-terminate-v4=127.0.0.1,0.0.0.0
#            ipset-terminate-v6=::1,::
#
# Patterns use PCRE2 syntax (Perl-compatible regex).

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <database.db> <patterns.txt>"
    echo ""
    echo "Examples:"
    echo "  $0 blocklist.db regex-patterns.txt"
    echo "  $0 blocklist.db < patterns.txt"
    echo ""
    echo "Schema v4.0: Imports regex patterns only (no IPv4/IPv6 columns!)."
    echo "Termination IPs configured in dnsmasq.conf:"
    echo "  ipset-terminate-v4=127.0.0.1,0.0.0.0"
    echo "  ipset-terminate-v6=::1,::"
    echo ""
    echo "Pattern syntax: PCRE2 (Perl-compatible)"
    echo "  ^ad[sz]?[0-9]*\\..*$  - matches ads.example.com, ad1.test.com"
    echo "  .*\\.tracker\\.com$    - matches anything ending in .tracker.com"
    exit 1
fi

DB_FILE="$1"
PATTERN_FILE="${2:-/dev/stdin}"

if [ ! -f "$DB_FILE" ]; then
    echo "Error: Database $DB_FILE not found!"
    echo "Create it first with ./createdb-optimized.sh"
    exit 1
fi

echo "========================================"
echo "Regex Patterns Import - Schema v4.0"
echo "========================================"
echo "Database: $DB_FILE"
echo "Input:    $PATTERN_FILE"
echo "Table:    block_regex"
echo ""
echo "NOTE: Termination IPs configured in dnsmasq.conf (ipset-terminate-v4/v6)"
echo ""

TEMP_SQL=$(mktemp)
trap "rm -f $TEMP_SQL" EXIT

echo "BEGIN TRANSACTION;" > "$TEMP_SQL"

COUNT=0
SKIPPED=0

echo "Processing regex patterns..."

while IFS= read -r pattern || [ -n "$pattern" ]; do
    # Skip empty lines
    [[ -z "$pattern" ]] && { ((SKIPPED++)); continue; }

    # Skip comments
    [[ "$pattern" =~ ^[[:space:]]*# ]] && { ((SKIPPED++)); continue; }

    # Remove leading/trailing whitespace
    pattern=$(echo "$pattern" | xargs)

    # Skip if empty after trimming
    [[ -z "$pattern" ]] && { ((SKIPPED++)); continue; }

    # Escape single quotes for SQL
    pattern_escaped="${pattern//\'/\'\'}"

    # Insert pattern (IPs come from IPSetTerminate config!)
    echo "INSERT OR REPLACE INTO block_regex (Pattern) VALUES ('$pattern_escaped');" >> "$TEMP_SQL"
    COUNT=$((COUNT + 1))

    # Progress indicator
    if [ $((COUNT % 10000)) -eq 0 ]; then
        echo "  Processed: $COUNT patterns..."
    fi
done < "$PATTERN_FILE"

echo "COMMIT;" >> "$TEMP_SQL"

# Import to database
echo ""
echo "Importing $COUNT patterns to block_regex..."
sqlite3 "$DB_FILE" < "$TEMP_SQL"

echo ""
echo "✅ Import complete!"
echo ""
echo "Statistics:"
echo "  Imported:     $COUNT patterns"
echo "  Skipped:      $SKIPPED lines"
echo "  Target Table: block_regex"
echo ""
echo "Termination IPs configured in dnsmasq.conf:"
echo "  ipset-terminate-v4=127.0.0.1,0.0.0.0"
echo "  ipset-terminate-v6=::1,::"
echo ""

# Show table stats
echo "Table stats:"
sqlite3 "$DB_FILE" <<EOF
.mode line
SELECT COUNT(*) as total_patterns FROM block_regex;
EOF

echo ""
echo "⚠️  WARNING: Regex patterns will be compiled at dnsmasq startup."
echo "   Large pattern counts (>100k) may impact startup time and RAM usage!"
echo ""
echo "Done!"
