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

## Inkrementelle Import/Delete Skripte

| Typ | Import | Delete |
|-----|--------|--------|
| Domains (wildcard) | `/op/databaseAVX/domains/import` | `/op/databaseAVX/domains/delete` |
| Hosts (exact) | `/op/databaseAVX/hosts/import` | `/op/databaseAVX/hosts/delete` |
| IPs | `/op/databaseAVX/ip/import` | `/op/databaseAVX/ip/delete` |

Datenbank: `/usr/local/etc/dnsmasq/aviontex.db`
