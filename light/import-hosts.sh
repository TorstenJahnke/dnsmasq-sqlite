#!/bin/sh
# Incremental import for block_hosts (exact hostname matching)
# Version: 5.0
#
# This script adds hosts to an EXISTING database without recreating it.
# Duplicates are automatically skipped (INSERT OR IGNORE).
#
# Usage: ./import-hosts.sh [file] [database]
#        ./import-hosts.sh /path/to/hosts.txt
#        ./import-hosts.sh /path/to/hosts.txt /path/to/db.db
#
# Input format: One hostname per line (exact match, no wildcards)
# Example:
#   ads.example.com
#   tracker.example.org
#   malware.test.net

# Configuration
HOSTFILE="${1:-/usr/local/etc/hosts-blocklist.txt}"
DATABASE="${2:-/usr/local/etc/dnsmasq/aviontex.db}"
DNSMASQ_GROUP="wheel"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=========================================="
echo " Incremental Host Import (block_hosts)"
echo "=========================================="
echo ""

# Check if files exist
if [ ! -f "$HOSTFILE" ]; then
    echo "${RED}Error: $HOSTFILE not found${NC}"
    exit 1
fi

if [ ! -f "$DATABASE" ]; then
    echo "${RED}Error: $DATABASE not found${NC}"
    echo "Run setup-db.sh or create-db.sh first!"
    exit 1
fi

# Count entries
LINES=$(wc -l < "$HOSTFILE" | tr -d ' ')
BEFORE=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_hosts;" 2>/dev/null)

if [ -z "$BEFORE" ]; then
    echo "${RED}Error: block_hosts table does not exist${NC}"
    echo "Run setup-db.sh first!"
    exit 1
fi

echo "Input file:  $HOSTFILE"
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
.import '$HOSTFILE' block_hosts
SQL

# Set permissions
chown root:${DNSMASQ_GROUP} "$DATABASE" "${DATABASE}-wal" "${DATABASE}-shm" 2>/dev/null
chmod 644 "$DATABASE" "${DATABASE}-wal" "${DATABASE}-shm" 2>/dev/null

# Statistics
AFTER=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_hosts;")
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
