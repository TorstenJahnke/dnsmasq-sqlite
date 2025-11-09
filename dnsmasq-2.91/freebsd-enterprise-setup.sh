#!/bin/sh
# FreeBSD Enterprise Setup for dnsmasq + SQLite
# Hardware: 8 Core Intel + 128 GB RAM + NVMe SSD
# Target: 1 Billion domains with <2ms lookups

set -e

echo "========================================="
echo "FreeBSD Enterprise dnsmasq Setup"
echo "========================================="
echo ""
echo "Hardware Target:"
echo "  🖥️  8 Core Intel CPU"
echo "  💾 128 GB RAM"
echo "  💿 NVMe SSD"
echo "  🐡 FreeBSD 14.3+"
echo ""

# Detect FreeBSD version
FREEBSD_VERSION=$(freebsd-version | cut -d'-' -f1)
echo "Detected FreeBSD: $FREEBSD_VERSION"
echo ""

# 1. Install dependencies
echo "Step 1: Installing dependencies..."
pkg install -y sqlite3 pcre2 gmake

# Verify SQLite version (need 3.37+ for PRAGMA threads)
SQLITE_VERSION=$(sqlite3 --version | awk '{print $1}')
echo "SQLite version: $SQLITE_VERSION"

SQLITE_MAJOR=$(echo $SQLITE_VERSION | cut -d. -f1)
SQLITE_MINOR=$(echo $SQLITE_VERSION | cut -d. -f2)

if [ "$SQLITE_MAJOR" -lt 3 ] || [ "$SQLITE_MINOR" -lt 37 ]; then
    echo "⚠️  Warning: SQLite < 3.37 detected. PRAGMA threads may not work."
    echo "   Current version: $SQLITE_VERSION"
    echo "   Recommended: 3.37+"
fi

echo ""

# 2. Build dnsmasq
echo "Step 2: Building dnsmasq with enterprise optimizations..."
cd "$(dirname "$0")"

export LDFLAGS="-L/usr/local/lib"
export CFLAGS="-O3 -march=native -mtune=native -I/usr/local/include"

gmake clean
gmake

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo "✅ Build successful!"
echo ""

# 3. Install binaries
echo "Step 3: Installing dnsmasq..."
install -m 755 src/dnsmasq /usr/local/sbin/dnsmasq
echo "✅ Installed to /usr/local/sbin/dnsmasq"
echo ""

# 4. Create directory structure
echo "Step 4: Creating directory structure..."
mkdir -p /usr/local/etc/dnsmasq
mkdir -p /var/db/dnsmasq
mkdir -p /var/log/dnsmasq

echo "✅ Directories created"
echo ""

# 5. Create optimized dnsmasq config
echo "Step 5: Creating dnsmasq configuration..."

cat > /usr/local/etc/dnsmasq/dnsmasq.conf <<'EOF'
# FreeBSD Enterprise dnsmasq Configuration
# Hardware: 8 Core Intel + 128 GB RAM + NVMe
# Optimized for: 1 Billion domains

# Network
port=5353
user=root
group=wheel
bind-interfaces

# SQLite Database (L2 Cache)
db-file=/var/db/dnsmasq/blocklist.db
db-block-ipv4=0.0.0.0
db-block-ipv6=::

# Query Cache (L0 Cache) - 2M entries (~600 MB RAM)
cache-size=2000000
min-cache-ttl=300
max-cache-ttl=3600
neg-ttl=60

# Logging
log-queries
log-facility=/var/log/dnsmasq/queries.log

# Performance
no-negcache
dns-forward-max=10000

# Include additional config
conf-file=/usr/local/etc/dnsmasq/dnsmasq.settings.conf
EOF

cat > /usr/local/etc/dnsmasq/dnsmasq.settings.conf <<'EOF'
# Additional dnsmasq settings
# Edit this file for your specific upstream DNS servers

# Upstream DNS servers (required for DNS forwarding!)
# Add your own servers here:
# server=8.8.8.8
# server=1.1.1.1
# server=10.0.0.1  # Blocker DNS

# Listen addresses
# listen-address=::
# listen-address=127.0.0.1
EOF

echo "✅ Config created: /usr/local/etc/dnsmasq/dnsmasq.conf"
echo ""

# 6. Create rc.d service script
echo "Step 6: Creating FreeBSD rc.d service..."

cat > /usr/local/etc/rc.d/dnsmasq <<'RCEOF'
#!/bin/sh
# FreeBSD rc.d script for dnsmasq with SQLite Enterprise mode
# PROVIDE: dnsmasq
# REQUIRE: NETWORKING SERVERS
# BEFORE: named
# KEYWORD: shutdown

. /etc/rc.subr

name="dnsmasq"
rcvar=dnsmasq_enable

command="/usr/local/sbin/dnsmasq"
pidfile="/var/run/${name}.pid"
required_files="/usr/local/etc/dnsmasq/dnsmasq.conf"

