# Regex Quick Start - IP-Set Zuweisen

## 1. Datenbank erstellen

```bash
./createdb-regex.sh blocklist.db
```

## 2. Regex-Patterns mit IP-Sets einfügen

### Methode 1: Einzelne Patterns mit SQL

```bash
sqlite3 blocklist.db <<EOF
-- Pattern 1: Alle ads.* Domains → IP-Set 10.0.1.1 / fd00:1::1
INSERT INTO domain_regex (Pattern, IPv4, IPv6) VALUES
  ('^ads\..*', '10.0.1.1', 'fd00:1::1');

-- Pattern 2: Alle *.tracker.com → IP-Set 10.0.2.1 / fd00:2::1
INSERT INTO domain_regex (Pattern, IPv4, IPv6) VALUES
  ('.*\.tracker\.com$', '10.0.2.1', 'fd00:2::1');

-- Pattern 3: www|cdn + analytics → IP-Set 10.0.3.1 / fd00:3::1
INSERT INTO domain_regex (Pattern, IPv4, IPv6) VALUES
  ('^(www|cdn)\.analytics\..*', '10.0.3.1', 'fd00:3::1');
EOF
```

### Methode 2: Aus Datei importieren (gleiche IP für alle)

```bash
# Patterns in Datei (eine Zeile = ein Pattern)
cat > patterns.txt <<EOF
^ads\..*
.*\.tracker\.com$
^(www|cdn)\.analytics\..*
EOF

# Importieren mit EINEM IP-Set für ALLE Patterns
./import-regex.sh patterns.txt blocklist.db 10.0.5.1 fd00:5::1
```

### Methode 3: Mehrere Dateien mit unterschiedlichen IP-Sets

```bash
# Pattern-Gruppe 1: Ads (IP-Set 1)
echo "^ads\\..*" > ads-patterns.txt
./import-regex.sh ads-patterns.txt blocklist.db 10.0.1.1 fd00:1::1

# Pattern-Gruppe 2: Tracker (IP-Set 2)
echo ".*\\.tracker\\.com$" > tracker-patterns.txt
./import-regex.sh tracker-patterns.txt blocklist.db 10.0.2.1 fd00:2::1

# Pattern-Gruppe 3: Analytics (IP-Set 3)
echo "^(www|cdn)\\.analytics\\..*" > analytics-patterns.txt
./import-regex.sh analytics-patterns.txt blocklist.db 10.0.3.1 fd00:3::1
```

## 3. Prüfen was in der DB ist

```bash
sqlite3 blocklist.db <<EOF
.mode column
.headers on
SELECT * FROM domain_regex;
EOF
```

Ausgabe:
```
Pattern                        IPv4       IPv6
-----------------------------  ---------  -----------
^ads\..*                       10.0.1.1   fd00:1::1
.*\.tracker\.com$              10.0.2.1   fd00:2::1
^(www|cdn)\.analytics\..*     10.0.3.1   fd00:3::1
```

## 4. IP-Set ändern (UPDATE)

```bash
sqlite3 blocklist.db <<EOF
-- Pattern finden und IP-Set ändern
UPDATE domain_regex
SET IPv4='10.0.99.1', IPv6='fd00:99::1'
WHERE Pattern='^ads\..*';
EOF
```

## 5. dnsmasq starten

```bash
./src/dnsmasq -d -p 5353 \
  --db-file=blocklist.db \
  --db-block-ipv4=0.0.0.0 \
  --db-block-ipv6=:: \
  --log-queries
```

**Wichtig**: `--db-block-ipv4` und `--db-block-ipv6` sind **Fallback-IPs**.
- Wenn Pattern IPv4/IPv6 in DB hat → nutzt DB-IP
- Wenn Pattern NULL in DB hat → nutzt Fallback-IP

## 6. Testen

