#!/usr/bin/env bash
# Backup OpenCloud compose Docker volumes (config + local data volumes).
# No pg_dump: the core stack has no Postgres.
#
# - Writes timestamp dirs under BACKUP_ROOT (default /unmount/.../install-snapshots)
# - Keeps MAX_SNAPSHOTS dirs; deletes oldest only after a new backup succeeds
# - Checks destination mount free space before starting; aborts without deleting anything
# - Notifies Discord on insufficient space or backup failure
#   (DISCORD_WEBHOOK_URL or /etc/amvara/disk-alert.env)
#
# Usage:
#   sudo /opt/opencloud/scripts/backup-volumes.sh
#
# Environment overrides:
#   COMPOSE_DIR=/opt/opencloud/opencloud-compose
#   BACKUP_ROOT=/unmount/opencloud-backup/install-snapshots
#   MAX_SNAPSHOTS=2
#   SPACE_MARGIN_PERCENT=10
#   ALPINE_IMAGE=alpine:3.19
set -euo pipefail

COMPOSE_DIR="${COMPOSE_DIR:-/opt/opencloud/opencloud-compose}"
BACKUP_ROOT="${BACKUP_ROOT:-/unmount/opencloud-backup/install-snapshots}"
MAX_SNAPSHOTS="${MAX_SNAPSHOTS:-2}"
SPACE_MARGIN_PERCENT="${SPACE_MARGIN_PERCENT:-10}"
ALPINE_IMAGE="${ALPINE_IMAGE:-alpine:3.19}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="${BACKUP_ROOT}/${STAMP}"
HOSTNAMEHOOK="$(hostname -I | awk '{print $1}')"
LOG_TAG="opencloud-backup-volumes"
BACKUP_OK=0
ALERTED=0

log() {
  local msg="[$(date +%Y-%m-%dT%H:%M:%S)] $*"
  echo "${msg}"
  logger -t "${LOG_TAG}" -- "${msg}" 2>/dev/null || true
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

# Escape text for JSON string embedding (title/body).
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  printf "%s" "$s"
}

