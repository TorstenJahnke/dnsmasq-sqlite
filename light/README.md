# dnsmasq SQLite Light

Simple SQLite-based DNS blocking for dnsmasq.

## Setup

```bash
# 1. Create database
./setup-db.sh /usr/local/etc/dnsmasq/aviontex.db

# 2. Import blocklist
./import-blocklist.sh /usr/local/etc/dnsmasq/aviontex.db /tmp/blocklist.txt

# 3. Configure dnsmasq (add to /usr/local/etc/dnsmasq.conf)
sqlite-database=/usr/local/etc/dnsmasq/aviontex.db
sqlite-block-ipv4=178.162.228.81
sqlite-block-ipv6=2a00:c98:4002:2:8::81

# 4. Restart dnsmasq
service dnsmasq restart
```

## Tables

- `block_exact` - Exact domain matches only
- `block_wildcard_fast` - Matches domain and all subdomains

## Files

- `setup-db.sh` - Creates the database
- `import-blocklist.sh` - Imports domains from text file
- `dnsmasq.conf.example` - Example configuration
