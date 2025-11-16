# Per-Domain Termination IPs (10-20 IP Sets)

## Überblick

Jede Domain in der Datenbank kann **ein spezifisches IPv4/IPv6-Paar** haben. Du kannst **10-20 unterschiedliche IP-Sets** verwenden und diese verschiedenen Domains zuweisen.

## Schema

```sql
CREATE TABLE domain (
    Domain TEXT PRIMARY KEY,
    IPv4 TEXT,              -- Termination IPv4 (optional)
    IPv6 TEXT               -- Termination IPv6 (optional)
) WITHOUT ROWID;

CREATE TABLE domain_exact (
    Domain TEXT PRIMARY KEY,
    IPv4 TEXT,              -- Termination IPv4 (optional)
    IPv6 TEXT               -- Termination IPv6 (optional)
) WITHOUT ROWID;
```

## Verwendung

### Beispiel: 10 unterschiedliche IP-Sets

```sql
-- IP-Set 1: Standard-Blocker
INSERT INTO domain (Domain, IPv4, IPv6) VALUES ('ads.com', '10.0.0.1', 'fd00::1');
INSERT INTO domain (Domain, IPv4, IPv6) VALUES ('tracker1.net', '10.0.0.1', 'fd00::1');
INSERT INTO domain (Domain, IPv4, IPv6) VALUES ('spam1.org', '10.0.0.1', 'fd00::1');

-- IP-Set 2: Analytics-Blocker
INSERT INTO domain (Domain, IPv4, IPv6) VALUES ('analytics.com', '10.0.0.2', 'fd00::2');
INSERT INTO domain (Domain, IPv4, IPv6) VALUES ('metrics.io', '10.0.0.2', 'fd00::2');

-- IP-Set 3: Malware-Blocker
INSERT INTO domain (Domain, IPv4, IPv6) VALUES ('malware.net', '10.0.0.3', 'fd00::3');
INSERT INTO domain (Domain, IPv4, IPv6) VALUES ('phishing.org', '10.0.0.3', 'fd00::3');

-- IP-Set 4-10: Weitere Sets
INSERT INTO domain (Domain, IPv4, IPv6) VALUES ('social-tracker.com', '10.0.0.4', 'fd00::4');
INSERT INTO domain (Domain, IPv4, IPv6) VALUES ('crypto-miner.io', '10.0.0.5', 'fd00::5');
-- ...bis zu 20 verschiedene IP-Sets
```

## Wildcard vs. Exact Matching

### Wildcard (domain-Tabelle)
```sql
INSERT INTO domain (Domain, IPv4, IPv6) VALUES ('ads.com', '10.0.0.1', 'fd00::1');
```
**Blockt:**
- `ads.com` ✅
- `www.ads.com` ✅
- `cdn.tracking.ads.com` ✅
- Alle Subdomains! ✅

### Exact (domain_exact-Tabelle)
```sql
INSERT INTO domain_exact (Domain, IPv4, IPv6) VALUES ('paypal-evil.de', '10.0.1.1', 'fd00:1::1');
```
**Blockt:**
- `paypal-evil.de` ✅

**Blockt NICHT:**
- `www.paypal-evil.de` ❌
- `api.paypal-evil.de` ❌

## Fallback-Mechanismus

### Option 1: Per-Domain IPs (empfohlen)
```sql
INSERT INTO domain (Domain, IPv4, IPv6) VALUES ('ads.com', '10.0.0.1', 'fd00::1');
```
→ Gibt `10.0.0.1` / `fd00::1` zurück

### Option 2: Nur IPv4
```sql
INSERT INTO domain (Domain, IPv4) VALUES ('tracker.net', '10.0.0.2');
```
→ Gibt `10.0.0.2` zurück
→ IPv6: Nutzt globales `--db-block-ipv6` (falls gesetzt)

### Option 3: Keine IPs (Fallback)
```sql
INSERT INTO domain (Domain) VALUES ('malware.org');
```
→ Nutzt globale `--db-block-ipv4` und `--db-block-ipv6`

