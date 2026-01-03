#!/bin/sh
# SQLite Blocklist Database Creator for FreeBSD
# Version: 5.0
#
# Usage: ./create-db.sh

# Konfiguration
BLACKLIST="/usr/local/etc/blacklist.txt"
DATABASE="/usr/local/etc/dnsmasq/aviontex.db"

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=========================================="
echo " SQLite Blocklist Database Creator v5.0"
echo "=========================================="
echo ""

# Prüfe ob Quelldatei existiert
if [ ! -f "$BLACKLIST" ]; then
    echo "${RED}Fehler: $BLACKLIST nicht gefunden${NC}"
    exit 1
fi

# Zähle Einträge
LINES=$(wc -l < "$BLACKLIST" | tr -d ' ')
echo "Quelldatei:  $BLACKLIST"
echo "Einträge:    $LINES"
echo "Zieldatei:   $DATABASE"
echo ""

# Lösche alte Datenbank
echo "[1/5] Lösche alte Datenbank..."
rm -f "$DATABASE" "${DATABASE}-wal" "${DATABASE}-shm"

# Erstelle Verzeichnis falls nicht vorhanden
mkdir -p "$(dirname "$DATABASE")"

# Erstelle Datenbank
echo "[2/5] Erstelle optimierte Datenbank..."
sqlite3 "$DATABASE" << 'SQL'
-- Import-Optimierungen (maximale Geschwindigkeit)
PRAGMA page_size = 8192;
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
PRAGMA cache_size = -4194304;
PRAGMA temp_store = MEMORY;
PRAGMA locking_mode = EXCLUSIVE;

-- Tabellen (WITHOUT ROWID = Tabelle ist der Index)
CREATE TABLE block_wildcard (
    Domain TEXT PRIMARY KEY NOT NULL
) WITHOUT ROWID;

CREATE TABLE block_hosts (
    Domain TEXT PRIMARY KEY NOT NULL
) WITHOUT ROWID;

CREATE TABLE block_ips (
    Source_IP TEXT PRIMARY KEY NOT NULL,
    Target_IP TEXT NOT NULL
) WITHOUT ROWID;
SQL

# Import
echo "[3/5] Importiere Domains (das dauert bei $LINES Einträgen)..."
START=$(date +%s)

sqlite3 "$DATABASE" << SQL
PRAGMA synchronous = OFF;
PRAGMA journal_mode = OFF;
PRAGMA cache_size = -4194304;
.mode list
.import $BLACKLIST block_wildcard
SQL

END=$(date +%s)
DURATION=$((END - START))

# Optimieren
echo "[4/5] Optimiere Datenbank..."
sqlite3 "$DATABASE" << 'SQL'
PRAGMA locking_mode = NORMAL;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
ANALYZE;
SQL

# Verifizieren
echo "[5/5] Verifiziere..."
COUNT=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_wildcard;")
SIZE=$(ls -lh "$DATABASE" | awk '{print $5}')

echo ""
echo "=========================================="
echo "${GREEN} Fertig!${NC}"
echo "=========================================="
echo ""
echo "Datenbank:   $DATABASE"
echo "Einträge:    $COUNT"
echo "Größe:       $SIZE"
echo "Dauer:       ${DURATION}s"
echo ""
echo "Tabellen:"
sqlite3 "$DATABASE" ".tables"
echo ""
