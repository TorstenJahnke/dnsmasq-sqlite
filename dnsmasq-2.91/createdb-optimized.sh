#!/usr/bin/env bash

# Optimized SQLite domain database import script
# Supports multiple blocklist sources with fast batch imports

set -e

DB_FILE="${1:-blocklist.db}"
BATCH_SIZE=10000

echo "Creating SQLite blocklist database: $DB_FILE"

# Create database schema
sqlite3 "$DB_FILE" <<EOF
CREATE TABLE IF NOT EXISTS domain (
    Domain TEXT PRIMARY KEY
) WITHOUT ROWID;
EOF

echo "Database schema created."

# Function: Fast batch import from CSV/TXT
import_list() {
    local file="$1"
    local column="${2:-1}"  # Which column contains the domain (default: 1)
    local skip_lines="${3:-0}"  # Lines to skip (headers)

    echo "Importing from: $file"

    # Fast import with batch transactions
    awk -v col="$column" -v skip="$skip_lines" -v batch="$BATCH_SIZE" '
        NR <= skip { next }
        {
            if (NF >= col) {
                # Extract domain from specified column
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $col)
                if ($col != "" && $col !~ /^#/) {
                    domains[count++] = $col
                }
            }

            # Batch insert every BATCH_SIZE domains
            if (count >= batch) {
                print "BEGIN TRANSACTION;"
                for (i = 0; i < count; i++) {
                    printf "INSERT OR IGNORE INTO domain VALUES (\"%s\");\n", domains[i]
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
                    printf "INSERT OR IGNORE INTO domain VALUES (\"%s\");\n", domains[i]
                }
                print "COMMIT;"
            }
        }
    ' "$file" | sqlite3 "$DB_FILE"
}

# Example blocklists (uncomment what you need)

# Option 1: Top 10M domains from DomCop (for testing/whitelisting - NOT for blocking!)
# echo "Downloading top 10 million domains..."
# curl -o top10m.csv.zip "https://www.domcop.com/files/top/top10milliondomains.csv.zip"
# unzip -o top10m.csv.zip
# import_list "top10milliondomains.csv" 2 1  # Domain is in column 2, skip 1 header line

# Option 2: StevenBlack's unified hosts (recommended!)
echo "Downloading StevenBlack unified hosts..."
curl -o hosts.txt "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
grep -v "^#\|^$\|localhost\|local$\|broadcasthost" hosts.txt | \
    awk '{print $2}' | grep -v "^$" > domains.txt
import_list "domains.txt" 1 0
rm -f domains.txt hosts.txt

# Option 3: Add your custom domains
if [ -f "custom_blocklist.txt" ]; then
    echo "Importing custom blocklist..."
    import_list "custom_blocklist.txt" 1 0
fi

# Create index for fast lookups
echo "Creating index (this may take a while)..."
sqlite3 "$DB_FILE" "CREATE UNIQUE INDEX IF NOT EXISTS idx_Domain ON domain(Domain);"

# Optimize database
echo "Optimizing database..."
sqlite3 "$DB_FILE" "VACUUM; ANALYZE;"

# Show statistics
COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM domain;")
SIZE=$(du -h "$DB_FILE" | cut -f1)

echo ""
echo "✅ Database created successfully!"
echo "   File: $DB_FILE"
echo "   Size: $SIZE"
echo "   Domains: $COUNT"
echo ""
echo "Usage: ./src/dnsmasq -d -p 5353 --db-file $DB_FILE --db-block-ipv4 0.0.0.0 --db-block-ipv6 ::"
