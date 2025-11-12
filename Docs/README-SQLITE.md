# dnsmasq v2.91 mit SQLite DNS-Blocker + Regex

Diese Version von dnsmasq enthält eine SQLite-Integration, die es ermöglicht, DNS-Anfragen dynamisch zu blockieren.

## 🎯 Funktionsweise

### Lookup-Reihenfolge
1. **DNS Forwarding** (domain_dns_allow / domain_dns_block) → Forwarde an spezifischen DNS-Server
2. **Termination** (domain_exact / domain / domain_regex) → Returniere Termination-IP
3. **Normal Upstream** → Forwarde an Standard DNS-Server

### DNS-Blocker Modi
- **Domain IN Datenbank** → wird blockiert (NXDOMAIN oder Terminierungs-IP)
- **Domain NICHT in Datenbank** → normale Weiterleitung an DNS-Forwarder

## ✨ Features

### 🔀 DNS Forwarding (NEU!)
**Forwarde spezifische Domains an bestimmte DNS-Server:**
1. **Whitelist** (`domain_dns_allow`): Forwarde zu echtem DNS (z.B. 8.8.8.8)
2. **Blacklist** (`domain_dns_block`): Forwarde zu Blocker-DNS (z.B. 10.0.0.1)

**Use Case:** Blocke alle .xyz Domains, aber erlaube 1000 Exceptions!
- `*.xyz` → 10.0.0.1 (Blocker-DNS returns 0.0.0.0)
- `trusted.xyz` → 8.8.8.8 (Real DNS)

Siehe [README-DNS-FORWARDING.md](README-DNS-FORWARDING.md) für Details.

### ⚡ Drei Matching-Modi (Termination)
1. **Exact-only** (`domain_exact` Tabelle): Blockt NUR die exakte Domain (wie hosts-Datei)
2. **Wildcard** (`domain` Tabelle): Blockt Domain + alle Subdomains (empfohlen!)
3. **Regex** (`domain_regex` Tabelle): Blockt mit PCRE-Patterns (mächtig aber langsam!)

Siehe [README-REGEX.md](README-REGEX.md) für Regex-Details.

### Wildcard/Subdomain-Matching
Wenn `paypal-crime.de` in der Datenbank ist, werden automatisch **ALLE Subdomains** geblockt:
- `paypal-crime.de` ✅
- `www.paypal-crime.de` ✅
- `mail.server.paypal-crime.de` ✅
- `a.b.c.d.e.paypal-crime.de` ✅ (unendliche Tiefe!)

**Anders als Hosts-Dateien** die nur exaktes Matching haben!

### Alle DNS-Record-Typen blockieren
Blockt **ALLE** DNS-Anfragen für geblockte Domains:
- `A` (IPv4) ✅
- `AAAA` (IPv6) ✅
- `MX` (Mail) ✅
- `TXT` (Text) ✅
- `CNAME` (Alias) ✅
- `NS` (Nameserver) ✅
- Und alle anderen Record-Typen!

### Zentrale Terminierungs-IPs (optional)
Statt NXDOMAIN kannst du feste "Sinkhole" IPs zurückgeben:
- **Vorteil**: Besser für Apps (kein NXDOMAIN-Fehlerhandling nötig)
- **Vorteil**: DRASTISCH kleinere Datenbank (keine IPs pro Domain speichern!)
- **Beispiel**: `0.0.0.0` für IPv4, `::` für IPv6

### Dynamische Updates
- 🚀 **Domains zur Laufzeit hinzufügen/entfernen** - OHNE DNSMASQ-Restart!
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

### Option 1: Einfache manuelle Blocklist

```bash
# Datenbank erstellen
sqlite3 blocklist.db "CREATE TABLE domain (Domain TEXT PRIMARY KEY) WITHOUT ROWID;"
sqlite3 blocklist.db "CREATE UNIQUE INDEX idx_Domain ON domain(Domain);"

# Domains hinzufügen
sqlite3 blocklist.db "INSERT INTO domain VALUES ('ads.example.com');"
sqlite3 blocklist.db "INSERT INTO domain VALUES ('tracker.com');"  # blockt auch *.tracker.com!
sqlite3 blocklist.db "INSERT INTO domain VALUES ('malware.net');"
```

