#!/bin/bash
# ============================================================================
# Complete Database Workflow: Import → Cleanup → Export → Reset
# ============================================================================
# Usage: ./workflow-cleanup-database.sh <database> <import-dir> [--reset-after]
#
# Steps:
#   1. Import all .txt files from import-dir
#   2. Cleanup duplicate entries (priority-based)
#   3. Export cleaned data to backup folder
#   4. (Optional) Reset database if --reset-after is specified
#
# File naming convention in import-dir:
#   block-exact.txt       → block_exact table
#   block-wildcard.txt    → block_wildcard table
#   block-regex.txt       → block_regex table
#   dns-allow.txt         → fqdn_dns_allow table
#   dns-block.txt         → fqdn_dns_block table
# ============================================================================

set -e

DB_FILE="${1}"
IMPORT_DIR="${2}"
RESET_FLAG="${3}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

if [ -z "$DB_FILE" ] || [ -z "$IMPORT_DIR" ]; then
    echo "Usage: $0 <database> <import-dir> [--reset-after]"
    echo ""
    echo "Example:"
    echo "  $0 blocklist.db ./data-import"
    echo "  $0 blocklist.db ./data-import --reset-after"
    echo ""
    echo "Import directory structure:"
    echo "  data-import/"
    echo "    ├── block-exact.txt       # Exact match domains"
    echo "    ├── block-wildcard.txt    # Wildcard domains"
    echo "    ├── block-regex.txt       # Regex patterns"
    echo "    ├── dns-allow.txt         # Whitelist domains"
    echo "    └── dns-block.txt         # Blacklist domains"
    echo ""
    echo "Options:"
    echo "  --reset-after  Reset database after export (WARNING: deletes all data!)"
    echo ""
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "❌ Error: Database '$DB_FILE' not found!"
    echo ""
    echo "Create database first:"
    echo "  cd Database_Creation"
    echo "  ./createdb.sh $DB_FILE"
    exit 1
fi

if [ ! -d "$IMPORT_DIR" ]; then
    echo "❌ Error: Import directory '$IMPORT_DIR' not found!"
    exit 1
fi

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Database Cleanup Workflow${NC}"
echo -e "${BLUE}=========================================${NC}"
echo "Database:    $DB_FILE"
echo "Import from: $IMPORT_DIR"
echo "Reset after: $([ "$RESET_FLAG" = "--reset-after" ] && echo "YES" || echo "NO")"
echo ""

# Create backup directory with timestamp
BACKUP_DIR="./backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo -e "${GREEN}Backup directory: $BACKUP_DIR${NC}"
echo ""

# =============================================================================
# STEP 1: IMPORT DATA
# =============================================================================
echo -e "${YELLOW}=========================================${NC}"
echo -e "${YELLOW}STEP 1: Importing Data${NC}"
echo -e "${YELLOW}=========================================${NC}"
echo ""

IMPORTED_FILES=0

# Import block-exact
if [ -f "$IMPORT_DIR/block-exact.txt" ]; then
    echo "Importing block-exact.txt..."
    $SCRIPT_DIR/Import/import-block-exact.sh "$DB_FILE" "$IMPORT_DIR/block-exact.txt"
    IMPORTED_FILES=$((IMPORTED_FILES + 1))
    echo ""
fi

# Import block-wildcard
if [ -f "$IMPORT_DIR/block-wildcard.txt" ]; then
    echo "Importing block-wildcard.txt..."
    $SCRIPT_DIR/Import/import-block-wildcard.sh "$DB_FILE" "$IMPORT_DIR/block-wildcard.txt"
    IMPORTED_FILES=$((IMPORTED_FILES + 1))
    echo ""
fi

# Import block-regex
if [ -f "$IMPORT_DIR/block-regex.txt" ]; then
    echo "Importing block-regex.txt..."
    $SCRIPT_DIR/Import/import-block-regex.sh "$DB_FILE" "$IMPORT_DIR/block-regex.txt"
    IMPORTED_FILES=$((IMPORTED_FILES + 1))
    echo ""
fi

# Import dns-allow
if [ -f "$IMPORT_DIR/dns-allow.txt" ]; then
    echo "Importing dns-allow.txt..."
    $SCRIPT_DIR/Import/import-fqdn-dns-allow.sh "$DB_FILE" "$IMPORT_DIR/dns-allow.txt"
    IMPORTED_FILES=$((IMPORTED_FILES + 1))
    echo ""
fi

# Import dns-block
if [ -f "$IMPORT_DIR/dns-block.txt" ]; then
    echo "Importing dns-block.txt..."
    $SCRIPT_DIR/Import/import-fqdn-dns-block.sh "$DB_FILE" "$IMPORT_DIR/dns-block.txt"
    IMPORTED_FILES=$((IMPORTED_FILES + 1))
    echo ""
