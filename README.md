# dnsmasq-sqlite

SQLite-basierter DNS-Blocker für DNSMASQ v2.91

## 📂 Repository-Struktur

```
dnsmasq-sqlite/
├── dnsmasq-2.91/              # Clean DNSMASQ v2.91 Source Code
├── dnsmasq2.91-PATCH/         # SQLite Integration Patches
│   ├── src/db.c               # SQLite database implementation
│   ├── src/*.{c,h}            # Modified DNSMASQ source files
│   ├── Makefile               # Build configuration with SQLite
│   └── README.md              # Patch documentation
├── Management_DB/             # Database management scripts
│   ├── Database_Creation/     # DB creation and optimization scripts
│   ├── Setup/                 # FreeBSD/Linux setup scripts
│   ├── Build/                 # Build scripts and patches
│   ├── Import/Export/         # Data import/export tools
│   └── Search/Delete/Reset/   # Database management tools
└── Docs/                      # Additional documentation
```

## 🎯 Was ist dnsmasq-sqlite?

Eine modifizierte Version von DNSMASQ die SQLite nutzt um DNS-Requests dynamisch zu blockieren.

### Funktionsweise (DNS-Blocker)

```
Eingehende DNS-Query
    ↓
Domain in SQLite-Datenbank?
    ├─ JA  → BLOCKIEREN (NXDOMAIN)
    └─ NEIN → Normale Weiterleitung an DNS-Forwarder
```

### Vorteile

- 🚀 **Dynamisch**: Domains zur Laufzeit hinzufügen/entfernen (kein DNSMASQ-Restart nötig)
- ⚡ **Schnell**: Indexierte SQLite-Lookups für Millionen von Domains
- 💾 **Effizient**: Weniger RAM als große Hosts-Dateien
- 🔧 **Flexibel**: Standard SQL für Domain-Management

## 🚀 Quick Start

```bash
# 1. Dependencies installieren
sudo apt install build-essential libsqlite3-dev

# 2. Patches anwenden
cp dnsmasq2.91-PATCH/* dnsmasq-2.91/ -r

# 3. Kompilieren
cd dnsmasq-2.91
make

# 4. Datenbank erstellen
cd ../Management_DB/Database_Creation
./createdb.sh

# 5. DNSMASQ starten
cd ../../dnsmasq-2.91
./src/dnsmasq -d -p 5353 --db-file blocklist.db --log-queries

# 6. Testen
dig @127.0.0.1 -p 5353 ads.example.com        # → NXDOMAIN (geblockt)
dig @127.0.0.1 -p 5353 google.com             # → Normale Auflösung
```

## 🔄 Dynamische Verwaltung (ohne Restart)

```bash
# Domain blockieren
sqlite3 blocklist.db "INSERT INTO domain VALUES ('tracker.example.com');"

# Domain freigeben
sqlite3 blocklist.db "DELETE FROM domain WHERE Domain='tracker.example.com';"

# Oder verwende die Management-Scripte in Management_DB/
```

## 🔧 Implementierung

Die SQLite-Integration verwendet eine Blacklist-Logik: Domains in der Datenbank werden blockiert (NXDOMAIN), alle anderen werden normal aufgelöst.

## 📝 Patches

Siehe `dnsmasq2.91-PATCH/README.md` für Details zu allen Änderungen.

**Modifizierte Dateien:**
- `src/db.c` - SQLite database implementation (neu)
- `src/config.h` - SQLite configuration
- `src/dnsmasq.h` - Function declarations
- `src/option.c` - CLI option `--db-file`
- `src/rfc1035.c` - DNS query blocking logic
- `src/forward.c` - DNS forwarding integration
- `Makefile` - SQLite build flags

## 📖 Dokumentation

- **`dnsmasq2.91-PATCH/README.md`** - Patch-Dokumentation
- **`Management_DB/`** - Verschiedene Setup- und Management-Guides

## 💡 Use Cases

- **Ad-Blocker**: DNS-Level Werbeblocker
- **Malware-Protection**: Blockierung von bekannten Malware-Domains
- **Parental Control**: Jugendschutz-Filter
- **Corporate Filter**: Unternehmensnetzwerk-Filterung
- **Privacy**: Tracking-Domain-Blocker

## 🤝 Credits

- Original DNSMASQ: Simon Kelley (https://thekelleys.org.uk/dnsmasq/)
- SQLite-Integration für DNSMASQ v2.91

## 📄 Lizenz

Wie DNSMASQ selbst (GPL v2/v3)

## 🔗 Links

- DNSMASQ Official: https://thekelleys.org.uk/dnsmasq/
- SQLite: https://sqlite.org/
