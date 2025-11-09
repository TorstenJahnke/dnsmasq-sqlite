# SQLite Integration für DNSMASQ

Dieser Ordner enthält die SQLite-Integration die ursprünglich für dnsmasq v2.81 entwickelt wurde.

## Dateien

- **db.c** - Komplette SQLite-Logik (103 Zeilen)
- **createdb.sh** - Script zum Erstellen der Domain-Datenbank

## Änderungen an DNSMASQ Core

### 1. src/config.h
```c
// Zeile ~174
#define HAVE_SQLITE
```

### 2. src/dnsmasq.h
```c
// Am Ende der Datei
#ifdef HAVE_SQLITE
#include <sqlite3.h>

void db_set_file(char *file);
void db_init(void);
void db_cleanup(void);
int db_check_block(const char *domain);  // Umbenannt von db_check_allow
#endif
```

### 3. src/option.c

**A) LOPT Definition (~Zeile 170):**
```c
#define LOPT_DB_FILE       500
```

**B) Long Options Array (~Zeile 343):**
```c
{ "db-file", 1, 0, LOPT_DB_FILE },
```

**C) Help Text (~Zeile 523):**
```c
{ LOPT_DB_FILE, ARG_ONE, "<path>", gettext_noop("Load domains from Sqlite .db"), NULL },
```

**D) Case Handler (~Zeile 4448):**
```c
#ifdef HAVE_SQLITE
    case LOPT_DB_FILE:
    {
      db_set_file(opt_string_alloc(arg));
      break;
    }
#endif
```

### 4. src/rfc1035.c

In der `answer_request()` Funktion, am Ende der Question-Processing-Loop:

```c
// WICHTIG: Korrigierte Blacklist-Logik!
#ifdef HAVE_SQLITE
if (!ans) {
  if (db_check_block(name)) {  // Wenn Domain IN DB → blockieren
    ans = 1;
    nxdomain = 1;
    sec_data = 0;
    if (!dryrun)
      log_query(F_CONFIG | F_NEG, name, NULL, NULL);
  }
  // Wenn NICHT in DB: ans bleibt 0 → normale Forwarding-Logik
}
#endif
```

**Original-Bug (v2.81):** Hatte `if (!db_check_allow(name))` - war eine Whitelist statt Blacklist!

### 5. Makefile

**A) SQLite pkg-config Variablen (~Zeile 54-55):**
```makefile
sqlite_cflags = `echo $(COPTS) | $(top)/bld/pkg-wrapper HAVE_SQLITE $(PKG_CONFIG) --cflags sqlite3`
sqlite_libs =   `echo $(COPTS) | $(top)/bld/pkg-wrapper HAVE_SQLITE $(PKG_CONFIG) --libs sqlite3`
```

**B) db.o zu Objects hinzufügen (~Zeile 82):**
```makefile
objs = cache.o rfc1035.o util.o option.o forward.o network.o \
       dnsmasq.o dhcp.o lease.o rfc2131.o netlink.o dbus.o bpf.o \
       helper.o tftp.o log.o conntrack.o dhcp6.o rfc3315.o \
       dhcp-common.o outpacket.o radv.o slaac.o auth.o ipset.o \
       domain.o dnssec.o blockdata.o tables.o loop.o inotify.o \
       poll.o rrfilter.o edns0.o arp.o crypto.o dump.o ubus.o metrics.o db.o
```

**C) SQLite zu build flags (~Zeile 90-91):**
```makefile
build_cflags="$(version) $(dbus_cflags) $(idn2_cflags) $(idn_cflags) $(ct_cflags) $(lua_cflags) $(nettle_cflags) $(sqlite_cflags)" \
build_libs="$(dbus_libs) $(idn2_libs) $(idn_libs) $(ct_libs) $(lua_libs) $(sunos_libs) $(nettle_libs) $(gmp_libs) $(ubus_libs) $(sqlite_libs)" \
```

## Verhalten

### DNS-Blocker-Logik (korrigiert)
- Domain **in DB** → NXDOMAIN (geblockt)
- Domain **nicht in DB** → normale Weiterleitung an DNS Forwarder

### Vorteil
Datenbank kann zur Laufzeit geändert werden (Domains hinzufügen/löschen) ohne DNSMASQ-Restart!

## Datenbank-Schema

```sql
CREATE TABLE domain (Domain TEXT UNIQUE);
CREATE UNIQUE INDEX idx_Domain ON domain(Domain);
```

## Verwendung

```bash
# DNSMASQ starten
./src/dnsmasq -d -p 9999 --db-file domains.db --log-queries

# Domain blockieren (zur Laufzeit!)
sqlite3 domains.db "INSERT INTO domain VALUES ('ads.example.com');"

# Domain freigeben
sqlite3 domains.db "DELETE FROM domain WHERE Domain='ads.example.com';"
```

## Portierung auf neuere DNSMASQ Versionen

1. Kopiere `db.c` nach `src/db.c`
2. Kopiere `createdb.sh` ins Root-Verzeichnis
3. Wende die oben dokumentierten Änderungen auf die entsprechenden Dateien an
4. Kompiliere mit `make`

**Hinweis:** Zeilennummern können in neueren Versionen abweichen!