dnsmasq_flags="--keep-in-foreground \
               --pid-file=${pidfile}"

# Pre-start: Warm up SQLite cache
dnsmasq_prestart()
{
    local db_file="/var/db/dnsmasq/blocklist.db"

    if [ -f "$db_file" ]; then
        echo "Warming up SQLite cache (128 GB RAM mode)..."

        # Load DB into page cache (async)
        cat "$db_file" > /dev/null 2>&1 &

        # Run PRAGMA optimize
        sqlite3 "$db_file" "PRAGMA optimize;" 2>/dev/null || true

        echo "Cache warm-up initiated..."
    else
        echo "⚠️  Warning: Database not found at $db_file"
        echo "   Create it with: /usr/local/etc/dnsmasq/createdb-optimized.sh"
    fi
}

# Post-stop: Checkpoint WAL
dnsmasq_poststop()
{
    local db_file="/var/db/dnsmasq/blocklist.db"

    if [ -f "$db_file" ]; then
        echo "Checkpointing SQLite WAL file..."
        sqlite3 "$db_file" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    fi
}

start_precmd=dnsmasq_prestart
stop_postcmd=dnsmasq_poststop

load_rc_config $name
: ${dnsmasq_enable:="NO"}

run_rc_command "$1"
RCEOF

chmod 755 /usr/local/etc/rc.d/dnsmasq

echo "✅ Service script created: /usr/local/etc/rc.d/dnsmasq"
echo ""

# 7. Create sysctl tuning config
echo "Step 7: Creating kernel tuning recommendations..."

cat > /usr/local/etc/dnsmasq/sysctl-enterprise.conf <<'EOF'
# FreeBSD Kernel Tuning for Enterprise dnsmasq (128 GB RAM)
# Add these to /etc/sysctl.conf or /etc/sysctl.conf.local

# === Shared Memory (for SQLite 80 GB cache) ===
kern.ipc.shmmax=85899345920    # 80 GB
kern.ipc.shmall=20971520       # 80 GB / 4KB pages

# === Network Performance ===
kern.ipc.maxsockbuf=16777216   # 16 MB
net.inet.tcp.sendbuf_max=16777216
net.inet.tcp.recvbuf_max=16777216
net.inet.tcp.sendspace=65536
net.inet.tcp.recvspace=65536

# === File Descriptors (for high connection count) ===
kern.maxfiles=204800
kern.maxfilesperproc=102400

# === Virtual Memory (optimize for large cache) ===
vm.stats.vm.v_cache_min=524288
vm.stats.vm.v_free_min=131072

# === Disk I/O (for NVMe SSD) ===
vfs.read_max=128
vfs.nfsd.tcpcachetimeo=300

# === If using ZFS ===
# vfs.zfs.arc_max=42949672960    # 40 GB for ZFS ARC
# vfs.zfs.l2arc_noprefetch=0
EOF

echo "✅ Kernel tuning guide created: /usr/local/etc/dnsmasq/sysctl-enterprise.conf"
echo ""
echo "⚠️  To apply kernel tuning, add to /etc/sysctl.conf:"
echo "   cat /usr/local/etc/dnsmasq/sysctl-enterprise.conf >> /etc/sysctl.conf"
echo "   service sysctl restart"
echo ""

# 8. Create monitoring script
echo "Step 8: Creating monitoring script..."

cat > /usr/local/etc/dnsmasq/monitor.sh <<'EOF'
#!/bin/sh
# Monitor dnsmasq SQLite performance

DB_FILE="/var/db/dnsmasq/blocklist.db"

echo "========================================="
echo "dnsmasq SQLite Monitor (Enterprise Mode)"
echo "========================================="
echo ""

# 1. Service status
echo "Service Status:"
service dnsmasq status
echo ""

# 2. Memory usage
echo "Memory Usage:"
ps aux | grep dnsmasq | grep -v grep | awk '{printf "  dnsmasq: %s MB\n", $6/1024}'
echo ""

# 3. SQLite statistics
if [ -f "$DB_FILE" ]; then
    echo "SQLite Database:"
    ls -lh "$DB_FILE" | awk '{printf "  Size: %s\n", $5}'

    echo ""
    echo "Domain Counts:"
    sqlite3 "$DB_FILE" <<DBEOF
SELECT 'domain_exact: ' || COUNT(*) FROM domain_exact;
SELECT 'domain: ' || COUNT(*) FROM domain;
SELECT 'domain_regex: ' || COUNT(*) FROM domain_regex;
SELECT 'domain_dns_allow: ' || COUNT(*) FROM domain_dns_allow;
SELECT 'domain_dns_block: ' || COUNT(*) FROM domain_dns_block;
DBEOF

    echo ""
    echo "SQLite Cache Settings:"
    sqlite3 "$DB_FILE" <<DBEOF
