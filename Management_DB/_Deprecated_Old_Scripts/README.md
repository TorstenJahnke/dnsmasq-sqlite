# Deprecated Scripts

Diese Scripts sind veraltet und wurden durch die neuen **Management_DB/** Scripts ersetzt.

## ⚠️ Nicht mehr verwenden!

Die alten Scripts in diesem Ordner sind **nicht kompatibel** mit Schema v4.0!

## Migration:

| Alt (Deprecated) | Neu (Management_DB/) |
|------------------|----------------------|
| `add-dns-allow.sh` | `Management_DB/Import/import-fqdn-dns-allow.sh` |
| `add-dns-block.sh` | `Management_DB/Import/import-fqdn-dns-block.sh` |
| `add-regex.sh` | `Management_DB/Import/import-block-regex.sh` |
| `add-regex-patterns.sh` | `Management_DB/Import/import-block-regex.sh` |
| `import-regex.sh` | `Management_DB/Import/import-block-regex.sh` |
| `add-hosts.sh` | `Management_DB/Import/import-block-exact.sh` |
| `convert-hosts-to-sqlite.sh` | `Management_DB/Import/import-block-exact.sh` |

## Verwende stattdessen:

```bash
cd ../Management_DB/
```

Siehe: **Management_DB/README.md** für vollständige Dokumentation!
