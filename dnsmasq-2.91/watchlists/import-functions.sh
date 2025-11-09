#!/bin/bash
# Shared import functions for watchlist system
# Used by all import-*.sh scripts

# Default database location (can be overridden)
DB_FILE="${DB_FILE:-../blocklist.db}"
BATCH_SIZE="${BATCH_SIZE:-10000}"

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

    local count_before=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM $table;" 2>/dev/null || echo "0")
    echo "  Importing into $table: $file"

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

    local count_after=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM $table;" 2>/dev/null || echo "0")
    local added=$((count_after - count_before))
    echo "    ✅ Added $added domains (total: $count_after)"
}

# Function: Process whitelist (delete domains from DB)
# Args: $1=whitelist_file $2=table (domain|domain_exact)
process_whitelist() {
    local file="$1"
    local table="$2"

    if [ ! -f "$file" ]; then
        echo "⚠️  Whitelist not found: $file (skipping)"
        return
    fi

    local count_before=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM $table;" 2>/dev/null || echo "0")
    echo "  Processing whitelist for $table: $file"

    # Generate DELETE statements
    awk '
        NF > 0 && $1 !~ /^#/ {
            # Remove whitespace and trailing dots
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
            gsub(/\.$/, "", $1)
            if ($1 != "") {
                printf "DELETE FROM '"$table"' WHERE Domain = '\''%s'\'';\n", $1
            }
        }
    ' "$file" | sqlite3 "$DB_FILE"

    local count_after=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM $table;" 2>/dev/null || echo "0")
    local removed=$((count_before - count_after))
    echo "    ✅ Removed $removed domains (remaining: $count_after)"
}