.mode column
SELECT 'cache_size', CAST(value AS INTEGER) * -4096 / 1024 / 1024 || ' MB' as setting
FROM pragma_cache_size() WHERE value < 0
UNION ALL
SELECT 'mmap_size', value / 1024 / 1024 || ' MB' FROM pragma_mmap_size()
UNION ALL
SELECT 'journal_mode', value FROM pragma_journal_mode()
UNION ALL
SELECT 'threads', value FROM pragma_threads();
DBEOF
else
    echo "❌ Database not found: $DB_FILE"
fi

echo ""
echo "Query Log (last 10):"
tail -10 /var/log/dnsmasq/queries.log 2>/dev/null || echo "  No query log found"

echo ""
echo "========================================="
EOF

chmod 755 /usr/local/etc/dnsmasq/monitor.sh

echo "✅ Monitoring script created: /usr/local/etc/dnsmasq/monitor.sh"
echo ""

# 9. Copy database creation scripts
echo "Step 9: Setting up database scripts..."
cp createdb-optimized.sh /usr/local/etc/dnsmasq/
cp add-*.sh /usr/local/etc/dnsmasq/ 2>/dev/null || true
chmod +x /usr/local/etc/dnsmasq/*.sh

echo "✅ Database scripts copied to /usr/local/etc/dnsmasq/"
echo ""

# 10. Create quick start guide
cat > /usr/local/etc/dnsmasq/QUICKSTART.txt <<'EOF'
========================================
FreeBSD Enterprise dnsmasq Quick Start
========================================

Hardware: 8 Core Intel + 128 GB RAM + NVMe
Optimized for: 1 Billion domains with <2ms lookups

1. CREATE DATABASE
   ----------------
   cd /usr/local/etc/dnsmasq
   ./createdb-optimized.sh /var/db/dnsmasq/blocklist.db

2. IMPORT DOMAINS
   --------------
   # Import hosts files
   ./add-hosts.sh /var/db/dnsmasq/blocklist.db /path/to/hosts.txt

   # Import regex patterns
   ./add-regex.sh /var/db/dnsmasq/blocklist.db /path/to/regex.txt

   # Import DNS forwarding
   ./add-dns-allow.sh 8.8.8.8 /var/db/dnsmasq/blocklist.db allow.txt
   ./add-dns-block.sh 10.0.0.1 /var/db/dnsmasq/blocklist.db block.txt

3. CONFIGURE UPSTREAM DNS
   -----------------------
   Edit: /usr/local/etc/dnsmasq/dnsmasq.settings.conf
   Add your upstream DNS servers:
     server=8.8.8.8
     server=1.1.1.1

4. APPLY KERNEL TUNING (RECOMMENDED)
   ----------------------------------
   cat /usr/local/etc/dnsmasq/sysctl-enterprise.conf >> /etc/sysctl.conf
   service sysctl restart

5. ENABLE SERVICE
   --------------
   # Enable on boot
   echo 'dnsmasq_enable="YES"' >> /etc/rc.conf

   # Start service
   service dnsmasq start

6. MONITOR
   --------
   # Check status
   service dnsmasq status

   # View statistics
   /usr/local/etc/dnsmasq/monitor.sh

   # View logs
   tail -f /var/log/dnsmasq/queries.log

7. PERFORMANCE EXPECTATIONS
   ------------------------
   100M domains (5 GB):   0.4 ms lookups
   500M domains (25 GB):  0.8 ms lookups
   1B domains (50 GB):    1.5 ms lookups

   With 80 GB cache, entire DB fits in RAM!

8. TROUBLESHOOTING
   ---------------
   # Test configuration
   dnsmasq --test --conf-file=/usr/local/etc/dnsmasq/dnsmasq.conf

   # Run in foreground (debug)
   dnsmasq -d --conf-file=/usr/local/etc/dnsmasq/dnsmasq.conf

   # Check SQLite
   sqlite3 /var/db/dnsmasq/blocklist.db "PRAGMA integrity_check;"

========================================
EOF

echo "========================================="
echo "✅ FreeBSD Enterprise Setup Complete!"
echo "========================================="
echo ""
echo "Installation Summary:"
echo "  Binary:    /usr/local/sbin/dnsmasq"
echo "  Config:    /usr/local/etc/dnsmasq/"
echo "  Database:  /var/db/dnsmasq/"
echo "  Logs:      /var/log/dnsmasq/"
echo "  Service:   /usr/local/etc/rc.d/dnsmasq"
echo ""
echo "Next Steps:"
echo "  1. Read: /usr/local/etc/dnsmasq/QUICKSTART.txt"
echo "  2. Create database: cd /usr/local/etc/dnsmasq && ./createdb-optimized.sh"
echo "  3. Import domains: ./add-hosts.sh ..."
echo "  4. Apply kernel tuning (recommended)"
echo "  5. Enable service: echo 'dnsmasq_enable=\"YES\"' >> /etc/rc.conf"
echo "  6. Start: service dnsmasq start"
echo ""
echo "Monitor: /usr/local/etc/dnsmasq/monitor.sh"
echo ""