```bash
# Sollte geblockt werden (Pattern ^ads\\.*)
dig @127.0.0.1 -p 5353 ads.com
# Antwort: 10.0.1.1 (IPv4 aus DB!)

dig @127.0.0.1 -p 5353 AAAA ads.com
# Antwort: fd00:1::1 (IPv6 aus DB!)

# Sollte geblockt werden (Pattern .*\\.tracker\\.com$)
dig @127.0.0.1 -p 5353 evil.tracker.com
# Antwort: 10.0.2.1

# Sollte geblockt werden (Pattern ^(www|cdn)\\.analytics\\..*)
dig @127.0.0.1 -p 5353 www.analytics.example.net
# Antwort: 10.0.3.1
```

## Pattern-Syntax (PCRE2)

### Einfache Patterns
```regex
^ads\..*           # Alle Domains die mit "ads." starten
.*\.evil\.com$     # Alle Domains die mit ".evil.com" enden
^exact\.domain$    # Nur exakt "exact.domain"
```

### Alternativen
```regex
^(www|cdn|api)\.   # Startet mit www. ODER cdn. ODER api.
\.(com|net|org)$   # Endet mit .com ODER .net ODER .org
```

### Character Classes
```regex
^[0-9]+\.          # Startet mit Zahlen (123.example.com)
^[a-z]+tracker     # Kleinbuchstaben + "tracker"
```

## IP-Set Strategie

### Option A: Ein IP-Set pro Kategorie
```sql
-- Ads → 10.0.1.x
INSERT INTO domain_regex (Pattern, IPv4, IPv6) VALUES ('^ads\..*', '10.0.1.1', 'fd00:1::1');

-- Tracker → 10.0.2.x
INSERT INTO domain_regex (Pattern, IPv4, IPv6) VALUES ('.*tracker.*', '10.0.2.1', 'fd00:2::1');

-- Malware → 10.0.3.x
INSERT INTO domain_regex (Pattern, IPv4, IPv6) VALUES ('.*malware.*', '10.0.3.1', 'fd00:3::1');
```

### Option B: Ein IP-Set pro Company (watchlist)
```sql
-- Sophos Patterns → 10.0.10.x
INSERT INTO domain_regex (Pattern, IPv4, IPv6) VALUES ('^.*sophos.*evil', '10.0.10.1', 'fd00:10::1');

-- Microsoft Patterns → 10.0.20.x
INSERT INTO domain_regex (Pattern, IPv4, IPv6) VALUES ('^.*microsoft.*malware', '10.0.20.1', 'fd00:20::1');
```

### Option C: NULL = Fallback nutzen
```sql
-- Kein spezielles IP-Set → nutzt --db-block-ipv4/6
INSERT INTO domain_regex (Pattern, IPv4, IPv6) VALUES ('^generic\.pattern', NULL, NULL);
```

## Performance-Tipp

⚠️ **Für 1-2 Millionen Patterns**: Regex ist LANGSAM!

**Besser**: Wenn möglich, konvertiere zu Exact/Wildcard:
```bash
# LANGSAM (Regex):
INSERT INTO domain_regex (Pattern, IPv4, IPv6) VALUES ('^ads\.example\.com$', '10.0.1.1', 'fd00:1::1');

# SCHNELL (Exact):
INSERT INTO domain_exact (Domain, IPv4, IPv6) VALUES ('ads.example.com', '10.0.1.1', 'fd00:1::1');

# SCHNELL (Wildcard = Domain + Subdomains):
INSERT INTO domain (Domain, IPv4, IPv6) VALUES ('ads.example.com', '10.0.1.1', 'fd00:1::1');
```

**Regel**: Nutze Regex NUR wenn du wirklich komplexe Patterns brauchst!

## Siehe auch

- [README-REGEX.md](README-REGEX.md) - Komplette Regex-Dokumentation
- [README-SQLITE.md](README-SQLITE.md) - SQLite Blocker Basis
- [watchlists/README.md](watchlists/README.md) - Watchlist-System für Companies
