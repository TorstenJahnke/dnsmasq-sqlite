# DNS Forwarding with SQLite - Whitelist/Blacklist

## Overview

DNS Forwarding allows you to forward specific domains to specific DNS servers using SQLite tables instead of config file entries.

### Use Cases

1. **Block entire TLDs with exceptions**
   - Block all `.xyz` domains → forward to blocker DNS (10.0.0.1)
   - Allow 1000 trusted `.xyz` domains → forward to real DNS (8.8.8.8)

2. **Split DNS for security**
   - Internal domains → internal DNS server
   - External domains → public DNS server

3. **Ad-blocking with exceptions**
   - All tracking domains → blocker DNS
   - Whitelisted analytics → real DNS

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      DNS Query Flow                          │
└─────────────────────────────────────────────────────────────┘

Query: "trusted.xyz" arrives

  1. Check domain_dns_allow (WHITELIST)
     ├─ Match: "trusted.xyz" → 8.8.8.8
     └─ ✅ Forward to 8.8.8.8 (Real DNS)

Query: "evil.xyz" arrives

  1. Check domain_dns_allow (WHITELIST)
     └─ No match

  2. Check domain_dns_block (BLACKLIST)
     ├─ Match: "*.xyz" → 10.0.0.1
     └─ ❌ Forward to 10.0.0.1 (Blocker DNS → returns 0.0.0.0)

Query: "example.com" arrives

  1. Check domain_dns_allow
     └─ No match

  2. Check domain_dns_block
     └─ No match

  3. Check domain_exact (termination)
     └─ No match

  4. Check domain (termination, wildcard)
     └─ No match

  5. Check domain_regex (termination, regex)
     └─ No match

  6. ✅ Use normal upstream servers
```

## Lookup Order

**CRITICAL:** Whitelist is checked **FIRST**, then blacklist!

1. **domain_dns_allow** (whitelist) - Forward to real DNS
2. **domain_dns_block** (blacklist) - Forward to blocker DNS
3. **domain_exact** - Return termination IP (exact match only)
4. **domain** - Return termination IP (wildcard match)
5. **domain_regex** - Return termination IP (regex patterns)
6. **Normal upstream** - Default DNS servers

## Database Schema

### domain_dns_allow (Whitelist)

Forward specific domains to real DNS servers (bypasses blocking).

```sql
CREATE TABLE domain_dns_allow (
    Domain TEXT PRIMARY KEY,
    Server TEXT NOT NULL  -- "8.8.8.8" or "1.1.1.1#5353"
) WITHOUT ROWID;
```

**Examples:**
```sql
-- Allow trusted.xyz → forward to Google DNS
INSERT INTO domain_dns_allow VALUES ('trusted.xyz', '8.8.8.8');

-- Allow mycompany.xyz → forward to Cloudflare DNS with custom port
INSERT INTO domain_dns_allow VALUES ('mycompany.xyz', '1.1.1.1#5353');
```

### domain_dns_block (Blacklist)

Forward domains to blocker DNS server (e.g., internal DNS returning 0.0.0.0).

```sql
CREATE TABLE domain_dns_block (
    Domain TEXT PRIMARY KEY,
    Server TEXT NOT NULL  -- "10.0.0.1"
) WITHOUT ROWID;
```

**Examples:**
```sql
-- Block all .xyz TLD → forward to blocker DNS
INSERT INTO domain_dns_block VALUES ('*.xyz', '10.0.0.1');

-- Block all .tk TLD
INSERT INTO domain_dns_block VALUES ('*.tk', '10.0.0.1');

-- Block specific tracker
INSERT INTO domain_dns_block VALUES ('*.doubleclick.net', '10.0.0.1');
```

## Server String Format

Server addresses can include optional port:

- `8.8.8.8` - Default port 53
- `8.8.8.8#5353` - Custom port 5353
- `::1` - IPv6, default port 53
- `::1#5353` - IPv6 with custom port

**Important:** The DNS server **MUST** be configured in dnsmasq.conf as an upstream server!

```conf
# dnsmasq.conf

# Real DNS servers (for whitelist)
server=8.8.8.8
server=1.1.1.1

# Blocker DNS (for blacklist)
server=10.0.0.1
```