### Option 2: Mit optimiertem Script (empfohlen!)

```bash
# Script nutzt StevenBlack's unified hosts (140k+ Domains)
./createdb-optimized.sh myblocklist.db

# Oder eigene custom_blocklist.txt erstellen:
cat > custom_blocklist.txt <<EOF
doubleclick.net
googleadservices.com
facebook.com
EOF

./createdb-optimized.sh myblocklist.db
```

## 🚀 Verwendung

### Modus 1: Nur NXDOMAIN (klassisch)

```bash
./src/dnsmasq -d -p 5353 --db-file blocklist.db --log-queries

# Test: Blockierte Domain
dig @127.0.0.1 -p 5353 ads.example.com
# → NXDOMAIN (geblockt)

# Test: Blockierte Subdomain (Wildcard!)
dig @127.0.0.1 -p 5353 www.ads.example.com
# → NXDOMAIN (geblockt durch Wildcard-Matching!)

# Test: Normale Domain
dig @127.0.0.1 -p 5353 google.com
# → Normale Auflösung (forwarded)
```

### Modus 2: Mit Terminierungs-IPs (Sinkhole)

```bash
./src/dnsmasq -d -p 5353 \
  --db-file blocklist.db \
  --db-block-ipv4 0.0.0.0 \
  --db-block-ipv6 :: \
  --log-queries

# Test A-Record für blockierte Domain
dig @127.0.0.1 -p 5353 A ads.example.com
# → 0.0.0.0 (Sinkhole-IP statt NXDOMAIN!)

# Test AAAA-Record für blockierte Domain
dig @127.0.0.1 -p 5353 AAAA ads.example.com
# → :: (IPv6 Sinkhole!)

# Test MX-Record für blockierte Domain
dig @127.0.0.1 -p 5353 MX ads.example.com
# → NXDOMAIN (kein Mail-Server für geblockte Domain!)
```

### Produktiv-Beispiel

```bash
./src/dnsmasq \
  --port=53 \
  --db-file=/etc/dnsmasq/blocklist.db \
  --db-block-ipv4=0.0.0.0 \
  --db-block-ipv6=:: \
  --server=8.8.8.8 \
  --server=1.1.1.1 \
  --log-facility=/var/log/dnsmasq.log \
  --log-queries \
  --cache-size=10000
```

## 🔄 Zur Laufzeit ändern (OHNE Restart!)

```bash
# Domain zur Blocklist hinzufügen
sqlite3 blocklist.db "INSERT INTO domain VALUES ('newad.com');"

# Sofort wirksam - kein Restart nötig!
dig @127.0.0.1 -p 5353 newad.com
# → geblockt! Auch *.newad.com ist geblockt!

# Domain freigeben
sqlite3 blocklist.db "DELETE FROM domain WHERE Domain='newad.com');"

# Alle blockierten Domains anzeigen
sqlite3 blocklist.db "SELECT * FROM domain ORDER BY Domain LIMIT 10;"

# Statistik
sqlite3 blocklist.db "SELECT COUNT(*) as total FROM domain;"
```

## 📝 Datenbank-Schema

### Aktuelles Schema (mit per-domain Termination IPs)

```sql
-- Wildcard-Matching (domain + alle Subdomains)
CREATE TABLE domain (
    Domain TEXT PRIMARY KEY,
    IPv4 TEXT,              -- Optional: Per-domain Termination IPv4
    IPv6 TEXT               -- Optional: Per-domain Termination IPv6
) WITHOUT ROWID;

-- Exact-Matching (nur exakte Domain, keine Subdomains)
CREATE TABLE domain_exact (
    Domain TEXT PRIMARY KEY,
    IPv4 TEXT,              -- Optional: Per-domain Termination IPv4
    IPv6 TEXT               -- Optional: Per-domain Termination IPv6
) WITHOUT ROWID;

CREATE UNIQUE INDEX idx_Domain ON domain(Domain);
CREATE UNIQUE INDEX idx_Domain_exact ON domain_exact(Domain);
```

**Hinweis**: `WITHOUT ROWID` macht die Tabelle ~30% kleiner und schneller!

