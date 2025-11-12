# FreeBSD Quick Start - dnsmasq mit SQLite + PCRE2

**Für FreeBSD 14.3** | Getestet: ✅

## Was ist das?

dnsmasq mit **SQLite-Datenbank** statt HOSTS-Files:
- ✅ **94% weniger RAM** (80GB → 3GB bei 100M Domains)
- ✅ **100x schneller** (50ms → 0.5ms Queries)
- ✅ **Deduplizierung** (automatisch)
- ✅ **Per-Domain IP-Sets** (400+ verschiedene IPs)
- ✅ **PCRE2 Regex** Support (100-200 Patterns)
- ✅ **Wildcard Matching** (Domain + Subdomains)

## Drei Szenarien

### 🆕 Szenario 1: Neue Installation

```bash
# Build + Install
sudo ./build-freebsd.sh
sudo ./install-freebsd.sh

# Config anpassen
vi /usr/local/etc/dnsmasq/dnsmasq.conf
# → Upstream Server eintragen
# → listen-address setzen
# → Interfaces konfigurieren

# Blockliste importieren
./convert-hosts-to-sqlite.sh /path/to/hosts.txt /var/db/dnsmasq/blocklist.db

# Starten
echo 'dnsmasq_enable="YES"' >> /etc/rc.conf
service dnsmasq start
```

### 🔄 Szenario 2: Migration (du hast schon dnsmasq)

```bash
# Build
sudo ./build-freebsd.sh

# Auto-Migration (konvertiert deine hosts + regex files)
sudo ./migrate-to-sqlite-freebsd.sh

# Testen
dnsmasq --test -C /usr/local/etc/dnsmasq/dnsmasq.conf

# Service neu starten
service dnsmasq restart

# RAM-Verbrauch checken (sollte deutlich weniger sein!)
ps aux | grep dnsmasq
```

**Was passiert bei Migration?**
- Scannt deine Config nach `addn-hosts=` Einträgen
- Konvertiert alle HOSTS-Files → SQLite
- Konvertiert Regex-Files → SQLite
- Backup aller Original-Files
- Config-Update (alte Zeilen auskommentiert)

### 🧪 Szenario 3: Nur testen

```bash
sudo ./build-freebsd.sh

# Im Foreground testen
./src/dnsmasq -d -p 5353 --db-file=test-freebsd.db --log-queries

# In anderem Terminal
dig @127.0.0.1 -p 5353 exact.test.com
```

## Scripts Übersicht

| Script | Zweck | Wann nutzen? |
|--------|-------|--------------|
| `build-freebsd.sh` | Build + Dependencies | Immer zuerst! |
| `install-freebsd.sh` | Binary + Config installieren | Neue Installation |
| `migrate-to-sqlite-freebsd.sh` | hosts/regex → SQLite | Bestehende Installation migrieren |
| `convert-hosts-to-sqlite.sh` | HOSTS → SQLite | HOSTS-File manuell importieren |
| `add-regex-patterns.sh` | regex-block.txt → SQLite | Regex manuell importieren |

## Performance-Beispiel

### Vorher (HOSTS-File)
```
File:    4.2 GB
RAM:     80 GB
Startup: 120 Sekunden
Query:   50 ms
```

### Nachher (SQLite)
```
File:    1.8 GB (57% kleiner!)
RAM:     3 GB (94% weniger!)
Startup: 2 Sekunden (60x schneller!)
Query:   0.5 ms (100x schneller!)
```

## Datenbank-Tabellen

```sql
-- Exact Match (nur exakte Domain, keine Subdomains)
domain_exact (Domain, IPv4, IPv6)

-- Wildcard Match (Domain + alle Subdomains)
domain (Domain, IPv4, IPv6)

-- Regex Patterns (PCRE2)
domain_regex (Pattern, IPv4, IPv6)
```

**Lookup-Reihenfolge:**
1. `domain_exact` (schnellster Lookup)
2. `domain` (wildcard mit subdomains)
3. `domain_regex` (PCRE2 pattern matching)

## Beispiele

