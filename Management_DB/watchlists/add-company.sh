#!/bin/bash
# Helper script to create a new company watchlist from TEMPLATE

set -e

if [ $# -lt 3 ]; then
    echo "Usage: $0 <company-name> <ipv4> <ipv6>"
    echo ""
    echo "Examples:"
    echo "  $0 sophos 10.0.2.1 fd00:2::1"
    echo "  $0 watchlist-internet.at 10.0.1.1 fd00:1::1"
    echo "  $0 microsoft 10.0.3.1 fd00:3::1"
    exit 1
fi

COMPANY="$1"
IPV4="$2"
IPV6="$3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$SCRIPT_DIR/$COMPANY"

if [ -d "$TARGET_DIR" ]; then
    echo "❌ Error: Directory '$COMPANY' already exists!"
    exit 1
fi

echo "Creating watchlist for: $COMPANY"
echo "IP-Set: $IPV4 / $IPV6"
echo ""

# Copy TEMPLATE
echo "Copying TEMPLATE..."
cp -r "$SCRIPT_DIR/TEMPLATE" "$TARGET_DIR"

# Rename all files
echo "Renaming files..."
cd "$TARGET_DIR"
for f in TEMPLATE*; do
    if [ -f "$f" ]; then
        mv "$f" "${f/TEMPLATE/$COMPANY}"
    fi
done

# Replace TEMPLATE in file contents
echo "Updating file contents..."
sed -i "s/TEMPLATE/$COMPANY/g" *
sed -i "s/IPV4=\"10.0.0.1\"/IPV4=\"$IPV4\"/g" "import-$COMPANY.sh"
sed -i "s/IPV6=\"fd00::1\"/IPV6=\"$IPV6\"/g" "import-$COMPANY.sh"

# Make script executable
chmod +x "import-$COMPANY.sh"

echo ""
echo "✅ Created: $TARGET_DIR/"
echo ""
echo "Files created:"
ls -1 "$TARGET_DIR/"
echo ""
echo "Next steps:"
echo "1. Edit $COMPANY.txt and $COMPANY.exact.txt with your domains"
echo "2. Optionally edit $COMPANY.wl and $COMPANY.exact.wl for whitelists"
echo "3. Run: cd $COMPANY && ./import-$COMPANY.sh"
echo ""
echo "Or import all companies in parallel:"
echo "  cd $SCRIPT_DIR && ./import-all-parallel.sh"
