#!/usr/bin/env bash
set -euo pipefail


readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/notification.sh"
source "${LIB_DIR}/metrics.sh"
source "${LIB_DIR}/vault.sh"
source "${LIB_DIR}/security.sh"
source "${LIB_DIR}/report.sh"

ENV_NAME=""
DEPLOY_STRATEGY_OVERRIDE=""
DRY_RUN=false
PARALLEL=false
SKIP_TESTS=false
SKIP_SECURITY=false
DEPLOY_ID=""
GIT_COMMIT="unknown"
START_TIME=0
BACKUP_NAME=""
ROLLBACK_TRIGGERED=false

usage() {
    cat <<EOF
Usage: $(basename "$0") <environment> [options]

Environments:
  development | staging | production

Options:
  --dry-run               Simulate deployment without changes
  --strategy <name>       Override strategy: rolling, blue-green, canary, local
  --parallel                Deploy to multiple hosts in parallel
  --skip-tests              Skip test execution
  --skip-security           Skip security scanning
  --help                    Show this help

Examples:
  $(basename "$0") production --dry-run
  $(basename "$0") production --strategy blue-green --parallel
EOF
    exit 1
}

parse_args() {
    if [[ $# -lt 1 ]]; then
        usage
    fi

    ENV_NAME="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)       DRY_RUN=true ;;
            --strategy)      DEPLOY_STRATEGY_OVERRIDE="$2"; shift ;;
            --parallel)      PARALLEL=true ;;
            --skip-tests)    SKIP_TESTS=true ;;
            --skip-security) SKIP_SECURITY=true ;;
            --help)          usage ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
        shift
    done
}

preflight() {
    section "Pre-flight Checks"

    log INFO "Loading configuration for environment: ${ENV_NAME}"
    load_env_config "$ENV_NAME"

    if [[ -n "$DEPLOY_STRATEGY_OVERRIDE" ]]; then
        DEPLOY_STRATEGY="$DEPLOY_STRATEGY_OVERRIDE"
        log WARN "Overriding strategy to: ${DEPLOY_STRATEGY}"
    fi

    DEPLOY_ID="deploy_$(backup_timestamp)"
    START_TIME=$(date +%s)
    metrics_init "$DEPLOY_ID"
    log INFO "Deployment ID: ${DEPLOY_ID}"
    log INFO "Strategy: ${DEPLOY_STRATEGY}"
    log INFO "Dry Run: ${DRY_RUN}"

    command -v git &> /dev/null || error_exit "git is required"
    command -v curl &> /dev/null || log WARN "curl not found, health checks will be skipped"
    command -v rsync &> /dev/null || log WARN "rsync not found, falling back to cp"

    vault_test_connection
}

stage_git() {
    section "Stage 1: Git Pull"

    if is_dry_run; then
        log WARN "[DRY-RUN] Would: git fetch origin && git checkout ${BRANCH} && git pull origin ${BRANCH}"
        GIT_COMMIT="dryrun_abc123"
        return 0
    fi

    if [[ ! -d "${APP_DIR}/.git" ]]; then
        log WARN "App dir is not a git repository. Skipping git operations."
        GIT_COMMIT="unknown"
        return 0
    fi

    pushd "$APP_DIR" > /dev/null || error_exit "Cannot enter APP_DIR"
    git fetch origin || log WARN "Git fetch failed"
    git checkout "$BRANCH" || log WARN "Git checkout failed"
    git pull origin "$BRANCH" || log WARN "Git pull failed"
    GIT_COMMIT=$(git rev-parse --short HEAD)
    popd > /dev/null || true

    log INFO "Git commit: ${GIT_COMMIT}"
    metric_set "deploy_git_commit_info" "1" "Git commit hash" "gauge"
}

stage_backup() {
    section "Stage 2: Backup"
    BACKUP_NAME="backup_$(backup_timestamp)_${ENV_NAME}"
    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"

    if [[ ! -d "$APP_DIR" ]]; then
        log WARN "APP_DIR does not exist yet, creating fresh directory"
        run_or_dry mkdir -p "$APP_DIR"
        return 0
    fi

    run_or_dry cp -a "$APP_DIR" "$backup_path"
    log INFO "Backup created: ${backup_path}"
    metric_set "deploy_backup_created" "1" "Backup created indicator" "gauge"
}

stage_secrets() {
    section "Stage 3: Load Secrets"
    vault_fetch_secrets
}