## Import Scripts

### Whitelist (domain_dns_allow)

```bash
# Import allow list
./add-dns-allow.sh 8.8.8.8 blocklist.db allow-list.txt

# Format of allow-list.txt:
trusted.xyz
mycompany.xyz
important-site.xyz
```

### Blacklist (domain_dns_block)

```bash
# Import block list
./add-dns-block.sh 10.0.0.1 blocklist.db block-list.txt

# Format of block-list.txt:
*.xyz
*.tk
*.doubleclick.net
*.googleadservices.com
```

### Example: Block .xyz TLD with exceptions

```bash
# 1. Create database
./createdb-optimized.sh blocklist.db

# 2. Block all .xyz domains
echo "*.xyz" | ./add-dns-block.sh 10.0.0.1 blocklist.db

# 3. Allow trusted exceptions
cat > /tmp/allow.txt <<EOF
trusted.xyz
mycompany.xyz
important.xyz
EOF

./add-dns-allow.sh 8.8.8.8 blocklist.db /tmp/allow.txt

# 4. Start dnsmasq
dnsmasq -d --db-file=blocklist.db --log-queries
```

## Complete Example

Run the example script:

```bash
./example-dns-forwarding.sh blocklist.db
```

This creates a complete setup with:
- Block list: `*.xyz`, `*.tk`, tracking domains → 10.0.0.1
- Allow list: `trusted.xyz`, `mycompany.xyz` → 8.8.8.8

## Testing

### Test Whitelist

```bash
# Should forward to 8.8.8.8 (allowed)
dig @127.0.0.1 trusted.xyz

# Check dnsmasq logs:
# forward (allow): trusted.xyz → 8.8.8.8
```

### Test Blacklist

```bash
# Should forward to 10.0.0.1 (blocked)
dig @127.0.0.1 evil.xyz

# Check dnsmasq logs:
# forward (block): evil.xyz → 10.0.0.1
```

### Test Normal Upstream

```bash
# Should use normal upstream (not in SQLite)
dig @127.0.0.1 example.com

# No "forward" log entry
```

## dnsmasq Configuration

### Minimal Config

```conf
# /usr/local/etc/dnsmasq/dnsmasq.conf

# Port
port=53

# Upstream DNS servers (required!)
server=8.8.8.8
server=1.1.1.1
server=10.0.0.1  # Blocker DNS

# SQLite database
conf-file=/usr/local/etc/dnsmasq/dnsmasq.settings.conf
```

```conf
# /usr/local/etc/dnsmasq/dnsmasq.settings.conf

# SQLite database for DNS forwarding + blocking
db-file=/var/db/dnsmasq/blocklist.db

# Default termination IPs (fallback)
db-block-ipv4=0.0.0.0
db-block-ipv6=::
```

### Full Config (FreeBSD Example)

```conf
# /usr/local/etc/dnsmasq/dnsmasq.conf

# Network
port=5353
user=root
group=wheel
listen-address=::
bind-interfaces

# Upstream servers
server=8.8.8.8
server=1.1.1.1
server=10.0.0.1  # Blocker DNS

# Cache
cache-size=2000000
neg-ttl=60
max-ttl=3600

# Logging
log-queries
log-facility=/usr/local/etc/dnsmasq/status.log

# SQLite
conf-file=/usr/local/etc/dnsmasq/dnsmasq.settings.conf
```

## Performance

DNS forwarding lookups are **O(log n)** using SQLite indexes:

- Covering indexes for 2x faster queries
- Wildcard matching with `LIKE '%.' || Domain`
- Ordered by longest match (most specific first)

**Benchmark (100M domains):**
- Exact match: 0.2 ms
- Wildcard match: 0.4 ms
- Regex match: 1.6 ms

## Troubleshooting

### Server not found error

```
SQLite forwarding: server 8.8.8.8 not found for trusted.xyz
```

**Fix:** Add server to dnsmasq.conf:
```conf
server=8.8.8.8
```

### Domain not forwarding

**Check logs:**
```bash
dnsmasq -d --db-file=blocklist.db --log-queries
```

