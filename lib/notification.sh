#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

send_discord() {
    local message=$1 webhook=${DISCORD_WEBHOOK:-}
    [[ -n $webhook ]] || return 0
    is_dry_run && { log DRY-RUN "Would notify Discord"; return 0; }
    command -v curl >/dev/null 2>&1 || { log WARN "curl unavailable; Discord notification skipped"; return 0; }
    local payload
    if command -v jq >/dev/null 2>&1; then payload=$(jq -cn --arg content "$message" '{content:$content}'); else payload=$(printf '{"content":"%s"}' "${message//\/\\}"); fi
    curl --fail --silent --show-error --max-time 10 -H 'Content-Type: application/json' --data "$payload" "$webhook" >/dev/null || log WARN "Discord notification failed"
}

send_slack() {
    local message=$1 level=${2:-info} webhook=${SLACK_WEBHOOK:-}
    [[ -n $webhook ]] || return 0
    is_dry_run && { log DRY-RUN "Would notify Slack"; return 0; }
    command -v curl >/dev/null 2>&1 || { log WARN "curl unavailable; Slack notification skipped"; return 0; }
    local payload
    if command -v jq >/dev/null 2>&1; then payload=$(jq -cn --arg text "[$level] $message" '{text:$text}'); else payload=$(printf '{"text":"[%s] %s"}' "$level" "${message//\/\\}"); fi
    curl --fail --silent --show-error --max-time 10 -H 'Content-Type: application/json' --data "$payload" "$webhook" >/dev/null || log WARN "Slack notification failed"
}

notify() { local level=$1 message=$2; send_discord "[$level] $message"; send_slack "$message" "$level"; }
