#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# ChatOps Webhook Server (Senior: ChatOps Integration)
# ============================================================
# This script can be used as a simple webhook receiver or curl target
# to trigger deployments from Slack/Discord/Mattermost.
# Usage example:
#   ./chatops.sh deploy production
#   curl -X POST http://localhost:9000/deploy -d '{"env":"production"}'
# ============================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/notification.sh"

usage() {
    cat <<EOF
ChatOps Quick Commands:
  $(basename "$0") deploy <env> [--strategy <s>] [--parallel]
  $(basename "$0") status <env>
  $(basename "$0") rollback <env> <backup>

Server mode:
  $(basename "$0") server --port 9000
EOF
    exit 1
}

command="${1:-}"
shift || usage

handle_deploy() {
    local env_name="$1"
    shift
    log INFO "ChatOps: Deploying ${env_name}"
    notify info "ChatOps: deployment to ${env_name} triggered"
    "${SCRIPT_DIR}/deploy.sh" "$env_name" "$@"
}

handle_status() {
    local env_name="$1"
    log INFO "ChatOps: Checking status for ${env_name}"
    if [[ -f "${SCRIPT_DIR}/logs/deploy.log" ]]; then
        tail -n 10 "${SCRIPT_DIR}/logs/deploy.log"
    fi
}

handle_rollback() {
    local env_name="$1"
    local backup="$2"
    log INFO "ChatOps: Rolling back ${env_name} to ${backup}"
    notify warn "ChatOps: rollback triggered for ${env_name}"
    "${SCRIPT_DIR}/rollback.sh" "$env_name" "$backup"
}

server_mode() {
    local port="${1:-9000}"
    log INFO "Starting ChatOps webhook server on port ${port}"
    log WARN "This is a demo stub. In production use a proper webhook listener or a bot."

    # Example: listen with netcat (very simple, not for production)
    while true; do
        {
            read -r method path _
            read -r header
            while [[ "$header" != $'\r' && -n "$header" ]]; do
                read -r header
            done
            read -r -d '' body

            log INFO "Received ${method} ${path}"

            echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n"
            echo '{"status":"ok","message":"ChatOps webhook received"}'

            if [[ "$path" == "/deploy" ]]; then
                local env_name
                env_name=$(echo "$body" | grep -oP '"env"\s*:\s*"\K[^"]+' || echo "production")
                handle_deploy "$env_name" &
            fi
        } | nc -l -p "$port" &
        wait $!
    done
}

# --- Main dispatcher ---
case "$command" in
    deploy)
        handle_deploy "$@"
        ;;
    status)
        handle_status "$@"
        ;;
    rollback)
        handle_rollback "$@"
        ;;
    server)
        shift || true
        server_mode "$@"
        ;;
    *)
        usage
        ;;
esac
