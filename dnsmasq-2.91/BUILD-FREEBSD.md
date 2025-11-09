# Building dnsmasq with SQLite + PCRE2 on FreeBSD

## Quick Start (Automated)

**Recommended for FreeBSD 14.3:**

```bash
# Run automated build script (installs dependencies automatically)
sudo ./build-freebsd.sh

# Or clean build:
sudo ./build-freebsd.sh clean
```

The script will:
- ✅ Install sqlite3, pcre2, gmake (if missing)
- ✅ Set up build environment automatically
- ✅ Compile with SQLite + PCRE2 regex support
- ✅ Create test database with examples
- ✅ Show quick test commands

**Skip to "Testing" section below after running the script.**

---

## Manual Build

### Prerequisites

```bash
# Install dependencies
pkg install sqlite3 pcre2 gmake
```

### Build

### Option 1: Using gmake (recommended)

```bash
cd dnsmasq-2.91
gmake
```

### Option 2: Using BSD make with gmake wrapper

If `gmake` is not available:
```bash
make  # Will use BSD make, may need adjustments
```

## Common Issues

### Issue 1: SQLite not found

**Error:**
```
sqlite3.h: No such file or directory
```

**Fix:**
```bash
pkg install sqlite3
```

### Issue 2: Linker can't find libsqlite3

**Error:**
```
ld: library not found for -lsqlite3
```

**Fix (Option A):** Set library path
```bash
export LDFLAGS="-L/usr/local/lib"
export CFLAGS="-I/usr/local/include"
gmake
```

**Fix (Option B):** Edit Makefile
```bash
# Edit Makefile and add:
LDFLAGS += -L/usr/local/lib
CFLAGS += -I/usr/local/include
```

### Issue 3: GNU-specific features

**Error:**
```
error: unknown warning option '-Wno-format-truncation'
```

**Fix:** Edit `src/config.h` and comment out problematic GCC-specific warnings:
```c
// #pragma GCC diagnostic ignored "-Wformat-truncation"
```

## Full Build Example (FreeBSD 13+)

```bash
# Install dependencies
pkg install sqlite3 gmake

# Build
cd dnsmasq-2.91
export LDFLAGS="-L/usr/local/lib"
export CFLAGS="-I/usr/local/include"
gmake clean
gmake

# Verify
ls -lh src/dnsmasq
ldd src/dnsmasq | grep sqlite
```

Expected output:
```
libsqlite3.so.0 => /usr/local/lib/libsqlite3.so.0
```

## Makefile Adjustments for FreeBSD

If you need to modify the Makefile for FreeBSD:

```makefile
# At the top of Makefile, add:
.if ${.MAKE.OS} == "FreeBSD"
LDFLAGS += -L/usr/local/lib
CFLAGS += -I/usr/local/include
.endif
```

Or use gmake-specific syntax:

```makefile
# Detect FreeBSD
ifeq ($(shell uname -s),FreeBSD)
    LDFLAGS += -L/usr/local/lib
    CFLAGS += -I/usr/local/include
endif
```

## Testing

### Basic SQLite Test

```bash
# Create test database (if not already created by build-freebsd.sh)
./createdb-regex.sh test.db

# Add test domains
sqlite3 test.db <<EOF
-- Exact match only
INSERT INTO domain_exact (Domain, IPv4, IPv6) VALUES ('exact.test.com', '10.0.1.1', 'fd00:1::1');

-- Wildcard (blocks domain + subdomains)
INSERT INTO domain (Domain, IPv4, IPv6) VALUES ('wildcard.test.com', '10.0.2.1', 'fd00:2::1');

-- Regex pattern
INSERT INTO domain_regex (Pattern, IPv4, IPv6) VALUES ('^ads\\..*', '10.0.3.1', 'fd00:3::1');
EOF

# Run dnsmasq
./src/dnsmasq -d -p 5353 --db-file=test.db --db-block-ipv4=0.0.0.0 --db-block-ipv6=:: --log-queries
```

### Test Queries (in another terminal)

```bash
# Test exact match
dig @127.0.0.1 -p 5353 exact.test.com
# Expected: 10.0.1.1

# Test wildcard (subdomain should match)
dig @127.0.0.1 -p 5353 sub.wildcard.test.com
# Expected: 10.0.2.1

# Test regex pattern
dig @127.0.0.1 -p 5353 ads.example.com
# Expected: 10.0.3.1 (matched by ^ads\\..* pattern)

# Test with AAAA (IPv6)
dig @127.0.0.1 -p 5353 AAAA exact.test.com
# Expected: fd00:1::1
```

### Import regex-block.txt (if you have one)

```bash
# Create your regex patterns file
cat > regex-block.txt <<EOF
^ads\\..*
.*\\.tracker\\.com$
^(www|cdn)\\.analytics\\..*
EOF

# Import with specific IP-set
./add-regex-patterns.sh 10.0.5.1 fd00:5::1 test.db

# Test
dig @127.0.0.1 -p 5353 ads.whatever.com
# Expected: 10.0.5.1
```

## Installation (Optional)

```bash
# Install system-wide
gmake install

# Or manual install
cp src/dnsmasq /usr/local/sbin/
chmod 755 /usr/local/sbin/dnsmasq
```

## rc.conf Integration

```bash
# /etc/rc.conf
dnsmasq_enable="YES"
dnsmasq_flags="-d -p 53 --db-file=/var/db/dnsmasq/blocklist.db --db-block-ipv4=0.0.0.0 --db-block-ipv6=::"
```

## Ports/Packages Notes

This is a custom build with **SQLite + PCRE2 regex** integration. The official FreeBSD dnsmasq port does NOT include these features.

Do not install the official port if you want SQLite/regex functionality:
```bash
# DON'T do this if you want SQLite + regex:
# pkg install dns/dnsmasq
```

Instead, use this custom build.

### Feature Comparison

| Feature | Official FreeBSD Port | This Build |
|---------|----------------------|------------|
| Basic DNS | ✅ | ✅ |
| SQLite exact match | ❌ | ✅ |
| SQLite wildcard | ❌ | ✅ |
| PCRE2 regex | ❌ | ✅ |
| Per-domain IPs | ❌ | ✅ |
| 400+ IP-sets | ❌ | ✅ |

## Troubleshooting

### ldd shows wrong libsqlite3

```bash
ldd src/dnsmasq
```

If it shows `/lib/libsqlite3.so` instead of `/usr/local/lib/libsqlite3.so`:

```bash
export LD_LIBRARY_PATH=/usr/local/lib
```

Or rebuild with explicit rpath:
```bash
gmake LDFLAGS="-L/usr/local/lib -Wl,-rpath,/usr/local/lib"
```

### Database permissions

```bash
# Ensure dnsmasq can read the database
chmod 644 blocklist.db
chown _dnsmasq:_dnsmasq blocklist.db  # If running as _dnsmasq user
```

## Performance Tuning (FreeBSD)

```bash
# /etc/sysctl.conf
kern.ipc.somaxconn=1024
net.inet.tcp.sendspace=65536
net.inet.tcp.recvspace=65536

# Apply
sysctl -f /etc/sysctl.conf
```

## See Also

- FreeBSD Handbook: https://docs.freebsd.org/
- SQLite on FreeBSD: `/usr/local/share/doc/sqlite3/`
- dnsmasq documentation: https://thekelleys.org.uk/dnsmasq/doc.html