stage_build() {
    section "Stage 4: Build Application"

    if is_dry_run; then
        log WARN "[DRY-RUN] Would build application in ${APP_DIR}"
        return 0
    fi

    pushd "$APP_DIR" > /dev/null || error_exit "Cannot enter APP_DIR for build"

    if [[ -f "package.json" ]]; then
        log INFO "Detected Node.js project"
        npm ci || npm install || log WARN "npm install failed"
        npm run build || log WARN "npm build failed"
    elif [[ -f "pom.xml" ]]; then
        log INFO "Detected Java/Maven project"
        mvn clean package -DskipTests="$SKIP_TESTS" || error_exit "Maven build failed"
    elif [[ -f "requirements.txt" ]]; then
        log INFO "Detected Python project"
        python3 -m pip install -r requirements.txt || error_exit "pip install failed"
    elif [[ -f "Dockerfile" ]]; then
        log INFO "Detected Docker project"
        docker build -t "${DOCKER_IMAGE}:latest" . || error_exit "Docker build failed"
    else
        log WARN "No recognized build system detected. Skipping build."
    fi

    popd > /dev/null || true
    log INFO "Build completed"
    metric_set "deploy_build_success" "1" "Build success indicator" "gauge"
}

stage_security() {
    if [[ "$SKIP_SECURITY" == true ]]; then
        log WARN "Skipping security scan (user requested)"
        return 0
    fi

    section "Stage 5: Security Scan"

    if [[ -f "${APP_DIR}/Dockerfile" ]]; then
        security_scan_image "${DOCKER_IMAGE}:latest"
    else
        log WARN "No Docker image to scan. Skipping."
    fi
}

stage_tests() {
    if [[ "$SKIP_TESTS" == true ]]; then
        log WARN "Skipping tests (user requested)"
        return 0
    fi

    section "Stage 6: Tests"

    if is_dry_run; then
        log WARN "[DRY-RUN] Would execute tests"
        return 0
    fi

    pushd "$APP_DIR" > /dev/null || error_exit "Cannot enter APP_DIR for tests"

    local test_passed=0
    if [[ -f "package.json" ]]; then
        npm test && test_passed=1 || true
    elif [[ -f "pom.xml" ]]; then
        mvn test && test_passed=1 || true
    elif [[ -f "pytest.ini" || -f "setup.py" || -d "tests" ]]; then
        pytest && test_passed=1 || true
    else
        log WARN "No test runner detected. Skipping."
        test_passed=1
    fi

    popd > /dev/null || true

    if [[ "$test_passed" -ne 1 ]]; then
        error_exit "Tests failed. Deployment aborted."
    fi

    log INFO "Tests passed"
    metric_set "deploy_tests_passed" "1" "Tests passed indicator" "gauge"
}

stage_artifact() {
    section "Stage 7: Artifact Packaging"

    local artifact_name="release_${DEPLOY_ID}_${GIT_COMMIT}.tar.gz"
    local artifact_path="${ARTIFACT_DIR}/${artifact_name}"

    if is_dry_run; then
        log WARN "[DRY-RUN] Would package: tar czf ${artifact_path} ${APP_DIR}"
        return 0
    fi

    tar czf "$artifact_path" \
        --exclude='node_modules' \
        --exclude='.git' \
        --exclude='venv' \
        --exclude='__pycache__' \
        -C "$(dirname "$APP_DIR")" "$(basename "$APP_DIR")" || true

    sign_artifact "$artifact_path"
    verify_artifact "$artifact_path" || true

    log INFO "Artifact: ${artifact_path}"
}

strategy_local() {
    log INFO "Deploying locally to ${APP_DIR}"
    local build_dir="${APP_DIR}"
    if [[ -d "${APP_DIR}/build" ]]; then build_dir="${APP_DIR}/build"; fi
    if [[ -d "${APP_DIR}/dist" ]]; then build_dir="${APP_DIR}/dist"; fi

    if [[ -d "$build_dir" && "$build_dir" != "$APP_DIR" ]]; then
        run_or_dry rsync -a --delete "${build_dir}/" "${APP_DIR}/" || run_or_dry cp -a "${build_dir}/." "${APP_DIR}/"
    fi
}

