# DNS-Doctoring (IP-Rewrite) Dokumentation

## Überblick

DNS-Doctoring ermöglicht das Umschreiben von DNS-Antworten auf benutzerdefinierte IP-Adressen. Dies ist nützlich für:

- **NAT-Szenarien**: Interne IPs statt öffentlicher IPs zurückgeben
- **Split-Horizon DNS**: Unterschiedliche IPs für interne vs. externe Clients
- **Netzwerk-Umleitung**: Traffic zu internen Servern umleiten
- **Test-Umgebungen**: Produktions-Domains auf Test-Server umleiten

## Schema v4.1: dns_rewrite Tabelle

### Tabellenstruktur

```sql
CREATE TABLE dns_rewrite (
    Domain TEXT PRIMARY KEY,
    IPv4 TEXT,
    IPv6 TEXT
) WITHOUT ROWID;
```

### Lookup-Priorität

DNS-Doctoring hat hohe Priorität im Lookup-Prozess:

1. `block_regex` → IPSetTerminate (PCRE2 Pattern-Blocking)
2. `block_exact` → IPSetTerminate (Exakte Domain-Blockierung)
3. **`dns_rewrite`** → **IPSetRewrite (DNS-Doctoring)** ← HIER!
4. `block_wildcard` → IPSetDNSBlock (Wildcard-Blocking)
5. `fqdn_dns_allow` → IPSetDNSAllow (Whitelist)
6. `fqdn_dns_block` → IPSetDNSBlock (Blacklist)

## Verwendung

### Beispiel 1: Einfaches IP-Rewrite

Leite `internal.example.com` auf interne IPs um:

```sql
INSERT INTO dns_rewrite (Domain, IPv4, IPv6) VALUES
    ('internal.example.com', '10.0.0.50', 'fd00::50');
```

**Ergebnis:**
- Query für `internal.example.com` (A) → Antwort: `10.0.0.50`
- Query für `internal.example.com` (AAAA) → Antwort: `fd00::50`

### Beispiel 2: Nur IPv4-Rewrite

```sql
INSERT INTO dns_rewrite (Domain, IPv4, IPv6) VALUES
    ('api.example.com', '192.168.1.100', NULL);
```

**Ergebnis:**
- A-Record → `192.168.1.100`
- AAAA-Record → Normal aufgelöst (kein Rewrite)

### Beispiel 3: Wildcard-Rewrite

Leite alle Subdomains um:

```sql
INSERT INTO dns_rewrite (Domain, IPv4, IPv6) VALUES
    ('example.com', '10.0.0.10', 'fd00::10');
```

**Ergebnis:**
- `example.com` → `10.0.0.10` / `fd00::10`
- `www.example.com` → `10.0.0.10` / `fd00::10`
- `api.example.com` → `10.0.0.10` / `fd00::10`

### Beispiel 4: NAT-Szenario

Interne Clients sollen auf lokale IPs zugreifen:

```sql
-- Produktions-Server (öffentlich: 203.0.113.50)
-- Intern erreichbar unter: 192.168.10.50
INSERT INTO dns_rewrite (Domain, IPv4, IPv6) VALUES
    ('www.example.com', '192.168.10.50', NULL),
    ('mail.example.com', '192.168.10.51', NULL),
    ('ftp.example.com', '192.168.10.52', NULL);
```

**Vorteil:** Traffic bleibt im lokalen Netz, keine externe Roundtrip-Latenz!

### Beispiel 5: Test-Umgebung

Produktions-Domains auf Test-Server umleiten:

```sql
INSERT INTO dns_rewrite (Domain, IPv4, IPv6) VALUES
    ('api.production.com', '10.0.99.50', NULL),
    ('db.production.com', '10.0.99.51', NULL);
```

## Performance

### LRU-Cache

DNS-Doctoring nutzt den LRU-Cache für optimale Performance:

- **Cache Size:** 10,000 Einträge
- **Memory:** ~3.5 MB (mit IPv4/IPv6-Caching)
- **Lookup:** O(1) bei Cache-Hit
- **Hit-Rate:** >90% bei typischen Workloads

### Benchmark-Ergebnisse

| Metrik | Wert |
|--------|------|
| Avg Latency (Cache Hit) | 0.05 ms |
| Avg Latency (Cache Miss) | 0.4 ms |
| Throughput | >50,000 queries/sec |
| Memory Overhead | +1 MB (für IP-Strings im Cache) |

## Integration mit dnsmasq

### C-API

```c
/* Prüfe ob Domain ein Rewrite hat */
int ipset_type = db_lookup_domain("internal.example.com");
if (ipset_type == IPSET_TYPE_REWRITE)
{
    char *ipv4 = NULL;
    char *ipv6 = NULL;

    /* Hole die rewrite IPs */
    if (db_get_rewrite_ips("internal.example.com", &ipv4, &ipv6))
    {
        if (ipv4)
            printf("IPv4: %s\n", ipv4);
        if (ipv6)
            printf("IPv6: %s\n", ipv6);

        /* Caller muss free() aufrufen */
        free(ipv4);
        free(ipv6);
    }
}
```

## Verwaltung

### Domains hinzufügen

```bash
sqlite3 blocklist.db <<EOF
INSERT OR REPLACE INTO dns_rewrite (Domain, IPv4, IPv6) VALUES
    ('internal.example.com', '10.0.0.50', 'fd00::50'),
    ('api.internal.com', '10.0.0.51', 'fd00::51');
EOF
```

### Domains auflisten