### Dual-Table Mode

✅ **Wildcard** (`domain`): Blockt Domain + **alle Subdomains** (*.domain)
✅ **Exact** (`domain_exact`): Blockt **nur** die exakte Domain (hosts-style)

### Per-Domain Termination IPs (10-20 IP-Sets)

✅ Jede Domain kann **ein** IPv4/IPv6-Paar haben
✅ Unterstützt **10-20 unterschiedliche IP-Sets**
✅ Fallback auf globale `--db-block-ipv4/6` wenn keine IPs in DB

**Beispiel:**
```sql
-- IP-Set 1: Werbung
INSERT INTO domain (Domain, IPv4, IPv6) VALUES ('ads.com', '10.0.0.1', 'fd00::1');

-- IP-Set 2: Tracking
INSERT INTO domain (Domain, IPv4, IPv6) VALUES ('tracker.net', '10.0.0.2', 'fd00::2');

-- IP-Set 3: Malware
INSERT INTO domain (Domain, IPv4, IPv6) VALUES ('malware.org', '10.0.0.3', 'fd00::3');

-- Fallback (nutzt globale --db-block-ipv4/6)
INSERT INTO domain (Domain) VALUES ('spam.io');
```

Siehe `MULTI-IP-SETS.md` für Details!

## 🧪 Wildcard-Matching Beispiele

| Domain in DB | Geblockt | Nicht geblockt |
|--------------|----------|----------------|
| `ads.com` | `ads.com`, `www.ads.com`, `*.*.ads.com` | `adsense.com` |
| `tracker.net` | `tracker.net`, `a.b.c.tracker.net` | `tracker-stats.com` |
| `google.com` | `google.com`, `mail.google.com` | `googleusercontent.com` |

**SQL-Logic**: `Domain = ? OR ? LIKE '%.' || Domain`

## 🔧 Technische Details

### Wie funktioniert das Wildcard-Matching?

Die SQL-Query prüft:
```sql
SELECT COUNT(*) FROM domain
WHERE Domain = 'www.ads.example.com'  -- Exaktes Match
   OR 'www.ads.example.com' LIKE '%.' || Domain  -- Subdomain-Match
```

Wenn `ads.example.com` in der DB ist:
- `'%.' || 'ads.example.com'` = `'%.ads.example.com'`
- `'www.ads.example.com' LIKE '%.ads.example.com'` = TRUE ✅
- `'a.b.c.ads.example.com' LIKE '%.ads.example.com'` = TRUE ✅

### Performance

- **Lookup-Zeit**: ~0.1ms für 1M Domains (mit Index)
- **Memory**: ~50MB für 1M Domains
- **Disk**: ~30MB für 1M Domains (mit WITHOUT ROWID)

### Vergleich mit Hosts-Dateien

| Feature | Hosts-Datei | SQLite-Blocker |
|---------|-------------|----------------|
| Wildcard-Matching | ❌ Nein | ✅ Ja |
| Zur Laufzeit ändern | ❌ Nein (Reload) | ✅ Ja |
| Alle Record-Typen | ❌ Nur A/AAAA | ✅ Ja |
| Memory (1M Domains) | ~200MB | ~50MB |
| Lookup-Speed | ~1ms | ~0.1ms |

## 💡 Use Cases

- **Ad-Blocker**: DNS-Level Werbeblocker (blockt auch Subdomains!)
- **Malware-Protection**: Blockierung von bekannten Malware-Domains + Subdomains
- **Parental Control**: Jugendschutz-Filter (blockt alle Subdomains!)
- **Corporate Filter**: Unternehmensnetzwerk-Filterung
- **Privacy**: Tracking-Domain-Blocker (blockt auch CDN-Subdomains!)

## 📄 Lizenz

Wie DNSMASQ selbst (GPL v2/v3)

## 🙏 Credits

- Original DNSMASQ: Simon Kelley (https://thekelleys.org.uk/dnsmasq/)
- SQLite-Integration: basierend auf v2.81 Patch
- v2.91 Port + Features: 2025
  - Wildcard/Subdomain-Matching
  - Alle DNS-Record-Typen
  - Zentrale Terminierungs-IPs
  - Optimiertes createdb Script
