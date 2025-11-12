#!/bin/bash
# Convert HOSTS file to SQLite database
# Usage: ./convert-hosts-to-sqlite.sh hosts.txt output.db [ipv4] [ipv6]
#
# Performance: ~1 million lines per minute on SSD

set -e

HOSTS_FILE="${1:-/etc/hosts}"
DB_FILE="${2:-blocklist.db}"
DEFAULT_IPV4="${3:-0.0.0.0}"
DEFAULT_IPV6="${4:-::}"
BATCH_SIZE="${BATCH_SIZE:-50000}"

if [ ! -f "$HOSTS_FILE" ]; then
    echo "❌ Error: HOSTS file not found: $HOSTS_FILE"
    exit 1
fi

echo "========================================"
echo "HOSTS → SQLite Conversion"
echo "========================================"
echo "Input:      $HOSTS_FILE"
echo "Output:     $DB_FILE"
echo "Default IPv4: $DEFAULT_IPV4"
echo "Default IPv6: $DEFAULT_IPV6"
echo "Batch size: $BATCH_SIZE"
echo ""

# Count lines
echo "Counting lines..."
total=$(wc -l < "$HOSTS_FILE")
echo "Total lines: $total"
echo ""

# Create database
if [ ! -f "$DB_FILE" ]; then
    echo "Creating database..."
    ./createdb-dual.sh "$DB_FILE" > /dev/null
fi

echo "Converting HOSTS to SQLite..."
echo "(This may take a while for large files...)"
echo ""

start_time=$(date +%s)
imported=0
skipped=0
batch=0

# Start transaction
sqlite3 "$DB_FILE" <<EOF
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA cache_size=100000;
BEGIN TRANSACTION;
EOF

# Parse HOSTS file
while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines
    [[ -z "$line" ]] && { ((skipped++)); continue; }

    # Skip comments
    [[ "$line" =~ ^[[:space:]]*# ]] && { ((skipped++)); continue; }

    # Parse line format: IP DOMAIN [DOMAIN2 ...]
    # Examples:
    #   0.0.0.0 ads.com
    #   127.0.0.1 localhost
    #   0.0.0.0 tracker.net ads.tracker.net

    # Extract fields
    read -r ip domain rest <<< "$line"

    # Skip if no domain
    [[ -z "$domain" ]] && { ((skipped++)); continue; }

    # Skip localhost entries
    [[ "$domain" == "localhost" ]] && { ((skipped++)); continue; }
    [[ "$domain" == "localhost.localdomain" ]] && { ((skipped++)); continue; }

    # Determine IPv4/IPv6 from HOSTS file IP
    ipv4=""
    ipv6=""

    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # IPv4 address
        ipv4="$ip"
        ipv6="$DEFAULT_IPV6"
    elif [[ "$ip" =~ : ]]; then
        # IPv6 address
        ipv4="$DEFAULT_IPV4"
        ipv6="$ip"
    else
        # Unknown format, use defaults
        ipv4="$DEFAULT_IPV4"
        ipv6="$DEFAULT_IPV6"
    fi

    # Escape single quotes for SQL
    domain_escaped="${domain//\'/\'\'}"
    ipv4_escaped="${ipv4//\'/\'\'}"
    ipv6_escaped="${ipv6//\'/\'\'}"

    # Insert into wildcard table (blocks domain + subdomains)
    sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO domain (Domain, IPv4, IPv6) VALUES ('$domain_escaped', '$ipv4_escaped', '$ipv6_escaped');" 2>/dev/null || true

    ((imported++))
    ((batch++))

    # Commit and start new transaction every BATCH_SIZE
    if [ $((batch % BATCH_SIZE)) -eq 0 ]; then
        sqlite3 "$DB_FILE" "COMMIT; BEGIN TRANSACTION;"

        elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -gt 0 ]; then
            rate=$((imported / elapsed))
            echo "  Progress: $imported / $total ($rate/sec)..."
        else
            echo "  Progress: $imported / $total..."
        fi
    fi

    # Process additional domains on the same line
    if [ -n "$rest" ]; then
        for extra_domain in $rest; do
            [[ -z "$extra_domain" ]] && continue
            [[ "$extra_domain" =~ ^# ]] && break  # Stop at comments

            extra_domain_escaped="${extra_domain//\'/\'\'}"
            sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO domain (Domain, IPv4, IPv6) VALUES ('$extra_domain_escaped', '$ipv4_escaped', '$ipv6_escaped');" 2>/dev/null || true
            ((imported++))
        done
    fi

done < "$HOSTS_FILE"

# Final commit
sqlite3 "$DB_FILE" "COMMIT;"

end_time=$(date +%s)
duration=$((end_time - start_time))

echo ""
echo "========================================"
echo "✅ Conversion completed!"
echo "========================================"
echo "Imported:  $imported domains"
echo "Skipped:   $skipped lines"
echo "Duration:  ${duration}s"

if [ $duration -gt 0 ]; then
    rate=$((imported / duration))
    echo "Rate:      $rate domains/sec"
fi

echo ""

# Show statistics
sqlite3 "$DB_FILE" <<EOF
.mode line
SELECT 'Total domains in DB: ' || COUNT(*) FROM domain;
SELECT 'Database size: ' FROM pragma_page_count, pragma_page_size;
EOF

db_size=$(stat -f%z "$DB_FILE" 2>/dev/null || stat -c%s "$DB_FILE" 2>/dev/null || echo "unknown")
if [ "$db_size" != "unknown" ]; then
    db_size_mb=$((db_size / 1024 / 1024))
    echo "Database file: ${db_size_mb} MB"
fi

echo ""
echo "Compare to original HOSTS file:"
hosts_size=$(stat -f%z "$HOSTS_FILE" 2>/dev/null || stat -c%s "$HOSTS_FILE" 2>/dev/null || echo "unknown")
if [ "$hosts_size" != "unknown" ]; then
    hosts_size_mb=$((hosts_size / 1024 / 1024))
    echo "HOSTS file:    ${hosts_size_mb} MB"

    if [ "$db_size" != "unknown" ]; then
        reduction=$(( (hosts_size - db_size) * 100 / hosts_size ))
        echo "Reduction:     ${reduction}% smaller!"
    fi
fi

echo ""
echo "Test with:"
echo "  dnsmasq -d -p 5353 --db-file=$DB_FILE --db-block-ipv4=$DEFAULT_IPV4 --db-block-ipv6=$DEFAULT_IPV6 --log-queries"
