#!/bin/sh
# Install script for dnsmasq with SQLite on FreeBSD
# Creates directory structure and config files
# Usage: ./install-freebsd.sh [database-path]

set -e

echo "========================================="
echo "dnsmasq SQLite Installation (FreeBSD)"
echo "========================================="
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Error: This script must be run as root"
    echo "Run: sudo $0"
    exit 1
fi

# Check if binary exists
if [ ! -f "src/dnsmasq" ]; then
    echo "❌ Error: dnsmasq binary not found at src/dnsmasq"
    echo "Run ./build-freebsd.sh first!"
    exit 1
fi

# Configuration
INSTALL_DIR="/usr/local/sbin"
CONFIG_DIR="/usr/local/etc/dnsmasq"
DB_DIR="/var/db/dnsmasq"
DB_FILE="${1:-$DB_DIR/blocklist.db}"

echo "Installation paths:"
echo "  Binary:  $INSTALL_DIR/dnsmasq"
echo "  Config:  $CONFIG_DIR/"
echo "  Database: $DB_FILE"
echo ""

# Create directories
echo "Creating directories..."
mkdir -p "$CONFIG_DIR"
mkdir -p "$DB_DIR"
echo "  ✅ $CONFIG_DIR"
echo "  ✅ $DB_DIR"
echo ""

# Install binary
echo "Installing binary..."
cp src/dnsmasq "$INSTALL_DIR/dnsmasq"
chmod 755 "$INSTALL_DIR/dnsmasq"
echo "  ✅ $INSTALL_DIR/dnsmasq"
echo ""

# Create database if not exists
if [ ! -f "$DB_FILE" ]; then
    echo "Creating SQLite database..."
    ./createdb-regex.sh "$DB_FILE"
    echo "  ✅ $DB_FILE"
    echo ""
else
    echo "Database already exists: $DB_FILE"
    echo ""
fi

# Create main config
echo "Creating config files..."

cat > "$CONFIG_DIR/dnsmasq.conf" <<'EOF'
# ############################################################################
# DNSMASQ Konfiguration - SQLite Edition
# FreeBSD 14.3
# ############################################################################

        #log-queries
        log-facility=/usr/local/etc/dnsmasq/status.log

# ############################################################################
# UPSTREAM & FORWARDING
# ############################################################################

        all-servers

        # TODO: Configure your upstream DNS servers here
        # Example:
        # server=2a00:c98:4002:1:a::34
        # server=fd2f:50a9:8371:eca5:b5d:1:1:34

        # Fallback (until you configure your own)
        server=1.1.1.1
        server=8.8.8.8

# ############################################################################
# Listen
# ############################################################################

        # TODO: Configure your listen addresses
        # Example:
        # listen-address=2a00:c98:4002:1:6::350
        # listen-address=fd2f:50a9:8371:eca5:a461:1:2:350

        # Default: localhost only
        listen-address=127.0.0.1
        listen-address=::1

        bind-interfaces
        port=5353

# ############################################################################
# DHCP SwitchOFF
# ############################################################################

        # TODO: Add your network interfaces
        # no-dhcp-interface=bge0
        # no-dhcp-interface=bge1
        no-dhcp-interface=lo0

# ############################################################################
# User/Group (FreeBSD)
# ############################################################################

        user=root
        group=wheel

# ############################################################################
# DNS Settings
# ############################################################################

        clear-on-reload
        fast-dns-retry=50,20
        min-port=1025
        query-port=8888

        dns-forward-max=500000

        no-resolv
        no-hosts
        domain-needed
        bogus-priv

# ----------------------------------------------------------------------------
# Cache (2 million entries for massive datasets)
# ----------------------------------------------------------------------------

        cache-size=2000000
        min-cache-ttl=300
        max-cache-ttl=7200
        auth-ttl=900
        local-ttl=900
        neg-ttl=20
        use-stale-cache=1800

# ----------------------------------------------------------------------------
# Weitere Settings
# ----------------------------------------------------------------------------

        edns-packet-max=4096
        strip-mac
        rebind-localhost-ok
        no-negcache
        no-ident
        no-0x20-encode

# ----------------------------------------------------------------------------
# SQLite Database & Additional Config
# ----------------------------------------------------------------------------

        conf-file=/usr/local/etc/dnsmasq/dnsmasq.settings.conf
