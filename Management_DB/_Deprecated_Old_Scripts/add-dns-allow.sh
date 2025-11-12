#!/bin/bash
# Import DNS allow list (whitelist) - Schema v4.0
# Usage: ./add-dns-allow.sh <database.db> [allow-list.txt]
#
# Format of allow-list.txt:
#   trusted-ads.com
#   allowed.tracking.com
#   *.safe-domain.xyz
#
# IMPORTANT: DNS servers are configured in dnsmasq.conf, NOT in database!
#   ipset-dns-allow=8.8.8.8,1.1.1.1#5353,[2001:4860:4860::8888]:53
#
# All domains in fqdn_dns_allow will be forwarded to IPSetDNSAllow servers.

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <database.db> [allow-list.txt]"
    echo ""
    echo "Examples:"
    echo "  $0 blocklist.db allow-list.txt"
    echo "  $0 blocklist.db < allow-list.txt"
    echo ""
    echo "Schema v4.0: Imports domains to fqdn_dns_allow table (domain-only)."
    echo "DNS servers are configured in dnsmasq.conf:"
    echo "  ipset-dns-allow=8.8.8.8,1.1.1.1#5353"
    echo ""
    echo "Use case: Block all .xyz domains, but allow trusted.xyz"
    echo "          → trusted.xyz will be forwarded to IPSetDNSAllow servers"
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
echo "DNS Allow List (Whitelist) Import"
echo "Schema v4.0: Domain-only (IPSets)"
echo "========================================"
echo "Database: $DB_FILE"
echo "Input:    $INPUT_FILE"
echo "Table:    fqdn_dns_allow"
echo ""
echo "NOTE: DNS servers configured in dnsmasq.conf (ipset-dns-allow)"
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

    # Insert into fqdn_dns_allow (Schema v4.0: domain-only, no server column!)
    echo "INSERT OR REPLACE INTO fqdn_dns_allow (Domain) VALUES ('$domain');" >> "$TEMP_SQL"
    COUNT=$((COUNT + 1))

    # Progress indicator
    if [ $((COUNT % 10000)) -eq 0 ]; then
        echo "  Processed: $COUNT domains..."
    fi
done < "$INPUT_FILE"

echo "COMMIT;" >> "$TEMP_SQL"

# Import to database
echo "Importing $COUNT domains to fqdn_dns_allow..."
sqlite3 "$DB_FILE" < "$TEMP_SQL"

echo ""
echo "✅ Import complete!"
echo ""
echo "Statistics:"
echo "  Imported:    $COUNT domains"
echo "  Target Table: fqdn_dns_allow"
echo "  DNS Servers:  Configure in dnsmasq.conf (ipset-dns-allow)"
echo ""
echo "Example dnsmasq.conf:"
echo "  ipset-dns-allow=8.8.8.8,1.1.1.1#5353,[2001:4860:4860::8888]:53"
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
