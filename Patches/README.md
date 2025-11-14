# dnsmasq SQLite Feature Patches

Diese Patches fügen Domain Aliasing und IP-Rewriting Features zu dnsmasq 2.91 hinzu.

## Geänderte Dateien

```
Patches/
├── README.md              # Diese Datei
├── CHANGES.txt            # Detailliertes Änderungsprotokoll
├── FILE-SUMMARY.txt       # Technische Code-Analyse
└── dnsmasq-2.91/
    └── src/
        ├── db.c           # SQLite DB-Funktionen (42 KB)
        ├── dnsmasq.h      # Function Declarations (62 KB)
        └── rfc1035.c      # DNS Integration (69 KB)
```

## Features

### 1. Domain Aliasing (CNAME-Redirects mit Wildcard-Subdomain-Support)

**Datenbank-Tabelle:**
```sql
CREATE TABLE domain_alias (
    Source_Domain TEXT PRIMARY KEY,
    Target_Domain TEXT NOT NULL
) WITHOUT ROWID;
```

**Verhalten:**
```
DB: intel.com → keweon.center

Query: intel.com         → CNAME: keweon.center
Query: www.intel.com     → CNAME: www.keweon.center (automatisch!)
Query: mail.intel.com    → CNAME: mail.keweon.center (automatisch!)
```

**Implementation:** `rfc1035.c:1683-1708` in `answer_request()`

### 2. IP-Rewriting (DNS-Doctoring für NAT/Split-Horizon DNS)

**Datenbank-Tabellen:**
```sql
CREATE TABLE ip_rewrite_v4 (
    Source_IPv4 TEXT PRIMARY KEY,
    Target_IPv4 TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE ip_rewrite_v6 (
    Source_IPv6 TEXT PRIMARY KEY,
    Target_IPv6 TEXT NOT NULL
) WITHOUT ROWID;
```

**Verhalten:**
```
DB: 178.223.16.21 → 10.20.0.10

Upstream antwortet: example.com → 178.223.16.21
dnsmasq rewrites:   example.com → 10.20.0.10
Client erhält:      example.com → 10.20.0.10
```

**Implementation:**
- IPv4: `rfc1035.c:1036-1056` in `extract_addresses()`
- IPv6: `rfc1035.c:1057-1077` in `extract_addresses()`

## Installation

### Schritt 1: Backup erstellen
```bash
cp -r dnsmasq-2.91/src dnsmasq-2.91/src.backup
```

### Schritt 2: Patches anwenden
```bash
cp Patches/dnsmasq-2.91/src/db.c dnsmasq-2.91/src/
cp Patches/dnsmasq-2.91/src/dnsmasq.h dnsmasq-2.91/src/
cp Patches/dnsmasq-2.91/src/rfc1035.c dnsmasq-2.91/src/
```

### Schritt 3: Kompilieren
```bash
cd dnsmasq-2.91
make clean
make -j8
sudo make install
```

### Schritt 4: Datenbank erstellen
```bash
# Datenbank mit Schema 6.2.1 erstellen
# (siehe Management_DB/Database_Creation/createdb-optimized.sh im Hauptverzeichnis)
./createdb-optimized.sh /var/lib/dnsmasq/blocklist.db
```

### Schritt 5: dnsmasq konfigurieren
```bash
# /etc/dnsmasq.conf
db-file=/var/lib/dnsmasq/blocklist.db
log-queries
```

## Geänderte Dateien im Detail

### db.c (42 KB)

**Neue Funktionen:**

1. `char* db_get_domain_alias(const char *source_domain)` (Zeilen ~991-1046)
   - Two-step lookup: Exact Match → Parent Domain + Subdomain-Preservation
   - Beispiel: "www.intel.com" → "www.keweon.center"

2. `char* db_get_rewrite_ipv4(const char *source_ipv4)` (Zeilen ~1057-1085)
   - Lookup in ip_rewrite_v4 Tabelle
   - Gibt Ziel-IP zurück oder NULL

