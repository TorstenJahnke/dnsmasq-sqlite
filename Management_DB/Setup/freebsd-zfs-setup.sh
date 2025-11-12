#!/bin/sh
# Optional: ZFS optimization for dnsmasq SQLite database
# Run AFTER freebsd-enterprise-setup.sh

set -e

echo "========================================="
echo "ZFS Optimization for dnsmasq SQLite"
echo "========================================="
echo ""

# Check if ZFS is available
if ! which zfs >/dev/null 2>&1; then
    echo "❌ ZFS not found. This script requires ZFS."
    echo "   If you're using UFS, you can skip this."
    exit 1
fi

# Detect root pool
ROOT_POOL=$(zfs list -H -o name / 2>/dev/null | head -1 | cut -d/ -f1)

if [ -z "$ROOT_POOL" ]; then
    echo "❌ Could not detect ZFS root pool"
    exit 1
fi

echo "Detected ZFS root pool: $ROOT_POOL"
echo ""

# Create ZFS dataset for dnsmasq
DATASET="${ROOT_POOL}/dnsmasq"

if zfs list "$DATASET" >/dev/null 2>&1; then
    echo "⚠️  Dataset $DATASET already exists."
    read -p "Recreate? This will DELETE existing data! (y/N): " confirm
    if [ "$confirm" != "y" ]; then
        echo "Aborted."
        exit 0
    fi
    zfs destroy -r "$DATASET"
fi

echo "Creating ZFS dataset: $DATASET"

# Create dataset with optimizations for SQLite
zfs create \
    -o mountpoint=/var/db/dnsmasq \
    -o compression=lz4 \
    -o recordsize=4K \
    -o primarycache=metadata \
    -o logbias=throughput \
    -o sync=standard \
    -o atime=off \
    "$DATASET"

echo "✅ ZFS dataset created with SQLite optimizations"
echo ""

# Show configuration
echo "ZFS Configuration:"
zfs get compression,recordsize,primarycache,logbias,sync,atime "$DATASET"
echo ""

# Create snapshots directory
zfs create "${DATASET}/snapshots" 2>/dev/null || true

echo "Optimization Details:"
echo "  compression=lz4       → 20-30% space savings"
echo "  recordsize=4K         → Matches SQLite page size"
echo "  primarycache=metadata → SQLite caches data, ZFS caches metadata"
echo "  logbias=throughput    → Optimized for large sequential writes"
echo "  sync=standard         → Safe + fast (SQLite handles sync)"
echo "  atime=off             → No access time updates (faster)"
echo ""

# Create snapshot script
cat > /usr/local/etc/dnsmasq/snapshot.sh <<'EOF'
#!/bin/sh
# Create ZFS snapshot of dnsmasq database

DATASET="$1"
SNAPSHOT_NAME="dnsmasq-$(date +%Y%m%d-%H%M%S)"

if [ -z "$DATASET" ]; then
    DATASET=$(zfs list -H -o name /var/db/dnsmasq 2>/dev/null)
fi

if [ -z "$DATASET" ]; then
    echo "Error: Could not find ZFS dataset"
    exit 1
fi

echo "Creating snapshot: ${DATASET}@${SNAPSHOT_NAME}"
zfs snapshot "${DATASET}@${SNAPSHOT_NAME}"

if [ $? -eq 0 ]; then
    echo "✅ Snapshot created successfully"
    echo ""
    echo "List all snapshots:"
    zfs list -t snapshot -o name,used,creation "$DATASET"
    echo ""
    echo "Restore snapshot:"
    echo "  zfs rollback ${DATASET}@${SNAPSHOT_NAME}"
else
    echo "❌ Snapshot failed"
    exit 1
fi
EOF

chmod 755 /usr/local/etc/dnsmasq/snapshot.sh

echo "✅ Snapshot script created: /usr/local/etc/dnsmasq/snapshot.sh"
echo ""

# Create periodic snapshot cron job suggestion
cat > /usr/local/etc/dnsmasq/crontab-suggestion.txt <<'EOF'
# Add to /etc/crontab for automatic daily snapshots

# Daily snapshot at 2 AM
0 2 * * * root /usr/local/etc/dnsmasq/snapshot.sh

# Keep only last 7 snapshots (cleanup old ones)
0 3 * * * root zfs list -H -t snapshot -o name -s creation | grep dnsmasq- | head -n -7 | xargs -n1 zfs destroy
EOF

echo "Cron job suggestion created: /usr/local/etc/dnsmasq/crontab-suggestion.txt"
echo ""

# Performance comparison
cat <<'EOF'
========================================
ZFS vs UFS Performance
========================================

Benefits of ZFS for SQLite:
  ✅ LZ4 compression: 20-30% space savings
  ✅ Instant snapshots: Zero-downtime backups
  ✅ Checksums: Data integrity verification
  ✅ Copy-on-write: Safe updates
  ✅ recordsize=4K: Perfect alignment with SQLite

Expected space savings:
  50 GB DB → ~35 GB on disk (30% compression)
  100 GB DB → ~70 GB on disk (30% compression)

Snapshot benefits:
  - Instant backup before updates
  - Instant rollback if issues
  - No downtime
  - Minimal space (only changed blocks)

Create snapshot:
  /usr/local/etc/dnsmasq/snapshot.sh

Restore snapshot:
  zfs rollback zroot/dnsmasq@snapshot-name

========================================
EOF

echo "✅ ZFS optimization complete!"
echo ""
echo "Database location: /var/db/dnsmasq/ (ZFS)"
echo "Next: Run ./createdb-optimized.sh to create database"
echo ""