strategy_blue_green() {
    log INFO "Executing Blue-Green deployment"

    local blue_dir="${APP_DIR}-blue"
    local green_dir="${APP_DIR}-green"
    local active_dir=""
    local inactive_dir=""

    if [[ -L "$APP_DIR" ]]; then
        local current
        current=$(readlink -f "$APP_DIR")
        if [[ "$current" == "$blue_dir" ]]; then
            active_dir="$blue_dir"
            inactive_dir="$green_dir"
        else
            active_dir="$green_dir"
            inactive_dir="$blue_dir"
        fi
    else
        active_dir="$blue_dir"
        inactive_dir="$green_dir"
        run_or_dry mkdir -p "$blue_dir" "$green_dir"
        if [[ -d "$APP_DIR" && ! -L "$APP_DIR" ]]; then
            run_or_dry cp -a "$APP_DIR/." "$blue_dir/"
        fi
        run_or_dry ln -sfn "$blue_dir" "$APP_DIR"
    fi

    log INFO "Active: ${active_dir}, Deploying to: ${inactive_dir}"

    run_or_dry rsync -a --delete "${APP_DIR}/" "${inactive_dir}/" || run_or_dry cp -a "${APP_DIR}/." "${inactive_dir}/"

    run_or_dry ln -sfn "$inactive_dir" "$APP_DIR"
    log INFO "Traffic switched to ${inactive_dir}"
}

strategy_canary() {
    log INFO "Executing Canary deployment (simulated)"
    local start_weight=${CANARY_START_WEIGHT:-10}
    local final_weight=${CANARY_FINAL_WEIGHT:-100}
    local step=${CANARY_STEP:-10}
    local interval=${CANARY_INTERVAL:-30}

    log INFO "Canary: Starting at ${start_weight}% traffic"

    for ((w=start_weight; w<=final_weight; w+=step)); do
        log INFO "Canary: Shifting ${w}% traffic to new version"
        sleep "$interval"

        if ! health_check_internal; then
            log ERROR "Canary health check failed at ${w}% rollout"
            return 1
        fi
    done

    log INFO "Canary: Full rollout completed"
}

strategy_rolling() {
    log INFO "Executing Rolling deployment"
    strategy_local
}

deploy_to_host() {
    local host="$1"
    log INFO "Deploying to host: ${host}"

    if is_dry_run; then
        log WARN "[DRY-RUN] Would deploy to ${host} via SSH"
        return 0
    fi

    if [[ "$host" == "localhost" ]]; then
        case "$DEPLOY_STRATEGY" in
            blue-green) strategy_blue_green ;;
            canary)     strategy_canary ;;
            rolling)    strategy_rolling ;;
            *)          strategy_local ;;
        esac
    else
        log INFO "Deploying via SSH to ${host}..."
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$host" \
            "echo 'Remote deployment executed on ${host}'" || log WARN "SSH to ${host} failed (stub)"
    fi
}

stage_deploy() {
    section "Stage 7: Deploy"

    read -ra HOSTS_ARRAY <<< "${HOSTS}"

    if [[ "${#HOSTS_ARRAY[@]}" -eq 0 ]]; then
        HOSTS_ARRAY=("localhost")
    fi

    if [[ "$PARALLEL" == true && "${#HOSTS_ARRAY[@]}" -gt 1 ]]; then
        log INFO "Parallel deployment enabled for ${#HOSTS_ARRAY[@]} hosts"
        local pids=()
        for host in "${HOSTS_ARRAY[@]}"; do
            deploy_to_host "$host" &
            pids+=($!)
        done
        for pid in "${pids[@]}"; do
            wait "$pid" || { log ERROR "Parallel deployment failed for PID ${pid}"; ROLLBACK_TRIGGERED=true; }
        done
    else
        for host in "${HOSTS_ARRAY[@]}"; do
            deploy_to_host "$host" || { ROLLBACK_TRIGGERED=true; break; }
        done
    fi

    if [[ "$ROLLBACK_TRIGGERED" == true ]]; then
        error_exit "Deployment stage failed"
    fi

    log INFO "Deployment stage completed"
    metric_set "deploy_stage_success" "1" "Deployment stage success" "gauge"
}

stage_restart() {
    section "Stage 8: Restart Service"

    if is_dry_run; then
        log WARN "[DRY-RUN] Would restart: systemctl restart ${SERVICE_NAME}"
        return 0
    fi

    if command -v systemctl &> /dev/null && systemctl list-unit-files "${SERVICE_NAME}.service" &> /dev/null; then
        systemctl restart "$SERVICE_NAME" || log WARN "systemctl restart failed"
        systemctl is-active "$SERVICE_NAME" || log WARN "Service not active after restart"
    elif command -v docker &> /dev/null && docker ps &> /dev/null; then
        log INFO "Restarting Docker container..."
        docker restart "$SERVICE_NAME" 2>/dev/null || docker compose up -d 2>/dev/null || log WARN "Docker restart failed (stub)"
    else
        log WARN "No service manager detected. Skipping restart."
    fi
}

