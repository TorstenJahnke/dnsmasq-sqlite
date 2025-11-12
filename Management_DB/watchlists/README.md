# Watchlist System (Template-based, Parallel Import)

## Overview

This system allows managing **400+ company watchlists** with:
- ✅ **Parallel import** (all 400 companies at once!)
- ✅ **Per-company IP-sets** (10-450 different IPs)
- ✅ **Wildcard + Exact matching**
- ✅ **Whitelist support**
- ✅ **Template-based** (copy & paste to create new companies)

## Quick Start

### 1. Create a new company

```bash
./add-company.sh sophos 10.0.2.1 fd00:2::1
```

This creates:
```
sophos/
├── sophos.txt          # Wildcard blocklist
├── sophos.exact.txt    # Exact-only blocklist
├── sophos.wl           # Wildcard whitelist
├── sophos.exact.wl     # Exact whitelist
└── import-sophos.sh    # Import script with IP-set
```

### 2. Add domains

```bash
cd sophos
echo "ads.sophos.com" >> sophos.txt
echo "tracker.sophos.net" >> sophos.txt
echo "login.sophos.com" >> sophos.wl  # Whitelist (don't block)
```

### 3. Import

**Single company:**
```bash
cd sophos
./import-sophos.sh
```

**All companies in parallel:**
```bash
./import-all-parallel.sh
```

## File Types

### Blocklists

**`<company>.txt`** - Wildcard blocklist
- Blocks domain **+ all subdomains**
- Example: `ads.com` blocks `ads.com`, `www.ads.com`, `*.*.ads.com`

**`<company>.exact.txt`** - Exact-only blocklist (hosts-style)
- Blocks **ONLY** the exact domain, NOT subdomains
- Example: `paypal-evil.de` blocks ONLY `paypal-evil.de`, NOT `www.paypal-evil.de`

### Whitelists

**`<company>.wl`** - Wildcard whitelist
- **Removes** domains from wildcard blocklist
- Use to unblock specific domains

**`<company>.exact.wl`** - Exact whitelist
- **Removes** domains from exact blocklist

## Examples

### Example 1: watchlist-internet.at

```bash
./add-company.sh watchlist-internet.at 10.0.1.1 fd00:1::1
cd watchlist-internet.at

# Add blocked domains
cat > watchlist-internet.at.txt <<EOF
scam-site.com
phishing.net
malware.org
EOF

# Whitelist false positives
cat > watchlist-internet.at.wl <<EOF
google.com
youtube.com
EOF

# Import
./import-watchlist-internet.at.sh
```

### Example 2: Multiple companies

```bash
# Create multiple companies
./add-company.sh sophos 10.0.2.1 fd00:2::1
./add-company.sh microsoft 10.0.3.1 fd00:3::1
./add-company.sh oracle 10.0.4.1 fd00:4::1

# Edit their lists
nano sophos/sophos.txt
nano microsoft/microsoft.txt
nano oracle/oracle.txt

# Import ALL in parallel (30-60 seconds for 400 companies!)
./import-all-parallel.sh
```

## Parallel Import

**How it works:**
- Each company runs in a separate background process
- SQLite handles concurrency automatically
- Scales to **100+ parallel writers**

**Performance:**
- **Sequential**: 400 × 3 sec = 20 minutes
- **Parallel**: ~30-60 seconds on 16-core system!

**Monitoring:**
```bash
# Watch progress in real-time
./import-all-parallel.sh

# Check logs if something fails
cat /tmp/import-sophos.log
```

## Manual Creation (without add-company.sh)

```bash
# Copy template
cp -r TEMPLATE sophos

# Rename files
cd sophos
for f in TEMPLATE*; do mv "$f" "${f/TEMPLATE/sophos}"; done

# Update script
sed -i 's/TEMPLATE/sophos/g' *
nano import-sophos.sh  # Change IPV4/IPV6

# Make executable
chmod +x import-sophos.sh
```

## IP-Sets

Each company gets its own IPv4 + IPv6 pair:

```bash
# Company 1
./add-company.sh watchlist-internet.at 10.0.1.1 fd00:1::1

# Company 2
./add-company.sh sophos 10.0.2.1 fd00:2::1

# Company 3
./add-company.sh microsoft 10.0.3.1 fd00:3::1

# ... up to 400-450 different IP-sets
```

When a domain is blocked, it returns the company's specific IP!

## Database Structure

```sql
-- Wildcard matching (blocks domain + subdomains)
CREATE TABLE domain (
    Domain TEXT PRIMARY KEY,
    IPv4 TEXT,
    IPv6 TEXT
) WITHOUT ROWID;

-- Exact matching (blocks ONLY exact domain)
CREATE TABLE domain_exact (
    Domain TEXT PRIMARY KEY,
    IPv4 TEXT,
    IPv6 TEXT
) WITHOUT ROWID;
```

## Troubleshooting

### Import fails

Check log:
```bash
cat /tmp/import-<company>.log
```

### Database locked

SQLite is handling concurrency. It will retry automatically.

### Missing executable permissions

```bash
chmod +x import-*.sh
chmod +x add-company.sh
chmod +x import-all-parallel.sh
```

## Integration with Cron

```bash
# Daily sync
0 2 * * * cd /path/to/watchlists && ./import-all-parallel.sh > /tmp/watchlist-sync.log 2>&1
```

## Advanced

### Custom batch size

```bash
export BATCH_SIZE=50000
./import-all-parallel.sh
```

### Custom database location

```bash
export DB_FILE=/custom/path/blocklist.db
./import-all-parallel.sh
```

### Limit concurrent jobs

Edit `import-all-parallel.sh` and uncomment:
```bash
if [ ${#pids[@]} -ge 16 ]; then
    wait -n
fi
```

## See Also

- `../README-SQLITE.md` - Main dnsmasq-sqlite documentation
- `../MULTI-IP-SETS.md` - Per-domain IP documentation
- `../createdb-dual.sh` - Alternative import script for large lists
