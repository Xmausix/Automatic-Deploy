# Automatic Deploy — documentation

## Purpose

This tool runs a controlled application deployment: it validates configuration, fetches the selected branch, creates a backup, builds and tests the application, optionally scans an image, deploys, restarts the service, and performs a health check. A failed health check triggers rollback.

## Requirements

Bash 4.2+, Git, and the tools used by the selected project. `curl`, `rsync`, Docker, systemd, `jq`, Vault, Trivy/Grype, GPG, and `dialog` are optional integrations.

## Configuration

Edit the appropriate file in `config/`. Key variables:

| Variable | Meaning |
|---|---|
| `APP_DIR` | application directory |
| `BRANCH` | branch to deploy |
| `SERVICE_NAME` | systemd service or container |
| `DEPLOY_STRATEGY` | `local`, `rolling`, `blue-green`, or `canary` |
| `HOSTS` | space-separated hosts; use `localhost` for local deployment |
| `HEALTH_URL` | readiness endpoint |
| `HEALTH_TIMEOUT` | health-check timeout in seconds |
| `VAULT_PATH` | optional Vault KV path |

Keep webhooks and tokens outside the repository, for example in a secret manager or the process environment.

## Usage

```bash
./deploy.sh development --dry-run
./deploy.sh staging --strategy rolling
./deploy.sh production --strategy blue-green
./deploy.sh production --skip-tests
./rollback.sh production backup_YYYYMMDD_HHMMSS_production --dry-run
./menu.sh
```

`--skip-tests` and `--skip-security` are explicit escape hatches and should be exceptional. `--parallel` deploys to multiple hosts concurrently; use it only when the application and infrastructure support it.

## Flow and artifacts

Logs are written to `logs/`, backups to `backups/`, artifacts to `releases/`, and reports to `reports/`. Prometheus metrics are written as `.prom` files. Do not commit these directories or files containing secrets.

## Production operations

1. Verify configuration and directory permissions.
2. Run a dry run.
3. Run tests and security scanning.
4. Monitor health checks, logs, and the generated report.
5. If deployment fails, roll back and verify service health.

The simple ChatOps listener is demonstrational. For production, use an authenticated endpoint behind a reverse proxy with signature validation, access controls, rate limiting, and a job queue.
