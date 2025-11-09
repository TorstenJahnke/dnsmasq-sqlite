# dnsmasq v2.91 mit SQLite DNS-Blocker

Diese Version von dnsmasq enthält eine SQLite-Integration, die es ermöglicht, DNS-Anfragen dynamisch zu blockieren.

## 🎯 Funktionsweise (DNS-Blocker)

- **Domain IN Datenbank** → wird blockiert (NXDOMAIN)
- **Domain NICHT in Datenbank** → normale Weiterleitung an DNS-Forwarder

## ✨ Vorteile

- 🚀 **Dynamisch**: Domains zur Laufzeit hinzufügen/entfernen (kein DNSMASQ-Restart nötig!)
- ⚡ **Schnell**: Indexierte SQLite-Lookups für Millionen von Domains
- 💾 **Effizient**: Weniger RAM als große Hosts-Dateien
- 🔧 **Flexibel**: Standard SQL für Domain-Management

## 🛠️ Building

```bash
# Dependencies installieren
sudo apt install build-essential libsqlite3-dev

# Kompilieren
cd dnsmasq-2.91
make

# Binary liegt in: src/dnsmasq
```

## 📦 Datenbank erstellen

```bash
# Einfache Blocklist-Datenbank
sqlite3 blocklist.db "CREATE TABLE domain (Domain TEXT UNIQUE);"
sqlite3 blocklist.db "CREATE UNIQUE INDEX idx_Domain ON domain(Domain);"

# Domains hinzufügen
sqlite3 blocklist.db "INSERT INTO domain VALUES ('ads.example.com');"
sqlite3 blocklist.db "INSERT INTO domain VALUES ('tracker.example.com');"
sqlite3 blocklist.db "INSERT INTO domain VALUES ('malware.example.com');"

# Oder mit dem mitgelieferten Script (lädt Top 10M Domains)
./createdb.sh
```

## 🚀 Verwendung

```bash
# DNSMASQ mit SQLite-Blocker starten
./src/dnsmasq -d -p 5353 --db-file blocklist.db --log-queries

# Test: Blockierte Domain
dig @127.0.0.1 -p 5353 ads.example.com
# Antwort: NXDOMAIN (geblockt)

# Test: Normale Domain
dig @127.0.0.1 -p 5353 google.com
# Antwort: Normale Auflösung (forwarded)
```

## 🔄 Zur Laufzeit ändern (OHNE Restart!)

```bash
# Domain zur Blocklist hinzufügen
sqlite3 blocklist.db "INSERT INTO domain VALUES ('newad.example.com');"

# Sofort wirksam - kein Restart nötig!
dig @127.0.0.1 -p 5353 newad.example.com
# Antwort: NXDOMAIN (geblockt)

# Domain freigeben
sqlite3 blocklist.db "DELETE FROM domain WHERE Domain='newad.example.com';"
```

## 🔍 Alle blockierten Domains anzeigen

```bash
sqlite3 blocklist.db "SELECT * FROM domain ORDER BY Domain;"
```

## 📝 Datenbank-Schema

```sql
CREATE TABLE domain (
    Domain TEXT UNIQUE
);
CREATE UNIQUE INDEX idx_Domain ON domain(Domain);
```

## 🐛 Bug-Fix Historie

**Wichtig**: Die ursprüngliche v2.81 Integration hatte einen Logik-Bug:

- ❌ **ALT (Whitelist)**: `if (!db_check_allow(name))` → nur Domains IN DB wurden aufgelöst
- ✅ **NEU (Blacklist)**: `if (db_check_block(name))` → Domains IN DB werden blockiert

Diese v2.91 Portierung enthält die **korrigierte Blacklist-Logik**!

## 📂 Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `src/db.c` | ✨ NEU - SQLite-Logik |
| `src/config.h` | `#define HAVE_SQLITE` |
| `src/dnsmasq.h` | Function Declarations |
| `src/option.c` | `--db-file` CLI Option |
| `src/rfc1035.c` | Blacklist-Check in `answer_request()` |
| `Makefile` | SQLite Build-Flags |
| `createdb.sh` | ✨ NEU - DB-Erstellungs-Script |

## 🔧 Technische Details

- **Version**: dnsmasq 2.91 + SQLite
- **Binary-Größe**: ~447KB
- **SQLite-Linking**: `-lsqlite3`
- **Prepared Statements**: Ja (Performance-Optimierung)
- **Check-Location**: `rfc1035.c:2311` in `answer_request()`

## 📄 Lizenz

Wie DNSMASQ selbst (GPL v2/v3)

## 🙏 Credits

- Original DNSMASQ: Simon Kelley
- SQLite-Integration: basierend auf v2.81 Patch
- v2.91 Port + Bug-Fix: 2025
