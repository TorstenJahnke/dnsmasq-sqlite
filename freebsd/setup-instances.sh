#!/bin/sh
#
# Setup 8 dnsmasq instances for FreeBSD
#
# Usage: ./setup-instances.sh
#
# Creates:
#   - 8 config files (dnsmasq1.conf - dnsmasq8.conf)
#   - Installs rc.d script
#   - Creates directories

CONFDIR="/usr/local/etc/dnsmasq"
RCDIR="/usr/local/etc/rc.d"
PIDDIR="/var/run/dnsmasq"
LOGDIR="/var/log/dnsmasq"

# SQLite Datenbank
DATABASE="/usr/local/etc/dnsmasq/aviontex.db"
TLD2LIST="/usr/local/etc/2ndlevel.txt"

# Upstream DNS
UPSTREAM1="8.8.8.8"
UPSTREAM2="8.8.4.4"

# Block-IPs
BLOCK_IPV4="0.0.0.0"
BLOCK_IPV6="::"

echo ""
echo "==========================================="
echo " dnsmasq Multi-Instance Setup"
echo "==========================================="
echo ""

# Verzeichnisse erstellen
echo "[1/4] Erstelle Verzeichnisse..."
mkdir -p "$CONFDIR"
mkdir -p "$PIDDIR"
mkdir -p "$LOGDIR"

# Config-Dateien erstellen
echo "[2/4] Erstelle 8 Konfigurationsdateien..."

for i in 1 2 3 4 5 6 7 8; do
    PORT=$((5300 + i))
    CONF="$CONFDIR/dnsmasq${i}.conf"

    cat > "$CONF" << EOF
# dnsmasq Instance $i
# Port: $PORT

listen-address=127.0.0.1
port=$PORT
pid-file=$PIDDIR/dnsmasq${i}.pid

no-hosts
no-resolv

server=$UPSTREAM1
server=$UPSTREAM2

cache-size=10000

sqlite-database=$DATABASE
sqlite-tld2-list=$TLD2LIST
sqlite-block-ipv4=$BLOCK_IPV4
sqlite-block-ipv6=$BLOCK_IPV6
sqlite-block-txt=blocked
sqlite-block-mx=blocked.local

# log-facility=$LOGDIR/dnsmasq${i}.log
EOF

    echo "  Erstellt: $CONF (Port $PORT)"
done

# rc.d Script installieren
echo "[3/4] Installiere rc.d Script..."
SCRIPT_DIR="$(dirname "$0")"
if [ -f "$SCRIPT_DIR/rc.d/dnsmasq_multi" ]; then
    cp "$SCRIPT_DIR/rc.d/dnsmasq_multi" "$RCDIR/"
    chmod 755 "$RCDIR/dnsmasq_multi"
    echo "  Installiert: $RCDIR/dnsmasq_multi"
else
    echo "  WARNUNG: rc.d/dnsmasq_multi nicht gefunden"
fi

# rc.conf Eintrag
echo "[4/4] Aktiviere in rc.conf..."
if ! grep -q "dnsmasq_multi_enable" /etc/rc.conf 2>/dev/null; then
    cat >> /etc/rc.conf << 'EOF'

# dnsmasq Multi-Instance
dnsmasq_multi_enable="YES"
dnsmasq_multi_instances="1 2 3 4 5 6 7 8"
EOF
    echo "  Hinzugefügt zu /etc/rc.conf"
else
    echo "  Bereits in /etc/rc.conf vorhanden"
fi

echo ""
echo "==========================================="
echo " Fertig!"
echo "==========================================="
echo ""
echo "Konfigurationen: $CONFDIR/dnsmasq[1-8].conf"
echo "Ports:           5301-5308"
echo ""
echo "Befehle:"
echo "  service dnsmasq_multi start    # Alle starten"
echo "  service dnsmasq_multi stop     # Alle stoppen"
echo "  service dnsmasq_multi status   # Status anzeigen"
echo "  service dnsmasq_multi restart  # Neustarten"
echo ""
echo "Test:"
echo "  dig @127.0.0.1 -p 5301 google.com"
echo ""
