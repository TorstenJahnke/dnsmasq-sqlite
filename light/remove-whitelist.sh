#!/bin/sh
# Remove whitelisted domains from blocklist database
# Version: 5.0
#
# Usage: ./remove-whitelist.sh [whitelist] [datenbank]
#        ./remove-whitelist.sh /usr/local/etc/whitelist.txt
#        ./remove-whitelist.sh /path/to/whitelist.txt /path/to/db.db

# Konfiguration
WHITELIST="${1:-/usr/local/etc/whitelist.txt}"
DATABASE="${2:-/usr/local/etc/dnsmasq/aviontex01.db}"

echo ""
echo "=========================================="
echo " Whitelist Removal"
echo "=========================================="
echo ""

# Prüfe ob Dateien existieren
if [ ! -f "$WHITELIST" ]; then
    echo "Fehler: $WHITELIST nicht gefunden"
    exit 1
fi

if [ ! -f "$DATABASE" ]; then
    echo "Fehler: $DATABASE nicht gefunden"
    exit 1
fi

# Zähle
LINES=$(wc -l < "$WHITELIST" | tr -d ' ')
BEFORE=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_wildcard;")

echo "Whitelist:   $WHITELIST"
echo "Einträge:    $LINES"
echo "Datenbank:   $DATABASE"
echo "Vorher:      $BEFORE"
echo ""

# Temporäre Tabelle erstellen und Whitelist importieren
echo "Lösche Einträge..."
sqlite3 "$DATABASE" << SQL
PRAGMA synchronous = OFF;
PRAGMA cache_size = -1048576;

-- Temporäre Tabelle für Whitelist
CREATE TEMP TABLE whitelist (Domain TEXT PRIMARY KEY);

.mode list
.import $WHITELIST whitelist

-- Lösche alle Domains die in Whitelist sind
DELETE FROM block_wildcard WHERE Domain IN (SELECT Domain FROM whitelist);
DELETE FROM block_hosts WHERE Domain IN (SELECT Domain FROM whitelist);

-- Aufräumen
DROP TABLE whitelist;
SQL

# Statistik
AFTER=$(sqlite3 "$DATABASE" "SELECT COUNT(*) FROM block_wildcard;")
REMOVED=$((BEFORE - AFTER))

echo ""
echo "=========================================="
echo " Fertig!"
echo "=========================================="
echo ""
echo "Vorher:      $BEFORE"
echo "Nachher:     $AFTER"
echo "Gelöscht:    $REMOVED"
echo ""