fi

if [ $IMPORTED_FILES -eq 0 ]; then
    echo "⚠️  Warning: No import files found in $IMPORT_DIR"
    echo ""
    echo "Expected files:"
    echo "  - block-exact.txt"
    echo "  - block-wildcard.txt"
    echo "  - block-regex.txt"
    echo "  - dns-allow.txt"
    echo "  - dns-block.txt"
    echo ""
    read -p "Continue anyway? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi
fi

echo -e "${GREEN}✅ Import completed: $IMPORTED_FILES file(s)${NC}"
echo ""

# =============================================================================
# STEP 2: CLEANUP DUPLICATES
# =============================================================================
echo -e "${YELLOW}=========================================${NC}"
echo -e "${YELLOW}STEP 2: Cleaning Up Duplicates${NC}"
echo -e "${YELLOW}=========================================${NC}"
echo ""

$SCRIPT_DIR/Delete/cleanup-duplicates.sh "$DB_FILE" --auto

echo ""

# =============================================================================
# STEP 3: EXPORT CLEANED DATA
# =============================================================================
echo -e "${YELLOW}=========================================${NC}"
echo -e "${YELLOW}STEP 3: Exporting Cleaned Data${NC}"
echo -e "${YELLOW}=========================================${NC}"
echo ""

echo "Exporting to: $BACKUP_DIR"
echo ""

# Export each table
sqlite3 "$DB_FILE" "SELECT Domain FROM block_exact;" > "$BACKUP_DIR/block-exact.txt" 2>/dev/null || true
sqlite3 "$DB_FILE" "SELECT Domain FROM block_wildcard;" > "$BACKUP_DIR/block-wildcard.txt" 2>/dev/null || true
sqlite3 "$DB_FILE" "SELECT Pattern FROM block_regex;" > "$BACKUP_DIR/block-regex.txt" 2>/dev/null || true
sqlite3 "$DB_FILE" "SELECT Domain FROM fqdn_dns_allow;" > "$BACKUP_DIR/dns-allow.txt" 2>/dev/null || true
sqlite3 "$DB_FILE" "SELECT Domain FROM fqdn_dns_block;" > "$BACKUP_DIR/dns-block.txt" 2>/dev/null || true

# Count exported lines
echo "Exported files:"
for file in "$BACKUP_DIR"/*.txt; do
    if [ -f "$file" ]; then
        COUNT=$(wc -l < "$file")
        echo "  $(basename $file): $COUNT entries"
    fi
done
echo ""

echo -e "${GREEN}✅ Export completed${NC}"
echo ""

# =============================================================================
# STEP 4 (OPTIONAL): RESET DATABASE
# =============================================================================
if [ "$RESET_FLAG" = "--reset-after" ]; then
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "${YELLOW}STEP 4: Resetting Database${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    echo ""

    echo -e "${RED}⚠️  WARNING: This will DELETE ALL data from the database!${NC}"
    echo ""
    echo "Backup location: $BACKUP_DIR"
    echo ""
    read -p "Are you sure you want to reset the database? (type 'RESET' to confirm): " CONFIRM

    if [ "$CONFIRM" = "RESET" ]; then
        echo ""
        echo "Resetting database..."
        $SCRIPT_DIR/Reset/reset-all-tables.sh "$DB_FILE" --yes

        echo ""
        echo -e "${GREEN}✅ Database reset completed${NC}"
    else
        echo ""
        echo "Reset cancelled."
    fi
    echo ""
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Workflow Summary${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "✅ 1. Import:  $IMPORTED_FILES file(s) imported"
echo "✅ 2. Cleanup: Duplicates removed (priority-based)"
echo "✅ 3. Export:  Cleaned data backed up to $BACKUP_DIR"
if [ "$RESET_FLAG" = "--reset-after" ]; then
    echo "✅ 4. Reset:   Database reset completed"
fi
echo ""

# Final statistics
echo "Final database statistics:"
sqlite3 "$DB_FILE" <<'EOF'
.mode column
.headers on
SELECT
    'block_exact' AS Table_Name,
    COUNT(*) AS Entries
FROM block_exact
UNION ALL
SELECT 'block_wildcard', COUNT(*) FROM block_wildcard
UNION ALL
SELECT 'block_regex', COUNT(*) FROM block_regex
UNION ALL
SELECT 'fqdn_dns_allow', COUNT(*) FROM fqdn_dns_allow
UNION ALL
SELECT 'fqdn_dns_block', COUNT(*) FROM fqdn_dns_block;
EOF

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Workflow completed successfully! 🚀${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "Next steps:"
echo "  1. Review cleaned data in $BACKUP_DIR"
echo "  2. Test database with dnsmasq"
echo "  3. Deploy to production"
echo ""
