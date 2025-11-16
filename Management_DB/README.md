# Database Management Scripts

Komplette Management-Suite für dnsmasq-sqlite Datenbank-Operationen.

**Status:** ✅ **Updated for Phase 1+2** (2025-11-16)
**Performance:** 25K-35K QPS expected with Phase 1+2 optimizations

## ⚠️ Important: Phase 1+2 Updates

**Alle Scripts wurden für Phase 1+2 aktualisiert!**
- Thread-safety fixes
- Connection pool support (32 connections)
- Corrected SQLite PRAGMAs
- 73% storage savings with normalized schema

**Siehe:** `README-PHASE2.md` für Details zu den Updates.

## Ordner-Struktur

```
Management_DB/
├── Build/                    # ✅ Build scripts (Phase 1+2 ready)
├── Database_Creation/        # ✅ DB creation (Phase 1+2 optimized)
├── Import/                   # Import von Domains/Patterns
├── Export/                   # Export der Datenbank
├── Delete/                   # Löschen + Duplikat-Cleanup
├── Reset/                    # Tabellen leeren (VORSICHT!)
├── Search/                   # Suche und Statistiken
├── Setup/                    # FreeBSD deployment
└── workflow-cleanup-database.sh  # ⭐ NEW! Complete workflow
```

---

## 🔨 Build Scripts (Phase 1+2 Ready)

Kompiliert dnsmasq mit Phase 1+2 Optimierungen.

### Verfügbare Scripts:

| Script | Beschreibung |
|--------|--------------|
| `build-freebsd.sh` | ✅ FreeBSD Build mit Phase 1+2 optimizations |

### Usage:

```bash
cd Build/

# Clean build with Phase 1+2 optimizations
sudo ./build-freebsd.sh clean

# Expected output:
#   ✅ Connection pool code detected
#   ✅ Thread-safety code detected
#   Expected: 25K-35K QPS
```

**Features:**
- Builds with `-pthread` flag (CRITICAL for thread-safety!)
- Uses `COPTS="-DHAVE_SQLITE -DHAVE_REGEX -pthread"`
- Uses `LIBS="-lsqlite3 -lpcre2-8 -pthread"`
- Verifies connection pool and thread-safety code
- Shows Phase 1+2 performance metrics

---

## 🗄️ Database Creation Scripts

Erstellt optimierte Datenbanken mit Phase 1 PRAGMAs.

### Verfügbare Scripts:

| Script | Beschreibung |
|--------|--------------|
| `createdb-phase2.sh` | ⭐ **Empfohlen!** Phase 1+2 optimized (legacy or normalized) |
| `createdb.sh` | Basic schema (für einfache Tests) |
| `createdb-regex.sh` | Schema mit Regex-Support (für Tests) |
| `migrate-to-sqlite-freebsd.sh` | Migration von alten Daten |
| `optimize-db-after-import.sh` | Post-import Optimierung |

### Usage:

```bash
cd Database_Creation/

# Legacy schema (kompatibel mit bestehendem Code)
./createdb-phase2.sh mydatabase.db legacy

# Normalized schema (73% storage savings!)
./createdb-phase2.sh mydatabase.db normalized
```

**Phase 1 SQLite PRAGMAs (included):**
- `mmap_size=0` - CRITICAL for >100GB databases
- `cache_size=-41943040` - 40GB cache (optimized for 128GB RAM)
- `busy_timeout=5000` - Multi-threading support
- `wal_autocheckpoint=1000` - Aggressive for read-heavy workload

---

## 📥 Import Scripts

Import von Domains/Patterns aus Text-Dateien in die Datenbank.

### Verfügbare Scripts:

| Script | Tabelle | Priority | Aktion |
|--------|---------|----------|--------|
| `import-block-regex.sh` | block_regex | 1 (HIGHEST) | PCRE2 Regex-Patterns → IPSetTerminate |
| `import-block-exact.sh` | block_exact | 2 | Exakte Domains (KEINE Subdomains!) → IPSetTerminate |
| `import-block-wildcard.sh` | block_wildcard | 3 | Domains + Subdomains → IPSetDNSBlock |
| `import-fqdn-dns-allow.sh` | fqdn_dns_allow | 4 | Whitelist → IPSetDNSAllow |
| `import-fqdn-dns-block.sh` | fqdn_dns_block | 5 (LOWEST) | Blacklist → IPSetDNSBlock |

