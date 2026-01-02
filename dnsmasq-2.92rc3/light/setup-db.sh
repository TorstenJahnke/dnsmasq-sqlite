#!/bin/sh
#
# SQLite Database Setup for dnsmasq
# Creates the blocking database with required tables
#

DB_PATH="${1:-/usr/local/etc/dnsmasq/aviontex.db}"
DB_DIR=$(dirname "$DB_PATH")

echo "Setting up dnsmasq SQLite database..."
echo "Database: $DB_PATH"

# Create directory if needed
if [ ! -d "$DB_DIR" ]; then
    echo "Creating directory $DB_DIR"
    mkdir -p "$DB_DIR"
fi

# Remove old database if exists
if [ -f "$DB_PATH" ]; then
    echo "Removing existing database"
    rm -f "$DB_PATH"
fi

# Create database with schema
sqlite3 "$DB_PATH" <<'SQL'
-- Exact domain blocking
-- Domains here are blocked exactly as entered
CREATE TABLE block_exact (
    Domain TEXT PRIMARY KEY
);

-- Wildcard domain blocking
-- A domain here blocks itself and all subdomains
-- e.g. "facebook.com" blocks www.facebook.com, api.facebook.com, etc.
CREATE TABLE block_wildcard_fast (
    Domain TEXT PRIMARY KEY
);

-- Indexes for fast lookups
CREATE INDEX idx_block_exact ON block_exact(Domain);
CREATE INDEX idx_block_wildcard ON block_wildcard_fast(Domain);

-- Example data (can be removed)
-- INSERT INTO block_exact (Domain) VALUES ('ads.example.com');
-- INSERT INTO block_wildcard_fast (Domain) VALUES ('doubleclick.net');
SQL

if [ $? -eq 0 ]; then
    echo "Database created successfully!"
    echo ""
    echo "Tables:"
    sqlite3 "$DB_PATH" ".tables"
    echo ""
    echo "Add to dnsmasq.conf:"
    echo "  sqlite-database=$DB_PATH"
    echo "  sqlite-block-ipv4=178.162.228.81"
    echo "  sqlite-block-ipv6=2a00:c98:4002:2:8::81"
else
    echo "ERROR: Failed to create database"
    exit 1
fi
