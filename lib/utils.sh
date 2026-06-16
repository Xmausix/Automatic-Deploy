#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Senior DevOps Deployment Toolkit — Utilities
# ============================================================
if [[ -n "${UTILS_SOURCED:-}" ]]; then return; fi
UTILS_SOURCED=1

if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    readonly SCRIPT_DIR
fi
readonly LOG_FILE="${SCRIPT_DIR}/logs/deploy.log"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

ensure_log_dir() {
    mkdir -p "$(dirname "$LOG_FILE")"
}

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""

    case "$level" in
        INFO)  color="$GREEN" ;;
        WARN)  color="$YELLOW" ;;
        ERROR) color="$RED" ;;
        STEP)  color="$CYAN" ;;
        *)     color="$NC" ;;
    esac

    # Console output with colors
    echo -e "${color}[${timestamp}] ${level}: ${message}${NC}"

    # File output plain text
    ensure_log_dir
    echo "[${timestamp}] ${level}: ${message}" >> "$LOG_FILE"
}

section() {
    echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log STEP "$1"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

error_exit() {
    log ERROR "$1"
    exit 1
}

confirm() {
    local msg="$1"
    read -r -p "$msg [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

load_env_config() {
    local env_name="$1"
    local config_file="${SCRIPT_DIR}/config/${env_name}.conf"

    if [[ ! -f "$config_file" ]]; then
        error_exit "Configuration file not found: $config_file"
    fi

    # Source config with safety checks
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        # Export variable
        export "$key=$value"
    done < "$config_file"

    # Set defaults if not provided
    export DEPLOY_STRATEGY="${DEPLOY_STRATEGY:-rolling}"
    export HEALTH_URL="${HEALTH_URL:-http://localhost:8080/health}"
    export HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-30}"
    export HEALTH_INTERVAL="${HEALTH_INTERVAL:-2}"
    export PROMETHEUS_PORT="${PROMETHEUS_PORT:-9100}"
    export ARTIFACT_DIR="${SCRIPT_DIR}/releases"
    export BACKUP_DIR="${SCRIPT_DIR}/backups"
    export REPORT_DIR="${SCRIPT_DIR}/reports"

    mkdir -p "$ARTIFACT_DIR" "$BACKUP_DIR" "$REPORT_DIR"
}

is_dry_run() {
    [[ "${DRY_RUN:-false}" == "true" ]]
}

dry_run_echo() {
    if is_dry_run; then
        echo -e "${YELLOW}[DRY-RUN] Would execute: $*${NC}"
    else
        echo "$@"
    fi
}

run_or_dry() {
    if is_dry_run; then
        log WARN "[DRY-RUN] Would execute: $*"
    else
        "$@"
    fi
}

backup_timestamp() {
    date +%Y%m%d_%H%M%S
}

format_duration() {
    local start=$1
    local end=$2
    local duration=$((end - start))
    echo "${duration}s"
}
