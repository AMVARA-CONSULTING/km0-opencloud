#!/usr/bin/env bash
# Regenerate OpenCloud built-in IDM LDAPS certificate with SANs for Dex.
#
# Default auto-generated cert only includes localhost/127.0.0.1. Dex reaches IDM
# at opencloud:9235 on opencloud_opencloud-net and needs DNS:opencloud in the SAN.
#
# Usage:
#   ./scripts/regenerate-opencloud-idm-ldap-cert.sh
#   ./scripts/regenerate-opencloud-idm-ldap-cert.sh --restart
#
# Environment:
#   OPENCLOUD_DATA_VOLUME=opencloud_opencloud-data
#   OPENCLOUD_LDAP_HOST=opencloud
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_VOLUME="${OPENCLOUD_DATA_VOLUME:-opencloud_opencloud-data}"
IDM_DIR="${OPENCLOUD_IDM_DIR:-/var/lib/docker/volumes/${DATA_VOLUME}/_data/idm}"
LDAP_HOST="${OPENCLOUD_LDAP_HOST:-opencloud}"
RESTART=false

for arg in "$@"; do
  case "$arg" in
    --restart) RESTART=true ;;
    -h|--help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [[ ! -d "${IDM_DIR}" ]]; then
  echo "Error: IDM directory not found: ${IDM_DIR}" >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "Error: openssl required on the host." >&2
  exit 1
fi

echo "Regenerating IDM LDAP cert in ${IDM_DIR} (SAN: localhost, ${LDAP_HOST}, 127.0.0.1)..."

ts="$(date +%Y%m%d-%H%M%S)"
for f in ldap.crt ldap.key; do
  if [[ -f "${IDM_DIR}/${f}" ]]; then
    cp -a "${IDM_DIR}/${f}" "${IDM_DIR}/${f}.bak-${ts}"
  fi
done

openssl req -x509 -newkey rsa:4096 \
  -keyout "${IDM_DIR}/ldap.key" \
  -out "${IDM_DIR}/ldap.crt" \
  -days 825 -sha256 -nodes -batch \
  -subj '/O=Acme Corp/CN=OpenCloud' \
  -addext "subjectAltName=DNS:localhost,DNS:${LDAP_HOST},IP:127.0.0.1"

chmod 600 "${IDM_DIR}/ldap.key"
chmod 644 "${IDM_DIR}/ldap.crt"

openssl x509 -in "${IDM_DIR}/ldap.crt" -noout -subject -ext subjectAltName

if [[ "${RESTART}" == true ]]; then
  echo "Restarting OpenCloud and Dex..."
  (cd "${REPO_ROOT}/opencloud-compose" && docker compose restart opencloud)
  (cd "${REPO_ROOT}/dex" && docker compose up -d --force-recreate)
fi

echo "Done. Restart opencloud (and dex) if you did not pass --restart."
