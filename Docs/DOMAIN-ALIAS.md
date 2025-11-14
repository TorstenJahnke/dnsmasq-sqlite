# Domain-Aliasing - Schema v6.2.1

## Überblick

Domain-Aliasing ermöglicht die Umleitung von DNS-Queries von einer Domain zu einer anderen **BEFORE** der DNS-Auflösung. Dies funktioniert ähnlich wie CNAME-Records, aber auf DNS-Server-Ebene.

## Funktionsweise

```
1. DNS-Query: old.domain.com
2. Alias-Check in Datenbank
3. Alias gefunden: old.domain.com → new.domain.com
4. DNS-Auflösung für: new.domain.com (statt old.domain.com)
5. Ergebnis (z.B.): 203.0.113.50
6. Antwort an Client: 203.0.113.50
```

**Wichtig:** Der Client fragt nach `old.domain.com`, erhält aber die IP von `new.domain.com`!

## Datenbank-Schema

```sql
CREATE TABLE domain_alias (
    Source_Domain TEXT PRIMARY KEY,  -- Ursprüngliche Domain (angefragte Domain)
    Target_Domain TEXT NOT NULL      -- Ziel-Domain (tatsächlich aufgelöste Domain)
) WITHOUT ROWID;
```

## Verwendung

### Beispiel 1: Domain-Umleitung

```bash
# Alte Domain → Neue Domain
./manage-domain-alias.sh blocklist.db add old.example.com new.example.com

# Test
./manage-domain-alias.sh blocklist.db test old.example.com
# ✓ Alias found: old.example.com → new.example.com
```

**Ergebnis:**
- DNS-Query für `old.example.com`
- System löst `new.example.com` auf
- Client erhält IP von `new.example.com`

### Beispiel 2: Lokale Overrides

```bash
# Umleitung auf lokalen Server
./manage-domain-alias.sh blocklist.db add api.production.com api.local.dev
```

**Use Case:** Entwickler-Umgebung - Produktions-API wird auf lokale Dev-API umgeleitet.

### Beispiel 3: Mehrere Aliases

```bash
# Mehrere alte Domains auf eine neue umleiten
./manage-domain-alias.sh blocklist.db add legacy1.example.com modern.example.com
./manage-domain-alias.sh blocklist.db add legacy2.example.com modern.example.com
./manage-domain-alias.sh blocklist.db add legacy3.example.com modern.example.com

# Alle anzeigen
./manage-domain-alias.sh blocklist.db list
```

## Management-Skript

### Syntax

```bash
./manage-domain-alias.sh <database> <action> [args...]
```

### Aktionen

**Hinzufügen:**
```bash
./manage-domain-alias.sh blocklist.db add old.domain.com new.domain.com
```

**Entfernen:**
```bash
./manage-domain-alias.sh blocklist.db remove old.domain.com
```

**Testen:**
```bash
./manage-domain-alias.sh blocklist.db test old.domain.com
```

**Auflisten:**
```bash
./manage-domain-alias.sh blocklist.db list
```

## Direkte SQL-Verwaltung

### Hinzufügen

```sql
INSERT INTO domain_alias (Source_Domain, Target_Domain) VALUES
    ('old.example.com', 'new.example.com'),
    ('legacy.api.com', 'modern.api.com');
```

### Aktualisieren

```sql
UPDATE domain_alias SET Target_Domain = 'updated.domain.com'
WHERE Source_Domain = 'old.domain.com';
```

### Entfernen

```sql
DELETE FROM domain_alias WHERE Source_Domain = 'old.domain.com';
```

### Abfragen

```sql
-- Alle Aliases
SELECT * FROM domain_alias;

-- Spezifischer Alias
SELECT Target_Domain FROM domain_alias WHERE Source_Domain = 'old.domain.com';
```

## Kombination mit IP-Rewriting

Domain-Aliasing und IP-Rewriting können kombiniert werden:

```bash
# 1. Domain Alias: old.com → new.com
./manage-domain-alias.sh blocklist.db add old.example.com new.example.com

# 2. IP Rewrite: 203.0.113.50 → 10.20.0.10
./manage-ip-rewrite.sh blocklist.db add-v4 203.0.113.50 10.20.0.10
```

**Ablauf:**
```
Query: old.example.com
→ Alias: old.example.com → new.example.com
→ DNS: new.example.com → 203.0.113.50
→ IP-Rewrite: 203.0.113.50 → 10.20.0.10
→ Antwort: 10.20.0.10
```

## Use Cases

### 1. Migration von Domains

**Problem:** Alte Domain soll auf neue Domain umgeleitet werden.

**Lösung:**
```bash
./manage-domain-alias.sh blocklist.db add old-company.com new-company.com
```

**Vorteil:** Interne Clients nutzen automatisch die neue Domain.

### 2. Entwickler-Umgebungen

**Problem:** Produktions-APIs sollen auf lokale Dev-Instanzen zeigen.

**Lösung:**
```bash
./manage-domain-alias.sh blocklist.db add api.production.com api.localhost:3000
./manage-domain-alias.sh blocklist.db add db.production.com db.localhost:5432
```

### 3. A/B Testing

**Problem:** Verschiedene Versionen einer Anwendung testen.

**Lösung:**
```bash
# Team A
./manage-domain-alias.sh blocklist.db add app.example.com app-v1.example.com

# Team B
./manage-domain-alias.sh blocklist.db add app.example.com app-v2.example.com
```

### 4. Failover

**Problem:** Primärer Server ausgefallen → Backup nutzen.

