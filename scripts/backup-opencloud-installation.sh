#!/usr/bin/env bash
# Full OpenCloud installation backup: /opt/opencloud, host nginx, served HTML,
# Let's Encrypt certs, OIDC credential files, and Docker volumes (opencloud + dex).
# Writes an expanded tree under BACKUP_ROOT/<stamp>/ and a timestamped .tar.gz archive.
#
# Usage:
#   sudo /opt/opencloud/scripts/backup-opencloud-installation.sh
#
# Includes host nginx (/etc/nginx/sites-available/opencloud*) and HTML
# (/var/www/opencloud-auth, /var/www/certbot). Restore: see
# backup-opencloud-installation.README.md in this directory.
#
# Environment overrides:
#   BACKUP_ROOT=/opt/backup_opencloud_installation
#   OPENCLOUD_DIR=/opt/opencloud
#   TLS_DOMAIN=cloud.km0digital.com
#   KEEP_EXPANDED=true   # set to false to remove the directory after creating the tar
set -euo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-/opt/backup_opencloud_installation}"
OPENCLOUD_DIR="${OPENCLOUD_DIR:-/opt/opencloud}"
TLS_DOMAIN="${TLS_DOMAIN:-cloud.km0digital.com}"
KEEP_EXPANDED="${KEEP_EXPANDED:-true}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="${BACKUP_ROOT}/${STAMP}"
TAR_NAME="opencloud-installation-backup-${STAMP}.tar.gz"
TAR_PATH="${BACKUP_ROOT}/${TAR_NAME}"
ALPINE_IMAGE="${ALPINE_IMAGE:-alpine:3.19}"

log() {
  echo "[$(date +%H:%M:%S)] $*" | tee -a "${DEST}/manifest/backup.log"
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Error: run as root (nginx, letsencrypt, /var/www)." >&2
    exit 1
  fi
}

backup_docker_volume() {
  local cname="$1"
  local outname="$2"
  if docker volume inspect "${cname}" &>/dev/null; then
    log "Docker volume: ${cname}"
    docker run --rm \
      -v "${cname}:/from:ro" \
      -v "${DEST}/docker-volumes:/backup" \
      "${ALPINE_IMAGE}" \
      tar czf "/backup/${outname}-${STAMP}.tar.gz" -C /from .
  else
    log "SKIP missing docker volume: ${cname}"
  fi
}

