#!/bin/bash
# Import HOSTS file to SQLite - Schema v4.0
# Usage: ./add-hosts.sh <database.db> <hosts.txt> [--wildcard|--exact]
#
# Format of hosts.txt:
#   0.0.0.0 ads.example.com
#   127.0.0.1 tracker.com
#   0.0.0.0 spam.net
#
# IMPORTANT: IPv4/IPv6 addresses from hosts file are IGNORED!
#            Termination IPs are configured in dnsmasq.conf:
#              ipset-terminate-v4=127.0.0.1,0.0.0.0
#              ipset-terminate-v6=::1,::
#
# Options:
#   --wildcard  Import to block_wildcard (blocks domain + subdomains)
#   --exact     Import to block_exact (blocks only exact domain)
#   (default: --wildcard)

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <database.db> <hosts.txt> [--wildcard|--exact]"
    echo ""
    echo "Examples:"
    echo "  $0 blocklist.db hosts.txt                # wildcard (default)"
    echo "  $0 blocklist.db hosts.txt --wildcard     # block domain + subdomains"
    echo "  $0 blocklist.db hosts.txt --exact        # block only exact domain"
    echo ""
    echo "Schema v4.0: Imports domains only (no IPv4/IPv6 columns!)."
    echo "Termination IPs configured in dnsmasq.conf:"
    echo "  ipset-terminate-v4=127.0.0.1,0.0.0.0"
    echo "  ipset-terminate-v6=::1,::"
    exit 1
fi

DB_FILE="$1"
HOSTS_FILE="$2"
MODE="${3:---wildcard}"

if [ ! -f "$DB_FILE" ]; then
    echo "Error: Database $DB_FILE not found!"
    echo "Create it first with ./createdb-optimized.sh"
    exit 1
fi

if [ ! -f "$HOSTS_FILE" ]; then
    echo "Error: HOSTS file $HOSTS_FILE not found!"
    exit 1
fi

# Determine target table
case "$MODE" in
    --wildcard)
        TABLE="block_wildcard"
        DESC="Wildcard (domain + subdomains)"
        ;;
    --exact)
        TABLE="block_exact"
        DESC="Exact (domain only, no subdomains)"
        ;;
    *)
        echo "Error: Invalid mode '$MODE'. Use --wildcard or --exact"
        exit 1
        ;;
esac

echo "========================================"
echo "HOSTS File Import - Schema v4.0"
echo "========================================"
echo "Database:  $DB_FILE"
echo "Input:     $HOSTS_FILE"
echo "Mode:      $DESC"
echo "Table:     $TABLE"
echo ""
echo "NOTE: IPv4/IPv6 from hosts file are IGNORED!"
echo "      Termination IPs configured in dnsmasq.conf (ipset-terminate-v4/v6)"
echo ""

# Count lines
echo "Counting lines..."
total=$(wc -l < "$HOSTS_FILE")
echo "Total lines: $total"
echo ""

TEMP_SQL=$(mktemp)
trap "rm -f $TEMP_SQL" EXIT

echo "BEGIN TRANSACTION;" > "$TEMP_SQL"

COUNT=0
SKIPPED=0

echo "Processing HOSTS file..."

while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines
    [[ -z "$line" ]] && { ((SKIPPED++)); continue; }

    # Skip comments
    [[ "$line" =~ ^[[:space:]]*# ]] && { ((SKIPPED++)); continue; }

    # Parse line format: IP DOMAIN [DOMAIN2 ...]
    # Examples:
    #   0.0.0.0 ads.com
    #   127.0.0.1 tracker.net
    read -r ip domain rest <<< "$line"

    # Skip if no domain
    [[ -z "$domain" ]] && { ((SKIPPED++)); continue; }

    # Skip localhost entries
    [[ "$domain" == "localhost" ]] && { ((SKIPPED++)); continue; }
    [[ "$domain" == "localhost."* ]] && { ((SKIPPED++)); continue; }

    # Skip invalid domains (must contain .)
    [[ ! "$domain" =~ \. ]] && { ((SKIPPED++)); continue; }

    # Insert domain (IP is ignored - comes from IPSetTerminate config!)
    echo "INSERT OR REPLACE INTO $TABLE (Domain) VALUES ('$domain');" >> "$TEMP_SQL"
    COUNT=$((COUNT + 1))

    # Process additional domains on same line
    if [ -n "$rest" ]; then
        for extra_domain in $rest; do
            [[ "$extra_domain" == "localhost" ]] && continue
            [[ "$extra_domain" == "localhost."* ]] && continue
            [[ ! "$extra_domain" =~ \. ]] && continue

            echo "INSERT OR REPLACE INTO $TABLE (Domain) VALUES ('$extra_domain');" >> "$TEMP_SQL"
            COUNT=$((COUNT + 1))
        done
    fi

    # Progress indicator
    if [ $((COUNT % 50000)) -eq 0 ]; then
        echo "  Processed: $COUNT domains..."
    fi
done < "$HOSTS_FILE"

echo "COMMIT;" >> "$TEMP_SQL"

# Import to database
echo ""
echo "Importing $COUNT domains to $TABLE..."
sqlite3 "$DB_FILE" < "$TEMP_SQL"

echo ""
echo "✅ Import complete!"
echo ""
echo "Statistics:"
echo "  Imported:     $COUNT domains"
echo "  Skipped:      $SKIPPED lines"
echo "  Target Table: $TABLE"
echo "  Mode:         $DESC"
echo ""
echo "Termination IPs configured in dnsmasq.conf:"
echo "  ipset-terminate-v4=127.0.0.1,0.0.0.0"
echo "  ipset-terminate-v6=::1,::"
echo ""

# Show table stats
echo "Table stats:"
sqlite3 "$DB_FILE" <<EOF
.mode line
SELECT COUNT(*) as total_domains FROM $TABLE;
EOF

echo ""
echo "Done!"