### Option 4: NXDOMAIN (kein Fallback)
Wenn weder per-domain IPs noch globale `--db-block-ipv4/6` gesetzt sind:
→ Gibt NXDOMAIN zurück (klassisches Blocking)

## CLI-Optionen

```bash
./src/dnsmasq -d -p 5353 \
  --db-file=blocklist.db \
  --db-block-ipv4=0.0.0.0 \      # Fallback IPv4 (optional)
  --db-block-ipv6=:: \            # Fallback IPv6 (optional)
  --log-queries
```

## Import-Script

### Import mit IP-Sets

```bash
# StevenBlack hosts mit IP-Set 1
./createdb-dual.sh blocklist.db

# Danach manuell IP-Sets zuweisen:
sqlite3 blocklist.db <<EOF
-- Alle Domains ohne IPs bekommen IP-Set 1
UPDATE domain SET IPv4 = '10.0.0.1', IPv6 = 'fd00::1' WHERE IPv4 IS NULL;

-- Spezielle Domains mit IP-Set 2
UPDATE domain SET IPv4 = '10.0.0.2', IPv6 = 'fd00::2'
WHERE Domain LIKE '%analytics%' OR Domain LIKE '%tracker%';

-- Malware-Domains mit IP-Set 3
UPDATE domain SET IPv4 = '10.0.0.3', IPv6 = 'fd00::3'
WHERE Domain LIKE '%malware%' OR Domain LIKE '%phishing%';
EOF
```

### Import mit custom IP-Sets

```bash
# Erstelle Datei mit Domain + IP
cat > ads_set1.txt <<EOF
ads.com 10.0.0.1 fd00::1
tracker.net 10.0.0.1 fd00::1
spam.org 10.0.0.1 fd00::1
EOF

cat > analytics_set2.txt <<EOF
analytics.com 10.0.0.2 fd00::2
metrics.io 10.0.0.2 fd00::2
EOF

# Import (manuell per SQL)
awk '{printf "INSERT OR IGNORE INTO domain (Domain, IPv4, IPv6) VALUES (\"%s\", \"%s\", \"%s\");\n", $1, $2, $3}' ads_set1.txt | sqlite3 blocklist.db
awk '{printf "INSERT OR IGNORE INTO domain (Domain, IPv4, IPv6) VALUES (\"%s\", \"%s\", \"%s\");\n", $1, $2, $3}' analytics_set2.txt | sqlite3 blocklist.db
```

## Beispiel-Queries

### Alle Domains mit IP-Set 1
```sql
SELECT Domain FROM domain WHERE IPv4 = '10.0.0.1' AND IPv6 = 'fd00::1';
```

### Domains ohne IP-Set (Fallback)
```sql
SELECT Domain FROM domain WHERE IPv4 IS NULL AND IPv6 IS NULL;
```

### Anzahl Domains pro IP-Set
```sql
SELECT IPv4, IPv6, COUNT(*) as count
FROM domain
GROUP BY IPv4, IPv6
ORDER BY count DESC;
```

### IP-Set ändern
```sql
-- Alle Tracker-Domains auf IP-Set 5 umstellen
UPDATE domain
SET IPv4 = '10.0.0.5', IPv6 = 'fd00::5'
WHERE Domain LIKE '%tracker%' OR Domain LIKE '%analytics%';
```

## Performance

### Lookup-Zeit
- **Exact Match**: ~0.1ms (indexed)
- **Wildcard Match**: ~0.15ms (indexed + LIKE)
- **Kein Unterschied** ob mit oder ohne per-domain IPs

### Speicher
- **Ohne IPs**: ~20 bytes pro Domain
- **Mit IPv4+IPv6**: ~50 bytes pro Domain
- **Für 6 Milliarden Domains**: ~300 GB (mit IPs) vs. ~120 GB (ohne IPs)

## Vorteile

