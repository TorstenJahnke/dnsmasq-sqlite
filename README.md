# dnsmasq-sqlite

SQLite-basierter DNS-Blocker für DNSMASQ

## Projekt-Status

Dieses Repository wird gerade umstrukturiert:

1. ✅ **Legacy-Code gesichert** (`legacy/` Verzeichnis)
   - Originale SQLite-Integration für dnsmasq v2.81 (2018)
   - Enthält Bug-Fix Dokumentation und korrigierte Version

2. ⏳ **Warte auf aktuellen DNSMASQ Source Code**
   - Wird auf aktuelle Version portiert (v2.90 oder neuer)

3. 📋 **Next Steps**
   - SQLite-Integration auf neue DNSMASQ-Version portieren
   - Logik-Bug beheben (Whitelist → Blacklist)
   - Testen und dokumentieren

## Was ist dnsmasq-sqlite?

Eine modifizierte Version von DNSMASQ die SQLite nutzt um DNS-Requests dynamisch zu blockieren:

### Funktionsweise (DNS-Blocker)
- Domain **in Datenbank** → wird blockiert (NXDOMAIN)
- Domain **nicht in Datenbank** → normale Weiterleitung an DNS-Forwarder

### Vorteile
- 🚀 **Dynamisch**: Domains zur Laufzeit hinzufügen/entfernen (kein DNSMASQ-Restart nötig)
- ⚡ **Schnell**: Indexierte SQLite-Lookups für Millionen von Domains
- 💾 **Effizient**: Weniger RAM als große Hosts-Dateien
- 🔧 **Flexibel**: Standard SQL für Domain-Management

## Legacy-Integration (v2.81)

Details zur ursprünglichen Integration finden sich in `legacy/INTEGRATION.md`

**Wichtiger Hinweis**: Die ursprüngliche v2.81 Integration hatte einen Logik-Bug (Whitelist statt Blacklist). Die korrigierte Version ist als `legacy/db-FIXED.c` verfügbar.

## Verwendung (nach Portierung)

```bash
# DNSMASQ mit SQLite-Blocker starten
./src/dnsmasq -d -p 9999 --db-file blocklist.db --log-queries

# Domain zur Blocklist hinzufügen (zur Laufzeit!)
sqlite3 blocklist.db "INSERT INTO domain VALUES ('ads.example.com');"

# Domain freigeben
sqlite3 blocklist.db "DELETE FROM domain WHERE Domain='ads.example.com';"
```

## Building (nach Portierung)

```bash
sudo apt install build-essential libsqlite3-dev
make
```

## Lizenz

Wie DNSMASQ selbst (GPL v2/v3)
