# Building dnsmasq with SQLite on FreeBSD

## Prerequisites

```bash
# Install dependencies
pkg install sqlite3 gmake
```

## Build

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

```bash
# Create test database
cd dnsmasq-2.91/watchlists
../createdb-dual.sh test.db

# Add test domain
echo "test.com" | sqlite3 test.db "INSERT INTO domain (Domain, IPv4, IPv6) VALUES ('test.com', '10.0.0.1', 'fd00::1');"

# Run dnsmasq
./src/dnsmasq -d -p 5353 --db-file=test.db --db-block-ipv4=0.0.0.0 --db-block-ipv6=:: --log-queries
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

This is a custom build with SQLite integration. The official FreeBSD dnsmasq port does NOT include SQLite support.

Do not install the official port if you want SQLite functionality:
```bash
# DON'T do this if you want SQLite:
# pkg install dns/dnsmasq
```

Instead, use this custom build.

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
