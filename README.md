# dnsmasq-sqlite

SQLite-basierter DNS-Blocker für DNSMASQ

## ✅ Status: Portierung auf v2.91 abgeschlossen!

Die SQLite-Integration wurde erfolgreich auf **dnsmasq v2.91** (2025) portiert mit korrigierter Blacklist-Logik.

## 📂 Repository-Struktur

```
dnsmasq-sqlite/
├── dnsmasq-2.91/           # ← AKTUELLE VERSION (v2.91 + SQLite)
│   ├── src/                # Gepatchte Source-Dateien
│   ├── Makefile            # Mit SQLite-Build-Flags
│   ├── createdb.sh         # DB-Erstellungs-Script
│   └── README-SQLITE.md    # Ausführliche Doku
├── legacy/                 # Legacy v2.81 Integration
│   ├── INTEGRATION.md      # Portierungs-Anleitung
│   ├── db.c                # Original (Whitelist-Bug)
│   ├── db-FIXED.c          # Korrigiert (Blacklist)
│   └── createdb.sh         # DB-Script
└── README.md               # Diese Datei
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

# 2. Kompilieren
cd dnsmasq-2.91
make

# 3. Datenbank erstellen
sqlite3 blocklist.db "CREATE TABLE domain (Domain TEXT UNIQUE);"
sqlite3 blocklist.db "CREATE UNIQUE INDEX idx_Domain ON domain(Domain);"
sqlite3 blocklist.db "INSERT INTO domain VALUES ('ads.example.com');"

# 4. DNSMASQ starten
./src/dnsmasq -d -p 5353 --db-file blocklist.db --log-queries

# 5. Testen
dig @127.0.0.1 -p 5353 ads.example.com        # → NXDOMAIN (geblockt)
dig @127.0.0.1 -p 5353 google.com             # → Normale Auflösung
```

## 🔄 Zur Laufzeit ändern (OHNE Restart!)

```bash
# Domain blockieren
sqlite3 blocklist.db "INSERT INTO domain VALUES ('tracker.example.com');"

# Sofort wirksam - kein Restart nötig!

# Domain freigeben
sqlite3 blocklist.db "DELETE FROM domain WHERE Domain='tracker.example.com');"
```

## 🐛 Wichtiger Bug-Fix

Die ursprüngliche v2.81 Integration hatte einen **Logik-Bug** (Whitelist statt Blacklist):

| Version | Logik | Verhalten |
|---------|-------|-----------|
| ❌ v2.81 Original | `if (!db_check_allow())` | Nur Domains IN DB wurden aufgelöst (Whitelist) |
| ✅ v2.91 Fixed | `if (db_check_block())` | Domains IN DB werden blockiert (Blacklist) |

Diese Portierung enthält die **korrigierte Blacklist-Logik**!

## 📝 Änderungen an DNSMASQ v2.91

Nur **8 Dateien** wurden modifiziert:

| Datei | Änderung | Zeilen |
|-------|----------|--------|
| `src/db.c` | ✨ NEU - SQLite-Logik | +106 |
| `src/config.h` | `#define HAVE_SQLITE` | +1 |
| `src/dnsmasq.h` | Function Declarations | +8 |
| `src/option.c` | CLI Option `--db-file` | +4 Stellen |
| `src/rfc1035.c` | Blacklist-Check | +15 |
| `Makefile` | SQLite Build-Flags | +3 Stellen |
| `createdb.sh` | ✨ NEU - DB-Script | +10 |
| `.gitignore` | Build-Artefakte | +11 |

**Total**: ~150 Zeilen Code-Änderungen

## 📖 Dokumentation

- **`dnsmasq-2.91/README-SQLITE.md`** - Ausführliche Anleitung für v2.91
- **`legacy/INTEGRATION.md`** - Portierungs-Anleitung für andere Versionen

## 🔧 Build-Informationen

- **Version**: dnsmasq 2.91 + SQLite
- **Binary-Größe**: ~447KB
- **Kompiliert mit**: `-lsqlite3`
- **Getestet auf**: Linux 4.4.0

## 💡 Use Cases

- **Ad-Blocker**: DNS-Level Werbeblocker
- **Malware-Protection**: Blockierung von bekannten Malware-Domains
- **Parental Control**: Jugendschutz-Filter
- **Corporate Filter**: Unternehmensnetzwerk-Filterung
- **Privacy**: Tracking-Domain-Blocker

## 🤝 Contribution

- Original DNSMASQ: Simon Kelley (https://thekelleys.org.uk/dnsmasq/)
- SQLite-Integration: basierend auf v2.81 Patch
- v2.91 Port + Bug-Fix: 2025

## 📄 Lizenz

Wie DNSMASQ selbst (GPL v2/v3)

## 🔗 Links

- DNSMASQ Official: https://thekelleys.org.uk/dnsmasq/
- SQLite: https://sqlite.org/
