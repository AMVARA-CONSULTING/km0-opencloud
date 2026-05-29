#!/usr/bin/env bash
# Apply KM0 overrides and start OpenCloud + Collabora + WOPI stack.
# Requires opencloud-compose/.env with collabora variables (see
# overrides/opencloud-compose/.env.debian-collabora-external-proxy.example).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_DIR="${COMPOSE_DIR:-${REPO_ROOT}/opencloud-compose}"
ENV_FILE="${COMPOSE_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Copy the collabora .env example first." >&2
  exit 1
fi

if ! grep -q 'weboffice/collabora.yml' "${ENV_FILE}"; then
  echo "COMPOSE_FILE in ${ENV_FILE} does not include weboffice/collabora.yml." >&2
  echo "Use overrides/opencloud-compose/.env.debian-collabora-external-proxy.example as reference." >&2
  exit 1
fi

for var in COLLABORA_DOMAIN WOPISERVER_DOMAIN COLLABORA_ADMIN_PASSWORD; do
  if ! grep -q "^${var}=" "${ENV_FILE}"; then
    echo "Missing ${var} in ${ENV_FILE}." >&2
    exit 1
  fi
done

"${REPO_ROOT}/scripts/apply-opencloud-compose-overrides.sh"

cd "${COMPOSE_DIR}"
docker compose pull
docker compose up -d

echo "Waiting for collabora healthcheck..."
for _ in $(seq 1 30); do
  if docker compose ps collabora 2>/dev/null | grep -q '(healthy)'; then
    echo "collabora is healthy."
    docker compose ps
    exit 0
  fi
  sleep 5
done

echo "collabora not healthy yet — check: docker compose logs collabora collaboration opencloud" >&2
docker compose ps
exit 1
