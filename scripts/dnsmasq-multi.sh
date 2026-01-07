#!/bin/sh
#
# Start/Stop/Status für mehrere dnsmasq Instanzen
#
# Usage: ./dnsmasq-multi.sh start|stop|restart|status
#
# Für rc.local:
#   /usr/local/scripts/dnsmasq-multi.sh start

INSTANCES=8
CONFDIR="/usr/local/etc/dnsmasq"
DNSMASQ="/usr/local/sbin/dnsmasq"

start_all() {
    echo "Starting ${INSTANCES} dnsmasq instances..."
    for i in $(seq 1 $INSTANCES); do
        CONF="${CONFDIR}/dnsmasq${i}.conf"
        PID="/var/run/dnsmasq${i}.pid"

        if [ ! -f "$CONF" ]; then
            echo "  [$i] SKIP - ${CONF} nicht gefunden"
            continue
        fi

        if [ -f "$PID" ] && kill -0 $(cat "$PID") 2>/dev/null; then
            echo "  [$i] SKIP - läuft bereits (PID $(cat $PID))"
            continue
        fi

        ${DNSMASQ} -C "$CONF" -x "$PID"

        if [ $? -eq 0 ]; then
            sleep 0.1
            if [ -f "$PID" ]; then
                echo "  [$i] OK - PID $(cat $PID)"
            else
                echo "  [$i] OK"
            fi
        else
            echo "  [$i] FEHLER"
        fi
    done
}

stop_all() {
    echo "Stopping dnsmasq instances..."
    for i in $(seq 1 $INSTANCES); do
        PID="/var/run/dnsmasq${i}.pid"

        if [ -f "$PID" ]; then
            if kill -0 $(cat "$PID") 2>/dev/null; then
                kill $(cat "$PID")
                echo "  [$i] gestoppt"
            fi
            rm -f "$PID"
        fi
    done
}

status_all() {
    echo "Status dnsmasq instances:"
    RUNNING=0
    for i in $(seq 1 $INSTANCES); do
        PID="/var/run/dnsmasq${i}.pid"
        CONF="${CONFDIR}/dnsmasq${i}.conf"

        if [ -f "$PID" ] && kill -0 $(cat "$PID") 2>/dev/null; then
            PORT=$(grep -E "^[[:space:]]*port[[:space:]]*=" "$CONF" 2>/dev/null | sed 's/.*=[ ]*//' | tr -d ' ')
            echo "  [$i] RUNNING - PID $(cat $PID) - Port ${PORT:-?}"
            RUNNING=$((RUNNING + 1))
        else
            echo "  [$i] STOPPED"
        fi
    done
    echo ""
    echo "${RUNNING}/${INSTANCES} Instanzen laufen"
}

case "$1" in
    start)
        start_all
        ;;
    stop)
        stop_all
        ;;
    restart)
        stop_all
        sleep 1
        start_all
        ;;
    status)
        status_all
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
