# OpenCloud installation backup and restore

Script: [`backup-opencloud-installation.sh`](backup-opencloud-installation.sh)

## What the backup includes

| Backup path | Source on the host | Notes |
|-------------|-------------------|--------|
| `opt-opencloud/` | `/opt/opencloud/` | Compose stack, Dex, repo nginx templates, scripts, docs |
| **`host-nginx/`** | **`/etc/nginx/sites-available/opencloud`**, **`opencloud-acme-bootstrap`** | **Active host nginx site configs** |
| `host-nginx/repo-nginx/` | `/opt/opencloud/nginx/` | Version-controlled nginx templates in the repo |
| `host-nginx/sites-enabled-*.txt` | `/etc/nginx/sites-enabled/opencloud` | Symlink target recorded for reference |
| **`host-www/opencloud-auth/`** | **`/var/www/opencloud-auth/`** | **`login.html`** served at `https://cloud.km0.amvara.de/login.html` |
| **`host-www/certbot/`** | **`/var/www/certbot/`** | ACME HTTP-01 webroot |
| `letsencrypt/` | `/etc/letsencrypt/{live,archive,renewal}/cloud.km0.amvara.de*` | TLS certificates (default domain; override with `TLS_DOMAIN`) |
| `opt-credentials/` | `/opt/google-client-secret.json`, Apple JSON files | OIDC secrets referenced by Dex |
| `docker-volumes/` | Docker volumes `opencloud_opencloud-config`, `opencloud_opencloud-data`, `dex_dex-data` | Application data and Dex state |
| `manifest/` | Generated at backup time | `backup.log`, `runtime-snapshot.txt` |

**Not included:** `km0` corporate site nginx (`/etc/nginx/sites-available/km0`), Keycloak stack, or other unrelated services.

---

## Create a backup

```bash
sudo /opt/opencloud/scripts/backup-opencloud-installation.sh
```

Outputs:

- Expanded tree: `/opt/backup_opencloud_installation/<YYYYMMDD-HHMMSS>/`
- Archive: `/opt/backup_opencloud_installation/opencloud-installation-backup-<YYYYMMDD-HHMMSS>.tar.gz`
- Symlinks: `latest`, `latest.tar.gz`

Optional:

```bash
sudo KEEP_EXPANDED=false /opt/opencloud/scripts/backup-opencloud-installation.sh
```

---

## Restore overview

Restore on a **clean Debian host** with Docker, nginx, and certbot already installed (or restore TLS and re-issue certs if starting from scratch).

**Order:** stop services → restore files and volumes → start stacks → verify nginx → test HTTPS.

All commands below assume you run as **root** unless noted.

### 1. Extract the archive

```bash
BACKUP_ROOT=/opt/backup_opencloud_installation
ARCHIVE="${BACKUP_ROOT}/opencloud-installation-backup-20260522-195106.tar.gz"   # use your file

mkdir -p "${BACKUP_ROOT}"
tar -xzf "${ARCHIVE}" -C "${BACKUP_ROOT}"
STAMP="20260522-195106"   # folder name inside the tar
SRC="${BACKUP_ROOT}/${STAMP}"
```

Or use an already-expanded directory:

```bash
SRC=/opt/backup_opencloud_installation/latest
```

### 2. Restore `/opt/opencloud`

```bash
rsync -a "${SRC}/opt-opencloud/" /opt/opencloud/
chmod 600 /opt/opencloud/opencloud-compose/.env /opt/opencloud/dex/.env 2>/dev/null || true
```

### 3. Restore host nginx configuration

```bash
cp -a "${SRC}/host-nginx/opencloud" /etc/nginx/sites-available/opencloud
cp -a "${SRC}/host-nginx/opencloud-acme-bootstrap" /etc/nginx/sites-available/opencloud-acme-bootstrap 2>/dev/null || true

ln -sfn /etc/nginx/sites-available/opencloud /etc/nginx/sites-enabled/opencloud

nginx -t && systemctl reload nginx
```

Compare with `host-nginx/sites-enabled-opencloud-target.txt` if the symlink differed on the source host.

### 4. Restore HTML and ACME webroot

```bash
mkdir -p /var/www/opencloud-auth /var/www/certbot
rsync -a "${SRC}/host-www/opencloud-auth/" /var/www/opencloud-auth/
rsync -a "${SRC}/host-www/certbot/" /var/www/certbot/
chown -R www-data:www-data /var/www/certbot 2>/dev/null || true
```

