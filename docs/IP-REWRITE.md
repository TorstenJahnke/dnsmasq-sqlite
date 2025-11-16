# IP-Rewriting (DNS-Doctoring) - Schema v4.1

## Überblick

IP-Rewriting ermöglicht das Umschreiben von IP-Adressen in DNS-Antworten **NACH** der normalen DNS-Auflösung. Dies ist ideal für NAT-Szenarien und private Netzwerk-Mappings.

**Wichtig:** Dies ist **IP-zu-IP** Rewriting, **NICHT** Domain-zu-IP Rewriting!

## Funktionsweise

```
1. DNS-Query: example.com
2. DNS-Auflösung: 178.223.16.21
3. IP-Rewrite-Check: 178.223.16.21 in Datenbank?
4. JA → Rewrite zu: 10.20.0.10
5. Antwort an Client: 10.20.0.10
```

## Datenbank-Schema

### IPv4-Rewriting

```sql
CREATE TABLE ip_rewrite_v4 (
    Source_IPv4 TEXT PRIMARY KEY,  -- Öffentliche/externe IP
    Target_IPv4 TEXT NOT NULL      -- Private/interne IP
) WITHOUT ROWID;
```

### IPv6-Rewriting

```sql
CREATE TABLE ip_rewrite_v6 (
    Source_IPv6 TEXT PRIMARY KEY,  -- Öffentliche/externe IPv6
    Target_IPv6 TEXT NOT NULL      -- Private/interne IPv6
) WITHOUT ROWID;
```

## Verwendung

### Beispiel 1: Einfaches NAT

```bash
# Öffentliche IP 178.223.16.21 → Private IP 10.20.0.10
./manage-ip-rewrite.sh blocklist.db add-v4 178.223.16.21 10.20.0.10

# Test
./manage-ip-rewrite.sh blocklist.db test-v4 178.223.16.21
# Output: ✓ Rewrite found: 178.223.16.21 → 10.20.0.10
```

**Ergebnis:**
- DNS-Query für `example.com` gibt `178.223.16.21` zurück
- dnsmasq rewritet automatisch zu `10.20.0.10`
- Client erhält `10.20.0.10`

### Beispiel 2: IPv6 ULA Mapping

```bash
# Öffentliche IPv6 → Unique Local Address (ULA)
./manage-ip-rewrite.sh blocklist.db add-v6 2001:db8:cafe::1 fd00:dead:beef::10
```

### Beispiel 3: Mehrere IPs

```bash
# Mehrere öffentliche Server auf interne IPs mappen
./manage-ip-rewrite.sh blocklist.db add-v4 203.0.113.10 192.168.1.10
./manage-ip-rewrite.sh blocklist.db add-v4 203.0.113.11 192.168.1.11
./manage-ip-rewrite.sh blocklist.db add-v4 203.0.113.12 192.168.1.12

# Alle anzeigen
./manage-ip-rewrite.sh blocklist.db list-v4
```

## Management-Skript

### Syntax

```bash
./manage-ip-rewrite.sh <database> <action> [args...]
```

### Aktionen

**IPv4:**
```bash
# Hinzufügen
./manage-ip-rewrite.sh blocklist.db add-v4 178.223.16.21 10.20.0.10

# Entfernen
./manage-ip-rewrite.sh blocklist.db remove-v4 178.223.16.21

# Testen
./manage-ip-rewrite.sh blocklist.db test-v4 178.223.16.21

# Auflisten
./manage-ip-rewrite.sh blocklist.db list-v4
```

**IPv6:**
```bash
# Hinzufügen
./manage-ip-rewrite.sh blocklist.db add-v6 2001:db8::1 fd00::10

# Entfernen
./manage-ip-rewrite.sh blocklist.db remove-v6 2001:db8::1

# Testen
./manage-ip-rewrite.sh blocklist.db test-v6 2001:db8::1

# Auflisten
./manage-ip-rewrite.sh blocklist.db list-v6
```

**Alle:**
```bash
# Alle Regeln anzeigen (IPv4 + IPv6)
./manage-ip-rewrite.sh blocklist.db list-all
```

## Direkte SQL-Verwaltung

### Hinzufügen

```sql
-- IPv4
INSERT INTO ip_rewrite_v4 (Source_IPv4, Target_IPv4) VALUES
    ('178.223.16.21', '10.20.0.10'),
    ('203.0.113.50', '192.168.10.50');

-- IPv6
INSERT INTO ip_rewrite_v6 (Source_IPv6, Target_IPv6) VALUES
    ('2001:db8:cafe::1', 'fd00:dead:beef::10');
```

### Aktualisieren

```sql
UPDATE ip_rewrite_v4 SET Target_IPv4 = '10.20.0.99'
WHERE Source_IPv4 = '178.223.16.21';
```

### Entfernen

```sql
DELETE FROM ip_rewrite_v4 WHERE Source_IPv4 = '178.223.16.21';
```

### Abfragen

```sql
-- Alle IPv4-Regeln
SELECT * FROM ip_rewrite_v4;

-- Alle IPv6-Regeln
SELECT * FROM ip_rewrite_v6;

-- Spezifische IP
SELECT Target_IPv4 FROM ip_rewrite_v4 WHERE Source_IPv4 = '178.223.16.21';
```

## Use Cases

### 1. NAT-Szenario

**Problem:** Interne Clients greifen auf öffentliche Server zu, aber Traffic sollte intern bleiben.

