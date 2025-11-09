#!/bin/bash
# Import DNS block list (blacklist) to forward domains to blocker DNS server
# Usage: ./add-dns-block.sh <blocker-server-ip> <database.db> [block-list.txt]
#
# Format of block-list.txt:
#   *.xyz
#   *.tk
#   ads.example.com
#
# Server can include port: "10.0.0.1" or "10.0.0.1#5353"

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <blocker-dns-server> <database.db> [block-list.txt]"
    echo ""
    echo "Examples:"
    echo "  $0 10.0.0.1 blocklist.db block-list.txt"
    echo "  $0 127.0.0.1#5353 blocklist.db block-list.txt"
    echo "  $0 10.0.0.1 blocklist.db < block-list.txt"
    echo ""
    echo "This imports domains to domain_dns_block table."
    echo "Domains in this table are forwarded to the specified blocker DNS server."
    echo ""
    echo "Use case: Forward all .xyz domains → blocker DNS at 10.0.0.1"
    echo "          (blocker DNS returns 0.0.0.0 for everything)"
    exit 1
fi

BLOCKER_SERVER="$1"
DB_FILE="$2"
INPUT_FILE="${3:-/dev/stdin}"

if [ ! -f "$DB_FILE" ]; then
    echo "Error: Database $DB_FILE not found!"
    echo "Create it first with ./createdb-optimized.sh"
    exit 1
fi

echo "========================================"
echo "DNS Block List (Blacklist) Import"
echo "========================================"
echo "Blocker:  $BLOCKER_SERVER"
echo "Database: $DB_FILE"
echo "Input:    $INPUT_FILE"
echo ""

TEMP_SQL=$(mktemp)
trap "rm -f $TEMP_SQL" EXIT

echo "BEGIN TRANSACTION;" > "$TEMP_SQL"

COUNT=0

while IFS= read -r domain; do
    # Skip empty lines and comments
    [[ -z "$domain" || "$domain" =~ ^# ]] && continue

    # Remove leading/trailing whitespace
    domain=$(echo "$domain" | xargs)

    # Skip invalid domains
    if [ -z "$domain" ]; then
        continue
    fi

    # Insert into domain_dns_block
    echo "INSERT OR REPLACE INTO domain_dns_block (Domain, Server) VALUES ('$domain', '$BLOCKER_SERVER');" >> "$TEMP_SQL"
    COUNT=$((COUNT + 1))

    # Progress indicator
    if [ $((COUNT % 10000)) -eq 0 ]; then
        echo "  Processed: $COUNT domains..."
    fi
done < "$INPUT_FILE"

echo "COMMIT;" >> "$TEMP_SQL"

# Import to database
echo "Importing $COUNT domains to domain_dns_block..."
sqlite3 "$DB_FILE" < "$TEMP_SQL"

echo ""
echo "✅ Import complete!"
echo ""
echo "Statistics:"
echo "  Imported:       $COUNT domains"
echo "  Blocker Server: $BLOCKER_SERVER"
echo ""

# Show table stats
echo "DNS Block table stats:"
sqlite3 "$DB_FILE" <<EOF
SELECT
    COUNT(*) as total_domains,
    COUNT(DISTINCT Server) as unique_servers
FROM domain_dns_block;
EOF

echo ""
echo "Lookup order:"
echo "  1. domain_dns_allow  (whitelist - checked first!)"
echo "  2. domain_dns_block  (blacklist - checked second)"
echo "  3. domain_exact      (termination)"
echo "  4. domain            (termination, wildcard)"
echo "  5. domain_regex      (termination, regex)"
echo "  6. Normal upstream   (default DNS)"
echo ""
echo "Example queries:"
echo "  dnsmasq --test --db-file=$DB_FILE"
echo "  dig @127.0.0.1 <domain>"
echo ""
