#!/bin/bash

################################################################################
# Create required RDS PostgreSQL databases if they do not already exist.
#
# Usage:
#   ./create_rds_databases.sh
#
# Required env vars (from .env or environment):
#   RDS_HOST
#   RDS_PORT
#   RDS_PASSWORD
#   RDS_USER or RDS_USERNAME
#
# Optional DB name vars (any combination):
#   RDS_AIRFLOW_DB, RDS_DB
#   RDS_MLFLOW_DB
#   RDS_ANALYTICS_DB, RDS_DB_NAME
#
# Optional admin DB for connection:
#   RDS_ADMIN_DB (default: postgres)
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}INFO:${NC} $1"; }
print_ok() { echo -e "${GREEN}OK:${NC} $1"; }
print_warn() { echo -e "${YELLOW}WARN:${NC} $1"; }
print_err() { echo -e "${RED}ERROR:${NC} $1"; }

load_env() {
    if [ -f "$SCRIPT_DIR/.env" ]; then
        # Export .env entries into current shell.
        set -a
        source "$SCRIPT_DIR/.env"
        set +a
        print_ok "Loaded environment from .env"
    else
        print_warn ".env not found in project root; using current shell environment"
    fi
}

require_tools() {
    if ! command -v psql >/dev/null 2>&1; then
        print_err "psql is not installed or not in PATH"
        exit 1
    fi
}

normalize_env() {
    if [ -z "${RDS_USER:-}" ] && [ -n "${RDS_USERNAME:-}" ]; then
        export RDS_USER="$RDS_USERNAME"
    fi

    # Compatibility between local/ECS naming.
    if [ -z "${RDS_AIRFLOW_DB:-}" ] && [ -n "${RDS_DB:-}" ]; then
        export RDS_AIRFLOW_DB="$RDS_DB"
    fi

    if [ -z "${RDS_ANALYTICS_DB:-}" ] && [ -n "${RDS_DB_NAME:-}" ]; then
        export RDS_ANALYTICS_DB="$RDS_DB_NAME"
    fi
}

validate_env() {
    local missing=0

    for var in RDS_HOST RDS_PORT RDS_USER RDS_PASSWORD; do
        if [ -z "${!var:-}" ]; then
            print_err "$var is required but not set"
            missing=1
        fi
    done

    if [ "$missing" -ne 0 ]; then
        exit 1
    fi
}

collect_databases() {
    DATABASES=()

    [ -n "${RDS_AIRFLOW_DB:-}" ] && DATABASES+=("$RDS_AIRFLOW_DB")
    [ -n "${RDS_MLFLOW_DB:-}" ] && DATABASES+=("$RDS_MLFLOW_DB")
    [ -n "${RDS_ANALYTICS_DB:-}" ] && DATABASES+=("$RDS_ANALYTICS_DB")

    if [ "${#DATABASES[@]}" -eq 0 ]; then
        print_err "No target databases found. Set at least one of:"
        echo "  RDS_AIRFLOW_DB / RDS_DB"
        echo "  RDS_MLFLOW_DB"
        echo "  RDS_ANALYTICS_DB / RDS_DB_NAME"
        exit 1
    fi

    # De-duplicate while preserving first occurrence order.
    UNIQUE_DATABASES=()
    local db
    for db in "${DATABASES[@]}"; do
        if [[ " ${UNIQUE_DATABASES[*]} " != *" $db "* ]]; then
            UNIQUE_DATABASES+=("$db")
        fi
    done
}

sql_escape_literal() {
    # Escape single quotes for SQL literals.
    printf "%s" "$1" | sed "s/'/''/g"
}

sql_escape_identifier() {
    # Escape double quotes for SQL identifiers.
    printf "%s" "$1" | sed 's/"/""/g'
}

can_connect() {
    local db_name="$1"
    PGPASSWORD="$RDS_PASSWORD" psql \
        -h "$RDS_HOST" \
        -p "$RDS_PORT" \
        -U "$RDS_USER" \
        -d "$db_name" \
        -tAc "SELECT 1" >/dev/null 2>&1
}

pick_admin_db() {
    ADMIN_DB="${RDS_ADMIN_DB:-postgres}"
    if can_connect "$ADMIN_DB"; then
        print_ok "Connected to admin database: $ADMIN_DB"
        return
    fi

    if can_connect "template1"; then
        ADMIN_DB="template1"
        print_warn "Using fallback admin database: template1"
        return
    fi

    print_err "Cannot connect to admin database ('${RDS_ADMIN_DB:-postgres}' or template1)"
    print_err "Verify RDS connectivity, credentials, and DB access"
    exit 1
}

database_exists() {
    local db_name_escaped
    db_name_escaped="$(sql_escape_literal "$1")"

    PGPASSWORD="$RDS_PASSWORD" psql \
        -h "$RDS_HOST" \
        -p "$RDS_PORT" \
        -U "$RDS_USER" \
        -d "$ADMIN_DB" \
        -tAc "SELECT 1 FROM pg_database WHERE datname='${db_name_escaped}'" 2>/dev/null | grep -q '^1$'
}

create_database() {
    local db_identifier
    db_identifier="$(sql_escape_identifier "$1")"

    PGPASSWORD="$RDS_PASSWORD" psql \
        -h "$RDS_HOST" \
        -p "$RDS_PORT" \
        -U "$RDS_USER" \
        -d "$ADMIN_DB" \
        -v ON_ERROR_STOP=1 \
        -c "CREATE DATABASE \"${db_identifier}\";" >/dev/null
}

main() {
    echo "============================================================"
    echo "RDS Database Bootstrap"
    echo "============================================================"

    load_env
    require_tools
    normalize_env
    validate_env
    collect_databases
    pick_admin_db

    print_info "RDS host: $RDS_HOST:$RDS_PORT"
    print_info "RDS user: $RDS_USER"
    print_info "Target databases: ${UNIQUE_DATABASES[*]}"

    local created=0
    local skipped=0
    local db
    for db in "${UNIQUE_DATABASES[@]}"; do
        if database_exists "$db"; then
            print_warn "Database '$db' already exists - skipping"
            skipped=$((skipped + 1))
        else
            print_info "Creating database '$db'..."
            create_database "$db"
            print_ok "Database '$db' created"
            created=$((created + 1))
        fi
    done

    echo ""
    echo "Summary:"
    echo "  Created: $created"
    echo "  Skipped: $skipped"
    echo "  Total:   ${#UNIQUE_DATABASES[@]}"
}

main "$@"