EOF

echo "  ✅ $CONFIG_DIR/dnsmasq.conf"

# Create settings file with SQLite config
cat > "$CONFIG_DIR/dnsmasq.settings.conf" <<EOF
# ############################################################################
# SQLite Blocklist Configuration
# ############################################################################

# SQLite Database (replaces hosts files + regex files)
db-file=$DB_FILE

# Termination IP addresses (fallback if domain has NULL in DB)
db-block-ipv4=0.0.0.0
db-block-ipv6=::

# ############################################################################
# Additional Settings
# ############################################################################

# Add custom settings here if needed
# Example:
# address=/custom.domain/192.168.1.1

EOF

echo "  ✅ $CONFIG_DIR/dnsmasq.settings.conf"
echo ""

# Set permissions
echo "Setting permissions..."
chown -R root:wheel "$CONFIG_DIR"
chown -R root:wheel "$DB_DIR"
chmod 644 "$CONFIG_DIR"/*.conf
chmod 644 "$DB_FILE"
echo "  ✅ Permissions set (root:wheel)"
echo ""

# Create rc.d script
echo "Creating rc.d service script..."
cat > /usr/local/etc/rc.d/dnsmasq <<'EOF'
#!/bin/sh

# PROVIDE: dnsmasq
# REQUIRE: DAEMON
# KEYWORD: shutdown

. /etc/rc.subr

name="dnsmasq"
rcvar=dnsmasq_enable

load_rc_config $name

: ${dnsmasq_enable:="NO"}
: ${dnsmasq_config:="/usr/local/etc/dnsmasq/dnsmasq.conf"}

command="/usr/local/sbin/dnsmasq"
command_args="-C ${dnsmasq_config} -k"
pidfile="/var/run/${name}.pid"

run_rc_command "$1"
EOF

chmod 755 /usr/local/etc/rc.d/dnsmasq
echo "  ✅ /usr/local/etc/rc.d/dnsmasq"
echo ""

# Verify installation
echo "========================================="
echo "✅ Installation completed!"
echo "========================================="
echo ""
echo "Installed files:"
echo "  Binary:  $INSTALL_DIR/dnsmasq"
echo "  Config:  $CONFIG_DIR/dnsmasq.conf"
echo "  Settings: $CONFIG_DIR/dnsmasq.settings.conf"
echo "  Database: $DB_FILE"
echo "  Service:  /usr/local/etc/rc.d/dnsmasq"
echo ""

# Show database stats
if [ -f "$DB_FILE" ]; then
    echo "Database statistics:"
    sqlite3 "$DB_FILE" <<SQL
.mode line
SELECT 'Exact domains:  ' || COUNT(*) FROM domain_exact;
SELECT 'Wildcard domains: ' || COUNT(*) FROM domain;
SELECT 'Regex patterns: ' || COUNT(*) FROM domain_regex;
SQL
    echo ""
fi

echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "1. Edit config to match your network:"
echo "   vi $CONFIG_DIR/dnsmasq.conf"
echo "   - Set your upstream DNS servers"
echo "   - Set your listen-address(es)"
echo "   - Configure no-dhcp-interface for your NICs"
echo ""
echo "2. Import your blocklists:"
echo ""
echo "   # From HOSTS file:"
echo "   ./convert-hosts-to-sqlite.sh /path/to/hosts.txt $DB_FILE"
echo ""
echo "   # From regex-block.txt:"
echo "   ./add-regex-patterns.sh 10.0.1.1 fd00:1::1 $DB_FILE"
echo ""
echo "   # From watchlist companies:"
echo "   cd watchlists && ./import-all-parallel.sh $DB_FILE"
echo ""
echo "3. Test configuration:"
echo "   $INSTALL_DIR/dnsmasq --test -C $CONFIG_DIR/dnsmasq.conf"
echo ""
echo "4. Start in foreground (for testing):"
echo "   $INSTALL_DIR/dnsmasq -d -C $CONFIG_DIR/dnsmasq.conf --log-queries"
echo ""
echo "5. Enable service (for production):"
echo "   echo 'dnsmasq_enable=\"YES\"' >> /etc/rc.conf"
echo "   service dnsmasq start"
echo ""
echo "6. Check logs:"
echo "   tail -f $CONFIG_DIR/status.log"
echo ""
