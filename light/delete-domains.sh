#!/bin/sh
# Delete entries from block_wildcard (domain wildcard blocking)
# Version: 5.0
#
# This script removes domains from an EXISTING database.
# Can delete a single entry or multiple entries from a file.
#
# Usage: ./delete-domains.sh <domain|file> [database]
#        ./delete-domains.sh example.com
#        ./delete-domains.sh /path/to/whitelist.txt
#        ./delete-domains.sh example.com /path/to/db.db
#
# Input format (file): One domain per line
# Example:
#   ads.example.com
#   tracker.org

# Configuration
INPUT="${1:-/op/databaseAVX/domains/delete}"
DATABASE="${2:-/usr/local/etc/dnsmasq/aviontex.db}"
DNSMASQ_GROUP="wheel"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=========================================="
echo " Delete Domains (block_wildcard)"
echo "=========================================="
echo ""

# Check input
if [ -z "$INPUT" ]; then
    echo "${RED}Error: No input specified${NC}"
    echo ""
    echo "Usage: $0 <domain|file> [database]"
    echo "       $0 example.com"
    echo "       $0 /path/to/whitelist.txt"
    exit 1
fi

# Check database exists
if [ ! -f "$DATABASE" ]; then
    echo "${RED}Error: $DATABASE not found${NC}"
    exit 1
fi

# Count before
BEFORE=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_wildcard;" 2>/dev/null)

if [ -z "$BEFORE" ]; then
    echo "${RED}Error: block_wildcard table does not exist${NC}"
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
DELETE FROM block_wildcard WHERE Domain IN (SELECT Domain FROM delete_list);

-- Cleanup
DROP TABLE delete_list;
SQL

else
    # Single entry mode
    echo "Mode:     Single entry deletion"
    echo "Domain:   $INPUT"
    echo ""

    # Check if entry exists
    EXISTS=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_wildcard WHERE Domain = '$INPUT';")

    if [ "$EXISTS" -eq 0 ]; then
        echo "${YELLOW}Warning: '$INPUT' not found in block_wildcard${NC}"
        echo ""
        exit 0
    fi

    echo "Deleting..."
    sqlite3 "$DATABASE" "DELETE FROM block_wildcard WHERE Domain = '$INPUT';"
fi

# Set permissions
chown root:${DNSMASQ_GROUP} "$DATABASE" "${DATABASE}-wal" "${DATABASE}-shm" 2>/dev/null
chmod 644 "$DATABASE" "${DATABASE}-wal" "${DATABASE}-shm" 2>/dev/null

# Statistics
AFTER=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_wildcard;")
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
