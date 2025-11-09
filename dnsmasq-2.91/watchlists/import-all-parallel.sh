#!/bin/bash
# Import all company watchlists in PARALLEL
# Supports 400+ companies running simultaneously!

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_FILE="${DB_FILE:-$SCRIPT_DIR/../blocklist.db}"

# Export for child processes
export DB_FILE

echo "========================================"
echo "Parallel Watchlist Import"
echo "========================================"
echo "Database: $DB_FILE"
echo ""

# Count companies
total=0
for dir in "$SCRIPT_DIR"/*/; do
    [[ "$(basename "$dir")" == "TEMPLATE" ]] && continue
    [[ ! -f "$dir/import-"*.sh ]] && continue
    ((total++))
done

if [ $total -eq 0 ]; then
    echo "❌ No companies found!"
    echo ""
    echo "Create a company with:"
    echo "  ./add-company.sh <name> <ipv4> <ipv6>"
    exit 1
fi

echo "Found $total companies to import"
echo "Starting parallel import..."
echo ""

# Track PIDs
pids=()
failed=()
start_time=$(date +%s)

# Start all imports in parallel
for dir in "$SCRIPT_DIR"/*/; do
    company=$(basename "$dir")

    # Skip TEMPLATE
    [[ "$company" == "TEMPLATE" ]] && continue

    # Find import script
    import_script="$dir/import-$company.sh"
    [[ ! -f "$import_script" ]] && continue

    echo "[$(date +%H:%M:%S)] Starting: $company"

    # Run in background, capture output
    (
        cd "$dir"
        if ./import-"$company".sh > "/tmp/import-$company.log" 2>&1; then
            echo "[$(date +%H:%M:%S)] ✅ Completed: $company"
        else
            echo "[$(date +%H:%M:%S)] ❌ FAILED: $company (see /tmp/import-$company.log)"
            exit 1
        fi
    ) &

    pids+=($!)

    # Optional: Limit concurrent jobs (comment out for unlimited)
    # if [ ${#pids[@]} -ge 16 ]; then
    #     wait -n  # Wait for any one job to finish
    # fi
done

echo ""
echo "Waiting for all imports to complete..."
echo ""

# Wait for all and collect failures
for pid in "${pids[@]}"; do
    if ! wait $pid; then
        failed+=($pid)
    fi
done

end_time=$(date +%s)
duration=$((end_time - start_time))

echo ""
echo "========================================"
echo "Import Summary"
echo "========================================"
echo "Total companies: $total"
echo "Failed: ${#failed[@]}"
echo "Duration: ${duration}s"
echo ""

if [ ${#failed[@]} -gt 0 ]; then
    echo "❌ Some imports failed. Check /tmp/import-*.log for details"
    exit 1
else
    echo "✅ All imports completed successfully!"
    echo ""
    echo "Database statistics:"
    sqlite3 "$DB_FILE" <<EOF
SELECT 'Wildcard domains: ' || COUNT(*) FROM domain;
SELECT 'Exact domains: ' || COUNT(*) FROM domain_exact;
EOF
fi
