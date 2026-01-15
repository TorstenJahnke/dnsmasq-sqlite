#!/bin/sh
# Incremental import for block_wildcard (domain wildcard blocking)
# Version: 5.0
#
# This script adds domains to an EXISTING database without recreating it.
# Duplicates are automatically skipped (INSERT OR IGNORE).
# Wildcard: blocks domain AND all subdomains (e.g., example.com blocks *.example.com)
#
# Usage: ./import-domains.sh [file] [database]
#        ./import-domains.sh /path/to/domains.txt
#        ./import-domains.sh /path/to/domains.txt /path/to/db.db
#
# Input format: One domain per line
# Example:
#   ads.example.com      <- blocks ads.example.com AND *.ads.example.com
#   tracker.org          <- blocks tracker.org AND *.tracker.org

# Configuration
DOMAINFILE="${1:-/op/databaseAVX/domains/import}"
DATABASE="${2:-/usr/local/etc/dnsmasq/aviontex.db}"
DNSMASQ_GROUP="wheel"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=========================================="
echo " Incremental Domain Import (block_wildcard)"
echo "=========================================="
echo ""

# Check if files exist
if [ ! -f "$DOMAINFILE" ]; then
    echo "${RED}Error: $DOMAINFILE not found${NC}"
    exit 1
fi

if [ ! -f "$DATABASE" ]; then
    echo "${RED}Error: $DATABASE not found${NC}"
    echo "Run setup-db.sh or create-db.sh first!"
    exit 1
fi

# Count entries
LINES=$(wc -l < "$DOMAINFILE" | tr -d ' ')
BEFORE=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_wildcard;" 2>/dev/null)

if [ -z "$BEFORE" ]; then
    echo "${RED}Error: block_wildcard table does not exist${NC}"
    echo "Run setup-db.sh first!"
    exit 1
fi

echo "Input file:  $DOMAINFILE"
echo "New entries: $LINES"
echo "Database:    $DATABASE"
echo "Before:      $BEFORE"
echo ""

# Import with INSERT OR IGNORE (skips duplicates)
echo "Importing..."
sqlite3 "$DATABASE" << SQL
PRAGMA synchronous = OFF;
PRAGMA cache_size = -1048576;
.mode list
.import '$DOMAINFILE' block_wildcard
SQL

# Set permissions
chown root:${DNSMASQ_GROUP} "$DATABASE" "${DATABASE}-wal" "${DATABASE}-shm" 2>/dev/null
chmod 644 "$DATABASE" "${DATABASE}-wal" "${DATABASE}-shm" 2>/dev/null

# Statistics
AFTER=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_wildcard;")
ADDED=$((AFTER - BEFORE))

echo ""
echo "=========================================="
echo "${GREEN} Done!${NC}"
echo "=========================================="
echo ""
echo "Before:  $BEFORE"
echo "After:   $AFTER"
echo "Added:   $ADDED"
echo "(Duplicates were skipped)"
echo ""
