# DNSMASQ 2.91 - SQLite Integration Patches

This directory contains all modified and new files from the original dnsmasq-2.91 source code that implement SQLite database integration.

## Modified Files

### Root Level
- `Makefile` - Updated to include SQLite compilation flags and db.c

### src/ Directory
- `config.h` - Configuration for SQLite support
- `dnsmasq.h` - Header file with SQLite database declarations and structures
- `forward.c` - Modified DNS forwarding logic with database integration
- `option.c` - Added command-line options for database support
- `rfc1035.c` - DNS protocol handling with database lookups

## New Files

### src/ Directory
- `db.c` - Complete SQLite database implementation for DNS management

## Usage

To apply these patches to a clean dnsmasq-2.91 installation:
1. Copy all files from this directory to your dnsmasq-2.91 source directory
2. Ensure SQLite3 development libraries are installed
3. Build using the modified Makefile

## Dependencies

- SQLite3 (libsqlite3-dev)
- Standard dnsmasq build dependencies
