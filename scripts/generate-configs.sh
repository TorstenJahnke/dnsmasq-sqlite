#!/bin/sh
#
# Generiert 8 dnsmasq Konfigurationen
#
# Usage: ./generate-configs.sh
#
# Anpassen:
#   INSTANCES     - Anzahl Instanzen (4, 6, 8)
#   LISTEN_ADDR   - IPv6 Adresse
#   BASE_PORT     - Startport (5353, 5354, ...)
#   CONFDIR       - Zielverzeichnis

INSTANCES=8
LISTEN_ADDR="2a00:c98:4002:1:a::320"
BASE_PORT=5353
CONFDIR="/usr/local/etc/dnsmasq"

# Upstream DNS
UPSTREAM1="2a00:c98:4002:1:a::34"
UPSTREAM2="2a00:c98:4002:1:a::350"
UPSTREAM3="fd2f:50a9:8371:eca5:b5d:1:1:350"
UPSTREAM4="fd2f:50a9:8371:eca5:b5d:1:1:34"

# SQLite
DATABASE="${CONFDIR}/01/aviontex.db"
TLD2LIST="${CONFDIR}/2ndlevel.txt"
BLOCK_IPV4="178.162.228.81"
BLOCK_IPV6="2a00:c98:4002:2:8::81"

echo ""
echo "Generiere ${INSTANCES} dnsmasq Konfigurationen..."
echo ""

for i in $(seq 1 $INSTANCES); do
    PORT=$((BASE_PORT + i - 1))
    CONF="${CONFDIR}/dnsmasq${i}.conf"
    PID="/var/run/dnsmasq${i}.pid"

    cat > "$CONF" << EOF
################################################################
# dnsmasq Instance ${i} - Port ${PORT}
################################################################

user=root
group=wheel

listen-address=${LISTEN_ADDR}
bind-interfaces
port=${PORT}
no-dhcp-interface=bge0
no-dhcp-interface=bge1
no-dhcp-interface=lo0

################################################################
server=${UPSTREAM1}
server=${UPSTREAM2}
server=${UPSTREAM3}
server=${UPSTREAM4}
################################################################

################################################################
clear-on-reload
fast-dns-retry=50
min-port=1025
query-port=$((8888 + i - 1))
################################################################

################################################################
dns-forward-max=500000
no-resolv
no-hosts
domain-needed
cache-size=2000000
min-cache-ttl=300
max-cache-ttl=7200
auth-ttl=900
local-ttl=900
neg-ttl=20
use-stale-cache=1800
edns-packet-max=4096
strip-mac
rebind-localhost-ok
no-ident
no-0x20-encode
################################################################

################################################################
sqlite-database=${DATABASE}
sqlite-tld2-list=${TLD2LIST}
sqlite-block-ipv4=${BLOCK_IPV4}
sqlite-block-ipv6=${BLOCK_IPV6}
sqlite-block-txt=Privacy Protection Active.
sqlite-block-mx=10 mx-protect.keweon.center.
################################################################
EOF

    echo "  Erstellt: ${CONF} (Port ${PORT})"
done

echo ""
echo "Fertig! Configs in ${CONFDIR}/dnsmasq[1-${INSTANCES}].conf"
echo "Ports: ${BASE_PORT} - $((BASE_PORT + INSTANCES - 1))"
echo ""
