#!/usr/bin/env bash
# Create an OpenCloud app token for register-api Graph auth and update register-api/.env.
# OpenCloud rejects password Basic auth when PROXY_ENABLE_BASIC_AUTH=false (default).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ROOT}/register-api/.env"
OC_CONTAINER="${OPENCLOUD_CONTAINER:-opencloud-opencloud-1}"
SERVICE_USER="${GRAPH_SERVICE_USER:-admin}"

usage() {
  cat <<EOF
Usage: $0 [--user USERNAME] [--container CONTAINER]

Creates an app token via opencloud auth-app create and writes GRAPH_SERVICE_APP_TOKEN
to register-api/.env. Restarts register-api when docker compose is available.

Defaults: user=admin, container=${OC_CONTAINER}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) SERVICE_USER="$2"; shift 2 ;;
    --container) OC_CONTAINER="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if ! docker inspect "$OC_CONTAINER" >/dev/null 2>&1; then
  echo "Container not found: $OC_CONTAINER" >&2
  exit 1
fi

echo "Creating app token for user: ${SERVICE_USER}"
CREATE_OUT="$(docker exec "$OC_CONTAINER" opencloud auth-app create --user-name "$SERVICE_USER" 2>&1)"
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
# Password auth does not work with PROXY_ENABLE_BASIC_AUTH=false; remove stale value.
sed -i '/^GRAPH_SERVICE_PASSWORD=/d' "$ENV_FILE"

chmod 600 "$ENV_FILE"
echo "Updated ${ENV_FILE} (GRAPH_SERVICE_APP_TOKEN set; GRAPH_SERVICE_PASSWORD removed)."

if [[ -f "${ROOT}/register-api/docker-compose.yml" ]]; then
  (cd "${ROOT}/register-api" && docker compose up -d --build)
  echo "register-api restarted."
fi

HEALTH="$(curl -sf "http://127.0.0.1:8091/health" 2>/dev/null || true)"
if [[ -n "$HEALTH" ]]; then
  echo "Health: $HEALTH"
  if ! printf '%s' "$HEALTH" | grep -q '"graph_auth_ok":'; then
    echo "WARNING: graph_auth_ok is not true — verify token user can POST /graph/v1.0/users." >&2
    exit 1
  fi
fi

echo "Done. User ${SERVICE_USER} must have permission to create users (admin or delegated role)."
