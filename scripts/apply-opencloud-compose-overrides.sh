#!/usr/bin/env bash
# Aplica parches KM0 sobre un clon local de opencloud-eu/opencloud-compose.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_DIR="${COMPOSE_DIR:-${REPO_ROOT}/opencloud-compose}"
OVERRIDES="${OVERRIDES:-${REPO_ROOT}/overrides/opencloud-compose}"
PATCH="${OVERRIDES}/patches/docker-compose.oidc-env.patch"

if [[ ! -d "${COMPOSE_DIR}" ]]; then
  echo "Clonando upstream en ${COMPOSE_DIR}..."
  git clone https://github.com/opencloud-eu/opencloud-compose.git "${COMPOSE_DIR}"
fi

if [[ ! -f "${COMPOSE_DIR}/docker-compose.yml" ]]; then
  echo "Error: ${COMPOSE_DIR} no parece opencloud-compose." >&2
  exit 1
fi

echo "Copiando overrides desde ${OVERRIDES}..."
install -D -m 0644 "${OVERRIDES}/config/opencloud/csp.yaml" \
  "${COMPOSE_DIR}/config/opencloud/csp.yaml"
install -D -m 0644 "${OVERRIDES}/external-proxy/opencloud.yml" \
  "${COMPOSE_DIR}/external-proxy/opencloud.yml"

cd "${COMPOSE_DIR}"
if patch -p1 --forward --dry-run < "${PATCH}" >/dev/null 2>&1; then
  patch -p1 --forward < "${PATCH}"
  echo "Parche docker-compose.oidc-env aplicado."
elif patch -p1 -R --dry-run < "${PATCH}" >/dev/null 2>&1; then
  echo "Parche docker-compose.oidc-env ya estaba aplicado."
else
  echo "Error: no se pudo aplicar ${PATCH} (¿versión upstream distinta?)." >&2
  exit 1
fi

echo "Listo. Revisa opencloud-compose/.env (no está en Git) y ejecuta: cd ${COMPOSE_DIR} && docker compose up -d"
