#!/bin/sh
# Automatic build script for FreeBSD with SQLite + PCRE2 support
# Usage: ./build-freebsd.sh [clean]
# Tested on: FreeBSD 14.3

set -e

echo "========================================="
echo "dnsmasq SQLite + PCRE2 Build (FreeBSD)"
echo "========================================="
echo ""

# Detect FreeBSD version
if [ "$(uname -s)" != "FreeBSD" ]; then
    echo "⚠️  Warning: This script is for FreeBSD, but you're running $(uname -s)"
    echo "Continuing anyway..."
    echo ""
fi

freebsd_version=$(uname -r | cut -d'-' -f1)
echo "FreeBSD Version: $freebsd_version"
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Error: This script must be run as root (for pkg install)"
    echo "Run: sudo $0"
    exit 1
fi

echo "Installing dependencies..."
echo ""

# Check and install dependencies
PACKAGES=""

# Check sqlite3
if ! pkg info -e sqlite3; then
    echo "  → sqlite3 not found, will install"
    PACKAGES="$PACKAGES sqlite3"
else
    echo "  ✅ sqlite3 already installed"
fi

# Check pcre2
if ! pkg info -e pcre2; then
    echo "  → pcre2 not found, will install"
    PACKAGES="$PACKAGES pcre2"
else
    echo "  ✅ pcre2 already installed"
fi

# Check gmake
if ! pkg info -e gmake; then
    echo "  → gmake not found, will install"
    PACKAGES="$PACKAGES gmake"
else
    echo "  ✅ gmake already installed"
fi

# Install missing packages
if [ -n "$PACKAGES" ]; then
    echo ""
    echo "Installing missing packages:$PACKAGES"
    pkg install -y $PACKAGES
    echo ""
else
    echo ""
    echo "All dependencies already installed!"
    echo ""
fi

# Set build environment
echo "Setting up build environment..."
export LDFLAGS="-L/usr/local/lib"
export CFLAGS="-I/usr/local/include"
export PKG_CONFIG_PATH="/usr/local/libdata/pkgconfig"

echo "  LDFLAGS=$LDFLAGS"
echo "  CFLAGS=$CFLAGS"
echo "  PKG_CONFIG_PATH=$PKG_CONFIG_PATH"
echo ""

# Clean if requested
if [ "$1" = "clean" ]; then
    echo "Cleaning previous build..."
    gmake clean 2>/dev/null || true
    echo ""
fi

# Build
echo "Building dnsmasq..."
echo ""
gmake

echo ""
echo "========================================="
echo "✅ Build completed successfully!"
echo "========================================="
echo ""

# Verify binary
if [ -f "src/dnsmasq" ]; then
    echo "Binary: src/dnsmasq"
    ls -lh src/dnsmasq
    echo ""

    # Check linked libraries
    echo "Linked libraries:"
    ldd src/dnsmasq | grep -E "sqlite|pcre" || echo "  (no SQLite/PCRE2 libraries shown - might be statically linked)"
    echo ""
else
    echo "❌ Error: Binary not found at src/dnsmasq"
    exit 1
fi

# Create test database
echo "Creating test database..."
if [ -f "createdb-regex.sh" ]; then
    ./createdb-regex.sh test-freebsd.db > /dev/null 2>&1
    echo "  ✅ test-freebsd.db created"
else
    echo "  ⚠️  createdb-regex.sh not found, skipping test DB creation"
fi
echo ""

# Add test data
if [ -f "test-freebsd.db" ]; then
    echo "Adding test data..."

    # Add exact match
    sqlite3 test-freebsd.db "INSERT OR IGNORE INTO domain_exact (Domain, IPv4, IPv6) VALUES ('exact.test.com', '10.0.1.1', 'fd00:1::1');"

    # Add wildcard match
    sqlite3 test-freebsd.db "INSERT OR IGNORE INTO domain (Domain, IPv4, IPv6) VALUES ('wildcard.test.com', '10.0.2.1', 'fd00:2::1');"

    # Add regex pattern
    sqlite3 test-freebsd.db "INSERT OR IGNORE INTO domain_regex (Pattern, IPv4, IPv6) VALUES ('^ads\\..*', '10.0.3.1', 'fd00:3::1');"

    echo "  ✅ Test data added:"
    echo "     - exact.test.com → 10.0.1.1 (exact match)"
    echo "     - wildcard.test.com → 10.0.2.1 (wildcard + subdomains)"
    echo "     - ^ads\\..* → 10.0.3.1 (regex pattern)"
    echo ""
fi

echo "========================================="
echo "Build Summary"
echo "========================================="
echo "Binary:    $(pwd)/src/dnsmasq"
echo "Test DB:   $(pwd)/test-freebsd.db"
echo ""
echo "Quick Test:"
echo "  ./src/dnsmasq -d -p 5353 --db-file=test-freebsd.db --db-block-ipv4=0.0.0.0 --db-block-ipv6=:: --log-queries"
echo ""
echo "Then in another terminal:"
echo "  dig @127.0.0.1 -p 5353 exact.test.com       # Should return 10.0.1.1"
echo "  dig @127.0.0.1 -p 5353 sub.wildcard.test.com # Should return 10.0.2.1"
echo "  dig @127.0.0.1 -p 5353 ads.example.com      # Should return 10.0.3.1 (regex!)"
echo ""
echo "Install (optional):"
echo "  gmake install"
echo ""
