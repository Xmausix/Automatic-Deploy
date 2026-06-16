#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# ============================================================
# Notifications: Discord & Slack (Senior: ChatOps)
# ============================================================

send_discord() {
    local message="$1"
    local webhook="${DISCORD_WEBHOOK:-}"

    if [[ -z "$webhook" ]]; then
        log WARN "Discord webhook not configured. Skipping notification."
        return 0
    fi

    if is_dry_run; then
        log WARN "[DRY-RUN] Would send Discord: $message"
        return 0
    fi

    curl -s -H "Content-Type: application/json" \
         -d "{\"content\":\"$message\"}" \
         "$webhook" > /dev/null || log WARN "Discord notification failed"

    log INFO "Discord notification sent"
}

send_slack() {
    local message="$1"
    local status="${2:-info}"
    local webhook="${SLACK_WEBHOOK:-}"

    if [[ -z "$webhook" ]]; then
        log WARN "Slack webhook not configured. Skipping notification."
        return 0
    fi

    local color="#36a64f"
    [[ "$status" == "error" ]] && color="#ff0000"
    [[ "$status" == "warn" ]] && color="#ff9900"

    if is_dry_run; then
        log WARN "[DRY-RUN] Would send Slack: $message"
        return 0
    fi

    curl -s -H "Content-Type: application/json" \
         -d "{\"attachments\":[{\"color\":\"$color\",\"text\":\"$message\"}]}" \
         "$webhook" > /dev/null || log WARN "Slack notification failed"

    log INFO "Slack notification sent"
}

notify() {
    local level="$1"
    local msg="$2"
    send_discord "[$level] $msg"
    send_slack "[$level] $msg" "$level"
}
