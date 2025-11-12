#!/bin/bash
# Create SQLite database with regex pattern support
# Usage: ./createdb-regex.sh [database.db]

set -e

DB_FILE="${1:-blocklist.db}"

echo "========================================"
echo "Creating SQLite Database with Regex Support"
echo "========================================"
echo "Database: $DB_FILE"
echo ""

# Create database with tables
sqlite3 "$DB_FILE" <<EOF
-- Enable WAL mode for concurrent writes
PRAGMA journal_mode=WAL;

-- ============================================================================
-- DNS FORWARDING TABLES (checked FIRST in lookup order)
-- ============================================================================

-- DNS Allow (Whitelist): Forward to real DNS servers
-- Example: trusted-ads.com → 8.8.8.8 (bypass blocker)
CREATE TABLE IF NOT EXISTS domain_dns_allow (
    Domain TEXT PRIMARY KEY,
    Server TEXT NOT NULL
) WITHOUT ROWID;

-- DNS Block (Blacklist): Forward to blocker DNS server
-- Example: *.xyz → 10.0.0.1 (forward to blocker DNS)
CREATE TABLE IF NOT EXISTS domain_dns_block (
    Domain TEXT PRIMARY KEY,
    Server TEXT NOT NULL
) WITHOUT ROWID;

-- ============================================================================
-- TERMINATION TABLES (return fixed IPs directly)
-- ============================================================================

-- Exact-only matching table (hosts-style)
-- Blocks ONLY the exact domain, NOT subdomains
CREATE TABLE IF NOT EXISTS domain_exact (
    Domain TEXT PRIMARY KEY,
    IPv4 TEXT,
    IPv6 TEXT
) WITHOUT ROWID;

-- Wildcard matching table
-- Blocks domain AND all subdomains
CREATE TABLE IF NOT EXISTS domain (
    Domain TEXT PRIMARY KEY,
    IPv4 TEXT,
    IPv6 TEXT
) WITHOUT ROWID;

-- Regex pattern matching table
-- Matches domains against PCRE regex patterns
CREATE TABLE IF NOT EXISTS domain_regex (
    Pattern TEXT PRIMARY KEY,
    IPv4 TEXT,
    IPv6 TEXT
) WITHOUT ROWID;

-- Indexes for performance
CREATE UNIQUE INDEX IF NOT EXISTS idx_Domain_exact ON domain_exact(Domain);
CREATE UNIQUE INDEX IF NOT EXISTS idx_Domain ON domain(Domain);
CREATE UNIQUE INDEX IF NOT EXISTS idx_Pattern ON domain_regex(Pattern);
CREATE UNIQUE INDEX IF NOT EXISTS idx_dns_allow ON domain_dns_allow(Domain);
CREATE UNIQUE INDEX IF NOT EXISTS idx_dns_block ON domain_dns_block(Domain);

-- Verify schema
.schema
EOF

echo ""
echo "✅ Database created: $DB_FILE"
echo ""
echo "Tables:"
echo "  - domain_dns_allow:  Forward to real DNS (whitelist)"
echo "  - domain_dns_block:  Forward to blocker DNS (blacklist)"
echo "  - domain_exact:      Termination IP - exact match only"
echo "  - domain:            Termination IP - wildcard match"
echo "  - domain_regex:      Termination IP - regex patterns"
echo ""
echo "Lookup order:"
echo "  1. domain_dns_allow  (forward to real DNS)"
echo "  2. domain_dns_block  (forward to blocker DNS)"
echo "  3. domain_exact      (return termination IP)"
echo "  4. domain            (return termination IP, wildcard)"
echo "  5. domain_regex      (return termination IP, regex)"
echo "  6. Normal upstream   (default DNS)"
echo ""
echo "Usage:"
echo "  dnsmasq --db-file=$DB_FILE --db-block-ipv4=0.0.0.0 --db-block-ipv6=::"