### Usage:

```bash
cd Import/

# Regex-Patterns importieren
./import-block-regex.sh ../../blocklist.db patterns.txt

# Exakte Domains importieren
./import-block-exact.sh ../../blocklist.db exact-domains.txt

# Wildcard-Domains importieren
./import-block-wildcard.sh ../../blocklist.db wildcard-domains.txt
```

### Beispiel-Dateien:

- `example-block-regex.txt` - PCRE2 Patterns
- `example-block-exact.txt` - Exakte Domains
- `example-block-wildcard.txt` - Wildcard Domains
- `example-fqdn-dns-allow.txt` - Whitelist
- `example-fqdn-dns-block.txt` - Blacklist

### Wichtig - Duplikate:

**Die Datenbank verhindert Duplikate automatisch!**
- Alle Tabellen haben `PRIMARY KEY` auf Domain/Pattern
- `INSERT OR IGNORE` überspringt Duplikate automatisch
- Keine manuelle Duplikat-Prüfung nötig!

---

## 📤 Export Scripts

Export der Datenbank in Text-Dateien (z.B. für Backups).

### Verfügbare Scripts:

| Script | Beschreibung |
|--------|--------------|
| `export-all-tables.sh` | Exportiert ALLE Tabellen in separate Dateien |
| `export-single-table.sh` | Exportiert EINE Tabelle |

### Usage:

```bash
cd Export/

# Alle Tabellen exportieren
./export-all-tables.sh ../../blocklist.db ./backup

# Eine einzelne Tabelle exportieren
./export-single-table.sh ../../blocklist.db block_exact exported.txt
```

---

## 🗑️ Delete Scripts

Löschen einzelner oder mehrerer Einträge + Duplikat-Cleanup.

### Verfügbare Scripts:

| Script | Beschreibung |
|--------|--------------|
| `delete-single-entry.sh` | Löscht EINEN Eintrag |
| `delete-multiple-entries.sh` | Löscht MEHRERE Einträge aus Datei |
| `cleanup-duplicates.sh` | ⭐ **NEU!** Bereinigt Duplikate über Tabellen (priority-based) |

### Usage:

```bash
cd Delete/

# Einzelnen Eintrag löschen
./delete-single-entry.sh ../../blocklist.db block_exact ads.example.com

# Mehrere Einträge löschen
./delete-multiple-entries.sh ../../blocklist.db block_exact domains-to-delete.txt

# Duplikate bereinigen (interaktiv)
./cleanup-duplicates.sh ../../blocklist.db

# Duplikate bereinigen (automatisch)
./cleanup-duplicates.sh ../../blocklist.db --auto
```

**Priority-Logik für Duplikate:**
1. `fqdn_dns_allow` (whitelist - höchste Priorität)
2. `block_exact` (exakte Blockierung)
3. `block_wildcard` (wildcard Blockierung)
4. `fqdn_dns_block` (blacklist - niedrigste Priorität)

Wenn eine Domain in mehreren Tabellen existiert, wird sie in der höchsten Priorität behalten und aus niedrigeren entfernt.

⚠️ **Sicherheitsabfrage:** Alle Scripts fragen vor dem Löschen nach (außer `--auto`)!

---

## ♻️ Reset Scripts

Tabellen komplett leeren (GEFÄHRLICH!).

### Verfügbare Scripts:

| Script | Beschreibung |
|--------|--------------|
| `reset-single-table.sh` | Leert EINE Tabelle |
| `reset-all-tables.sh` | Leert ALLE Tabellen (NUCLEAR!) |

### Usage:

```bash
cd Reset/

# Eine Tabelle leeren
./reset-single-table.sh ../../blocklist.db block_exact

# ALLE Tabellen leeren (VORSICHT!)
./reset-all-tables.sh ../../blocklist.db
```

⚠️ **WARNUNG:**
- `reset-single-table.sh`: Fordert Table-Namen zur Bestätigung
- `reset-all-tables.sh`: Fordert "DELETE EVERYTHING" zur Bestätigung
- **Kann NICHT rückgängig gemacht werden!**

---

## 🔍 Search Scripts

Suche, Statistiken und Analyse.

### Verfügbare Scripts:

