#!/usr/bin/env bash
# Backup OpenCloud user data (opencloud-data Docker volume) to /data with rotation.
#
# - Runs every 5 days via /etc/cron.d/opencloud-user-backup
# - Keeps MAX_BACKUPS archives; deletes the oldest only after a new backup succeeds
# - Checks destination mount free space before starting; aborts without deleting anything
# - Notifies Discord on insufficient space (DISCORD_WEBHOOK_URL or /etc/amvara/disk-alert.env)
#
# Usage:
#   sudo /opt/opencloud/scripts/backup-user-data.sh
#
# Environment overrides:
#   BACKUP_ROOT=/data/opencloud-backup/user-data
#   MAX_BACKUPS=5
#   VOLUME_NAME=opencloud_opencloud-data
#   SPACE_MARGIN_PERCENT=10
set -euo pipefail

COMPOSE_DIR="${COMPOSE_DIR:-/opt/opencloud/opencloud-compose}"
BACKUP_ROOT="${BACKUP_ROOT:-/data/opencloud-backup/user-data}"
MAX_BACKUPS="${MAX_BACKUPS:-5}"
SPACE_MARGIN_PERCENT="${SPACE_MARGIN_PERCENT:-10}"
ALPINE_IMAGE="${ALPINE_IMAGE:-alpine:3.19}"
VOLUME_NAME="${VOLUME_NAME:-opencloud_opencloud-data}"
BACKUP_PREFIX="opencloud-user-data"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="${BACKUP_ROOT}/${BACKUP_PREFIX}-${STAMP}.tar.gz"
HOSTNAMEHOOK="$(hostname -I | awk '{print $1}')"
LOG_TAG="opencloud-user-backup"

log() {
  local msg="[$(date +%Y-%m-%dT%H:%M:%S)] $*"
  echo "${msg}"
  logger -t "${LOG_TAG}" -- "${msg}"
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log "ERROR: run as root"
    exit 1
  fi
}

resolve_discord_webhook_url() {
  if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
    echo "${DISCORD_WEBHOOK_URL}"
    return 0
  fi

  if [[ -r /etc/amvara/disk-alert.env ]]; then
    # shellcheck disable=SC1091
    source /etc/amvara/disk-alert.env
  fi

  if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
    echo "${DISCORD_WEBHOOK_URL}"
    return 0
  fi

  log "ERROR: set DISCORD_WEBHOOK_URL in the environment or /etc/amvara/disk-alert.env"
  return 1
}

send_discord_alert() {
  local title="$1"
  local status="$2"
  local color="$3"
  shift 3
  local body="$*"

  local url
  url="$(resolve_discord_webhook_url)" || return 1

  local payload
  payload="$(cat <<EOF
{
  "username": "OpenCloudBackup",
  "embeds": [
    {
      "title": "${title}",
      "color": ${color},
      "description": "${body}",
      "fields": [
        {
          "name": "Host",
          "value": "${HOSTNAMEHOOK}",
          "inline": true
        },
        {
          "name": "Status",
          "value": "${status}",
          "inline": true
        },
        {
          "name": "Backup path",
          "value": "${BACKUP_ROOT}",
          "inline": false
        }
      ],
      "author": {
        "name": "Script: ${0}"
      }
    }
  ]
}
EOF
)"

  if curl -fsS -H "Content-Type: application/json" -X POST -d "${payload}" "${url}" >/dev/null; then
    log "Discord alert sent (${status})"
  else
    log "WARNING: failed to send Discord alert (${status})"
    return 1
  fi
}

bytes_to_human() {
  local kb="$1"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec-i --suffix=B --format="%.1f" "$((kb * 1024))"
  else
    echo "${kb}K"
  fi
}

get_source_size_kb() {
  local vol_path="/var/lib/docker/volumes/${VOLUME_NAME}/_data"
  if [[ -d "${vol_path}" ]]; then
    du -sk "${vol_path}" | awk '{print $1}'
    return 0
  fi

  docker volume inspect "${VOLUME_NAME}" &>/dev/null || {
    log "ERROR: Docker volume '${VOLUME_NAME}' not found"
    exit 1
  }

  docker run --rm \
    -v "${VOLUME_NAME}:/from:ro" \
    "${ALPINE_IMAGE}" \
    du -sk /from | awk '{print $1}'
}

