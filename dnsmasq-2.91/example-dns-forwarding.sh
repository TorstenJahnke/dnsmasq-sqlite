#!/bin/bash
# Example: DNS Forwarding with Whitelist/Blacklist
#
# Use case: Block all .xyz TLD domains, but allow ~1000 trusted exceptions
#
# Architecture:
#   - Blocker DNS (10.0.0.1): Returns 0.0.0.0 for all queries
#   - Real DNS (8.8.8.8): Normal DNS resolution
#
# Strategy:
#   1. Add .xyz to domain_dns_block → forwards to 10.0.0.1 (blocker)
#   2. Add trusted.xyz to domain_dns_allow → forwards to 8.8.8.8 (real DNS)
#
# Lookup order: domain_dns_allow FIRST, then domain_dns_block
#   → trusted.xyz goes to 8.8.8.8 ✅
#   → untrusted.xyz goes to 10.0.0.1 ❌
#   → example.com goes to normal upstream (not in SQLite)

set -e

DB_FILE="${1:-blocklist.db}"

echo "========================================"
echo "DNS Forwarding Example Setup"
echo "========================================"
echo "Database: $DB_FILE"
echo ""

# Check if database exists
if [ ! -f "$DB_FILE" ]; then
    echo "Creating database..."
    ./createdb-optimized.sh "$DB_FILE"
    echo ""
fi

echo "Step 1: Block all .xyz TLD domains"
echo "  → Forward *.xyz to blocker DNS (10.0.0.1)"
echo ""

# Create block list
cat > /tmp/dns-block.txt <<EOF
# Block entire .xyz TLD
*.xyz
# Block entire .tk TLD
*.tk
# Block specific tracking domains
*.doubleclick.net
*.googleadservices.com
EOF

# Import to domain_dns_block
./add-dns-block.sh 10.0.0.1 "$DB_FILE" /tmp/dns-block.txt

echo ""
echo "Step 2: Allow trusted .xyz domains (exceptions)"
echo "  → Forward trusted domains to real DNS (8.8.8.8)"
echo ""

# Create allow list (whitelist)
cat > /tmp/dns-allow.txt <<EOF
# Trusted .xyz domains (exceptions)
trusted.xyz
mycompany.xyz
important-site.xyz
# Allow specific tracking for analytics
analytics.mysite.com
EOF

# Import to domain_dns_allow
./add-dns-allow.sh 8.8.8.8 "$DB_FILE" /tmp/dns-allow.txt

echo ""
echo "========================================"
echo "Configuration Complete!"
echo "========================================"
echo ""

# Show final statistics
echo "Database summary:"
sqlite3 "$DB_FILE" <<EOF
.mode column
.headers on
SELECT
    'domain_dns_allow' as table_name,
    COUNT(*) as domains,
    (SELECT DISTINCT Server FROM domain_dns_allow LIMIT 1) as dns_server
FROM domain_dns_allow
UNION ALL
SELECT
    'domain_dns_block' as table_name,
    COUNT(*) as domains,
    (SELECT DISTINCT Server FROM domain_dns_block LIMIT 1) as dns_server
FROM domain_dns_block;
EOF

echo ""
echo "Test queries:"
echo ""
echo "  # Should forward to 8.8.8.8 (allowed):"
echo "  dig @127.0.0.1 trusted.xyz"
echo ""
echo "  # Should forward to 10.0.0.1 (blocked via .xyz):"
echo "  dig @127.0.0.1 evil.xyz"
echo ""
echo "  # Should use normal upstream (not in SQLite):"
echo "  dig @127.0.0.1 example.com"
echo ""
echo "Start dnsmasq with:"
echo "  dnsmasq -d --db-file=$DB_FILE --log-queries"
echo ""

# Cleanup
rm -f /tmp/dns-block.txt /tmp/dns-allow.txt
