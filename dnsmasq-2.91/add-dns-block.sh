#!/bin/bash
# Import DNS block list (blacklist) - Schema v4.0
# Usage: ./add-dns-block.sh <database.db> [block-list.txt]
#
# Format of block-list.txt:
#   *.xyz
#   *.tk
#   ads.example.com
#
# IMPORTANT: Blocker DNS servers are configured in dnsmasq.conf, NOT in database!
#   ipset-dns-block=127.0.0.1#5353,[fd00::1]:5353
#
# All domains in fqdn_dns_block will be forwarded to IPSetDNSBlock servers.

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <database.db> [block-list.txt]"
    echo ""
    echo "Examples:"
    echo "  $0 blocklist.db block-list.txt"
    echo "  $0 blocklist.db < block-list.txt"
    echo ""
    echo "Schema v4.0: Imports domains to fqdn_dns_block table (domain-only)."
    echo "Blocker DNS servers are configured in dnsmasq.conf:"
    echo "  ipset-dns-block=127.0.0.1#5353,[fd00::1]:5353"
    echo ""
    echo "Use case: Block all .xyz domains by forwarding to blocker DNS"
    echo "          → blocker DNS returns 0.0.0.0 for everything"
    exit 1
fi

DB_FILE="$1"
INPUT_FILE="${2:-/dev/stdin}"

if [ ! -f "$DB_FILE" ]; then
    echo "Error: Database $DB_FILE not found!"
    echo "Create it first with ./createdb-optimized.sh"
    exit 1
fi

echo "========================================"
echo "DNS Block List (Blacklist) Import"
echo "Schema v4.0: Domain-only (IPSets)"
echo "========================================"
echo "Database: $DB_FILE"
echo "Input:    $INPUT_FILE"
echo "Table:    fqdn_dns_block"
echo ""
echo "NOTE: Blocker DNS servers configured in dnsmasq.conf (ipset-dns-block)"
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

    # Insert into fqdn_dns_block (Schema v4.0: domain-only, no server column!)
    echo "INSERT OR REPLACE INTO fqdn_dns_block (Domain) VALUES ('$domain');" >> "$TEMP_SQL"
    COUNT=$((COUNT + 1))

    # Progress indicator
    if [ $((COUNT % 10000)) -eq 0 ]; then
        echo "  Processed: $COUNT domains..."
    fi
done < "$INPUT_FILE"

echo "COMMIT;" >> "$TEMP_SQL"

# Import to database
echo "Importing $COUNT domains to fqdn_dns_block..."
sqlite3 "$DB_FILE" < "$TEMP_SQL"

echo ""
echo "✅ Import complete!"
echo ""
echo "Statistics:"
echo "  Imported:     $COUNT domains"
echo "  Target Table: fqdn_dns_block"
echo "  DNS Servers:  Configure in dnsmasq.conf (ipset-dns-block)"
echo ""
echo "Example dnsmasq.conf:"
echo "  ipset-dns-block=127.0.0.1#5353,[fd00::1]:5353"
echo ""

# Show table stats
echo "DNS Block table stats:"
sqlite3 "$DB_FILE" <<EOF
.mode line
SELECT COUNT(*) as total_domains FROM fqdn_dns_block;
EOF

echo ""
echo "Done! Domains will be forwarded to IPSetDNSBlock servers."
