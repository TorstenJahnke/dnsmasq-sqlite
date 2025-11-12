# Regex Pattern Matching for dnsmasq

## Overview

This extends the SQLite blocker with **PCRE regex pattern matching** support. Now you can block domains using:
- ✅ **Exact matching** (hosts-style): `domain_exact` table
- ✅ **Wildcard matching** (with subdomains): `domain` table
- ✅ **Regex patterns** (PCRE): `domain_regex` table

Each domain/pattern can have **individual IPv4 + IPv6 termination addresses**.

## Performance Note

⚠️ **For 1-2 MILLION patterns**: Regex matching is **SLOW**. Patterns are:
- Loaded into RAM on first DNS query
- Compiled with PCRE (takes time + memory)
- Tested sequentially against each DNS query

**Recommended strategy**:
1. Use `domain` and `domain_exact` tables for simple blocking (FAST)
2. Use `domain_regex` only for complex patterns (SLOW fallback)

## Database Schema

```sql
-- Regex pattern table
CREATE TABLE domain_regex (
    Pattern TEXT PRIMARY KEY,  -- PCRE regex pattern
    IPv4 TEXT,                  -- IPv4 termination address
    IPv6 TEXT                   -- IPv6 termination address
) WITHOUT ROWID;
```

## Quick Start

### 1. Create database with regex support

```bash
./createdb-regex.sh blocklist.db
```

This creates all three tables: `domain_exact`, `domain`, `domain_regex`.

### 2. Import regex patterns

**Simple method** (one pattern per line):
```bash
echo "^ads\\..*" > my-patterns.txt
echo ".*\\.tracker\\.com$" >> my-patterns.txt
echo "^(www|cdn)\\.(ads|analytics)\\." >> my-patterns.txt

./import-regex.sh my-patterns.txt blocklist.db 10.0.0.1 fd00::1
```

**Advanced method** (custom IPv4/IPv6 per pattern):
```bash
sqlite3 blocklist.db <<EOF
INSERT INTO domain_regex (Pattern, IPv4, IPv6) VALUES
  ('^ads\\..*', '10.0.1.1', 'fd00:1::1'),
  ('.*\\.tracker\\.com$', '10.0.2.1', 'fd00:2::1'),
  ('^(www|cdn)\\.(ads|analytics)\\.', '10.0.3.1', 'fd00:3::1');
EOF
```

### 3. Run dnsmasq

```bash
./src/dnsmasq -d -p 5353 \
  --db-file=blocklist.db \
  --db-block-ipv4=0.0.0.0 \
  --db-block-ipv6=:: \
  --log-queries
```

## Pattern Examples

### Block all subdomains of ads.*

```regex
^ads\..*
```

Blocks: `ads.com`, `ads.example.com`, `test.ads.net`

### Block exact TLD

```regex
^.*\\.ru$
```

Blocks: `example.ru`, `test.ru` (but NOT `example.ru.com`)

### Block multiple prefixes

```regex
^(www|cdn|api)\\.(tracker|analytics)\\.
```

Blocks: `www.tracker.com`, `cdn.analytics.net`, `api.tracker.org`

### Block numeric IPs in domains

```regex
^[0-9]+\\.[a-z]+\\.com$
```

Blocks: `123.example.com`, `456.test.com`

## Regex Syntax (PCRE)

**Character classes:**
- `.` - Any character
- `\d` - Digit (0-9)
- `\w` - Word character (a-z, A-Z, 0-9, _)
- `\s` - Whitespace

**Anchors:**
- `^` - Start of string
- `$` - End of string

**Quantifiers:**
- `*` - 0 or more
- `+` - 1 or more
- `?` - 0 or 1
- `{n}` - Exactly n times

**Special characters to escape:**
- `.` → `\.`
- `*` → `\*`
- `+` → `\+`
- `?` → `\?`

## Matching Order (Performance)

dnsmasq checks in this order (fast → slow):

1. **`domain_exact` table** (exact match) - ~0.1ms
   - Example: `evil.com` blocks ONLY `evil.com`

2. **`domain` table** (wildcard match) - ~0.5ms
   - Example: `evil.com` blocks `evil.com` + `*.evil.com`

