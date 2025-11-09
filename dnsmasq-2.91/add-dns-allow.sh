#!/bin/bash
# Import DNS allow list (whitelist) to forward domains to real DNS servers
# Usage: ./add-dns-allow.sh <server-ip> <database.db> [allow-list.txt]
#
# Format of allow-list.txt:
#   trusted-ads.com
#   allowed.tracking.com
#   *.safe-domain.xyz
#
# Server can include port: "8.8.8.8" or "8.8.8.8#5353"

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <dns-server> <database.db> [allow-list.txt]"
    echo ""
    echo "Examples:"
    echo "  $0 8.8.8.8 blocklist.db allow-list.txt"
    echo "  $0 1.1.1.1#5353 blocklist.db allow-list.txt"
    echo "  $0 8.8.8.8 blocklist.db < allow-list.txt"
    echo ""
    echo "This imports domains to domain_dns_allow table."
    echo "Domains in this table are forwarded to the specified DNS server."
    echo ""
    echo "Use case: Block all .xyz domains, but allow trusted.xyz → forward to 8.8.8.8"
    exit 1
fi

SERVER="$1"
DB_FILE="$2"
INPUT_FILE="${3:-/dev/stdin}"

if [ ! -f "$DB_FILE" ]; then
    echo "Error: Database $DB_FILE not found!"
    echo "Create it first with ./createdb-optimized.sh"
    exit 1
fi

echo "========================================"
echo "DNS Allow List (Whitelist) Import"
echo "========================================"
echo "Server:   $SERVER"
echo "Database: $DB_FILE"
echo "Input:    $INPUT_FILE"
echo ""

TEMP_SQL=$(mktemp)
trap "rm -f $TEMP_SQL" EXIT

echo "BEGIN TRANSACTION;" > "$TEMP_SQL"

COUNT=0
SKIPPED=0

while IFS= read -r domain; do
    # Skip empty lines and comments
    [[ -z "$domain" || "$domain" =~ ^# ]] && continue

    # Remove leading/trailing whitespace
    domain=$(echo "$domain" | xargs)

    # Skip invalid domains
    if [ -z "$domain" ]; then
        continue
    fi

    # Insert into domain_dns_allow
    echo "INSERT OR REPLACE INTO domain_dns_allow (Domain, Server) VALUES ('$domain', '$SERVER');" >> "$TEMP_SQL"
    COUNT=$((COUNT + 1))

    # Progress indicator
    if [ $((COUNT % 10000)) -eq 0 ]; then
        echo "  Processed: $COUNT domains..."
    fi
done < "$INPUT_FILE"

echo "COMMIT;" >> "$TEMP_SQL"

# Import to database
echo "Importing $COUNT domains to domain_dns_allow..."
sqlite3 "$DB_FILE" < "$TEMP_SQL"

echo ""
echo "✅ Import complete!"
echo ""
echo "Statistics:"
echo "  Imported:  $COUNT domains"
echo "  Server:    $SERVER"
echo ""

# Show table stats
echo "DNS Allow table stats:"
sqlite3 "$DB_FILE" <<EOF
SELECT
    COUNT(*) as total_domains,
    COUNT(DISTINCT Server) as unique_servers
FROM domain_dns_allow;
EOF

echo ""
echo "Example queries:"
echo "  dnsmasq --test --db-file=$DB_FILE"
echo "  dig @127.0.0.1 <domain>"
echo ""
