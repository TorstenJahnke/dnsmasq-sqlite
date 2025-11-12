# dnsmasq-sqlite Scripts Übersicht

## 📁 Ordner-Struktur

```
dnsmasq-2.91/
├── Management_DB/              ← Datenbank-Management (Import/Export/Delete/Search)
├── watchlists/                 ← Import-Scripts für Blocklisten
├── _Deprecated_Old_Scripts/    ← Alte, veraltete Scripts (nicht verwenden!)
│
├── src/                        ← C Source Code
├── Makefile                    ← Build System
│
└── *.sh                        ← Core Setup/Build Scripts (siehe unten)
```

---

## 🎯 Core Scripts (Haupt-Ordner)

### Database Creation:

| Script | Beschreibung |
|--------|--------------|
| `createdb-optimized.sh` | **EMPFOHLEN** - Erstellt DB mit 16KB pages, 100GB cache, optimiert für HP DL20 G10+ |
| `createdb-enterprise-128gb.sh` | Alte Version (4KB pages) |
| `createdb.sh` | Basis-Version (nicht optimiert) |
| `createdb-dual.sh` | Dual-Schema (v3 + v4) |
| `createdb-regex.sh` | Nur Regex-Tabelle |

**Empfehlung:** Immer `createdb-optimized.sh` verwenden!

### Post-Import Optimization:

| Script | Beschreibung |
|--------|--------------|
| `optimize-db-after-import.sh` | **WICHTIG** - ANALYZE + optional VACUUM + Read-Only Mode |

**Usage:**
```bash
./optimize-db-after-import.sh blocklist.db --readonly
```

### FreeBSD Setup:

| Script | Beschreibung |
|--------|--------------|
| `install-freebsd.sh` | Installiert dnsmasq auf FreeBSD |
| `build-freebsd.sh` | Build für FreeBSD |
| `freebsd-enterprise-setup.sh` | Enterprise Setup (128GB RAM, NVMe SSD) |
| `freebsd-zfs-setup.sh` | ZFS Setup für Datenbank |
| `migrate-to-sqlite-freebsd.sh` | Migration von HOSTS zu SQLite |

### Build Scripts:

| Script | Beschreibung |
|--------|--------------|
| `build-with-valkey.sh` | Build mit Valkey Support |

---

## 📊 Datenbank-Management

**Alle Import/Export/Delete/Search Operationen:**

```bash
cd Management_DB/
```

Siehe: **Management_DB/README.md** für vollständige Dokumentation!

### Quick Reference:

- **Import:** `Management_DB/Import/import-*.sh`
- **Export:** `Management_DB/Export/export-*.sh`
- **Delete:** `Management_DB/Delete/delete-*.sh`
- **Reset:** `Management_DB/Reset/reset-*.sh`
- **Search:** `Management_DB/Search/search-*.sh`

---

## 🚀 Schnellstart

### 1. Datenbank erstellen:

```bash
./createdb-optimized.sh blocklist.db
```

### 2. Daten importieren:

```bash
cd Management_DB/Import/

# Beispiel-Daten
./import-block-exact.sh ../../blocklist.db example-block-exact.txt

# Oder: Eigene Daten
./import-block-exact.sh ../../blocklist.db my-domains.txt
```

### 3. Nach Import optimieren:

```bash
cd ../../
./optimize-db-after-import.sh blocklist.db --readonly
```

### 4. dnsmasq konfigurieren:

Siehe: `dnsmasq.conf.example`

### 5. dnsmasq starten:

```bash
./src/dnsmasq -d -C dnsmasq.conf
```

---

## 📚 Watchlists (Automatischer Import)

Für große Blocklisten (Millionen von Einträgen):

```bash
cd watchlists/

# Alle Listen parallel importieren
./import-all-parallel.sh
```

Siehe: **watchlists/README.md** für Details.

---

## ⚠️ Wichtige Hinweise

### Schema v4.0 Features:

- ✅ 5 Lookup-Tabellen (block_regex, block_exact, block_wildcard, fqdn_dns_allow, fqdn_dns_block)
- ✅ IPSet-basiertes Routing (IPs in Config, nicht in DB!)
- ✅ LRU Cache (10,000 Einträge)
- ✅ Bloom Filter (~12MB für 10M Domains)
- ✅ 100GB SQLite Cache
- ✅ EXCLUSIVE Locking Mode
- ✅ 16KB Page Size

### Performance-Ziele:

- **Durchsatz:** 50,000 queries/sec
- **Latenz (Ø):** 0.05ms
- **Cache Hit Rate:** 90%+
- **Datenmenge:** 2-3 Milliarden Domains

### Hardware-Ziel:

- **Server:** HP DL20 G10+
- **RAM:** 128GB
- **Storage:** NVMe SSD
- **OS:** FreeBSD

---

## 📖 Weitere Dokumentation

- **Management_DB/README.md** - Datenbank-Management
- **watchlists/README.md** - Blocklisten-Import
- **src/db.c** - Source Code (Performance-Optimierungen)

---

## 🔧 Troubleshooting

### Script zeigt "Permission denied":

```bash
chmod +x script-name.sh
```

### Datenbank ist zu groß:

```bash
./optimize-db-after-import.sh blocklist.db
# Wähle "y" für VACUUM
```

### Performance-Probleme:

```bash
# Prüfe Cache Hit Rate
cd Management_DB/Search/
./search-statistics.sh ../../blocklist.db

# Falls Hit Rate < 80%, erhöhe LRU Cache in src/db.c:
# #define LRU_CACHE_SIZE 20000  (statt 10000)
```

---

**Version:** Schema 4.0
**Erstellt für:** HP DL20 G10+ (128GB RAM, FreeBSD)
**Performance:** Optimiert für 2-3 Milliarden Domains