get_mount_available_kb() {
  local mountpoint="$1"
  df -Pk "${mountpoint}" | awk 'NR==2 {gsub(/%/, "", $5); print $4}'
}

check_disk_space() {
  local source_kb required_kb available_kb mountpoint margin_kb
  local space_ref="${BACKUP_ROOT}"
  if [[ ! -e "${space_ref}" ]]; then
    space_ref="$(dirname "${BACKUP_ROOT}")"
  fi
  mountpoint="$(df -P "${space_ref}" 2>/dev/null | awk 'NR==2 {print $6}')"
  if [[ -z "${mountpoint}" ]]; then
    mountpoint="/data"
  fi

  source_kb="$(get_source_size_kb)"
  margin_kb=$((source_kb * SPACE_MARGIN_PERCENT / 100))
  required_kb=$((source_kb + margin_kb))
  available_kb="$(get_mount_available_kb "${mountpoint}")"

  log "Space check on ${mountpoint}: source=$(bytes_to_human "${source_kb}") required=$(bytes_to_human "${required_kb}") available=$(bytes_to_human "${available_kb}")"

  if [[ "${available_kb}" -lt "${required_kb}" ]]; then
    local msg="Insufficient space on ${mountpoint} for OpenCloud user-data backup. Required: $(bytes_to_human "${required_kb}") (source $(bytes_to_human "${source_kb}") + ${SPACE_MARGIN_PERCENT}% margin). Available: $(bytes_to_human "${available_kb}"). No backup created; existing archives were not deleted."
    log "ERROR: ${msg}"
    send_discord_alert \
      "OpenCloud user-data backup aborted — insufficient disk space" \
      "INSUFFICIENT_SPACE" \
      15158332 \
      "${msg}" || true
    exit 1
  fi
}

create_backup() {
  mkdir -p "${BACKUP_ROOT}"
  chmod 700 "${BACKUP_ROOT}"

  log "Creating backup ${ARCHIVE} from volume ${VOLUME_NAME}"
  docker run --rm \
    -v "${VOLUME_NAME}:/from:ro" \
    -v "${BACKUP_ROOT}:/backup" \
    "${ALPINE_IMAGE}" \
    tar czf "/backup/$(basename "${ARCHIVE}")" -C /from .

  if [[ ! -s "${ARCHIVE}" ]]; then
    log "ERROR: backup archive missing or empty: ${ARCHIVE}"
    rm -f "${ARCHIVE}"
    exit 1
  fi

  chmod 600 "${ARCHIVE}"
  log "Backup created: ${ARCHIVE} ($(du -h "${ARCHIVE}" | awk '{print $1}'))"
}

rotate_backups() {
  mapfile -t archives < <(find "${BACKUP_ROOT}" -maxdepth 1 -type f -name "${BACKUP_PREFIX}-*.tar.gz" | sort)
  local count="${#archives[@]}"

  if [[ "${count}" -le "${MAX_BACKUPS}" ]]; then
    log "Rotation: ${count}/${MAX_BACKUPS} backups present (nothing to delete)"
    return 0
  fi

  local to_delete=$((count - MAX_BACKUPS))
  log "Rotation: removing ${to_delete} oldest backup(s) (keeping ${MAX_BACKUPS})"

  local i=0
  while [[ "${i}" -lt "${to_delete}" ]]; do
    local old="${archives[$i]}"
    log "Deleting oldest backup: ${old}"
    rm -f "${old}"
    i=$((i + 1))
  done
}

update_latest_symlink() {
  ln -sfn "${ARCHIVE}" "${BACKUP_ROOT}/latest.tar.gz"
}

main() {
  require_root

  if [[ ! -f "${COMPOSE_DIR}/.env" ]]; then
    log "ERROR: missing ${COMPOSE_DIR}/.env"
    exit 1
  fi

  if ! docker volume inspect "${VOLUME_NAME}" &>/dev/null; then
    log "ERROR: Docker volume '${VOLUME_NAME}' does not exist (is the stack running?)"
    exit 1
  fi

  log "OpenCloud user-data backup started (stamp=${STAMP})"
  check_disk_space
  create_backup
  rotate_backups
  update_latest_symlink
  log "OpenCloud user-data backup finished successfully"
}

main "$@"