send_discord_alert() {
  local title="$1"
  local status="$2"
  local color="$3"
  shift 3
  local body="$*"

  local url
  url="$(resolve_discord_webhook_url)" || return 1

  local title_j body_j status_j path_j host_j
  title_j="$(json_escape "${title}")"
  body_j="$(json_escape "${body}")"
  status_j="$(json_escape "${status}")"
  path_j="$(json_escape "${BACKUP_ROOT}")"
  host_j="$(json_escape "${HOSTNAMEHOOK}")"

  local payload
  payload="$(cat <<EOF
{
  "username": "OpenCloudBackup",
  "embeds": [
    {
      "title": "${title_j}",
      "color": ${color},
      "description": "${body_j}",
      "fields": [
        {
          "name": "Host",
          "value": "${host_j}",
          "inline": true
        },
        {
          "name": "Status",
          "value": "${status_j}",
          "inline": true
        },
        {
          "name": "Backup path",
          "value": "${path_j}",
          "inline": false
        }
      ],
      "author": {
        "name": "Script: backup-volumes.sh"
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

get_mount_available_kb() {
  local mountpoint="$1"
  df -Pk "${mountpoint}" | awk 'NR==2 {gsub(/%/, "", $5); print $4}'
}

# Sum uncompressed size of compose volumes that exist (conservative for tar.gz).
get_source_size_kb() {
  local total=0
  local vol cname vol_path size
  for vol in "${VOLUMES[@]}"; do
    cname="${PROJECT}_${vol}"
    if ! docker volume inspect "${cname}" &>/dev/null; then
      continue
    fi
    vol_path="/var/lib/docker/volumes/${cname}/_data"
    if [[ -d "${vol_path}" ]]; then
      size="$(du -sk "${vol_path}" | awk '{print $1}')"
    else
      size="$(docker run --rm -v "${cname}:/from:ro" "${ALPINE_IMAGE}" du -sk /from | awk '{print $1}')"
    fi
    total=$((total + size))
  done
  echo "${total}"
}

check_disk_space() {
  local source_kb required_kb available_kb mountpoint margin_kb
  local space_ref="${BACKUP_ROOT}"
  if [[ ! -e "${space_ref}" ]]; then
    space_ref="$(dirname "${BACKUP_ROOT}")"
  fi
  mountpoint="$(df -P "${space_ref}" 2>/dev/null | awk 'NR==2 {print $6}')"
  if [[ -z "${mountpoint}" ]]; then
    mountpoint="/unmount"
  fi

  source_kb="$(get_source_size_kb)"
  if [[ "${source_kb}" -le 0 ]]; then
    log "ERROR: source size is 0 (no Docker volumes found to back up)"
    ALERTED=1
    send_discord_alert \
      "OpenCloud install-snapshots backup aborted — no volumes" \
      "NO_VOLUMES" \
      15158332 \
      "No existing compose volumes found under project ${PROJECT}. Nothing backed up." || true
    exit 1
  fi

  margin_kb=$((source_kb * SPACE_MARGIN_PERCENT / 100))
  required_kb=$((source_kb + margin_kb))
  available_kb="$(get_mount_available_kb "${mountpoint}")"

  log "Space check on ${mountpoint}: source=$(bytes_to_human "${source_kb}") required=$(bytes_to_human "${required_kb}") available=$(bytes_to_human "${available_kb}")"

  if [[ "${available_kb}" -lt "${required_kb}" ]]; then
    local msg="Insufficient space on ${mountpoint} for OpenCloud install-snapshots backup. Required: $(bytes_to_human "${required_kb}") (source $(bytes_to_human "${source_kb}") + ${SPACE_MARGIN_PERCENT}% margin). Available: $(bytes_to_human "${available_kb}"). No backup created; existing snapshots were not deleted."
    log "ERROR: ${msg}"
    ALERTED=1
    send_discord_alert \
      "OpenCloud install-snapshots backup aborted — insufficient disk space" \
      "INSUFFICIENT_SPACE" \
      15158332 \
      "${msg}" || true
    exit 1
  fi
}

create_backup() {
  mkdir -p "${DEST}"
  local vol cname
  local backed=0
  for vol in "${VOLUMES[@]}"; do
    cname="${PROJECT}_${vol}"
    if ! docker volume inspect "${cname}" &>/dev/null; then
      log "WARNING: Docker volume '${cname}' does not exist (skip)"
      continue
    fi
    log "Backing up ${cname} -> ${DEST}/${vol}-${STAMP}.tar.gz"
    docker run --rm \
      -v "${cname}:/from:ro" \
      -v "${DEST}:/backup" \
      "${ALPINE_IMAGE}" \
      tar czf "/backup/${vol}-${STAMP}.tar.gz" -C /from .
    if [[ ! -s "${DEST}/${vol}-${STAMP}.tar.gz" ]]; then
      log "ERROR: archive missing or empty: ${DEST}/${vol}-${STAMP}.tar.gz"
      rm -rf -- "${DEST}"
      ALERTED=1
      send_discord_alert \
        "OpenCloud install-snapshots backup failed — empty archive" \
        "EMPTY_ARCHIVE" \
        15158332 \
        "Archive for volume ${cname} was missing or empty. Partial stamp dir ${DEST} was removed. Existing snapshots were not deleted." || true
      exit 1
    fi
    backed=$((backed + 1))
  done

  if [[ "${backed}" -eq 0 ]]; then
    log "ERROR: no volumes backed up"
    rm -rf -- "${DEST}"
    ALERTED=1
    send_discord_alert \
      "OpenCloud install-snapshots backup failed — no volumes" \
      "NO_VOLUMES" \
      15158332 \
      "No compose volumes were backed up. Partial stamp dir removed." || true
    exit 1
  fi

  log "Backup created in ${DEST} (${backed} volume archive(s))"
  ls -la "${DEST}"
}

rotate_snapshots() {
  mapfile -t snaps < <(find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort)
  local count="${#snaps[@]}"
  if [[ "${count}" -le "${MAX_SNAPSHOTS}" ]]; then
    log "Rotation: ${count}/${MAX_SNAPSHOTS} install-snapshots (nothing to delete)"
    return 0
  fi
  local to_delete=$((count - MAX_SNAPSHOTS))
  log "Rotation: removing ${to_delete} oldest install-snapshot(s) (keeping ${MAX_SNAPSHOTS})"
  local i=0
  while [[ "${i}" -lt "${to_delete}" ]]; do
    local old="${BACKUP_ROOT}/${snaps[$i]}"
    log "Deleting oldest snapshot: ${old}"
    rm -rf -- "${old}"
    i=$((i + 1))
  done
}

on_unexpected_fail() {
  local ec=$?
  if [[ "${BACKUP_OK}" -eq 1 || "${ALERTED}" -eq 1 ]]; then
    return 0
  fi
  if [[ "${ec}" -eq 0 ]]; then
    return 0
  fi
  log "ERROR: backup-volumes failed (exit ${ec})"
  if [[ -d "${DEST:-}" ]] && [[ "${DEST}" == "${BACKUP_ROOT}/"* ]]; then
    rm -rf -- "${DEST}" || true
  fi
  ALERTED=1
  send_discord_alert \
    "OpenCloud install-snapshots backup failed" \
    "FAILED" \
    15158332 \
    "backup-volumes.sh exited with code ${ec} on host ${HOSTNAMEHOOK}. Partial stamp dir cleaned when possible. Existing snapshots were not rotated away." || true
}

main() {
  require_root
  trap on_unexpected_fail EXIT

  if [[ ! -f "${COMPOSE_DIR}/.env" ]]; then
    log "ERROR: missing ${COMPOSE_DIR}/.env"
    exit 1
  fi

  mkdir -p "${BACKUP_ROOT}"
  cd "${COMPOSE_DIR}"

  set -a
  # shellcheck disable=SC1091
  source .env
  set +a

  PROJECT="${COMPOSE_PROJECT_NAME:-$(basename "${COMPOSE_DIR}")}"

  mapfile -t VOLUMES < <(docker compose config --volumes | sort -u)
  if [[ ${#VOLUMES[@]} -eq 0 ]]; then
    log "ERROR: no volumes listed by docker compose config"
    ALERTED=1
    send_discord_alert \
      "OpenCloud install-snapshots backup aborted — compose volumes empty" \
      "NO_VOLUMES" \
      15158332 \
      "docker compose config --volumes returned no volumes in ${COMPOSE_DIR}." || true
    exit 1
  fi

  log "OpenCloud install-snapshots backup started (stamp=${STAMP} max=${MAX_SNAPSHOTS})"
  check_disk_space
  create_backup
  rotate_snapshots
  BACKUP_OK=1
  log "OpenCloud install-snapshots backup finished successfully"
}

main "$@"
