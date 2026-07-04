#!/usr/bin/env bash
# Create an OpenCloud app token for register-api Graph auth and update register-api/.env.
# OpenCloud rejects password Basic auth when PROXY_ENABLE_BASIC_AUTH=false (default).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ROOT}/register-api/.env"
OC_CONTAINER="${OPENCLOUD_CONTAINER:-opencloud-opencloud-1}"
SERVICE_USER="${GRAPH_SERVICE_USER:-admin}"
EXPIRES_IN="${GRAPH_TOKEN_EXPIRES_IN:-90d}"
DO_RESTART=1

usage() {
  cat <<EOF
Usage: $0 [--user USERNAME] [--container CONTAINER] [--expires-in DURATION] [--no-restart]

Creates an app token via opencloud auth-app create and writes GRAPH_SERVICE_APP_TOKEN
and GRAPH_SERVICE_APP_TOKEN_EXPIRES_AT to register-api/.env. Restarts register-api
when docker compose is available (unless --no-restart).

DURATION examples: 90d (default), 2160h, 72h. OpenCloud accepts hours/minutes/seconds only;
days are converted to hours (90d → 2160h).

Defaults: user=admin, container=${OC_CONTAINER}, expires-in=90d
EOF
}

# Convert 90d / 2160h / 30m to OpenCloud --expiration value (e.g. 2160h).
parse_expires_in() {
  local spec="$1"
  if [[ "$spec" =~ ^([0-9]+)[dD]$ ]]; then
    echo "$((${BASH_REMATCH[1]} * 24))h"
  elif [[ "$spec" =~ ^([0-9]+)([hmsHMS])$ ]]; then
    echo "${BASH_REMATCH[1]}${BASH_REMATCH[2],,}"
  else
    echo "Invalid --expires-in value: ${spec} (use e.g. 90d, 2160h, 72h)" >&2
    return 1
  fi
}

# Hours from DURATION for computing GRAPH_SERVICE_APP_TOKEN_EXPIRES_AT.
expires_in_hours() {
  local spec="$1"
  if [[ "$spec" =~ ^([0-9]+)[dD]$ ]]; then
    echo "$((${BASH_REMATCH[1]} * 24))"
  elif [[ "$spec" =~ ^([0-9]+)[hH]$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$spec" =~ ^([0-9]+)[mM]$ ]]; then
    echo "$((${BASH_REMATCH[1]} / 60))"
  elif [[ "$spec" =~ ^([0-9]+)[sS]$ ]]; then
    echo "0"
  else
    return 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) SERVICE_USER="$2"; shift 2 ;;
    --container) OC_CONTAINER="$2"; shift 2 ;;
    --expires-in) EXPIRES_IN="$2"; shift 2 ;;
    --no-restart) DO_RESTART=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

OC_EXPIRATION="$(parse_expires_in "$EXPIRES_IN")"
EXPIRE_HOURS="$(expires_in_hours "$EXPIRES_IN")"
EXPIRES_AT="$(date -u -d "+${EXPIRE_HOURS} hours" +%Y-%m-%dT%H:%M:%SZ)"

if ! docker inspect "$OC_CONTAINER" >/dev/null 2>&1; then
  echo "Container not found: $OC_CONTAINER" >&2
  exit 1
fi

echo "Creating app token for user: ${SERVICE_USER} (expiration: ${EXPIRES_IN} → ${OC_EXPIRATION})"
CREATE_OUT="$(docker exec "$OC_CONTAINER" opencloud auth-app create \
  --user-name "$SERVICE_USER" \
  --expiration "$OC_EXPIRATION" 2>&1)"
TOKEN="$(printf '%s\n' "$CREATE_OUT" | sed -n 's/^ token: //p')"
if [[ -z "$TOKEN" ]]; then
  echo "Failed to parse app token from opencloud output:" >&2
  printf '%s\n' "$CREATE_OUT" >&2
  exit 1
fi

mkdir -p "$(dirname "$ENV_FILE")"
if [[ ! -f "$ENV_FILE" ]]; then
  cp "${ROOT}/register-api/.env.example" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi

set_kv() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$val" >>"$ENV_FILE"
  fi
}

set_kv "GRAPH_SERVICE_USER" "$SERVICE_USER"
set_kv "GRAPH_SERVICE_APP_TOKEN" "$TOKEN"
set_kv "GRAPH_SERVICE_APP_TOKEN_EXPIRES_AT" "$EXPIRES_AT"
# Password auth does not work with PROXY_ENABLE_BASIC_AUTH=false; remove stale value.
sed -i '/^GRAPH_SERVICE_PASSWORD=/d' "$ENV_FILE"

chmod 600 "$ENV_FILE"
echo "Updated ${ENV_FILE} (GRAPH_SERVICE_APP_TOKEN set; expires ${EXPIRES_AT}; GRAPH_SERVICE_PASSWORD removed)."

if [[ "$DO_RESTART" -eq 1 && -f "${ROOT}/register-api/docker-compose.yml" ]]; then
  (cd "${ROOT}/register-api" && docker compose up -d --build register-api)
  echo "register-api restarted."
fi

HEALTH="$(curl -sf "http://127.0.0.1:8091/health" 2>/dev/null || true)"
if [[ -n "$HEALTH" ]]; then
  echo "Health: $HEALTH"
  if ! printf '%s' "$HEALTH" | grep -qE '"graph_auth_ok"[[:space:]]*:[[:space:]]*true'; then
    echo "WARNING: graph_auth_ok is not true — verify token user can POST /graph/v1.0/users." >&2
    exit 1
  fi
fi

echo "Done. User ${SERVICE_USER} must have permission to create users (admin or delegated role)."
