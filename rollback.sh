#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Rollback Utility — Senior DevOps Edition
# ============================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/notification.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <environment> <backup_name>

Example:
  $(basename "$0") production backup_20260615_143000_production

Options:
  --dry-run    Simulate rollback without applying changes
EOF
    exit 1
}

ENV_NAME=""
BACKUP_NAME=""
DRY_RUN=false

parse_args() {
    if [[ $# -lt 2 ]]; then usage; fi
    ENV_NAME="$1"
    BACKUP_NAME="$2"
    shift 2

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=true; shift ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
    done
}

main() {
    parse_args "$@"
    load_env_config "$ENV_NAME"

    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"

    if [[ ! -d "$backup_path" ]]; then
        error_exit "Backup not found: ${backup_path}"
    fi

    section "Rollback Started"
    log INFO "Environment: ${ENV_NAME}"
    log INFO "Backup: ${backup_path}"

    if [[ "$DRY_RUN" == true ]]; then
        log WARN "[DRY-RUN] Would restore ${backup_path} -> ${APP_DIR}"
        log WARN "[DRY-RUN] Would restart service ${SERVICE_NAME}"
    else
        log INFO "Stopping service ${SERVICE_NAME}..."
        if command -v systemctl &> /dev/null; then
            systemctl stop "$SERVICE_NAME" || true
        elif command -v docker &> /dev/null; then
            docker stop "$SERVICE_NAME" 2>/dev/null || true
        fi

        log INFO "Restoring backup..."
        rm -rf "${APP_DIR:?}"/*
        cp -a "${backup_path}/." "$APP_DIR/"

        log INFO "Starting service ${SERVICE_NAME}..."
        if command -v systemctl &> /dev/null; then
            systemctl start "$SERVICE_NAME" || true
        elif command -v docker &> /dev/null; then
            docker start "$SERVICE_NAME" 2>/dev/null || true
        fi

        log INFO "Rollback completed successfully"
        notify info "Rollback to ${BACKUP_NAME} completed for ${ENV_NAME}"
    fi
}

main "$@"
