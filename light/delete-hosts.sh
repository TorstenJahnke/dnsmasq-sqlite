#!/bin/sh
# Delete entries from block_hosts (exact hostname matching)
# Version: 5.0
#
# This script removes hosts from an EXISTING database.
# Can delete a single entry or multiple entries from a file.
#
# Usage: ./delete-hosts.sh <host|file> [database]
#        ./delete-hosts.sh ads.example.com
#        ./delete-hosts.sh /path/to/remove-hosts.txt
#        ./delete-hosts.sh ads.example.com /path/to/db.db
#
# Input format (file): One hostname per line
# Example:
#   ads.example.com
#   tracker.example.org

# Configuration
INPUT="${1:-/op/databaseAVX/hosts/delete}"
DATABASE="${2:-/usr/local/etc/dnsmasq/aviontex.db}"
DNSMASQ_GROUP="wheel"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=========================================="
echo " Delete Hosts (block_hosts)"
echo "=========================================="
echo ""

# Check input
if [ -z "$INPUT" ]; then
    echo "${RED}Error: No input specified${NC}"
    echo ""
    echo "Usage: $0 <host|file> [database]"
    echo "       $0 ads.example.com"
    echo "       $0 /path/to/remove-hosts.txt"
    exit 1
fi

# Check database exists
if [ ! -f "$DATABASE" ]; then
    echo "${RED}Error: $DATABASE not found${NC}"
    exit 1
fi

# Count before
BEFORE=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_hosts;" 2>/dev/null)

if [ -z "$BEFORE" ]; then
    echo "${RED}Error: block_hosts table does not exist${NC}"
    exit 1
fi

echo "Database: $DATABASE"
echo "Before:   $BEFORE"
echo ""

# Check if input is a file or single entry
if [ -f "$INPUT" ]; then
    # File mode: delete multiple entries
    LINES=$(wc -l < "$INPUT" | tr -d ' ')
    echo "Mode:     File deletion"
    echo "File:     $INPUT"
    echo "Entries:  $LINES"
    echo ""
    echo "Deleting..."

    # Create temp table, import entries to delete, then delete matching
    sqlite3 "$DATABASE" << SQL
PRAGMA synchronous = OFF;
PRAGMA cache_size = -1048576;

-- Create temp table for entries to delete
CREATE TEMP TABLE delete_list (Domain TEXT PRIMARY KEY NOT NULL) WITHOUT ROWID;

-- Import entries to delete
.mode list
.import '$INPUT' delete_list

-- Delete matching entries
DELETE FROM block_hosts WHERE Domain IN (SELECT Domain FROM delete_list);

-- Cleanup
DROP TABLE delete_list;
SQL

else
    # Single entry mode
    echo "Mode:     Single entry deletion"
    echo "Host:     $INPUT"
    echo ""

    # Check if entry exists
    EXISTS=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_hosts WHERE Domain = '$INPUT';")

    if [ "$EXISTS" -eq 0 ]; then
        echo "${YELLOW}Warning: '$INPUT' not found in block_hosts${NC}"
        echo ""
        exit 0
    fi

    echo "Deleting..."
    sqlite3 "$DATABASE" "DELETE FROM block_hosts WHERE Domain = '$INPUT';"
fi

# Set permissions
chown root:${DNSMASQ_GROUP} "$DATABASE" "${DATABASE}-wal" "${DATABASE}-shm" 2>/dev/null
chmod 644 "$DATABASE" "${DATABASE}-wal" "${DATABASE}-shm" 2>/dev/null

# Statistics
AFTER=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_hosts;")
DELETED=$((BEFORE - AFTER))

echo ""
echo "=========================================="
echo "${GREEN} Done!${NC}"
echo "=========================================="
echo ""
echo "Before:  $BEFORE"
echo "After:   $AFTER"
echo "Deleted: $DELETED"
echo ""
