#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -n ${UTILS_SOURCED:-} ]]; then return 0; fi
UTILS_SOURCED=1

if [[ -z ${SCRIPT_DIR:-} ]]; then
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
    readonly SCRIPT_DIR
fi
readonly LOG_FILE=${LOG_FILE:-${SCRIPT_DIR}/logs/deploy.log}

ensure_log_dir() { mkdir -p "$(dirname "$LOG_FILE")"; }

log() {
    local level=$1; shift
    local message=$*
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    ensure_log_dir
    printf '[%s] %s: %s\n' "$timestamp" "$level" "$message" | tee -a "$LOG_FILE" >&2
}

section() { log STEP "$1"; }
error_exit() { log ERROR "$1"; return 1; }
is_dry_run() { [[ ${DRY_RUN:-false} == true ]]; }
run_or_dry() { if is_dry_run; then log DRY-RUN "Would execute: $*"; else "$@"; fi; }
backup_timestamp() { date -u +%Y%m%d_%H%M%S; }
format_duration() { printf '%ss' "$(( $2 - $1 ))"; }

valid_environment() { [[ $1 =~ ^(development|staging|production)$ ]]; }
valid_strategy() { [[ $1 =~ ^(local|rolling|blue-green|canary)$ ]]; }

load_env_config() {
    local env_name=$1
    local config_file=${SCRIPT_DIR}/config/${env_name}.conf
    valid_environment "$env_name" || { log ERROR "Unsupported environment: $env_name"; return 1; }
    [[ -r $config_file ]] || { log ERROR "Configuration not readable: $config_file"; return 1; }
    unset APP_DIR BRANCH SERVICE_NAME REPO_URL HEALTH_URL HEALTH_TIMEOUT HEALTH_INTERVAL DEPLOY_STRATEGY HOSTS VAULT_PATH DOCKER_IMAGE DOCKER_REGISTRY CANARY_START_WEIGHT CANARY_FINAL_WEIGHT CANARY_STEP CANARY_INTERVAL PROMETHEUS_PORT DISCORD_WEBHOOK SLACK_WEBHOOK
    while IFS='=' read -r key value; do
        [[ -z ${key//[[:space:]]/} || $key == \#* ]] && continue
        key=${key//[[:space:]]/}
        [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { log ERROR "Invalid configuration key: $key"; return 1; }
        value=${value%$'\r'}
        value=${value#"${value%%[![:space:]]*}"}; value=${value%"${value##*[![:space:]]}"}
        printf -v "$key" '%s' "$value"
        export "$key"
    done < "$config_file"
    : "${APP_DIR:?APP_DIR is required}" "${SERVICE_NAME:?SERVICE_NAME is required}" "${BRANCH:?BRANCH is required}"
    DEPLOY_STRATEGY=${DEPLOY_STRATEGY:-rolling}; valid_strategy "$DEPLOY_STRATEGY" || { log ERROR "Unsupported strategy: $DEPLOY_STRATEGY"; return 1; }
    HEALTH_TIMEOUT=${HEALTH_TIMEOUT:-30}; HEALTH_INTERVAL=${HEALTH_INTERVAL:-2}; HOSTS=${HOSTS:-localhost}
    ARTIFACT_DIR=${ARTIFACT_DIR:-${SCRIPT_DIR}/releases}; BACKUP_DIR=${BACKUP_DIR:-${SCRIPT_DIR}/backups}; REPORT_DIR=${REPORT_DIR:-${SCRIPT_DIR}/reports}
    export DEPLOY_STRATEGY HEALTH_TIMEOUT HEALTH_INTERVAL HOSTS ARTIFACT_DIR BACKUP_DIR REPORT_DIR
    mkdir -p "$ARTIFACT_DIR" "$BACKUP_DIR" "$REPORT_DIR"
}

require_commands() {
    local missing=() command_name
    for command_name in "$@"; do command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name"); done
    ((${#missing[@]} == 0)) || { log ERROR "Missing required commands: ${missing[*]}"; return 1; }
}
