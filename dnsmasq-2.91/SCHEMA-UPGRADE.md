# Schema-Upgrade: ExactOnly Flag

## Problem

Manchmal braucht man für bestimmte Domains **exaktes** Matching statt Wildcard:

```
tracker.example.com (blocklist) → blockt auch api.tracker.example.com
Aber: api.tracker.example.com soll NICHT geblockt werden!
```

## Lösung

Erweitere die `domain`-Tabelle mit einem `ExactOnly`-Flag:

```sql
CREATE TABLE domain (
    Domain TEXT PRIMARY KEY,
    ExactOnly INTEGER DEFAULT 0  -- 0 = Wildcard, 1 = Nur exaktes Match
) WITHOUT ROWID;
```

## Upgrade bestehender Datenbank

```bash
# Backup erstellen
cp blocklist.db blocklist.db.backup

# Schema erweitern
sqlite3 blocklist.db <<EOF
-- Temporäre neue Tabelle erstellen
CREATE TABLE domain_new (
    Domain TEXT PRIMARY KEY,
    ExactOnly INTEGER DEFAULT 0
) WITHOUT ROWID;

-- Daten kopieren (ExactOnly = 0 für alle bestehenden)
INSERT INTO domain_new (Domain, ExactOnly)
SELECT Domain, 0 FROM domain;

-- Alte Tabelle löschen
DROP TABLE domain;

-- Neue Tabelle umbenennen
ALTER TABLE domain_new RENAME TO domain;

-- Index neu erstellen
CREATE UNIQUE INDEX idx_Domain ON domain(Domain);

-- Optimieren
VACUUM;
ANALYZE;
EOF

echo "✅ Schema upgraded! Alle bestehenden Domains haben ExactOnly=0 (Wildcard)"
```

## Verwendung

### Wildcard-Blocking (Standard)

```bash
# Blockt tracker.example.com UND alle Subdomains
sqlite3 blocklist.db "INSERT INTO domain (Domain, ExactOnly) VALUES ('tracker.example.com', 0);"

# Oder kürzer (ExactOnly=0 ist Default):
sqlite3 blocklist.db "INSERT INTO domain (Domain) VALUES ('tracker.example.com');"

# Geblockt:
# - tracker.example.com ✅
# - www.tracker.example.com ✅
# - api.tracker.example.com ✅
# - mail.sub.tracker.example.com ✅
```

### Exact-Only Blocking

```bash
# Blockt NUR tracker.example.com, NICHT die Subdomains
sqlite3 blocklist.db "INSERT INTO domain (Domain, ExactOnly) VALUES ('tracker.example.com', 1);"

# Geblockt:
# - tracker.example.com ✅
#
# NICHT geblockt:
# - www.tracker.example.com ❌
# - api.tracker.example.com ❌
```

### Gemischtes Beispiel

```bash
# Blocke die Hauptdomain mit allen Subdomains
sqlite3 blocklist.db "INSERT INTO domain VALUES ('ads.com', 0);"

# Aber erlaube spezifische Subdomains durch NICHT-Eintragen
# (api.ads.com ist automatisch erlaubt wenn nicht in DB)

# Alternative: Nutze ExactOnly für granulare Kontrolle
sqlite3 blocklist.db "INSERT INTO domain VALUES ('sub1.ads.com', 1);"  # Nur sub1, nicht *.sub1
sqlite3 blocklist.db "INSERT INTO domain VALUES ('sub2.ads.com', 0);"  # sub2 + alle *.sub2
```

## SQL-Query-Logik

### Alte Query (immer Wildcard):
```sql
SELECT COUNT(*) FROM domain
WHERE Domain = ? OR ? LIKE '%.' || Domain
```

### Neue Query (mit ExactOnly):
```sql
SELECT COUNT(*) FROM domain
WHERE Domain = ?                                -- Exaktes Match
   OR (ExactOnly = 0 AND ? LIKE '%.' || Domain) -- Wildcard nur wenn ExactOnly=0
```

## Import-Scripts

### createdb-optimized.sh erweitern

```bash
# Standard-Import (alle mit Wildcard)
awk '{ printf "INSERT OR IGNORE INTO domain (Domain, ExactOnly) VALUES (\"%s\", 0);\n", $1 }' hosts.txt | sqlite3 db

# Oder für exact-only Domains:
awk '{ printf "INSERT OR IGNORE INTO domain (Domain, ExactOnly) VALUES (\"%s\", 1);\n", $1 }' exact-only.txt | sqlite3 db
```

## Rückwärtskompatibilität

Falls du **KEINE** ExactOnly-Spalte in deiner DB hast:
- SQLite gibt Fehler "no such column: ExactOnly"
- Lösung 1: Schema upgraden (siehe oben)
- Lösung 2: Alte Tabelle funktioniert weiter mit Wildcard für alle

## Performance

- **Kein** Performance-Impact!
- Index funktioniert weiterhin auf `Domain`
- `ExactOnly`-Check ist nur ein einfacher Integer-Vergleich
