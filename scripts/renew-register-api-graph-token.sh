#!/usr/bin/env bash
# Safely renew the Graph App Token used by register-api.
#
# This script must only:
# - generate a new Graph App Token for register-api
# - update GRAPH_SERVICE_APP_TOKEN (and expiry metadata) in register-api/.env
# - restart register-api
# - verify /health
#
# It must never delete or modify users, volumes, storage, databases,
# OAuth/OIDC configuration, Dex configuration, or unrelated OpenCloud settings.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGISTER_API_DIR="${ROOT}/register-api"
ENV_FILE="${REGISTER_API_DIR}/.env"
SETUP_SCRIPT="${ROOT}/scripts/setup-register-api-graph-token.sh"
VERIFY_SCRIPT="${ROOT}/scripts/verify-register-api.sh"
RENEW_THRESHOLD_DAYS="${GRAPH_TOKEN_RENEW_THRESHOLD_DAYS:-14}"
EXPIRES_IN="${GRAPH_TOKEN_EXPIRES_IN:-90d}"
FORCE=0

usage() {
  cat <<EOF
Usage: $0 [--force] [--threshold-days N] [--expires-in DURATION]

Checks register-api Graph token expiry and health; renews when:
  - graph_auth_ok is false, or
  - fewer than ${RENEW_THRESHOLD_DAYS} days remain before GRAPH_SERVICE_APP_TOKEN_EXPIRES_AT

With --force, always renew regardless of expiry/health.

Safe scope: register-api/.env token fields + register-api container only.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --threshold-days) RENEW_THRESHOLD_DAYS="$2"; shift 2 ;;
    --expires-in) EXPIRES_IN="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

if [[ ! -x "$SETUP_SCRIPT" ]]; then
  log "ERROR Missing or non-executable setup script: $SETUP_SCRIPT"
  exit 1
fi

if [[ ! -x "$VERIFY_SCRIPT" ]]; then
  log "ERROR Missing or non-executable verify script: $VERIFY_SCRIPT"
  exit 1
fi

health_json() {
  curl -sf "http://127.0.0.1:8091/health" 2>/dev/null || true
}

graph_auth_ok() {
  local health="$1"
  printf '%s' "$health" | grep -qE '"graph_auth_ok"[[:space:]]*:[[:space:]]*true'
}

read_env_kv() {
  local key="$1"
  if [[ ! -f "$ENV_FILE" ]]; then
    return 1
  fi
  grep -m1 "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true
}

read_expires_at() {
  read_env_kv "GRAPH_SERVICE_APP_TOKEN_EXPIRES_AT"
}

read_service_user() {
  local user
  user="$(read_env_kv "GRAPH_SERVICE_USER" || true)"
  if [[ -n "$user" ]]; then
    printf '%s' "$user"
    return 0
  fi
  if [[ -n "${GRAPH_SERVICE_USER:-}" ]]; then
    printf '%s' "$GRAPH_SERVICE_USER"
  fi
}

wait_for_graph_auth() {
  local max_wait="${REGISTER_API_HEALTH_WAIT_SEC:-30}"
  local interval=2
  local elapsed=0
  local health=""
  while [[ "$elapsed" -lt "$max_wait" ]]; do
    health="$(health_json)"
    if [[ -n "$health" ]] && graph_auth_ok "$health"; then
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  log "ERROR register-api did not report graph_auth_ok:true within ${max_wait}s (last: ${health:-empty})"
  return 1
}

days_until_expiry() {
  local expires_at="$1"
  local expires_epoch now_epoch
  expires_epoch="$(date -d "$expires_at" +%s 2>/dev/null || echo "")"
  if [[ -z "$expires_epoch" ]]; then
    return 1
  fi
  now_epoch="$(date +%s)"
  echo $(( (expires_epoch - now_epoch) / 86400 ))
}

NEED_RENEW=0
REASON=""

if [[ "$FORCE" -eq 1 ]]; then
  NEED_RENEW=1
  REASON="--force"
else
  HEALTH="$(health_json)"
  if [[ -n "$HEALTH" ]] && ! graph_auth_ok "$HEALTH"; then
    NEED_RENEW=1
    REASON="graph_auth_ok is false"
  else
    EXPIRES_AT="$(read_expires_at)"
    if [[ -z "$EXPIRES_AT" ]]; then
      if [[ -n "$HEALTH" ]] && graph_auth_ok "$HEALTH"; then
        log "INFO No GRAPH_SERVICE_APP_TOKEN_EXPIRES_AT in ${ENV_FILE}; health OK — skipping renewal (run setup once to record expiry)"
        exit 0
      fi
      NEED_RENEW=1
      REASON="missing token expiry metadata"
    else
      DAYS_LEFT="$(days_until_expiry "$EXPIRES_AT" || echo "")"
      if [[ -z "$DAYS_LEFT" ]]; then
        log "WARNING Could not parse expiry ${EXPIRES_AT}; treating as renewal required"
        NEED_RENEW=1
        REASON="unparseable expiry date"
      elif [[ "$DAYS_LEFT" -lt "$RENEW_THRESHOLD_DAYS" ]]; then
        NEED_RENEW=1
        REASON="${DAYS_LEFT} day(s) remaining (< ${RENEW_THRESHOLD_DAYS})"
      else
        log "INFO Token valid for ${DAYS_LEFT} more day(s) (threshold ${RENEW_THRESHOLD_DAYS}); skipping renewal"
        exit 0
      fi
    fi
  fi
fi

if [[ "$NEED_RENEW" -ne 1 ]]; then
  log "INFO No renewal needed"
  exit 0
fi

SERVICE_USER="$(read_service_user || true)"
if [[ -z "$SERVICE_USER" ]]; then
  SERVICE_USER="admin"
fi

log "INFO Starting register-api Graph token renewal (${REASON})"
log "INFO Generating new token for user ${SERVICE_USER} (expires-in ${EXPIRES_IN})"
"$SETUP_SCRIPT" --user "$SERVICE_USER" --expires-in "$EXPIRES_IN" --no-restart

log "INFO Restarting register-api only"
cd "$REGISTER_API_DIR"
docker compose up -d --build register-api

log "INFO Waiting for register-api health"
wait_for_graph_auth

log "INFO Verifying register-api health"
"$VERIFY_SCRIPT"

log "INFO register-api Graph token renewal completed successfully"
