#!/bin/sh
# Migration script: Old dnsmasq (hosts + regex) → SQLite
# Converts your existing hosts and regex files to SQLite database
# Usage: ./migrate-to-sqlite-freebsd.sh

set -e

echo "========================================="
echo "Migration: HOSTS + Regex → SQLite"
echo "========================================="
echo ""

# Configuration
DB_FILE="/var/db/dnsmasq/blocklist.db"
OLD_CONFIG_DIR="/usr/local/etc/dnsmasq"
BACKUP_DIR="/var/db/dnsmasq/backup-$(date +%Y%m%d-%H%M%S)"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Error: This script must be run as root"
    echo "Run: sudo $0"
    exit 1
fi

echo "This script will:"
echo "  1. Scan your dnsmasq config for hosts files"
echo "  2. Scan your dnsmasq config for regex files"
echo "  3. Convert everything to SQLite"
echo "  4. Create backup of old files"
echo "  5. Update config to use SQLite"
echo ""
echo "Database will be created at: $DB_FILE"
echo "Backups will be saved to: $BACKUP_DIR"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [ "$REPLY" != "y" ]; then
    echo "Aborted."
    exit 1
fi

echo ""

# Create backup directory
echo "Creating backup directory..."
mkdir -p "$BACKUP_DIR"
echo "  ✅ $BACKUP_DIR"
echo ""

# Create database
if [ -f "$DB_FILE" ]; then
    echo "⚠️  Database already exists: $DB_FILE"
    read -p "Overwrite? (y/n) " -n 1 -r
    echo
    if [ "$REPLY" = "y" ]; then
        cp "$DB_FILE" "$BACKUP_DIR/blocklist.db.backup"
        rm "$DB_FILE"
        echo "  Backup saved to: $BACKUP_DIR/blocklist.db.backup"
    else
        echo "Using existing database."
    fi
fi

if [ ! -f "$DB_FILE" ]; then
    echo "Creating SQLite database..."
    ./createdb-regex.sh "$DB_FILE"
    echo "  ✅ $DB_FILE created"
    echo ""
fi

# Scan for hosts files in config
echo "Scanning for hosts files in dnsmasq config..."
HOSTS_FILES=""

if [ -f "$OLD_CONFIG_DIR/dnsmasq.conf" ]; then
    HOSTS_FILES=$(grep -E "^[[:space:]]*addn-hosts=" "$OLD_CONFIG_DIR/dnsmasq.conf" 2>/dev/null | sed 's/^[[:space:]]*addn-hosts=//' || true)
fi

if [ -f "$OLD_CONFIG_DIR/dnsmasq.settings.conf" ]; then
    HOSTS_FILES="$HOSTS_FILES $(grep -E "^[[:space:]]*addn-hosts=" "$OLD_CONFIG_DIR/dnsmasq.settings.conf" 2>/dev/null | sed 's/^[[:space:]]*addn-hosts=//' || true)"
fi

# Remove duplicates and empty lines
HOSTS_FILES=$(echo "$HOSTS_FILES" | tr ' ' '\n' | sort -u | grep -v '^$' || true)

if [ -n "$HOSTS_FILES" ]; then
    echo "Found hosts files:"
    echo "$HOSTS_FILES" | while read -r hfile; do
        echo "  - $hfile"
    done
    echo ""

    echo "Converting hosts files to SQLite..."
    echo "$HOSTS_FILES" | while read -r hfile; do
        if [ -f "$hfile" ]; then
            echo "  Converting: $hfile"
            ./convert-hosts-to-sqlite.sh "$hfile" "$DB_FILE" 0.0.0.0 ::

            # Backup original
            cp "$hfile" "$BACKUP_DIR/$(basename "$hfile")"
            echo "    ✅ Converted (backup: $BACKUP_DIR/$(basename "$hfile"))"
        else
            echo "    ⚠️  File not found: $hfile (skipping)"
        fi
    done
    echo ""
else
    echo "  No hosts files found in config."
    echo ""
fi

# Scan for regex files
echo "Scanning for regex files..."
REGEX_FILES=""

# Common locations for regex files
POSSIBLE_REGEX_FILES="
$OLD_CONFIG_DIR/regex.txt
$OLD_CONFIG_DIR/regex-block.txt
$OLD_CONFIG_DIR/blocklist-regex.txt
/var/db/dnsmasq/regex.txt
"

for rfile in $POSSIBLE_REGEX_FILES; do
    if [ -f "$rfile" ]; then
        REGEX_FILES="$REGEX_FILES $rfile"
    fi
done