**Lösung:**
```bash
# Öffentlicher Web-Server: 203.0.113.50
# Interne IP: 192.168.10.50
./manage-ip-rewrite.sh blocklist.db add-v4 203.0.113.50 192.168.10.50
```

**Vorteil:** Traffic bleibt im lokalen Netz, keine WAN-Roundtrips!

### 2. Multi-Homed Server

**Problem:** Server hat mehrere öffentliche IPs, intern aber nur eine.

**Lösung:**
```bash
./manage-ip-rewrite.sh blocklist.db add-v4 203.0.113.10 192.168.1.50
./manage-ip-rewrite.sh blocklist.db add-v4 203.0.113.11 192.168.1.50
./manage-ip-rewrite.sh blocklist.db add-v4 203.0.113.12 192.168.1.50
```

### 3. IPv6 Transition

**Problem:** Öffentliche IPv6-Adressen auf lokale ULAs mappen.

**Lösung:**
```bash
./manage-ip-rewrite.sh blocklist.db add-v6 2001:db8:cafe::10 fd00:1234:5678::10
```

### 4. Load-Balancer

**Problem:** Virtuelle IP zeigt auf verschiedene interne Server.

**Lösung:**
```bash
# VIP: 203.0.113.100 → verschiedene Backend-Server
./manage-ip-rewrite.sh blocklist.db add-v4 203.0.113.100 192.168.10.10
# (Rotation via external script)
```

## Performance

- **Lookup:** O(1) - B-Tree Index auf Source_IPv4/IPv6
- **Memory:** Minimal (nur Index, keine Caching nötig)
- **Latency:** <0.1 ms zusätzlich pro Query
- **Throughput:** Keine signifikante Auswirkung

## Debugging

### Log-Ausgabe aktivieren

```bash
./dnsmasq -d --log-queries --db-file=blocklist.db
```

**Beispiel-Log:**
```
IP Rewrite v4: 178.223.16.21 → 10.20.0.10
query[A] example.com from 192.168.1.100
reply example.com is 10.20.0.10  (rewritten from 178.223.16.21)
```

### Manuelle Tests

```bash
# Test mit dig
dig @127.0.0.1 example.com A

# Expected:
# ;; ANSWER SECTION:
# example.com.  300  IN  A  10.20.0.10
# (statt 178.223.16.21)
```

### Datenbank-Prüfung

```bash
# Alle Regeln
sqlite3 blocklist.db "SELECT * FROM ip_rewrite_v4; SELECT * FROM ip_rewrite_v6;"

# Anzahl
sqlite3 blocklist.db "SELECT COUNT(*) FROM ip_rewrite_v4; SELECT COUNT(*) FROM ip_rewrite_v6;"
```

## Wichtige Hinweise

### ✅ Funktioniert für

- NAT-Szenarien
- Private Netzwerk-Mappings
- IPv6 ULA-Mappings
- Load-Balancer VIPs
- Multi-Homed Server

### ❌ Funktioniert NICHT für

- Reverse DNS (PTR Records) - noch nicht implementiert
- Domain-basiertes Rewriting - verwenden Sie DNS-Forwarding dafür
- Dynamische IPs - muss manuell aktualisiert werden

### ⚠️ Sicherheit

**DNS-Rebinding-Risiko:**
```bash
# GEFÄHRLICH: Öffentliche IP auf localhost mappen!
./manage-ip-rewrite.sh blocklist.db add-v4 8.8.8.8 127.0.0.1
```

**Empfehlung:** Nur interne/private IP-Ranges verwenden!

**Private IP-Ranges:**
- IPv4: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
- IPv6: fd00::/8 (ULA)

## Integration mit dnsmasq.conf

```bash
# dnsmasq.conf
db-file=/var/db/dnsmasq/blocklist.db

# Erlaube private IPs in DNS-Antworten
rebind-localhost-ok
rebind-domain-ok=/local/
rebind-domain-ok=/internal/

# Log IP-Rewrites
log-queries
```

## Bulk-Import

```bash
# CSV-Format: Source,Target
cat ip-rewrites-v4.csv
178.223.16.21,10.20.0.10
203.0.113.50,192.168.10.50
203.0.113.51,192.168.10.51

# Import
sqlite3 blocklist.db <<EOF
.mode csv
.import ip-rewrites-v4.csv ip_rewrite_v4
EOF
```

## Troubleshooting

### Problem: Rewrite funktioniert nicht

**Lösung 1:** Prüfe ob Regel existiert
```bash
./manage-ip-rewrite.sh blocklist.db test-v4 178.223.16.21
```

**Lösung 2:** Prüfe dnsmasq-Logs
```bash
tail -f /var/log/dnsmasq.log | grep "IP Rewrite"
```

**Lösung 3:** DNS-Cache leeren
```bash
killall -HUP dnsmasq  # Reload
# oder
systemctl restart dnsmasq
```

### Problem: Falsche IP wird zurückgegeben

**Ursache:** Möglicherweise mehrere DNS-Server konfiguriert.

**Lösung:** Prüfe Upstream-DNS-Konfiguration
```bash
dig @127.0.0.1 example.com A +trace
```

## Siehe auch

- [README-SQLITE.md](README-SQLITE.md) - SQLite Blocker Dokumentation
- [PERFORMANCE-OPTIMIZED.md](PERFORMANCE-OPTIMIZED.md) - Performance-Guide
- [dnsmasq.conf.example](../dnsmasq.conf.example) - Vollständige Konfiguration

---

**Schema Version:** 4.1
**Feature:** IP-Rewriting (IP-zu-IP)
**Applied:** AFTER DNS resolution, before returning answer to client
