# Database Management Scripts

Komplette Management-Suite für dnsmasq-sqlite Datenbank-Operationen.

## Ordner-Struktur

```
Management_DB/
├── Import/          Import von Domains/Patterns in die Datenbank
├── Export/          Export der Datenbank in Text-Dateien
├── Delete/          Löschen einzelner oder mehrerer Einträge
├── Reset/           Tabellen leeren (VORSICHT!)
└── Search/          Suche und Statistiken
```

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

Löschen einzelner oder mehrerer Einträge.

### Verfügbare Scripts:

| Script | Beschreibung |
|--------|--------------|
| `delete-single-entry.sh` | Löscht EINEN Eintrag |
| `delete-multiple-entries.sh` | Löscht MEHRERE Einträge aus Datei |

### Usage:

```bash
cd Delete/

# Einzelnen Eintrag löschen
./delete-single-entry.sh ../../blocklist.db block_exact ads.example.com

# Mehrere Einträge löschen
./delete-multiple-entries.sh ../../blocklist.db block_exact domains-to-delete.txt
```

⚠️ **Sicherheitsabfrage:** Beide Scripts fragen vor dem Löschen nach!

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

## 🚀 Schnellstart

```bash
# 1. Datenbank erstellen (falls noch nicht vorhanden)
cd ../
./createdb-optimized.sh blocklist.db

# 2. Beispiel-Daten importieren
cd Management_DB/Import/
./import-block-exact.sh ../../blocklist.db example-block-exact.txt

# 3. Statistiken prüfen
cd ../Search/
./search-statistics.sh ../../blocklist.db

# 4. Nach Import optimieren
cd ../../
./optimize-db-after-import.sh blocklist.db --readonly
```

---

## 📞 Hilfe

Alle Scripts zeigen Hilfe ohne Parameter:

```bash
./import-block-exact.sh
# zeigt: Usage, Beispiele, Dateiformat
```

---

**Erstellt für:** HP DL20 G10+ mit 128GB RAM und FreeBSD
**Schema Version:** 4.0
**Performance:** Optimiert für 2-3 Milliarden Domains
