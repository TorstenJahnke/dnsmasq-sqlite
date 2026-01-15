#!/bin/sh
# Incremental import for block_ips (IP address rewriting)
# Version: 5.0
#
# This script adds IP rewrite rules to an EXISTING database without recreating it.
# Duplicates are automatically skipped (INSERT OR IGNORE).
#
# Usage: ./import-ips.sh [file] [database]
#        ./import-ips.sh /path/to/ips.txt
#        ./import-ips.sh /path/to/ips.txt /path/to/db.db
#
# Input format: CSV with Source_IP,Target_IP (one per line)
# Example:
#   178.223.16.21,10.20.0.10
#   192.168.1.100,10.0.0.1
#   2001:db8::1,fd00::1

# Configuration
IPFILE="${1:-/op/databaseAVX/ip/import}"
DATABASE="${2:-/usr/local/etc/dnsmasq/aviontex.db}"
DNSMASQ_GROUP="wheel"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=========================================="
echo " Incremental IP Import (block_ips)"
echo "=========================================="
echo ""

# Check if files exist
if [ ! -f "$IPFILE" ]; then
    echo "${RED}Error: $IPFILE not found${NC}"
    exit 1
fi

if [ ! -f "$DATABASE" ]; then
    echo "${RED}Error: $DATABASE not found${NC}"
    echo "Run setup-db.sh or create-db.sh first!"
    exit 1
fi

# Count entries
LINES=$(wc -l < "$IPFILE" | tr -d ' ')
BEFORE=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_ips;" 2>/dev/null)

if [ -z "$BEFORE" ]; then
    echo "${RED}Error: block_ips table does not exist${NC}"
    echo "Run setup-db.sh first!"
    exit 1
fi

echo "Input file:  $IPFILE"
echo "New entries: $LINES"
echo "Database:    $DATABASE"
echo "Before:      $BEFORE"
echo ""
echo "Format: Source_IP,Target_IP"
echo ""

# Import with INSERT OR IGNORE (skips duplicates)
echo "Importing..."
sqlite3 "$DATABASE" << SQL
PRAGMA synchronous = OFF;
PRAGMA cache_size = -1048576;
.mode csv
.import '$IPFILE' block_ips
SQL

# Set permissions
chown root:${DNSMASQ_GROUP} "$DATABASE" "${DATABASE}-wal" "${DATABASE}-shm" 2>/dev/null
chmod 644 "$DATABASE" "${DATABASE}-wal" "${DATABASE}-shm" 2>/dev/null

# Statistics
AFTER=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_ips;")
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