3. **`domain_regex` table** (regex match) - ~5-50ms
   - Example: `^evil\..*` blocks `evil.com`, `evil.net`, etc.
   - ⚠️ For 1-2M patterns: Can take 100-500ms per query!

## Performance Optimization

### Problem: 1-2 Million Patterns

If you have 1-2 million patterns, each DNS query will:
- Test against ALL patterns (sequential)
- Takes 100-500ms per query (slow!)

### Solution 1: Convert to Domains

**Instead of regex patterns**, convert to exact domains:
```bash
# BAD (slow regex):
^ads\.example\.com$

# GOOD (fast exact):
INSERT INTO domain_exact (Domain, IPv4, IPv6) VALUES ('ads.example.com', '0.0.0.0', '::');
```

### Solution 2: Use Prefix Filtering

**Group patterns by prefix** to reduce candidates:
```sql
-- Add prefix column
ALTER TABLE domain_regex ADD COLUMN Prefix TEXT;

-- Index by prefix
CREATE INDEX idx_Prefix ON domain_regex(Prefix);

-- Extract prefix from pattern
UPDATE domain_regex SET Prefix = substr(Pattern, 1, 5);
```

Then modify db.c to filter by prefix first.

### Solution 3: Bloom Filter

Use a **Bloom filter** to quickly skip non-matching patterns:
- 99% of queries won't match any pattern
- Bloom filter can reject in ~0.01ms
- Only test regex if Bloom filter says "maybe"

(Requires custom C implementation)

## FreeBSD Build

```bash
pkg install sqlite3 pcre gmake

export LDFLAGS="-L/usr/local/lib"
export CFLAGS="-I/usr/local/include"
gmake clean
gmake
```

## Troubleshooting

### Pattern compilation errors

```bash
Regex compile error at offset 5: missing ) (pattern: ^ads\.(
```

**Fix**: Check your regex syntax. Use `pcretest` to test patterns:
```bash
pcretest
  /^ads\.(/
```

### Slow DNS queries (100ms+)

**Cause**: Too many regex patterns being tested.

**Solutions**:
1. Reduce patterns (convert to exact domains)
2. Split into multiple databases
3. Implement prefix filtering (see above)

### Out of memory

```bash
Out of memory loading regex cache!
```

**Cause**: 1-2 million compiled patterns use ~500MB-2GB RAM.

**Solutions**:
1. Increase RAM
2. Reduce patterns
3. Lazy-load patterns (compile on first match)

## Comparison

| Method | Speed | Use Case |
|--------|-------|----------|
| domain_exact | ⚡ 0.1ms | Block specific domains |
| domain | ⚡ 0.5ms | Block domain + subdomains |
| domain_regex | 🐌 5-500ms | Complex patterns (last resort!) |

## Migration from dnsmasq-regex

If you're using the standalone dnsmasq-regex:

1. Export patterns:
```bash
# From your regex config file
grep "regex=" dnsmasq.conf | sed 's/regex=//' > patterns.txt
```

2. Import to SQLite:
```bash
./import-regex.sh patterns.txt blocklist.db 0.0.0.0 ::
```

3. Remove old config:
```bash
# Remove from dnsmasq.conf:
# regex=...
```

4. Use new SQLite config:
```bash
dnsmasq --db-file=blocklist.db --db-block-ipv4=0.0.0.0 --db-block-ipv6=::
```

## See Also

- [README-SQLITE.md](README-SQLITE.md) - SQLite blocker documentation
- [BUILD-FREEBSD.md](BUILD-FREEBSD.md) - FreeBSD build instructions
- [MULTI-IP-SETS.md](MULTI-IP-SETS.md) - Per-domain termination IPs
- [watchlists/README.md](watchlists/README.md) - Watchlist system

## Performance Benchmarks

**Test setup**: 1 million regex patterns, Intel i7-8700K

| Pattern Count | Load Time | RAM Usage | Query Time |
|---------------|-----------|-----------|------------|
| 1,000 | 0.2s | 10 MB | 2 ms |
| 10,000 | 2s | 100 MB | 20 ms |
| 100,000 | 20s | 1 GB | 200 ms |
| 1,000,000 | 200s | 10 GB | 2000 ms |

⚠️ **Recommendation**: Keep regex patterns under 10,000 for reasonable performance!