Expected output:
```
forward (allow): trusted.xyz → 8.8.8.8
forward (block): evil.xyz → 10.0.0.1
```

**Verify database:**
```bash
sqlite3 blocklist.db "SELECT * FROM domain_dns_allow WHERE Domain = 'trusted.xyz';"
sqlite3 blocklist.db "SELECT * FROM domain_dns_block WHERE Domain LIKE '%.xyz';"
```

### Whitelist not taking precedence

**Verify lookup order:**
```c
// In db.c:
// Check 1: domain_dns_allow (whitelist) - checked FIRST ✅
// Check 2: domain_dns_block (blacklist) - checked SECOND
```

If `trusted.xyz` is in both tables, allow table wins.

## Migration from Config Files

### Before (server=/domain/ip syntax)

```conf
# dnsmasq.conf
server=/trusted.xyz/8.8.8.8
server=/mycompany.xyz/8.8.8.8
server=/.xyz/10.0.0.1
server=/.tk/10.0.0.1
```

### After (SQLite tables)

```bash
# Import to SQLite
echo "*.xyz" | ./add-dns-block.sh 10.0.0.1 blocklist.db
echo "*.tk" | ./add-dns-block.sh 10.0.0.1 blocklist.db
echo "trusted.xyz" | ./add-dns-allow.sh 8.8.8.8 blocklist.db
echo "mycompany.xyz" | ./add-dns-allow.sh 8.8.8.8 blocklist.db
```

**Benefits:**
- Easier to manage 1000s of exceptions
- No config file reloads
- Faster lookups (B-tree index vs linear scan)
- Can import/export with scripts

## Advanced Examples

### Multiple Blocker DNS Servers

```sql
-- Different blockers for different categories
INSERT INTO domain_dns_block VALUES ('*.ads', '10.0.1.1');
INSERT INTO domain_dns_block VALUES ('*.tracking', '10.0.2.1');
INSERT INTO domain_dns_block VALUES ('*.malware', '10.0.3.1');
```

### Geographic DNS Routing

```sql
-- Route to geographically closer DNS
INSERT INTO domain_dns_allow VALUES ('*.eu', '9.9.9.9');   -- Europe
INSERT INTO domain_dns_allow VALUES ('*.us', '8.8.8.8');   -- USA
INSERT INTO domain_dns_allow VALUES ('*.asia', '1.1.1.1'); -- Asia
```

### Corporate Split DNS

```sql
-- Internal corporate domains → internal DNS
INSERT INTO domain_dns_allow VALUES ('*.corp.internal', '192.168.1.1');
INSERT INTO domain_dns_allow VALUES ('*.vpn.internal', '192.168.1.2');

-- All external → public DNS
(use normal upstream servers)
```

## SQL Queries

### Show all forwarding rules

```sql
-- Whitelist
SELECT Domain, Server, 'ALLOW' as Type
FROM domain_dns_allow
ORDER BY length(Domain) DESC;

-- Blacklist
SELECT Domain, Server, 'BLOCK' as Type
FROM domain_dns_block
ORDER BY length(Domain) DESC;
```

### Find conflicts

```sql
-- Domains in both allow and block (allow wins!)
SELECT a.Domain, a.Server as allow_server, b.Server as block_server
FROM domain_dns_allow a
JOIN domain_dns_block b ON a.Domain = b.Domain;
```

### Statistics

```sql
SELECT
    (SELECT COUNT(*) FROM domain_dns_allow) as whitelist_entries,
    (SELECT COUNT(*) FROM domain_dns_block) as blacklist_entries,
    (SELECT COUNT(DISTINCT Server) FROM domain_dns_allow) as unique_allow_servers,
    (SELECT COUNT(DISTINCT Server) FROM domain_dns_block) as unique_block_servers;
```

## See Also

- [README-SQLITE.md](README-SQLITE.md) - SQLite blocker basics
- [PERFORMANCE-OPTIMIZED.md](PERFORMANCE-OPTIMIZED.md) - Performance tuning
- [FREEBSD-QUICKSTART.md](FREEBSD-QUICKSTART.md) - FreeBSD installation
- [BUILD-FREEBSD.md](BUILD-FREEBSD.md) - FreeBSD build guide
