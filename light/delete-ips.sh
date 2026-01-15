#!/bin/sh
# Delete entries from block_ips (IP address rewriting)
# Version: 5.0
#
# This script removes IP rewrite rules from an EXISTING database.
# Can delete a single entry or multiple entries from a file.
# Deletion is based on Source_IP (the primary key).
#
# Usage: ./delete-ips.sh <source_ip|file> [database]
#        ./delete-ips.sh 178.223.16.21
#        ./delete-ips.sh /path/to/remove-ips.txt
#        ./delete-ips.sh 178.223.16.21 /path/to/db.db
#
# Input format (file): One Source_IP per line
# Example:
#   178.223.16.21
#   192.168.1.100
#   2001:db8::1

# Configuration
INPUT="${1:-/op/databaseAVX/ip/delete}"
DATABASE="${2:-/usr/local/etc/dnsmasq/aviontex.db}"
DNSMASQ_GROUP="wheel"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=========================================="
echo " Delete IPs (block_ips)"
echo "=========================================="
echo ""

# Check input
if [ -z "$INPUT" ]; then
    echo "${RED}Error: No input specified${NC}"
    echo ""
    echo "Usage: $0 <source_ip|file> [database]"
    echo "       $0 178.223.16.21"
    echo "       $0 /path/to/remove-ips.txt"
    exit 1
fi

# Check database exists
if [ ! -f "$DATABASE" ]; then
    echo "${RED}Error: $DATABASE not found${NC}"
    exit 1
fi

# Count before
BEFORE=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_ips;" 2>/dev/null)

if [ -z "$BEFORE" ]; then
    echo "${RED}Error: block_ips table does not exist${NC}"
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

    # Create temp table, import Source_IPs to delete, then delete matching
    sqlite3 "$DATABASE" << SQL
PRAGMA synchronous = OFF;
PRAGMA cache_size = -1048576;

-- Create temp table for IPs to delete
CREATE TEMP TABLE delete_list (Source_IP TEXT PRIMARY KEY NOT NULL) WITHOUT ROWID;

-- Import IPs to delete
.mode list
.import '$INPUT' delete_list

-- Delete matching entries
DELETE FROM block_ips WHERE Source_IP IN (SELECT Source_IP FROM delete_list);

-- Cleanup
DROP TABLE delete_list;
SQL

else
    # Single entry mode
    echo "Mode:     Single entry deletion"
    echo "Source_IP: $INPUT"
    echo ""

    # Check if entry exists and show current mapping
    EXISTS=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_ips WHERE Source_IP = '$INPUT';")

    if [ "$EXISTS" -eq 0 ]; then
        echo "${YELLOW}Warning: '$INPUT' not found in block_ips${NC}"
        echo ""
        exit 0
    fi

    # Show what will be deleted
    TARGET=$(sqlite3 "$DATABASE" "SELECT Target_IP FROM block_ips WHERE Source_IP = '$INPUT';")
    echo "Current mapping: $INPUT -> $TARGET"
    echo ""

    echo "Deleting..."
    sqlite3 "$DATABASE" "DELETE FROM block_ips WHERE Source_IP = '$INPUT';"
fi

# Set permissions
chown root:${DNSMASQ_GROUP} "$DATABASE" "${DATABASE}-wal" "${DATABASE}-shm" 2>/dev/null
chmod 644 "$DATABASE" "${DATABASE}-wal" "${DATABASE}-shm" 2>/dev/null

# Statistics
AFTER=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_ips;")
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