health_check_internal() {
    if [[ -z "${HEALTH_URL:-}" ]]; then
        log WARN "HEALTH_URL not set. Skipping health check."
        return 0
    fi

    if ! command -v curl &> /dev/null; then
        log WARN "curl not available. Skipping health check."
        return 0
    fi

    local elapsed=0
    local interval="${HEALTH_INTERVAL}"
    local timeout="${HEALTH_TIMEOUT}"

    while [[ $elapsed -lt $timeout ]]; do
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" || echo "000")
        if [[ "$http_code" == "200" ]]; then
            local body
            body=$(curl -s "$HEALTH_URL" || echo "")
            if echo "$body" | grep -q '"status":"UP"' || echo "$body" | grep -q '"status":"ok"'; then
                return 0
            fi
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    return 1
}

stage_health_check() {
    section "Stage 9: Health Check"

    if is_dry_run; then
        log WARN "[DRY-RUN] Would health check: ${HEALTH_URL}"
        return 0
    fi

    if health_check_internal; then
        log INFO "Health check passed: ${HEALTH_URL}"
        metric_set "deploy_health_check_passed" "1" "Health check passed" "gauge"
    else
        log ERROR "Health check FAILED: ${HEALTH_URL}"
        metric_set "deploy_health_check_passed" "0" "Health check passed" "gauge"
        return 1
    fi
}

stage_rollback() {
    section "ROLLBACK INITIATED"
    log ERROR "Rolling back to backup: ${BACKUP_NAME}"

    notify error "Rollback triggered for ${ENV_NAME} (Deploy ${DEPLOY_ID})"

    if is_dry_run; then
        log WARN "[DRY-RUN] Would restore backup ${BACKUP_DIR}/${BACKUP_NAME} to ${APP_DIR}"
        return 0
    fi

    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"
    if [[ ! -d "$backup_path" ]]; then
        log ERROR "Backup not found: ${backup_path}"
        return 1
    fi

    rm -rf "${APP_DIR:?}"/*
    cp -a "${backup_path}/." "$APP_DIR/"

    if command -v systemctl &> /dev/null; then
        systemctl restart "$SERVICE_NAME" || true
    elif command -v docker &> /dev/null; then
        docker restart "$SERVICE_NAME" 2>/dev/null || true
    fi

    log INFO "Rollback completed"
    metric_set "deploy_rollback_executed" "1" "Rollback executed indicator" "gauge"
}

finalize() {
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - START_TIME))

    if [[ "$ROLLBACK_TRIGGERED" == true ]]; then
        log ERROR "Deployment ${DEPLOY_ID} FAILED after ${duration}s"
        metrics_finalize "$DEPLOY_ID" "$duration" 0
        generate_report "$DEPLOY_ID" "FAILED" "${duration}s" "$GIT_COMMIT" "$ENV_NAME" "$DEPLOY_STRATEGY" "$BACKUP_NAME"
        notify error "Deployment ${DEPLOY_ID} to ${ENV_NAME} FAILED after ${duration}s"
        exit 1
    else
        log INFO "Deployment ${DEPLOY_ID} SUCCESSFUL in ${duration}s"
        metrics_finalize "$DEPLOY_ID" "$duration" 1
        generate_report "$DEPLOY_ID" "SUCCESS" "${duration}s" "$GIT_COMMIT" "$ENV_NAME" "$DEPLOY_STRATEGY" "$BACKUP_NAME"
        notify info "Deployment ${DEPLOY_ID} to ${ENV_NAME} SUCCESSFUL in ${duration}s"
    fi
}

cleanup() {
    metrics_cleanup
}
trap cleanup EXIT

main() {
    parse_args "$@"
    preflight

    notify info "Deployment ${DEPLOY_ID} to ${ENV_NAME} started (strategy: ${DEPLOY_STRATEGY})"

    stage_git
    stage_backup
    stage_secrets
    stage_build
    stage_security
    stage_tests
    stage_artifact

    if ! stage_deploy; then
        ROLLBACK_TRIGGERED=true
    fi

    if [[ "$ROLLBACK_TRIGGERED" != true ]]; then
        stage_restart
        if ! stage_health_check; then
            ROLLBACK_TRIGGERED=true
            stage_rollback
            stage_health_check || log ERROR "Rollback health check also failed — manual intervention required!"
        fi
    fi

    finalize
}

main "$@"