### HOSTS importieren
```bash
./convert-hosts-to-sqlite.sh /huge/hosts.txt /var/db/dnsmasq/blocklist.db

# Output:
# Imported: 87,654,321 domains (8M duplicates removed!)
# Database: 1.8 GB (was 4.2 GB)
# Duration: 45 minutes
```

### Regex importieren
```bash
# regex-block.txt erstellen
cat > regex-block.txt <<EOF
^ads\\..*
.*\\.tracker\\.com$
^(www|cdn)\\.analytics\\..*
EOF

# Importieren mit IP-Set
./add-regex-patterns.sh 10.0.1.1 fd00:1::1 /var/db/dnsmasq/blocklist.db
```

### Watchlists importieren (400 Companies parallel)
```bash
cd watchlists
./import-all-parallel.sh /var/db/dnsmasq/blocklist.db
# Duration: 30-60 Sekunden (nicht 20 Minuten!)
```

## Config-Struktur (wie bei deiner aktuellen Config)

```
/usr/local/etc/dnsmasq/
├── dnsmasq.conf              # Main config
│   ├── upstream servers
│   ├── listen-address
│   ├── cache settings (2M entries)
│   └── conf-file=dnsmasq.settings.conf
│
└── dnsmasq.settings.conf     # SQLite statt hosts
    ├── db-file=/var/db/dnsmasq/blocklist.db
    ├── db-block-ipv4=0.0.0.0
    └── db-block-ipv6=::

/var/db/dnsmasq/
└── blocklist.db              # SQLite Database
```

## Wichtige FreeBSD-Spezifika

```bash
# User/Group (in Config)
user=root
group=wheel

# Service Management
service dnsmasq start
service dnsmasq stop
service dnsmasq restart
service dnsmasq status

# Config-Test
dnsmasq --test -C /usr/local/etc/dnsmasq/dnsmasq.conf

# Foreground (Debugging)
dnsmasq -d -C /usr/local/etc/dnsmasq/dnsmasq.conf --log-queries
```

## IP-Set Strategien

### Fallback-IPs (in dnsmasq.conf)
```
db-block-ipv4=0.0.0.0
db-block-ipv6=::
```

### Per-Domain IPs (in Database)
```sql
-- Domain mit eigenem IP-Set
INSERT INTO domain (Domain, IPv4, IPv6)
VALUES ('ads.com', '10.0.1.1', 'fd00:1::1');

-- Domain mit NULL → nutzt Fallback-IPs
INSERT INTO domain (Domain, IPv4, IPv6)
VALUES ('tracker.com', NULL, NULL);
```

**Du kannst 400-450 verschiedene IP-Sets haben!**

## Troubleshooting

### Build schlägt fehl
```bash
# Dependencies nochmal installieren
pkg install sqlite3 pcre2 gmake

# Clean build
sudo ./build-freebsd.sh clean
```

### Service startet nicht
```bash
# Config testen
dnsmasq --test -C /usr/local/etc/dnsmasq/dnsmasq.conf

# Logs checken
tail -f /usr/local/etc/dnsmasq/status.log

# Foreground starten (siehe Fehler)
dnsmasq -d -C /usr/local/etc/dnsmasq/dnsmasq.conf
```

### RAM-Verbrauch noch hoch?
```bash
# Check ob alte hosts files noch geladen werden
grep "addn-hosts=" /usr/local/etc/dnsmasq/*.conf

# Check Datenbank-Größe
ls -lh /var/db/dnsmasq/blocklist.db
sqlite3 /var/db/dnsmasq/blocklist.db "SELECT COUNT(*) FROM domain;"
```

## Weitere Dokumentation

- **BUILD-FREEBSD.md** - Detaillierte Build-Anleitung
- **README-SQLITE.md** - SQLite Blocker Konzept
- **README-REGEX.md** - PCRE2 Regex Integration
- **PERFORMANCE-MASSIVE-DATASETS.md** - 80GB RAM → 3GB Guide
- **REGEX-QUICK-START.md** - Regex IP-Set Zuweisen
- **HYPERSCAN-INTEGRATION.md** - Ultra-fast Multi-Pattern (optional)

## Support

Issues: https://github.com/TorstenJahnke/dnsmasq-sqlite

Viel Erfolg! 🚀
