#!/bin/bash
#
# IP Rewrite Management Script
# Manages IP-to-IP rewriting rules in dnsmasq-sqlite database
#
# Usage:
#   ./manage-ip-rewrite.sh <database> <action> [args...]
#

DB_FILE="${1}"
ACTION="${2}"

if [ -z "$DB_FILE" ] || [ -z "$ACTION" ]; then
    echo "Usage: $0 <database> <action> [args...]"
    echo ""
    echo "Actions:"
    echo "  add-v4 <source_ip> <target_ip>     - Add IPv4 rewrite rule"
    echo "  add-v6 <source_ip> <target_ip>     - Add IPv6 rewrite rule"
    echo "  remove-v4 <source_ip>              - Remove IPv4 rewrite rule"
    echo "  remove-v6 <source_ip>              - Remove IPv6 rewrite rule"
    echo "  list-v4                            - List all IPv4 rewrites"
    echo "  list-v6                            - List all IPv6 rewrites"
    echo "  list-all                           - List all rewrites"
    echo "  test-v4 <source_ip>                - Test IPv4 rewrite lookup"
    echo "  test-v6 <source_ip>                - Test IPv6 rewrite lookup"
    echo ""
    echo "Examples:"
    echo "  $0 blocklist.db add-v4 178.223.16.21 10.20.0.10"
    echo "  $0 blocklist.db add-v6 2001:db8::1 fd00::10"
    echo "  $0 blocklist.db list-all"
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "Error: Database file not found: $DB_FILE"
    exit 1
fi

case "$ACTION" in
    add-v4)
        SOURCE_IP="${3}"
        TARGET_IP="${4}"
        if [ -z "$SOURCE_IP" ] || [ -z "$TARGET_IP" ]; then
            echo "Error: Missing arguments"
            echo "Usage: $0 $DB_FILE add-v4 <source_ip> <target_ip>"
            exit 1
        fi

        echo "Adding IPv4 rewrite: $SOURCE_IP → $TARGET_IP"
        sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO ip_rewrite_v4 (Source_IPv4, Target_IPv4) VALUES ('$SOURCE_IP', '$TARGET_IP');"

        if [ $? -eq 0 ]; then
            echo "✓ IPv4 rewrite rule added successfully"
        else
            echo "✗ Failed to add IPv4 rewrite rule"
            exit 1
        fi
        ;;

    add-v6)
        SOURCE_IP="${3}"
        TARGET_IP="${4}"
        if [ -z "$SOURCE_IP" ] || [ -z "$TARGET_IP" ]; then
            echo "Error: Missing arguments"
            echo "Usage: $0 $DB_FILE add-v6 <source_ip> <target_ip>"
            exit 1
        fi

        echo "Adding IPv6 rewrite: $SOURCE_IP → $TARGET_IP"
        sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO ip_rewrite_v6 (Source_IPv6, Target_IPv6) VALUES ('$SOURCE_IP', '$TARGET_IP');"

        if [ $? -eq 0 ]; then
            echo "✓ IPv6 rewrite rule added successfully"
        else
            echo "✗ Failed to add IPv6 rewrite rule"
            exit 1
        fi
        ;;

    remove-v4)
        SOURCE_IP="${3}"
        if [ -z "$SOURCE_IP" ]; then
            echo "Error: Missing source IP"
            echo "Usage: $0 $DB_FILE remove-v4 <source_ip>"
            exit 1
        fi

        echo "Removing IPv4 rewrite for: $SOURCE_IP"
        sqlite3 "$DB_FILE" "DELETE FROM ip_rewrite_v4 WHERE Source_IPv4 = '$SOURCE_IP';"

        if [ $? -eq 0 ]; then
            echo "✓ IPv4 rewrite rule removed successfully"
        else
            echo "✗ Failed to remove IPv4 rewrite rule"
            exit 1
        fi
        ;;

    remove-v6)
        SOURCE_IP="${3}"
        if [ -z "$SOURCE_IP" ]; then
            echo "Error: Missing source IP"
            echo "Usage: $0 $DB_FILE remove-v6 <source_ip>"
            exit 1
        fi

        echo "Removing IPv6 rewrite for: $SOURCE_IP"
        sqlite3 "$DB_FILE" "DELETE FROM ip_rewrite_v6 WHERE Source_IPv6 = '$SOURCE_IP';"

        if [ $? -eq 0 ]; then
            echo "✓ IPv6 rewrite rule removed successfully"
        else
            echo "✗ Failed to remove IPv6 rewrite rule"
            exit 1
        fi
        ;;

    list-v4)
        echo "IPv4 Rewrite Rules:"
        echo "===================="
        sqlite3 "$DB_FILE" <<EOF
.mode column
.headers on
SELECT Source_IPv4 AS 'Source IP', Target_IPv4 AS 'Target IP' FROM ip_rewrite_v4 ORDER BY Source_IPv4;
EOF
        ;;

    list-v6)
        echo "IPv6 Rewrite Rules:"
        echo "===================="
        sqlite3 "$DB_FILE" <<EOF
.mode column
.headers on
SELECT Source_IPv6 AS 'Source IP', Target_IPv6 AS 'Target IP' FROM ip_rewrite_v6 ORDER BY Source_IPv6;
EOF
        ;;

    list-all)
        echo "IPv4 Rewrite Rules:"
        echo "===================="
        sqlite3 "$DB_FILE" <<EOF
.mode column
.headers on
SELECT Source_IPv4 AS 'Source IP', Target_IPv4 AS 'Target IP' FROM ip_rewrite_v4 ORDER BY Source_IPv4;
EOF
        echo ""
        echo "IPv6 Rewrite Rules:"
        echo "===================="
        sqlite3 "$DB_FILE" <<EOF
.mode column
.headers on
SELECT Source_IPv6 AS 'Source IP', Target_IPv6 AS 'Target IP' FROM ip_rewrite_v6 ORDER BY Source_IPv6;
EOF
        ;;

    test-v4)
        SOURCE_IP="${3}"
        if [ -z "$SOURCE_IP" ]; then
            echo "Error: Missing source IP"
            echo "Usage: $0 $DB_FILE test-v4 <source_ip>"
            exit 1
        fi

        echo "Testing IPv4 rewrite for: $SOURCE_IP"
        RESULT=$(sqlite3 "$DB_FILE" "SELECT Target_IPv4 FROM ip_rewrite_v4 WHERE Source_IPv4 = '$SOURCE_IP';")

        if [ -n "$RESULT" ]; then
            echo "✓ Rewrite found: $SOURCE_IP → $RESULT"
        else
            echo "✗ No rewrite rule found for $SOURCE_IP"
        fi
        ;;

    test-v6)
        SOURCE_IP="${3}"
        if [ -z "$SOURCE_IP" ]; then
            echo "Error: Missing source IP"
            echo "Usage: $0 $DB_FILE test-v6 <source_ip>"
            exit 1
        fi

        echo "Testing IPv6 rewrite for: $SOURCE_IP"
        RESULT=$(sqlite3 "$DB_FILE" "SELECT Target_IPv6 FROM ip_rewrite_v6 WHERE Source_IPv6 = '$SOURCE_IP';")

        if [ -n "$RESULT" ]; then
            echo "✓ Rewrite found: $SOURCE_IP → $RESULT"
        else
            echo "✗ No rewrite rule found for $SOURCE_IP"
        fi
        ;;

    *)
        echo "Error: Unknown action: $ACTION"
        echo "Run '$0' without arguments for usage information"
        exit 1
        ;;
esac
