#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"


METRICS_FILE=""

metrics_init() {
    local deploy_id="$1"
    METRICS_FILE="${SCRIPT_DIR}/logs/metrics_${deploy_id}.prom"
    cat > "$METRICS_FILE" <<EOF
deploy_start_timestamp $(date +%s)

deploy_info{environment="${ENV_NAME}",strategy="${DEPLOY_STRATEGY}",branch="${BRANCH:-unknown}"} 1
EOF
}

metric_set() {
    local name="$1"
    local value="$2"
    local help_text="${3:-}"
    local type_text="${4:-gauge}"

    if [[ -z "$METRICS_FILE" ]]; then
        log WARN "Metrics not initialized. Skipping metric $name."
        return 0
    fi

    if [[ -n "$help_text" ]]; then
        echo "# HELP ${name} ${help_text}" >> "$METRICS_FILE"
        echo "# TYPE ${name} ${type_text}" >> "$METRICS_FILE"
    fi
    echo "${name} ${value}" >> "$METRICS_FILE"
}

metrics_finalize() {
    local deploy_id="$1"
    local duration="$2"
    local success="$3"

    metric_set "deploy_duration_seconds" "$duration" "Total deployment duration in seconds" "gauge"
    metric_set "deploy_success_total" "$success" "Total successful deployments" "counter"
    metric_set "deploy_failure_total" "$((1 - success))" "Total failed deployments" "counter"

    if [[ -n "${PROMETHEUS_PORT:-}" ]] && command -v python3 &> /dev/null && ! is_dry_run; then
        (
            cd "$(dirname "$METRICS_FILE")"
            python3 -m http.server "$PROMETHEUS_PORT" --bind 127.0.0.1 &
            echo $! > "${SCRIPT_DIR}/logs/.metrics_server.pid"
        ) &> /dev/null || true
        log INFO "Metrics exposed at http://127.0.0.1:${PROMETHEUS_PORT}/$(basename "$METRICS_FILE")"
    fi
}

metrics_cleanup() {
    if [[ -f "${SCRIPT_DIR}/logs/.metrics_server.pid" ]]; then
        local pid
        pid=$(cat "${SCRIPT_DIR}/logs/.metrics_server.pid")
        kill "$pid" 2>/dev/null || true
        rm -f "${SCRIPT_DIR}/logs/.metrics_server.pid"
    fi
}
