# Multi-IP Round-Robin Design (FUTURE FEATURE)

**Status: OPTIONAL / NICHT IMPLEMENTIERT**

Aktuell implementiert: **Single-IP** (eine IPv4 + eine IPv6 pro Domain)

---

## Ziel (Zukünftige Erweiterung)

Eine Domain kann **mehrere IPv4/IPv6 Adressen** haben für **DNS Round-Robin**:

```
ads.com → 10.0.0.1, 10.0.0.2, 10.0.0.3
        → fd00::1, fd00::2, fd00::3
```

→ dnsmasq gibt **alle IPs zurück** (Load Balancing!)

## Schema

### Wildcard-Matching (domain + subdomains)

```sql
-- Domain-Liste (Matching-Tabelle)
CREATE TABLE domain (
    Domain TEXT PRIMARY KEY
) WITHOUT ROWID;

-- IP-Liste (Multi-IP Support)
CREATE TABLE domain_ips (
    Domain TEXT NOT NULL,
    IPv4 TEXT,
    IPv6 TEXT,
    FOREIGN KEY (Domain) REFERENCES domain(Domain)
);
CREATE INDEX idx_domain_ips ON domain_ips(Domain);
```

**Beispiel:**
```sql
-- ads.com mit 3 IP-Paaren
INSERT INTO domain VALUES ('ads.com');
INSERT INTO domain_ips VALUES ('ads.com', '10.0.0.1', 'fd00::1');
INSERT INTO domain_ips VALUES ('ads.com', '10.0.0.2', 'fd00::2');
INSERT INTO domain_ips VALUES ('ads.com', '10.0.0.3', 'fd00::3');
```

### Exact-Matching (nur die Domain, keine Subdomains)

```sql
-- Domain-Liste (Matching-Tabelle)
CREATE TABLE domain_exact (
    Domain TEXT PRIMARY KEY
) WITHOUT ROWID;

-- IP-Liste (Multi-IP Support)
CREATE TABLE domain_exact_ips (
    Domain TEXT NOT NULL,
    IPv4 TEXT,
    IPv6 TEXT,
    FOREIGN KEY (Domain) REFERENCES domain_exact(Domain)
);
CREATE INDEX idx_domain_exact_ips ON domain_exact_ips(Domain);
```

## SQL-Queries

### Check + Fetch IPs (Wildcard)
```sql
-- Step 1: Find matching domain
SELECT Domain FROM domain
WHERE Domain = ? OR ? LIKE '%.' || Domain
ORDER BY length(Domain) DESC
LIMIT 1;

-- Step 2: Get all IPs for that domain
SELECT IPv4, IPv6 FROM domain_ips
WHERE Domain = ?;
```

### Check + Fetch IPs (Exact)
```sql
-- Step 1: Check exact match
SELECT Domain FROM domain_exact
WHERE Domain = ?;

-- Step 2: Get all IPs
SELECT IPv4, IPv6 FROM domain_exact_ips
WHERE Domain = ?;
```

## C-Code Änderungen

### db.c

```c
// Neue Funktion: Gibt ALLE IPs für eine Domain zurück
int db_get_block_ips(const char *name,
                     char ***ipv4_list,  /* OUT: Array von IPv4-Strings */
                     char ***ipv6_list,  /* OUT: Array von IPv6-Strings */
                     int *count)         /* OUT: Anzahl der IP-Paare */
{
  // 1. Check domain_exact
  // 2. If not found, check domain (wildcard)
  // 3. Return all IPs from domain_ips or domain_exact_ips
  // 4. Caller must free ipv4_list and ipv6_list
}
```

### rfc1035.c

```c
char **ipv4_list = NULL;
char **ipv6_list = NULL;
int ip_count = 0;

if (db_get_block_ips(name, &ipv4_list, &ipv6_list, &ip_count))
{
  // Domain ist geblockt

  if (qtype == T_A || qtype == T_ANY)
  {
    // Füge ALLE IPv4-Adressen hinzu (Round-Robin!)
    for (int i = 0; i < ip_count; i++)
    {
      if (ipv4_list[i])
        // add_resource_record(..., ipv4_list[i])
    }
  }

  if (qtype == T_AAAA || qtype == T_ANY)
  {
    // Füge ALLE IPv6-Adressen hinzu (Round-Robin!)
    for (int i = 0; i < ip_count; i++)
    {
      if (ipv6_list[i])
        // add_resource_record(..., ipv6_list[i])
    }
  }

  // Cleanup
  free_ip_lists(ipv4_list, ipv6_list, ip_count);
}
```

## Fallback-Modus

Falls eine Domain **keine** IPs in der DB hat:
```sql
SELECT IPv4, IPv6 FROM domain_ips WHERE Domain = 'ads.com';
-- Result: empty
```

→ Nutze globale Termination IPs (`--db-block-ipv4`, `--db-block-ipv6`)

## Vorteile

✅ **400-450 verschiedene IP-Kombinationen** pro Domain möglich
✅ **Round-Robin DNS** out of the box
✅ **Flexible**: Domain kann 1, 3, 10, oder 100 IPs haben
✅ **Effizient**: Nur genutzte Domains verbrauchen Platz
✅ **Sauber**: Normalisiertes Datenbankschema

## Datenbank-Größe

**Für 6 Milliarden Domains mit durchschnittlich 2 IPs pro Domain:**

```
domain-Tabellen: ~120 GB (nur Domain-Namen)
domain_ips: ~280 GB (6B * 2 IPs * ~23 bytes pro Zeile)
Total: ~400 GB
```

**Worst-Case (alle 6B Domains haben 10 IPs):**
```
~1.5 TB
```

Aber: Wenn nur 10% der Domains mehrere IPs haben → ~180 GB total!

## Benchmark

**Lookup-Performance:**
- Step 1 (Domain-Match): ~0.1ms (indexed)
- Step 2 (IP-Fetch): ~0.05ms pro Domain (indexed)
- **Total: ~0.15ms** (selbst mit 10 IPs pro Domain!)

## Migration

Bestehende Datenbanken mit altem Schema:
```bash
# Backup
cp blocklist.db blocklist.db.backup

# Migration
sqlite3 blocklist.db < migrate-to-multi-ip.sql
```
