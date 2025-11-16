#!/bin/bash
#
# Domain Alias Management Script
# Manages domain-to-domain aliasing rules in dnsmasq-sqlite database
#
# Usage:
#   ./manage-domain-alias.sh <database> <action> [args...]
#

DB_FILE="${1}"
ACTION="${2}"

if [ -z "$DB_FILE" ] || [ -z "$ACTION" ]; then
    echo "Usage: $0 <database> <action> [args...]"
    echo ""
    echo "Actions:"
    echo "  add <source_domain> <target_domain>  - Add domain alias"
    echo "  remove <source_domain>                - Remove domain alias"
    echo "  list                                  - List all aliases"
    echo "  test <source_domain>                  - Test alias lookup"
    echo ""
    echo "Examples:"
    echo "  $0 blocklist.db add old.example.com new.example.com"
    echo "  $0 blocklist.db add some.domain.com alias.other.com"
    echo "  $0 blocklist.db list"
    echo "  $0 blocklist.db test old.example.com"
    exit 1
fi

if [ ! -f "$DB_FILE" ]; then
    echo "Error: Database file not found: $DB_FILE"
    exit 1
fi

case "$ACTION" in
    add)
        SOURCE_DOMAIN="${3}"
        TARGET_DOMAIN="${4}"
        if [ -z "$SOURCE_DOMAIN" ] || [ -z "$TARGET_DOMAIN" ]; then
            echo "Error: Missing arguments"
            echo "Usage: $0 $DB_FILE add <source_domain> <target_domain>"
            exit 1
        fi

        echo "Adding domain alias: $SOURCE_DOMAIN → $TARGET_DOMAIN"
        sqlite3 "$DB_FILE" "INSERT OR REPLACE INTO domain_alias (Source_Domain, Target_Domain) VALUES ('$SOURCE_DOMAIN', '$TARGET_DOMAIN');"

        if [ $? -eq 0 ]; then
            echo "✓ Domain alias added successfully"
            echo ""
            echo "DNS queries for '$SOURCE_DOMAIN' will now resolve '$TARGET_DOMAIN' instead"
        else
            echo "✗ Failed to add domain alias"
            exit 1
        fi
        ;;

    remove)
        SOURCE_DOMAIN="${3}"
        if [ -z "$SOURCE_DOMAIN" ]; then
            echo "Error: Missing source domain"
            echo "Usage: $0 $DB_FILE remove <source_domain>"
            exit 1
        fi

        echo "Removing domain alias for: $SOURCE_DOMAIN"
        sqlite3 "$DB_FILE" "DELETE FROM domain_alias WHERE Source_Domain = '$SOURCE_DOMAIN';"

        if [ $? -eq 0 ]; then
            echo "✓ Domain alias removed successfully"
        else
            echo "✗ Failed to remove domain alias"
            exit 1
        fi
        ;;

    list)
        echo "Domain Aliases:"
        echo "============================================"
        sqlite3 "$DB_FILE" <<EOF
.mode column
.headers on
.width 30 30
SELECT Source_Domain AS 'Source Domain', Target_Domain AS 'Target Domain' FROM domain_alias ORDER BY Source_Domain;
EOF

        COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM domain_alias;")
        echo ""
        echo "Total aliases: $COUNT"
        ;;

    test)
        SOURCE_DOMAIN="${3}"
        if [ -z "$SOURCE_DOMAIN" ]; then
            echo "Error: Missing source domain"
            echo "Usage: $0 $DB_FILE test <source_domain>"
            exit 1
        fi

        echo "Testing domain alias for: $SOURCE_DOMAIN"
        RESULT=$(sqlite3 "$DB_FILE" "SELECT Target_Domain FROM domain_alias WHERE Source_Domain = '$SOURCE_DOMAIN';")

        if [ -n "$RESULT" ]; then
            echo "✓ Alias found: $SOURCE_DOMAIN → $RESULT"
            echo ""
            echo "DNS queries for '$SOURCE_DOMAIN' will resolve '$RESULT'"
        else
            echo "✗ No alias found for $SOURCE_DOMAIN"
            echo ""
            echo "DNS queries for '$SOURCE_DOMAIN' will be resolved normally"
        fi
        ;;

    *)
        echo "Error: Unknown action: $ACTION"
        echo "Run '$0' without arguments for usage information"
        exit 1
        ;;
esac
