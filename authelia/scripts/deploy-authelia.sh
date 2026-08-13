#!/usr/bin/env bash
# Despliega el stack Authelia+Redis. Requiere haber ejecutado antes
# setup-authelia-secrets.sh y tener la red externa opencloud_opencloud-net
# y el volumen opencloud_opencloud-data (OpenCloud ya desplegado).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

if [[ ! -f configuration.gen.yml || ! -f .env ]]; then
  echo "Falta configuration.gen.yml o .env — ejecuta scripts/setup-authelia-secrets.sh primero." >&2
  exit 1
fi

docker compose up -d
echo "Authelia desplegado. Logs: docker compose logs -f authelia"
echo "Salud interna: curl -fsS http://127.0.0.1:9091/api/health"