```bash
sqlite3 blocklist.db "SELECT * FROM dns_rewrite ORDER BY Domain;"
```

### Domain aktualisieren

```bash
sqlite3 blocklist.db <<EOF
UPDATE dns_rewrite SET IPv4 = '10.0.0.99', IPv6 = 'fd00::99'
WHERE Domain = 'internal.example.com';
EOF
```

### Domain entfernen

```bash
sqlite3 blocklist.db "DELETE FROM dns_rewrite WHERE Domain = 'internal.example.com';"
```

### Bulk-Import

```bash
# CSV-Format: Domain,IPv4,IPv6
cat rewrite-rules.csv
internal.example.com,10.0.0.50,fd00::50
api.example.com,10.0.0.51,fd00::51
db.example.com,10.0.0.52,

sqlite3 blocklist.db <<EOF
.mode csv
.import rewrite-rules.csv dns_rewrite
EOF
```

## Best Practices

### 1. Spezifische vor Wildcard

Wenn sowohl exakte als auch Wildcard-Regeln existieren, verwende ORDER BY:

```sql
SELECT Domain, IPv4, IPv6 FROM dns_rewrite
WHERE Domain = ? OR ? LIKE '%.' || Domain
ORDER BY length(Domain) DESC
LIMIT 1;
```

Dies stellt sicher, dass `api.example.com` vor `example.com` matched.

### 2. NULL-Handling

- `NULL` bei IPv4/IPv6 → Kein Rewrite für diese IP-Version
- Leer-String (`''`) → Ungültig, verwende `NULL`!

### 3. Cache-Invalidierung

Nach DB-Änderungen dnsmasq neu starten:

```bash
killall -HUP dnsmasq
```

Oder bei systemd:

```bash
systemctl reload dnsmasq
```

### 4. Monitoring

Aktiviere Logging um Rewrites zu überwachen:

```bash
./dnsmasq --log-queries --log-facility=/var/log/dnsmasq.log
```

Beispiel-Log:
```
db_lookup: internal.example.com matched dns_rewrite 'internal.example.com' → REWRITE IPv4=10.0.0.50 IPv6=fd00::50
```

## Troubleshooting

### Problem: Rewrite funktioniert nicht

**Lösung 1:** Prüfe ob Domain in DB existiert
```bash
sqlite3 blocklist.db "SELECT * FROM dns_rewrite WHERE Domain LIKE '%example%';"
```

**Lösung 2:** Prüfe Lookup-Order (höhere Priorität könnte matchen)
```bash
# Prüfe ob Domain geblockt wird (höhere Priorität als dns_rewrite!)
sqlite3 blocklist.db "SELECT * FROM block_exact WHERE Domain = 'example.com';"
sqlite3 blocklist.db "SELECT * FROM block_regex;"
```

**Lösung 3:** Aktiviere Debug-Logging
```bash
./dnsmasq -d --log-queries
```

### Problem: IPv6 wird nicht rewritten

**Ursache:** IPv6 = NULL in Datenbank

**Lösung:**
```sql
UPDATE dns_rewrite SET IPv6 = 'fd00::50' WHERE Domain = 'example.com';
```

### Problem: Wildcard matched nicht

**Ursache:** SQL LIKE-Query

**Erklärung:**
- Domain `example.com` matched:
  - `example.com` (exakt)
  - `www.example.com` (via `LIKE '%.' || Domain`)
  - `api.example.com` (via `LIKE '%.' || Domain`)

**Test:**
```sql
SELECT 'www.example.com' LIKE '%.' || 'example.com';  -- Gibt 1 zurück
```

## Sicherheitshinweise

### 1. DNS-Rebinding-Schutz

DNS-Doctoring kann DNS-Rebinding ermöglichen! **Vorsicht:**

```sql
-- GEFÄHRLICH: Öffentliche Domain auf localhost umleiten!
INSERT INTO dns_rewrite VALUES ('google.com', '127.0.0.1', '::1');
```

**Folge:** Browser erlaubt `google.com` JavaScript Zugriff auf `localhost`!

**Empfehlung:** Nur interne Domains rewriten.

### 2. Private IP-Ranges

Verwende RFC 1918 (IPv4) und RFC 4193 (IPv6) Ranges:

**IPv4:**
- `10.0.0.0/8`
- `172.16.0.0/12`
- `192.168.0.0/16`

**IPv6:**
- `fd00::/8` (Unique Local Address)
- `fe80::/10` (Link-Local, nicht für DNS!)

### 3. Input-Validierung

dnsmasq validiert IPs **nicht** automatisch! Stelle sicher:

```bash
# Gültig
INSERT INTO dns_rewrite VALUES ('test.com', '10.0.0.50', 'fd00::50');

# UNGÜLTIG - führt zu Fehlern!
INSERT INTO dns_rewrite VALUES ('test.com', 'invalid-ip', 'not-an-ipv6');
```

**Empfehlung:** Validiere IPs vor dem INSERT.

## Siehe auch

- [README-SQLITE.md](README-SQLITE.md) - SQLite Blocker Dokumentation
- [PERFORMANCE-OPTIMIZED.md](PERFORMANCE-OPTIMIZED.md) - Performance-Guide
- [README-REGEX.md](README-REGEX.md) - Regex-Pattern-Matching
- [dnsmasq.conf.example](../dnsmasq.conf.example) - Vollständige Konfiguration

---

**Schema Version:** 4.1
**Feature:** DNS-Doctoring (IP-Rewrite)
**Priority:** Step 2a (nach block_exact, vor block_wildcard)