✅ **Flexible IP-Zuordnung**: 10-20 verschiedene IP-Sets
✅ **Kategorisierung**: Verschiedene IPs für Ads, Tracker, Malware, etc.
✅ **Fallback**: Globale `--db-block-ipv4/6` für Domains ohne IPs
✅ **Zur Laufzeit ändern**: `UPDATE domain SET IPv4=... WHERE ...`
✅ **Abwärtskompatibel**: Domains ohne IPs nutzen Fallback oder NXDOMAIN

## Migration von alter DB

### Von altem Schema (nur Domain) zu neuem Schema (Domain + IPs)

```bash
# Backup
cp blocklist.db blocklist.db.backup

# Migration
sqlite3 blocklist.db <<EOF
-- Tabelle für Wildcard erweitern
CREATE TABLE domain_new (
    Domain TEXT PRIMARY KEY,
    IPv4 TEXT,
    IPv6 TEXT
) WITHOUT ROWID;

-- Daten kopieren (ohne IPs)
INSERT INTO domain_new (Domain)
SELECT Domain FROM domain;

-- Alte Tabelle löschen
DROP TABLE domain;

-- Neue Tabelle umbenennen
ALTER TABLE domain_new RENAME TO domain;

-- Index neu erstellen
CREATE UNIQUE INDEX idx_Domain ON domain(Domain);

-- Gleiches für domain_exact
CREATE TABLE domain_exact_new (
    Domain TEXT PRIMARY KEY,
    IPv4 TEXT,
    IPv6 TEXT
) WITHOUT ROWID;

INSERT INTO domain_exact_new (Domain)
SELECT Domain FROM domain_exact;

DROP TABLE domain_exact;
ALTER TABLE domain_exact_new RENAME TO domain_exact;
CREATE UNIQUE INDEX idx_Domain_exact ON domain_exact(Domain);

-- Optimieren
VACUUM;
ANALYZE;
EOF

echo "✅ Migration completed!"
```

## Best Practices

1. **Konsistenz**: Verwende immer beide (IPv4 + IPv6) oder keine
2. **Kategorisierung**: Gruppiere ähnliche Domains mit gleichem IP-Set
3. **Fallback nutzen**: Domains ohne spezielle Anforderungen → Fallback
4. **Monitoring**: Logge welche IP-Sets verwendet werden
5. **Dokumentation**: Notiere welches IP-Set für welche Kategorie ist

## Beispiel-Setup: 10 IP-Sets

```bash
# IP-Set-Plan:
# 10.0.0.1 / fd00::1  → Werbung (ads, banners)
# 10.0.0.2 / fd00::2  → Tracking (analytics, metrics)
# 10.0.0.3 / fd00::3  → Malware (malware, phishing)
# 10.0.0.4 / fd00::4  → Social Media Tracker
# 10.0.0.5 / fd00::5  → Crypto Miner
# 10.0.0.6 / fd00::6  → Adult Content
# 10.0.0.7 / fd00::7  → Spam/Scam
# 10.0.0.8 / fd00::8  → CDN-Tracker
# 10.0.0.9 / fd00::9  → Telemetry
# 10.0.0.10 / fd00::10 → Sonstiges

# Dnsmasq starten
./src/dnsmasq -d -p 5353 \
  --db-file=blocklist.db \
  --db-block-ipv4=0.0.0.0 \
  --db-block-ipv6=:: \
  --log-queries

# Testen
dig @127.0.0.1 -p 5353 ads.com          # → 10.0.0.1 (IP-Set 1)
dig @127.0.0.1 -p 5353 analytics.com    # → 10.0.0.2 (IP-Set 2)
dig @127.0.0.1 -p 5353 malware.net      # → 10.0.0.3 (IP-Set 3)
```

## Zukünftige Erweiterung: Multi-IP Round-Robin

Siehe `MULTI-IP-DESIGN.md` für geplante Erweiterung:
- Mehrere IPs pro Domain
- Round-Robin DNS Load Balancing
- Separate `domain_ips` Tabelle

Aktuell: **Eine** IPv4 + **eine** IPv6 pro Domain ✅