main() {
  require_root

  mkdir -p "${DEST}"/{opt-opencloud,host-nginx,host-www,letsencrypt,docker-volumes,opt-credentials,manifest}
  log "Backup started -> ${DEST}"

  # 1) /opt/opencloud
  log "Sync ${OPENCLOUD_DIR}/"
  rsync -a \
    --exclude '.git/objects/pack' \
    "${OPENCLOUD_DIR}/" "${DEST}/opt-opencloud/"

  # 2) Host nginx (active site + ACME bootstrap + repo templates)
  log "Host nginx configs"
  for f in opencloud opencloud-acme-bootstrap; do
    if [[ -f "/etc/nginx/sites-available/${f}" ]]; then
      cp -a "/etc/nginx/sites-available/${f}" "${DEST}/host-nginx/${f}"
    fi
  done
  if [[ -L /etc/nginx/sites-enabled/opencloud ]]; then
    readlink -f /etc/nginx/sites-enabled/opencloud > "${DEST}/host-nginx/sites-enabled-opencloud-target.txt"
    ls -la /etc/nginx/sites-enabled/opencloud > "${DEST}/host-nginx/sites-enabled-opencloud-ls.txt"
  fi
  if [[ -d "${OPENCLOUD_DIR}/nginx" ]]; then
    cp -a "${OPENCLOUD_DIR}/nginx/" "${DEST}/host-nginx/repo-nginx/"
  fi

  # 3) Static www (login picker + certbot ACME webroot)
  log "Host www: opencloud-auth, certbot"
  if [[ -d /var/www/opencloud-auth ]]; then
    rsync -a /var/www/opencloud-auth/ "${DEST}/host-www/opencloud-auth/"
  fi
  if [[ -d /var/www/certbot ]]; then
    rsync -a /var/www/certbot/ "${DEST}/host-www/certbot/"
  fi

  # 4) Let's Encrypt for OpenCloud domain
  log "TLS certs for ${TLS_DOMAIN}"
  for sub in live archive renewal; do
    if [[ -e "/etc/letsencrypt/${sub}/${TLS_DOMAIN}" ]] \
      || [[ -f "/etc/letsencrypt/${sub}/${TLS_DOMAIN}.conf" ]]; then
      mkdir -p "${DEST}/letsencrypt/${sub}"
      shopt -s nullglob
      for item in "/etc/letsencrypt/${sub}/${TLS_DOMAIN}"*; do
        cp -aL "${item}" "${DEST}/letsencrypt/${sub}/"
      done
      shopt -u nullglob
    fi
  done

  # 5) OIDC credential files (paths referenced in docs)
  log "OIDC credential files from /opt"
  for f in \
    /opt/google-client-secret.json \
    /opt/apple-signin-credentials.json \
    /opt/apple-signin-credentials.example.json; do
    if [[ -f "${f}" ]]; then
      cp -a "${f}" "${DEST}/opt-credentials/"
    fi
  done

  # 6) Docker named volumes
  log "Docker volumes"
  backup_docker_volume opencloud_opencloud-config opencloud-config
  backup_docker_volume opencloud_opencloud-data opencloud-data
  backup_docker_volume dex_dex-data dex-data

  # 7) Runtime snapshot
  {
    echo "=== backup stamp ==="
    echo "${STAMP}"
    echo "=== tar archive ==="
    echo "${TAR_PATH}"
    echo "=== docker ps (opencloud/dex) ==="
    docker ps -a --filter name=opencloud --filter name=dex 2>/dev/null || true
    echo "=== docker volume ls (opencloud/dex) ==="
    docker volume ls 2>/dev/null | grep -E 'opencloud|dex' || true
    echo "=== nginx -t ==="
    nginx -t 2>&1 || true
  } > "${DEST}/manifest/runtime-snapshot.txt"

  cat > "${DEST}/README.txt" <<EOF
OpenCloud installation backup
Created: $(date -Is)
Expanded directory: ${DEST}
Archive: ${TAR_PATH}

Contents:
  opt-opencloud/     - copy of ${OPENCLOUD_DIR}
  host-nginx/        - /etc/nginx sites + repo nginx templates
  host-www/          - /var/www/opencloud-auth, /var/www/certbot
  letsencrypt/       - TLS for ${TLS_DOMAIN}
  opt-credentials/   - Google/Apple OIDC JSON from /opt
  docker-volumes/    - tar.gz of opencloud-config, opencloud-data, dex-data
  manifest/          - logs and runtime snapshot

Restore: extract ${TAR_NAME}, then copy paths back to their original locations.
EOF

  # 8) Timestamped tar archive (top-level folder = stamp name)
  log "Creating archive ${TAR_PATH}"
  tar -czf "${TAR_PATH}" -C "${BACKUP_ROOT}" "${STAMP}"

  ln -sfn "${DEST}" "${BACKUP_ROOT}/latest"
  ln -sfn "${TAR_PATH}" "${BACKUP_ROOT}/latest.tar.gz"

  if [[ "${KEEP_EXPANDED}" != "true" ]]; then
    log "Removing expanded directory (KEEP_EXPANDED=false)"
    rm -rf "${DEST}"
  fi

  log "Done."
  echo ""
  echo "Expanded backup: ${DEST}"
  echo "Tar archive:     ${TAR_PATH}"
  du -sh "${DEST}" "${TAR_PATH}" 2>/dev/null || du -sh "${TAR_PATH}"
}

main "$@"
