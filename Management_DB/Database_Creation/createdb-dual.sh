#!/usr/bin/env bash

# Dual-Mode SQLite DNS Blocker Database Import
# Supports:
# 1. domain_exact table (HOSTS match - exact only, no subdomains)
# 2. domain table (WILDCARD match - includes all subdomains)

set -e

DB_FILE="${1:-blocklist.db}"
BATCH_SIZE=10000

echo "========================================="
echo "SQLite Dual-Mode Blocker Database Import"
echo "========================================="
echo "Database: $DB_FILE"
echo ""

# Create database schema
echo "Creating schema..."
sqlite3 "$DB_FILE" <<EOF
-- Exact-only matching (hosts-style)
-- Blocks ONLY the exact domain, NOT subdomains
-- IPv4/IPv6: Per-domain termination IPs (supports 10-20 different IP sets)
CREATE TABLE IF NOT EXISTS domain_exact (
    Domain TEXT PRIMARY KEY,
    IPv4 TEXT,
    IPv6 TEXT
) WITHOUT ROWID;

-- Wildcard matching (*.domain)
-- Blocks domain AND all subdomains
-- IPv4/IPv6: Per-domain termination IPs (supports 10-20 different IP sets)
CREATE TABLE IF NOT EXISTS domain (
    Domain TEXT PRIMARY KEY,
    IPv4 TEXT,
    IPv6 TEXT
) WITHOUT ROWID;
EOF

echo "✅ Schema created"
echo ""

# Function: Fast batch import
# Args: $1=file $2=table (domain|domain_exact) $3=column $4=skip_lines $5=ipv4(optional) $6=ipv6(optional)
import_list() {
    local file="$1"
    local table="$2"
    local column="${3:-1}"
    local skip_lines="${4:-0}"
    local default_ipv4="${5:-}"
    local default_ipv6="${6:-}"

    if [ ! -f "$file" ]; then
        echo "⚠️  File not found: $file (skipping)"
        return
    fi

    local count_before=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM $table;")
    echo "Importing into $table: $file"

    # Fast batch import with transactions
    awk -v col="$column" -v skip="$skip_lines" -v batch="$BATCH_SIZE" -v table="$table" \
        -v ipv4="$default_ipv4" -v ipv6="$default_ipv6" '
        NR <= skip { next }
        {
            if (NF >= col) {
                # Extract domain from specified column
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $col)
                # Remove trailing dots
                gsub(/\.$/, "", $col)
                if ($col != "" && $col !~ /^#/ && $col !~ /^127\./ && $col !~ /^0\.0\.0\.0/) {
                    domains[count++] = $col
                }
            }

            # Batch insert every BATCH_SIZE domains
            if (count >= batch) {
                print "BEGIN TRANSACTION;"
                for (i = 0; i < count; i++) {
                    if (ipv4 != "" && ipv6 != "") {
                        printf "INSERT OR IGNORE INTO %s (Domain, IPv4, IPv6) VALUES (\"%s\", \"%s\", \"%s\");\n", table, domains[i], ipv4, ipv6
                    } else if (ipv4 != "") {
                        printf "INSERT OR IGNORE INTO %s (Domain, IPv4) VALUES (\"%s\", \"%s\");\n", table, domains[i], ipv4
                    } else if (ipv6 != "") {
                        printf "INSERT OR IGNORE INTO %s (Domain, IPv6) VALUES (\"%s\", \"%s\");\n", table, domains[i], ipv6
                    } else {
                        printf "INSERT OR IGNORE INTO %s (Domain) VALUES (\"%s\");\n", table, domains[i]
                    }
                }
                print "COMMIT;"
                count = 0
                delete domains
            }
        }
        END {
            # Insert remaining domains
            if (count > 0) {
                print "BEGIN TRANSACTION;"
                for (i = 0; i < count; i++) {
                    if (ipv4 != "" && ipv6 != "") {
                        printf "INSERT OR IGNORE INTO %s (Domain, IPv4, IPv6) VALUES (\"%s\", \"%s\", \"%s\");\n", table, domains[i], ipv4, ipv6
                    } else if (ipv4 != "") {
                        printf "INSERT OR IGNORE INTO %s (Domain, IPv4) VALUES (\"%s\", \"%s\");\n", table, domains[i], ipv4
                    } else if (ipv6 != "") {
                        printf "INSERT OR IGNORE INTO %s (Domain, IPv6) VALUES (\"%s\", \"%s\");\n", table, domains[i], ipv6
                    } else {
                        printf "INSERT OR IGNORE INTO %s (Domain) VALUES (\"%s\");\n", table, domains[i]
                    }
                }
                print "COMMIT;"
            }
        }
    ' "$file" | sqlite3 "$DB_FILE"

    local count_after=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM $table;")
    local added=$((count_after - count_before))
    echo "  ✅ Added $added domains (total: $count_after)"
}

