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

-- Verify schema
.schema
EOF

echo ""
echo "✅ Database created: $DB_FILE"
echo ""
echo "Tables:"
echo "  - domain_exact:  Exact-only matching (no subdomains)"
echo "  - domain:        Wildcard matching (with subdomains)"
echo "  - domain_regex:  Regex pattern matching"
echo ""
echo "Usage:"
echo "  ./createdb-dual.sh           # Import exact/wildcard domains"
echo "  ./import-regex.sh            # Import regex patterns"
echo "  dnsmasq --db-file=$DB_FILE --db-block-ipv4=0.0.0.0 --db-block-ipv6=::"