3. `char* db_get_rewrite_ipv6(const char *source_ipv6)` (Zeilen ~1086-1114)
   - Lookup in ip_rewrite_v6 Tabelle
   - IPv6-Unterstützung

**Prepared Statements:**
```c
static sqlite3_stmt *db_domain_alias = NULL;
static sqlite3_stmt *db_ip_rewrite_v4 = NULL;
static sqlite3_stmt *db_ip_rewrite_v6 = NULL;
```

### dnsmasq.h (62 KB)

**Neue Function Declarations:**
```c
char* db_get_domain_alias(const char *source_domain);
char* db_get_rewrite_ipv4(const char *source_ipv4);
char* db_get_rewrite_ipv6(const char *source_ipv6);
```

**Schema-Version Update:** 6.2.1

### rfc1035.c (69 KB)

**Änderung 1: Domain Aliasing (Zeilen 1683-1708)**
Integration in `answer_request()`:
- Prüft domain_alias Tabelle bei jeder Query
- Fügt CNAME-Record zur Response hinzu
- Löst Alias-Ziel auf für A/AAAA Queries

**Änderung 2: IP-Rewriting IPv4 (Zeilen 1036-1056)**
Integration in `extract_addresses()`:
- Prüft ip_rewrite_v4 Tabelle bei Response-Verarbeitung
- Überschreibt IP im addr-Struct
- Überschreibt IP im DNS-Paket (Cache-Konsistenz)

**Änderung 3: IP-Rewriting IPv6 (Zeilen 1057-1077)**
Integration in `extract_addresses()`:
- Identisch zu IPv4, aber für IPv6-Adressen

## Use Cases

### Domain Aliasing
- ✅ Malware/Phishing-Blocking (redirect zu blocked.local)
- ✅ Domain-Migration (alte.domain → neue.domain)
- ✅ Wildcard-Blocking (eine Regel → gesamte Domain-Familie)
- ✅ Testing/Development

### IP-Rewriting
- ✅ NAT-Umgebungen (Public IP → Private IP)
- ✅ Split-Horizon DNS
- ✅ Private Netzwerk-Mapping
- ✅ Development/Testing (Production IP → Dev IP)

## Performance

- **B-Tree Indizes** auf allen Primary Keys
- **WITHOUT ROWID** Tabellen für bessere Performance
- **Prepared Statements** (einmalig kompiliert, wiederverwendet)
- **O(1) Lookups** für Exact Matches
- **O(log n) Lookups** für Wildcard-Subdomain-Matching

## Testing

Alle Features wurden umfassend getestet:

```
Domain Aliasing:  5/5 Tests PASSED ✅
IP-Rewriting:     7/7 Tests PASSED ✅
Blocking:        11/11 Tests PASSED ✅
──────────────────────────────────────
TOTAL:           23/23 Tests PASSED ✅
```

Test-Programme verfügbar im Hauptverzeichnis.

## Commits

Diese Patches basieren auf folgenden Commits:

- **bfa089e** - Fix: Integrate Domain Aliasing into DNS query flow
- **39bacf6** - Implement IP-Rewriting (IPv4 & IPv6) in DNS response flow
- **afdf6ff** - Add: Patches directory with all modified dnsmasq files

## Kompatibilität

- **dnsmasq Version:** 2.91
- **SQLite Version:** 3.x+
- **Plattformen:** Linux
- **Compiler:** GCC, Clang

## Weitere Dokumentation

Vollständige Dokumentation im Hauptverzeichnis:
- `Docs/DOMAIN-ALIAS.md` - Domain Aliasing Feature
- `Docs/IP-REWRITE.md` - IP-Rewriting Feature
- `Management_DB/Database_Creation/createdb-optimized.sh` - Schema 6.2.1
- `manage-domain-alias.sh` - Management-Tool
- `manage-ip-rewrite.sh` - Management-Tool

## Lizenz

Diese Patches sind kompatibel mit der dnsmasq GPLv2 Lizenz.

---

**Version:** 6.2.1
**Letzte Aktualisierung:** 2025-11-14
**Status:** Production Ready ✅
