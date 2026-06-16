#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# ============================================================
# HashiCorp Vault Integration (Senior: Secrets Management)
# ============================================================

vault_fetch_secrets() {
    local path="${VAULT_PATH:-}"
    if [[ -z "$path" ]]; then
        log WARN "VAULT_PATH not configured. Skipping Vault integration."
        return 0
    fi

    if ! command -v vault &> /dev/null; then
        log WARN "Vault CLI not installed. Skipping secret fetch."
        return 0
    fi

    log INFO "Fetching secrets from Vault: $path"

    if is_dry_run; then
        log WARN "[DRY-RUN] Would fetch: vault kv get -format=json $path"
        return 0
    fi

    # Attempt to source secrets into environment
    local vault_json
    if vault_json=$(vault kv get -format=json "$path" 2>/dev/null); then
        # Extract keys and export (this is a simplified parser)
        while IFS= read -r key; do
            local val
            val=$(echo "$vault_json" | jq -r ".data.data.${key}")
            export "VAULT_${key^^}=$val"
            log INFO "Loaded secret: ${key}"
        done < <(echo "$vault_json" | jq -r '.data.data | keys[]')
    else
        log WARN "Failed to fetch secrets from Vault"
    fi
}

vault_test_connection() {
    if command -v vault &> /dev/null; then
        vault status 2>/dev/null || log WARN "Vault server unreachable"
    fi
}