| Script | Beschreibung |
|--------|--------------|
| `search-domain.sh` | Sucht Domain/Pattern in ALLEN Tabellen |
| `search-statistics.sh` | Zeigt Einträge, Größen, Konfiguration |
| `search-duplicates.sh` | Findet Duplikate über mehrere Tabellen |
| `search-top-domains.sh` | Zeigt Top N Einträge pro Tabelle |

### Usage:

```bash
cd Search/

# Domain in allen Tabellen suchen
./search-domain.sh ../../blocklist.db ads.example.com

# Mit Wildcard suchen
./search-domain.sh ../../blocklist.db '%google%'

# Statistiken anzeigen
./search-statistics.sh ../../blocklist.db

# Duplikate finden
./search-duplicates.sh ../../blocklist.db

# Top 20 Einträge zeigen
./search-top-domains.sh ../../blocklist.db 20
```

---

## 🚀 Complete Workflow (NEW!)

**Kompletter Workflow:** Import → Cleanup → Export → Reset

### Script:

| Script | Beschreibung |
|--------|--------------|
| `workflow-cleanup-database.sh` | ⭐ **NEU!** Kompletter Workflow in einem Script |

### Usage:

```bash
# Workflow ohne Reset
./workflow-cleanup-database.sh database.db ./import-data

# Workflow mit Reset nach Export
./workflow-cleanup-database.sh database.db ./import-data --reset-after
```

**Was passiert:**
1. **Import:** Importiert alle `.txt` Dateien aus `./import-data/`
   - `block-exact.txt` → `block_exact` Tabelle
   - `block-wildcard.txt` → `block_wildcard` Tabelle
   - `block-regex.txt` → `block_regex` Tabelle
   - `dns-allow.txt` → `fqdn_dns_allow` Tabelle
   - `dns-block.txt` → `fqdn_dns_block` Tabelle

2. **Cleanup:** Bereinigt Duplikate automatisch (priority-based)

3. **Export:** Exportiert bereinigte Daten nach `./backups/YYYYMMDD_HHMMSS/`

4. **Reset (optional):** Leert Datenbank nach Export (mit `--reset-after`)

**Beispiel-Verzeichnisstruktur:**
```
import-data/
├── block-exact.txt       # 1M domains
├── block-wildcard.txt    # 500K domains
├── dns-allow.txt         # 100 whitelisted domains
└── dns-block.txt         # 50K blacklisted domains

Nach Workflow:
backups/20251116_143022/
├── block-exact.txt       # 950K (50K Duplikate entfernt!)
├── block-wildcard.txt    # 480K (20K Duplikate entfernt!)
├── dns-allow.txt         # 100
└── dns-block.txt         # 40K (10K Duplikate entfernt!)
```

---

## 📊 Lookup-Reihenfolge (Schema v4.0)

Die Datenbank prüft Domains in dieser Reihenfolge:

```
1. LRU Cache (10,000 Einträge)
   └─ HIT → Return (90% der Fälle!)

2. block_regex (Priority 1)
   └─ Match → IPSetTerminate (direktes Blockieren)

3. Bloom Filter (für block_exact)
   └─ NEIN → skip block_exact

4. block_exact (Priority 2)
   └─ Match → IPSetTerminate (direktes Blockieren)

5. block_wildcard (Priority 3)
   └─ Match → IPSetDNSBlock (Forward zu Blocker-DNS)

6. fqdn_dns_allow (Priority 4)
   └─ Match → IPSetDNSAllow (Forward zu echtem DNS)

7. fqdn_dns_block (Priority 5)
   └─ Match → IPSetDNSBlock (Forward zu Blocker-DNS)

8. NONE → Normales DNS
```

---

## 🎯 Performance-Tipps

### Import-Performance:

1. **Große Dateien (>1M Einträge):**
   - Scripts nutzen automatisch TRANSACTIONS (100x schneller!)
   - Pre-processing (lowercase, trim) vor Import
   - DISTINCT filter gegen Duplikate

2. **Nach großem Import:**
   ```bash
   cd ../
   ./optimize-db-after-import.sh blocklist.db --readonly
   ```
   - Führt ANALYZE aus (bessere Query-Pläne)
   - Optional: VACUUM (Defragmentierung)
   - Optional: Read-only Mode (5-10% schneller)

### Such-Performance:

- **Wildcard-Suche:** `'%domain%'` ist langsam (Full Scan)
- **Prefix-Suche:** `'domain%'` ist schnell (Index-Nutzung)
- **Exakte Suche:** `'domain.com'` ist am schnellsten (Primary Key)

---

## 🔒 Sicherheit

### Duplikat-Schutz:

✅ **Automatisch durch PRIMARY KEY!**
- block_regex: `PRIMARY KEY (Pattern)`
- block_exact: `PRIMARY KEY (Domain)`
- block_wildcard: `PRIMARY KEY (Domain)`
- fqdn_dns_allow: `PRIMARY KEY (Domain)`
- fqdn_dns_block: `PRIMARY KEY (Domain)`

**INSERT OR IGNORE** überspringt Duplikate automatisch - keine manuelle Prüfung nötig!

### Backup-Empfehlung:

```bash
# Vor großen Änderungen: Backup erstellen
cd Export/
./export-all-tables.sh ../../blocklist.db ./backup-$(date +%Y%m%d)

# Oder: Datenbank-Datei kopieren
cp ../../blocklist.db ../../blocklist.db.backup
```

---

## 📚 Beispiel-Workflow

### 1. Neue Domains hinzufügen:

```bash
cd Import/

# 1. Domains in Datei schreiben
echo "ads.badsite.com" >> my-block-list.txt
echo "tracker.evil.net" >> my-block-list.txt

# 2. Importieren
./import-block-exact.sh ../../blocklist.db my-block-list.txt

# 3. Statistiken prüfen
cd ../Search/
./search-statistics.sh ../../blocklist.db
```

### 2. Domain finden und löschen:

```bash
cd Search/

# 1. Domain suchen
./search-domain.sh ../../blocklist.db ads.badsite.com

# 2. Löschen
cd ../Delete/
./delete-single-entry.sh ../../blocklist.db block_exact ads.badsite.com
```

### 3. Test-Datenbank zurücksetzen:

```bash
cd Reset/

# VORSICHT: Löscht ALLES!
./reset-all-tables.sh ../../blocklist.db
```

---

## 🚀 Schnellstart (Phase 1+2)

```bash
# 1. Build dnsmasq with Phase 1+2 optimizations
cd Build/
sudo ./build-freebsd.sh clean
cd ..

# 2. Datenbank erstellen (Phase 1+2 optimized)
cd Database_Creation/
./createdb-phase2.sh ../../blocklist.db legacy  # oder 'normalized'
cd ..

# 3. Beispiel-Daten importieren
cd Import/
./import-block-exact.sh ../../blocklist.db example-block-exact.txt
cd ..

# 4. Duplikate bereinigen
cd Delete/
./cleanup-duplicates.sh ../../blocklist.db --auto
cd ..

# 5. Statistiken prüfen
cd Search/
./search-statistics.sh ../../blocklist.db
cd ..

# 6. Nach Import optimieren
cd Database_Creation/
./optimize-db-after-import.sh ../../blocklist.db --readonly
```

**Oder komplett automatisch:**
```bash
# Kompletter Workflow in einem Script!
./workflow-cleanup-database.sh blocklist.db ./my-import-data
```

---

## 📞 Hilfe

Alle Scripts zeigen Hilfe ohne Parameter:

```bash
./import-block-exact.sh
# zeigt: Usage, Beispiele, Dateiformat
```

---

**Updated:** 2025-11-16 (Phase 1+2 ready)
**Target:** HP DL20 G10+ mit 128GB RAM und FreeBSD + ZFS
**Schema Version:** 4.0 (legacy) / 2.0 (normalized)
**Performance:**
- Phase 1+2: 25K-35K QPS
- Optimiert für 2-3 Milliarden Domains
- Thread-safe + Connection Pool (32 connections)
- 73% storage savings (normalized schema)

**Neue Features:**
- ✅ `cleanup-duplicates.sh` - Intelligente Duplikat-Bereinigung
- ✅ `workflow-cleanup-database.sh` - Kompletter Workflow
- ✅ `build-freebsd.sh` - Phase 1+2 Build
- ✅ `createdb-phase2.sh` - Phase 1+2 optimized DB

**Siehe auch:**
- `README-PHASE2.md` - Phase 1+2 Update Details
- `../../docs/FIXES_APPLIED.md` - Critical fixes summary
- `../../docs/PHASE2_IMPLEMENTATION.md` - Connection pool details
