#!/usr/bin/env bash
# Copia de seguridad de los volúmenes definidos en el compose actual (datos + config OpenCloud).
# No hace pg_dump: el stack núcleo oficial no incluye Postgres.
# Requisitos: docker, compose v2, .env en el directorio del stack.
set -euo pipefail

COMPOSE_DIR="${COMPOSE_DIR:-/opt/opencloud/opencloud-compose}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/opencloud}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="${BACKUP_ROOT}/${STAMP}"

if [[ ! -f "${COMPOSE_DIR}/.env" ]]; then
  echo "Error: no existe ${COMPOSE_DIR}/.env (copia y rellena desde .env.debian-core-external-proxy.example)" >&2
  exit 1
fi

mkdir -p "${DEST}"
cd "${COMPOSE_DIR}"

set -a
# shellcheck disable=SC1091
source .env
set +a

PROJECT="${COMPOSE_PROJECT_NAME:-$(basename "${COMPOSE_DIR}")}"

mapfile -t VOLUMES < <(docker compose config --volumes | sort -u)
if [[ ${#VOLUMES[@]} -eq 0 ]]; then
  echo "Error: no se pudo listar volúmenes (¿docker compose falló?)." >&2
  exit 1
fi

for vol in "${VOLUMES[@]}"; do
  cname="${PROJECT}_${vol}"
  if ! docker volume inspect "${cname}" &>/dev/null; then
    echo "Advertencia: el volumen Docker '${cname}' no existe (omito). Levanta el stack antes si es la primera vez." >&2
    continue
  fi
  echo "Respaldando ${cname} -> ${DEST}/${vol}-${STAMP}.tar.gz"
  docker run --rm \
    -v "${cname}:/from:ro" \
    -v "${DEST}:/backup" \
    alpine:3.19 \
    tar czf "/backup/${vol}-${STAMP}.tar.gz" -C /from .
done

echo "Listo. Artefactos en: ${DEST}"
ls -la "${DEST}"
