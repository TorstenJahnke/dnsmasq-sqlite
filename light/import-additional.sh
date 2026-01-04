#!/bin/sh
# Import additional blocklist into existing database
# Version: 5.0
#
# Usage: ./import-additional.sh [datei] [datenbank]
#        ./import-additional.sh /usr/local/etc/additional.txt
#        ./import-additional.sh /path/to/list.txt /path/to/db.db

# Konfiguration
ADDITIONAL="${1:-/usr/local/etc/additional-blacklist.txt}"
DATABASE="${2:-/usr/local/etc/dnsmasq/aviontex.db}"
DNSMASQ_GROUP="wheel"

echo ""
echo "=========================================="
echo " Additional Blocklist Import"
echo "=========================================="
echo ""

# Prüfe ob Dateien existieren
if [ ! -f "$ADDITIONAL" ]; then
    echo "Fehler: $ADDITIONAL nicht gefunden"
    exit 1
fi

if [ ! -f "$DATABASE" ]; then
    echo "Fehler: $DATABASE nicht gefunden"
    echo "Erst create-db.sh ausführen!"
    exit 1
fi

# Zähle
LINES=$(wc -l < "$ADDITIONAL" | tr -d ' ')
BEFORE=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_wildcard;")

echo "Quelldatei:  $ADDITIONAL"
echo "Neue:        $LINES"
echo "Datenbank:   $DATABASE"
echo "Vorher:      $BEFORE"
echo ""

# Import (INSERT OR IGNORE = Duplikate überspringen)
echo "Importiere..."
sqlite3 "$DATABASE" << SQL
PRAGMA synchronous = OFF;
PRAGMA cache_size = -1048576;
.mode list
.import $ADDITIONAL block_wildcard
SQL

# Berechtigungen setzen
chown root:${DNSMASQ_GROUP} "$DATABASE" "${DATABASE}-wal" "${DATABASE}-shm" 2>/dev/null
chmod 640 "$DATABASE" "${DATABASE}-wal" "${DATABASE}-shm" 2>/dev/null

# Statistik
AFTER=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_wildcard;")
ADDED=$((AFTER - BEFORE))

echo ""
echo "=========================================="
echo " Fertig!"
echo "=========================================="
echo ""
echo "Vorher:      $BEFORE"
echo "Nachher:     $AFTER"
echo "Hinzugefügt: $ADDED"
echo "(Duplikate wurden übersprungen)"
echo ""