# Remove duplicates
REGEX_FILES=$(echo "$REGEX_FILES" | tr ' ' '\n' | sort -u | grep -v '^$' || true)

if [ -n "$REGEX_FILES" ]; then
    echo "Found regex files:"
    echo "$REGEX_FILES" | while read -r rfile; do
        echo "  - $rfile"
    done
    echo ""

    echo "Converting regex files to SQLite..."
    echo "$REGEX_FILES" | while read -r rfile; do
        if [ -f "$rfile" ]; then
            echo "  Converting: $rfile"

            # Count patterns
            pattern_count=$(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$rfile" | wc -l | tr -d ' ')
            echo "    Patterns: $pattern_count"

            # Import with default IP-set
            # TODO: Adjust IPs if needed
            cp "$rfile" regex-block.txt
            ./add-regex-patterns.sh 0.0.0.0 :: "$DB_FILE"
            rm regex-block.txt

            # Backup original
            cp "$rfile" "$BACKUP_DIR/$(basename "$rfile")"
            echo "    ✅ Converted (backup: $BACKUP_DIR/$(basename "$rfile"))"
        fi
    done
    echo ""
else
    echo "  No regex files found."
    echo "  If you have regex patterns, create regex-block.txt and run:"
    echo "  ./add-regex-patterns.sh 0.0.0.0 :: $DB_FILE"
    echo ""
fi

# Update config
echo "Updating dnsmasq.settings.conf..."

if [ -f "$OLD_CONFIG_DIR/dnsmasq.settings.conf" ]; then
    # Backup
    cp "$OLD_CONFIG_DIR/dnsmasq.settings.conf" "$BACKUP_DIR/dnsmasq.settings.conf.backup"
    echo "  Backup: $BACKUP_DIR/dnsmasq.settings.conf.backup"

    # Comment out old addn-hosts lines
    sed -i.tmp 's/^[[:space:]]*addn-hosts=/# MIGRATED TO SQLITE: # addn-hosts=/' "$OLD_CONFIG_DIR/dnsmasq.settings.conf"

    # Check if SQLite config already exists
    if ! grep -q "db-file=" "$OLD_CONFIG_DIR/dnsmasq.settings.conf" 2>/dev/null; then
        # Add SQLite config
        cat >> "$OLD_CONFIG_DIR/dnsmasq.settings.conf" <<EOF

# ############################################################################
# SQLite Blocklist (migrated from hosts + regex files)
# ############################################################################

# SQLite Database
db-file=$DB_FILE

# Termination IP addresses (fallback if domain has NULL in DB)
db-block-ipv4=0.0.0.0
db-block-ipv6=::

EOF
        echo "  ✅ Added SQLite configuration"
    else
        echo "  ✅ SQLite configuration already exists"
    fi

    rm "$OLD_CONFIG_DIR/dnsmasq.settings.conf.tmp" 2>/dev/null || true
else
    echo "  ⚠️  dnsmasq.settings.conf not found, skipping config update"
fi

echo ""

# Show database stats
echo "========================================="
echo "✅ Migration completed!"
echo "========================================="
echo ""
echo "Database statistics:"
sqlite3 "$DB_FILE" <<SQL
.mode line
SELECT 'Exact domains:  ' || COUNT(*) FROM domain_exact;
SELECT 'Wildcard domains: ' || COUNT(*) FROM domain;
SELECT 'Regex patterns: ' || COUNT(*) FROM domain_regex;
SQL

db_size=$(stat -c%s "$DB_FILE" 2>/dev/null || stat -f%z "$DB_FILE" 2>/dev/null)
db_size_mb=$((db_size / 1024 / 1024))
echo "Database size:   ${db_size_mb} MB"
echo ""

echo "Backups saved to: $BACKUP_DIR"
echo ""

echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "1. Test new configuration:"
echo "   dnsmasq --test -C $OLD_CONFIG_DIR/dnsmasq.conf"
echo ""
echo "2. Test in foreground:"
echo "   dnsmasq -d -C $OLD_CONFIG_DIR/dnsmasq.conf --log-queries"
echo ""
echo "3. If everything works, restart service:"
echo "   service dnsmasq restart"
echo ""
echo "4. Monitor logs:"
echo "   tail -f $OLD_CONFIG_DIR/status.log"
echo ""
echo "5. Compare performance:"
echo "   # Before: Check RAM usage of old dnsmasq"
echo "   # After: Check RAM usage of new dnsmasq"
echo "   ps aux | grep dnsmasq"
echo ""
echo "Expect: 90%+ RAM reduction for large hosts files!"
echo ""
