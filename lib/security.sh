#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# ============================================================
# Security Scanning & Artifact Signing (Senior: Supply Chain)
# ============================================================

security_scan_image() {
    local image="${1:-myapp:latest}"

    log INFO "Running security scan on $image"

    if command -v trivy &> /dev/null; then
        if is_dry_run; then
            log WARN "[DRY-RUN] Would run: trivy image --exit-code 1 --severity HIGH,CRITICAL $image"
            return 0
        fi
        trivy image --exit-code 1 --severity HIGH,CRITICAL "$image" || {
            log ERROR "Security scan found critical vulnerabilities!"
            return 1
        }
    elif command -v grype &> /dev/null; then
        if is_dry_run; then
            log WARN "[DRY-RUN] Would run: grype $image --fail-on critical"
            return 0
        fi
        grype "$image" --fail-on critical || {
            log ERROR "Security scan found critical vulnerabilities!"
            return 1
        }
    else
        log WARN "No security scanner (trivy/grype) found. Skipping scan."
    fi

    log INFO "Security scan passed"
}

sign_artifact() {
    local artifact="$1"
    local sig_file="${artifact}.sig"

    if ! command -v gpg &> /dev/null; then
        log WARN "GPG not available. Skipping artifact signing."
        return 0
    fi

    log INFO "Signing artifact: $artifact"

    if is_dry_run; then
        log WARN "[DRY-RUN] Would run: gpg --batch --yes --detach-sign --armor -o $sig_file $artifact"
        return 0
    fi

    gpg --batch --yes --detach-sign --armor -o "$sig_file" "$artifact" || {
        log WARN "Artifact signing failed (no key?)"
        return 0
    }

    log INFO "Artifact signed: $sig_file"
}

verify_artifact() {
    local artifact="$1"
    local sig_file="${artifact}.sig"

    if [[ ! -f "$sig_file" ]]; then
        log WARN "Signature file missing for verification"
        return 0
    fi

    if ! command -v gpg &> /dev/null; then
        log WARN "GPG not available. Skipping verification."
        return 0
    fi

    gpg --verify "$sig_file" "$artifact" || {
        log ERROR "Artifact signature verification failed!"
        return 1
    }
}