Verify: `https://cloud.km0.amvara.de/login.html` should serve the restored picker page.

### 5. Restore TLS certificates (optional if re-issuing with certbot)

```bash
DOMAIN=cloud.km0.amvara.de

for sub in live archive renewal; do
  if [[ -d "${SRC}/letsencrypt/${sub}" ]]; then
    mkdir -p "/etc/letsencrypt/${sub}"
    cp -a "${SRC}/letsencrypt/${sub}/"* "/etc/letsencrypt/${sub}/"
  fi
done

# Fix permissions (Let's Encrypt expects root:root, private keys 600)
chown -R root:root /etc/letsencrypt
find /etc/letsencrypt -name 'privkey*.pem' -exec chmod 600 {} \;
```

If certs are expired or the hostname changed, skip this step and run certbot after nginx is configured:

```bash
certbot certonly --webroot -w /var/www/certbot -d cloud.km0.amvara.de
```

### 6. Restore OIDC credential files

```bash
cp -a "${SRC}/opt-credentials/"* /opt/ 2>/dev/null || true
chmod 600 /opt/google-client-secret.json /opt/apple-signin-credentials.json 2>/dev/null || true
```

Ensure Dex `.env` values match the restored JSON (Google client ID/secret, Apple settings).

### 7. Restore Docker volumes

Stop stacks first:

```bash
cd /opt/opencloud/opencloud-compose && docker compose down
cd /opt/opencloud/dex && docker compose down
```

Restore each volume (replace `<STAMP>` with the stamp inside `docker-volumes/`):

```bash
STAMP=20260522-195106
ALPINE=alpine:3.19

restore_volume() {
  local vol="$1"
  local tarball="$2"
  docker volume create "${vol}" 2>/dev/null || true
  docker run --rm \
    -v "${vol}:/to" \
    -v "$(dirname "${tarball}"):/backup:ro" \
    "${ALPINE}" \
    sh -c "cd /to && tar xzf /backup/$(basename "${tarball}")"
}

restore_volume opencloud_opencloud-config \
  "${SRC}/docker-volumes/opencloud-config-${STAMP}.tar.gz"
restore_volume opencloud_opencloud-data \
  "${SRC}/docker-volumes/opencloud-data-${STAMP}.tar.gz"
restore_volume dex_dex-data \
  "${SRC}/docker-volumes/dex-data-${STAMP}.tar.gz"
```

**Warning:** Restoring over existing volumes **overwrites** current data. Remove old volumes only if you intend a full replace:

```bash
docker volume rm opencloud_opencloud-config opencloud_opencloud-data dex_dex-data
# then recreate and restore as above
```

### 8. Start services

```bash
cd /opt/opencloud/opencloud-compose
docker compose up -d

cd /opt/opencloud/dex
docker compose up -d

docker ps --filter name=opencloud --filter name=dex
```

### 9. Verify

```bash
nginx -t
curl -sI https://cloud.km0.amvara.de/login.html | head -5
curl -sI https://cloud.km0.amvara.de/ | head -5
curl -sI https://cloud.km0.amvara.de/dex/.well-known/openid-configuration | head -5

cd /opt/opencloud/opencloud-compose && docker compose logs --tail=30 opencloud
docker logs --tail=30 opencloud-dex
```

---

## Partial restore (single component)

| Need only | Restore from |
|-----------|----------------|
| Nginx + HTML | Steps 3–4 |
| App config/data | Step 7 (`opencloud-*` volumes) + step 2 if `.env` changed |
| Dex / login UI | Step 2 (`/opt/opencloud/dex`), step 7 (`dex-data`), step 6 |
| TLS only | Step 5 |

---

## Security

Backups contain **secrets** (`.env`, OAuth JSON, TLS private keys, volume data). Store archives offline with restricted permissions:

```bash
chmod 700 /opt/backup_opencloud_installation
chmod 600 /opt/backup_opencloud_installation/*.tar.gz
```

Do not commit backup files to git.

---

## Related

- Volume-only backup (compose project): [`backup-volumes.sh`](backup-volumes.sh)
- Operations runbook: [`../docs/runbook.md`](../docs/runbook.md)
