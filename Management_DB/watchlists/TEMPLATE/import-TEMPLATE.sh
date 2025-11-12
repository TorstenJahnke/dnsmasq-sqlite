#!/bin/bash
set -e

# ========================================
# TEMPLATE Import Script
# ========================================
# Copy this directory and replace TEMPLATE with your company name!
#
# Example for "sophos":
#   cp -r TEMPLATE sophos
#   cd sophos
#   for f in TEMPLATE*; do mv "$f" "${f/TEMPLATE/sophos}"; done
#   sed -i 's/TEMPLATE/sophos/g' *
#   nano import-sophos.sh  # Change IP-Set below!

# ========================================
# Configuration (CHANGE THIS!)
# ========================================
NAME="TEMPLATE"
IPV4="10.0.0.1"          # ← Change to your IPv4!
IPV6="fd00::1"           # ← Change to your IPv6!

# Database location (relative to this script)
DB_FILE="${DB_FILE:-../../blocklist.db}"

# ========================================
# Import shared functions
# ========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../import-functions.sh"

echo "========================================"
echo "Importing: $NAME"
echo "IP-Set: $IPV4 / $IPV6"
echo "========================================"

# ========================================
# Import Wildcard Blocklist (domain table)
# ========================================
if [ -f "$NAME.txt" ]; then
    echo "Wildcard blocklist ($NAME.txt):"
    import_list "$NAME.txt" "domain" 1 0 "$IPV4" "$IPV6"
else
    echo "⚠️  No wildcard blocklist found ($NAME.txt)"
fi

# ========================================
# Import Exact Blocklist (domain_exact table)
# ========================================
if [ -f "$NAME.exact.txt" ]; then
    echo "Exact blocklist ($NAME.exact.txt):"
    import_list "$NAME.exact.txt" "domain_exact" 1 0 "$IPV4" "$IPV6"
else
    echo "⚠️  No exact blocklist found ($NAME.exact.txt)"
fi

# ========================================
# Process Wildcard Whitelist (remove from domain)
# ========================================
if [ -f "$NAME.wl" ]; then
    echo "Wildcard whitelist ($NAME.wl):"
    process_whitelist "$NAME.wl" "domain"
else
    echo "⚠️  No wildcard whitelist found ($NAME.wl)"
fi

# ========================================
# Process Exact Whitelist (remove from domain_exact)
# ========================================
if [ -f "$NAME.exact.wl" ]; then
    echo "Exact whitelist ($NAME.exact.wl):"
    process_whitelist "$NAME.exact.wl" "domain_exact"
else
    echo "⚠️  No exact whitelist found ($NAME.exact.wl)"
fi

echo "========================================"
echo "✅ $NAME import completed!"
echo "========================================"
