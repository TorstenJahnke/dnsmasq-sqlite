#!/bin/bash
# Test script for regex pattern matching
# Creates a test database and tests various patterns

set -e

DB_FILE="test-regex.db"
PORT=5353

echo "========================================"
echo "Regex Pattern Matcher Test"
echo "========================================"
echo ""

# Cleanup
rm -f "$DB_FILE" "$DB_FILE-shm" "$DB_FILE-wal"

# Create database
echo "Creating test database..."
./createdb-regex.sh "$DB_FILE" > /dev/null

# Add test patterns
echo "Adding test patterns..."
sqlite3 "$DB_FILE" <<EOF
-- Exact domain
INSERT INTO domain_exact (Domain, IPv4, IPv6) VALUES
  ('exact-block.com', '10.0.1.1', 'fd00:1::1');

-- Wildcard domain (blocks subdomains)
INSERT INTO domain (Domain, IPv4, IPv6) VALUES
  ('wildcard-block.com', '10.0.2.1', 'fd00:2::1');

-- Regex patterns
INSERT INTO domain_regex (Pattern, IPv4, IPv6) VALUES
  ('^ads\..*', '10.0.3.1', 'fd00:3::1'),
  ('.*\.tracker\.com$', '10.0.4.1', 'fd00:4::1'),
  ('^(www|cdn)\.analytics\..*', '10.0.5.1', 'fd00:5::1');
EOF

echo ""
echo "Database contents:"
sqlite3 "$DB_FILE" <<EOF
.mode line
SELECT 'Exact domains: ' || COUNT(*) FROM domain_exact;
SELECT 'Wildcard domains: ' || COUNT(*) FROM domain;
SELECT 'Regex patterns: ' || COUNT(*) FROM domain_regex;
EOF

echo ""
echo "========================================"
echo "Starting dnsmasq on port $PORT..."
echo "========================================"
echo ""
echo "Test queries to run in another terminal:"
echo ""
echo "# Should be blocked (exact):"
echo "  dig @127.0.0.1 -p $PORT exact-block.com"
echo ""
echo "# Should be allowed (exact doesn't block subdomains):"
echo "  dig @127.0.0.1 -p $PORT www.exact-block.com"
echo ""
echo "# Should be blocked (wildcard):"
echo "  dig @127.0.0.1 -p $PORT wildcard-block.com"
echo "  dig @127.0.0.1 -p $PORT www.wildcard-block.com"
echo ""
echo "# Should be blocked (regex ^ads\\.*):"
echo "  dig @127.0.0.1 -p $PORT ads.com"
echo "  dig @127.0.0.1 -p $PORT ads.example.net"
echo ""
echo "# Should be blocked (regex .*\\.tracker\\.com$):"
echo "  dig @127.0.0.1 -p $PORT evil.tracker.com"
echo "  dig @127.0.0.1 -p $PORT api.tracker.com"
echo ""
echo "# Should be blocked (regex ^(www|cdn)\\.analytics\\..*):"
echo "  dig @127.0.0.1 -p $PORT www.analytics.com"
echo "  dig @127.0.0.1 -p $PORT cdn.analytics.net"
echo ""
echo "# Should be allowed (doesn't match any pattern):"
echo "  dig @127.0.0.1 -p $PORT google.com"
echo "  dig @127.0.0.1 -p $PORT example.com"
echo ""
echo "Press Ctrl+C to stop dnsmasq"
echo ""
echo "========================================"
echo ""

# Run dnsmasq
./src/dnsmasq -d -p $PORT \
  --db-file="$DB_FILE" \
  --db-block-ipv4=0.0.0.0 \
  --db-block-ipv6=:: \
  --log-queries \
  --no-resolv \
  --no-hosts

echo ""
echo "Cleaning up..."
rm -f "$DB_FILE" "$DB_FILE-shm" "$DB_FILE-wal"