# ===========================================
# Import Options
# ===========================================

# Option 1: StevenBlack's unified hosts (WILDCARD - recommended!)
echo "Option 1: StevenBlack's unified hosts (wildcard mode)"
if [ ! -f "hosts.txt" ]; then
    echo "  Downloading..."
    curl -sS -o hosts.txt "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
fi
grep -v "^#\|^$\|localhost\|local$\|broadcasthost\|^127\.\|^0\.0\.0\.0\|^::" hosts.txt | \
    awk '{print $2}' | grep -v "^$" | sort -u > domains_wildcard.tmp
import_list "domains_wildcard.tmp" "domain" 1 0
rm -f domains_wildcard.tmp hosts.txt
echo ""

# Option 2: Custom exact-only blocklist
echo "Option 2: Custom exact-only domains"
if [ -f "custom_exact.txt" ]; then
    echo "  Found custom_exact.txt"
    import_list "custom_exact.txt" "domain_exact" 1 0
else
    echo "  No custom_exact.txt found (create it to add exact-only domains)"
fi
echo ""

# Option 3: Custom wildcard blocklist
echo "Option 3: Custom wildcard domains"
if [ -f "custom_wildcard.txt" ]; then
    echo "  Found custom_wildcard.txt"
    import_list "custom_wildcard.txt" "domain" 1 0
else
    echo "  No custom_wildcard.txt found (create it to add wildcard domains)"
fi
echo ""

# Create indexes
echo "Creating indexes..."
sqlite3 "$DB_FILE" <<EOF
CREATE UNIQUE INDEX IF NOT EXISTS idx_Domain_exact ON domain_exact(Domain);
CREATE UNIQUE INDEX IF NOT EXISTS idx_Domain ON domain(Domain);
EOF
echo "✅ Indexes created"
echo ""

# Optimize database
echo "Optimizing database..."
sqlite3 "$DB_FILE" "VACUUM; ANALYZE;"
echo "✅ Optimized"
echo ""

# Show statistics
echo "========================================="
echo "Database Statistics"
echo "========================================="
COUNT_EXACT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM domain_exact;")
COUNT_WILDCARD=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM domain;")
SIZE=$(du -h "$DB_FILE" | cut -f1)

echo "File: $DB_FILE"
echo "Size: $SIZE"
echo ""
echo "Exact-only (hosts):  $COUNT_EXACT domains"
echo "  → Blocks ONLY exact domain"
echo ""
echo "Wildcard (*.domain): $COUNT_WILDCARD domains"
echo "  → Blocks domain + all subdomains"
echo ""
echo "Total: $((COUNT_EXACT + COUNT_WILDCARD)) entries"
echo ""

# Usage examples
echo "========================================="
echo "Usage Examples"
echo "========================================="
echo ""
echo "# Add domain to exact-only table (hosts-style):"
echo "sqlite3 $DB_FILE \"INSERT INTO domain_exact (Domain, IPv4, IPv6) VALUES ('paypal-evil.de', '10.0.0.1', 'fd00::1');\""
echo "  → Blocks ONLY paypal-evil.de"
echo "  → www.paypal-evil.de is NOT blocked"
echo "  → Returns 10.0.0.1 / fd00::1"
echo ""
echo "# Add domain to wildcard table:"
echo "sqlite3 $DB_FILE \"INSERT INTO domain (Domain, IPv4, IPv6) VALUES ('ads.com', '10.0.0.2', 'fd00::2');\""
echo "  → Blocks ads.com AND *.*.*.ads.com (all subdomains!)"
echo "  → Returns 10.0.0.2 / fd00::2"
echo ""
echo "# Add without IPs (uses global --db-block-ipv4/6 fallback):"
echo "sqlite3 $DB_FILE \"INSERT INTO domain (Domain) VALUES ('tracker.net');\""
echo "  → Blocks tracker.net + all subdomains"
echo "  → Returns IPs from --db-block-ipv4 and --db-block-ipv6"
echo ""
echo "# Start dnsmasq:"
echo "./src/dnsmasq -d -p 5353 \\"
echo "  --db-file=$DB_FILE \\"
echo "  --db-block-ipv4=0.0.0.0 \\"
echo "  --db-block-ipv6=:: \\"
echo "  --log-queries"
echo ""
echo "========================================="
echo "Custom Import Files (Optional)"
echo "========================================="
echo ""
echo "Create these files for custom imports:"
echo ""
echo "# custom_exact.txt (hosts-style, one domain per line)"
echo "paypal-evil.de"
echo "tracker-exact.com"
echo ""
echo "# custom_wildcard.txt (wildcard, one domain per line)"
echo "ads.com"
echo "tracker.net"
echo ""
echo "Then re-run: ./createdb-dual.sh $DB_FILE"
echo ""