**Lösung:**
```bash
./manage-domain-alias.sh blocklist.db add primary.service.com backup.service.com
```

## Lookup-Priorität

Domain-Aliasing hat hohe Priorität (Step 2a):

```
1. block_regex      → IPSET_TYPE_TERMINATE (geblockt)
2. block_exact      → IPSET_TYPE_TERMINATE (geblockt)
2a. domain_alias    → Resolve target domain (ALIAS!)
3. block_wildcard   → IPSET_TYPE_DNS_BLOCK
4. fqdn_dns_allow   → IPSET_TYPE_DNS_ALLOW
5. fqdn_dns_block   → IPSET_TYPE_DNS_BLOCK
6. Normal DNS       → (mit Alias falls vorhanden)
7. ip_rewrite_v4/v6 → IP-Rewrite nach DNS
```

**Wichtig:** Wenn eine Domain in `block_exact` oder `block_regex` ist, wird sie NICHT aliased!

## Performance

- **Lookup:** O(1) - B-Tree Index auf Source_Domain
- **Memory:** Minimal (nur Index)
- **Latency:** <0.1 ms zusätzlich pro Query
- **Throughput:** Keine signifikante Auswirkung

## Debugging

### Log-Ausgabe aktivieren

```bash
./dnsmasq -d --log-queries --db-file=blocklist.db
```

**Beispiel-Log:**
```
Domain Alias: old.example.com → new.example.com
query[A] old.example.com from 192.168.1.100
forwarded old.example.com (resolving new.example.com instead)
reply new.example.com is 203.0.113.50
```

### Manuelle Tests

```bash
# Test mit dig
dig @127.0.0.1 old.example.com A

# Expected:
# ;; QUESTION SECTION:
# ;old.example.com.  IN  A
#
# ;; ANSWER SECTION:
# old.example.com.  300  IN  A  203.0.113.50
# (IP von new.example.com!)
```

### Datenbank-Prüfung

```bash
# Alle Aliases
sqlite3 blocklist.db "SELECT * FROM domain_alias;"

# Anzahl
sqlite3 blocklist.db "SELECT COUNT(*) FROM domain_alias;"
```

## Wichtige Hinweise

### ✅ Funktioniert für

- Domain-Migration
- Lokale Overrides
- Entwickler-Umgebungen
- A/B Testing
- Failover-Szenarien

### ❌ Funktioniert NICHT für

- Geblockte Domains (haben höhere Priorität)
- Wildcard-Aliasing (nur exakte Domains)
- Reverse DNS (PTR Records)

### ⚠️ Vorsicht

**Zirkuläre Aliases:**
```bash
# FALSCH: Zirkulärer Verweis!
./manage-domain-alias.sh blocklist.db add a.com b.com
./manage-domain-alias.sh blocklist.db add b.com a.com
```

**Folge:** Endlosschleife in DNS-Auflösung!

**Empfehlung:** Prüfen Sie Aliases vor dem Hinzufügen.

## Vergleich: Aliasing vs. CNAME

| Feature | Domain Alias (dnsmasq) | CNAME Record (DNS) |
|---------|------------------------|---------------------|
| **Wo?** | dnsmasq-Server | Authoritative DNS |
| **Scope** | Nur lokale Clients | Global (Internet) |
| **Performance** | Sehr schnell (lokal) | Langsamer (DNS-Query) |
| **Flexibilität** | Dynamisch (DB-Änderung) | Statisch (DNS-Änderung) |
| **Use Case** | Lokale Overrides | Globale Aliasing |

## Bulk-Import

```bash
# CSV-Format: Source,Target
cat domain-aliases.csv
old.example.com,new.example.com
legacy.api.com,modern.api.com
test.local,localhost

# Import
sqlite3 blocklist.db <<EOF
.mode csv
.import domain-aliases.csv domain_alias
EOF
```

## Troubleshooting

### Problem: Alias funktioniert nicht

**Lösung 1:** Prüfe ob Alias existiert
```bash
./manage-domain-alias.sh blocklist.db test old.example.com
```

**Lösung 2:** Prüfe Blocking-Regeln (höhere Priorität!)
```bash
sqlite3 blocklist.db "SELECT * FROM block_exact WHERE Domain = 'old.example.com';"
```

**Lösung 3:** DNS-Cache leeren
```bash
killall -HUP dnsmasq  # Reload
# oder
systemctl restart dnsmasq
```

### Problem: Zirkuläre Referenz

**Symptom:** DNS-Queries hängen oder timeout.

**Diagnose:**
```sql
-- Prüfe auf zirkuläre Referenzen
SELECT a1.Source_Domain, a1.Target_Domain, a2.Target_Domain AS 'Circular?'
FROM domain_alias a1
LEFT JOIN domain_alias a2 ON a1.Target_Domain = a2.Source_Domain
WHERE a2.Target_Domain = a1.Source_Domain;
```

**Lösung:** Entferne einen der beiden Aliases.

## Siehe auch

- [IP-REWRITE.md](IP-REWRITE.md) - IP-Rewriting Dokumentation
- [README-SQLITE.md](README-SQLITE.md) - SQLite Blocker Dokumentation
- [PERFORMANCE-OPTIMIZED.md](PERFORMANCE-OPTIMIZED.md) - Performance-Guide

---

**Schema Version:** 6.2.1
**Feature:** Domain-Aliasing (Domain-zu-Domain)
**Applied:** BEFORE DNS resolution (resolves target instead of source)
**Priority:** Step 2a (after block_exact, before block_wildcard)
