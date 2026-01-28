# dnsmasq 2.92 (Final) - SQLite Integration Patch

**Version:** 2.92 (Final Release) with SQLite Integration v5.0
**Date:** 2026-01-28
**Status:** PRODUCTION-READY

---

## INHALT

Dieser Ordner enthält die **gepatchten Quelldateien** von dnsmasq 2.92 (Final Release) mit SQLite-Integration.

### **Gepatchte Dateien:**

**Source Code:**
- `src/db.c` - SQLite-Integration (Domain-Blocking, IP-Rewriting)
- `src/dnsmasq.h` - Header mit SQLite-Funktionsprototypen
- `src/config.h` - Build-Konfiguration (HAVE_SQLITE)
- `src/forward.c` - DNS-Forwarding mit IP-Rewriting
- `src/option.c` - Config-Optionen (sqlite-database, sqlite-block-ipv4/ipv6)
- `src/rfc1035.c` - DNS-Antwort-Generierung mit Domain-Blocking

**Build:**
- `Makefile` - SQLite-Build-Unterstützung

---

## KONFIGURATIONSOPTIONEN

```conf
# SQLite Datenbank-Pfad (erforderlich)
sqlite-database=/var/lib/dnsmasq/dns.db

# Block-IP für A-Records (IPv4)
sqlite-block-ipv4=0.0.0.0

# Block-IP für AAAA-Records (IPv6)
sqlite-block-ipv6=::

# TLD2-Liste für korrektes Wildcard-Matching
sqlite-tld2-list=/etc/dnsmasq.d/2ndlevel.txt
```

---

## DATENBANK-SCHEMA

```sql
-- Domain-Blocking (exakt)
CREATE TABLE IF NOT EXISTS block_hosts (
    domain TEXT PRIMARY KEY COLLATE NOCASE
);

-- Wildcard-Blocking
CREATE TABLE IF NOT EXISTS block_wildcard (
    domain TEXT PRIMARY KEY COLLATE NOCASE
);

-- IP-Rewriting
CREATE TABLE IF NOT EXISTS block_ips (
    ip TEXT PRIMARY KEY
);

-- Indices für Performance
CREATE INDEX IF NOT EXISTS idx_block_hosts ON block_hosts(domain);
CREATE INDEX IF NOT EXISTS idx_block_wildcard ON block_wildcard(domain);
CREATE INDEX IF NOT EXISTS idx_block_ips ON block_ips(ip);
```

---

## INSTALLATION

```bash
# 1. Download dnsmasq 2.92 final
wget https://thekelleys.org.uk/dnsmasq/dnsmasq-2.92.tar.gz
tar xzf dnsmasq-2.92.tar.gz
cd dnsmasq-2.92

# 2. Kopiere Patch-Dateien
cp /path/to/dnsmasq2.92-PATCH/src/* src/
cp /path/to/dnsmasq2.92-PATCH/Makefile .

# 3. Kompilieren
make clean
make

# 4. Installieren
sudo make install
```

---

## FEATURES

- **Domain-Blocking:** Blockiert Domains via `block_hosts` und `block_wildcard` Tabellen
- **IP-Rewriting:** Ersetzt IPs via `block_ips` Tabelle
- **2nd-Level TLD Support:** Korrekte Behandlung von .co.uk, .com.au, etc.
- **Case-Insensitive Matching:** Domain-Vergleiche unabhängig von Groß-/Kleinschreibung
- **Thread-Safe:** SQLite-Verbindungspooling für Multi-Thread-Betrieb

---

## UNTERSCHIEDE ZU RC3

Diese Version basiert auf der **finalen 2.92 Release**, nicht RC3. Änderungen:
- Aktualisierte Copyright-Header (2000-2025)
- Potenzielle Bugfixes zwischen RC3 und Final
- Konsistente Integration mit finalem Code

---

## LIZENZ

dnsmasq is Copyright (c) 2000-2025 Simon Kelley
SQLite Integration by dnsmasq-sqlite project

GNU General Public License v2/v3
