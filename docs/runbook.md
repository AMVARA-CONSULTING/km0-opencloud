# Operations Runbook — OpenCloud on Debian 13

**OpenCloud (temporary Google OAuth test):** https://cloud.km0.amvara.de · **Web:** https://km0.amvara.de  
**OpenCloud (production hostname, restore after Google Console update):** https://cloud.km0digital.com  
For architecture, port map and data layout, see [`../README.md`](../README.md).  
Official docs: <https://docs.opencloud.eu/>

---

## Component inventory

| Component | Version | Config location | Status |
|-----------|---------|----------------|--------|
| Debian | 13.5 (Trixie) | `/etc/` | Running |
| Docker CE | 29.5.2 | `/etc/docker/daemon.json` | `systemctl status docker` |
| Docker Compose plugin | v5.1.4 | — | bundled with Docker CE |
| OpenCloud | rolling:7.0.0 | `/opt/opencloud/opencloud-compose/.env` | `docker compose ps` |
| Nginx (web) | 1.26.3 | `/etc/nginx/sites-available/km0` | `km0.amvara.de` → :9180 |
| Nginx (OpenCloud) | 1.26.3 | `/etc/nginx/sites-available/opencloud` | `cloud.km0digital.com` → :9200 |
| UFW | system | `/etc/ufw/` | `ufw status verbose` |
| Fail2ban | 1.1.0 | `/etc/fail2ban/jail.d/sshd.local` | `fail2ban-client status sshd` |
| TLS (web) | Let's Encrypt | `/etc/letsencrypt/live/km0.amvara.de/` | Web landing |
| TLS (cloud) | Let's Encrypt | `/etc/letsencrypt/live/cloud.km0digital.com/` | OpenCloud |
| Certbot | 4.0.0 | `/var/www/certbot` (webroot) | `certbot renew --dry-run` |

No PostgreSQL — the standard core stack uses embedded storage (Decomposed FS + BoltDB IDM).

---

## Day-to-day operations

### Working directory

All `docker compose` commands must run from:

```bash
cd /opt/opencloud/opencloud-compose
```

### Common commands

```bash
docker compose ps                        # Container status and uptime
docker compose logs -f opencloud         # Live log stream
docker compose logs --tail=100 opencloud # Last 100 lines
docker compose restart opencloud         # Graceful restart (keeps volumes)
docker compose down                      # Stop and remove container + network
docker compose up -d                     # Start in background
```

### Check for errors in logs

```bash
# Fatal and error level entries
docker compose logs opencloud | grep -E '"level":"(error|fatal)"'

# Nginx errors
tail -50 /var/log/nginx/error.log

# System journal (last hour)
journalctl -u docker --since "1 hour ago" --no-pager
journalctl -u nginx  --since "1 hour ago" --no-pager
```

---

## Configuration variables

All deployment variables live in a single file:

```
/opt/opencloud/opencloud-compose/.env   (chmod 600 — contains secrets)
```

The template for this deployment mode is:

```
/opt/opencloud/opencloud-compose/.env.debian-core-external-proxy.example
```

The upstream template with all available options is:

```
/opt/opencloud/opencloud-compose/.env.example
```

### Key variables explained

| Variable | Current value | Effect |
|----------|--------------|--------|
| `COMPOSE_FILE` | `docker-compose.yml:external-proxy/opencloud.yml` | External proxy overlay (binds `127.0.0.1:9200`) |
| `COMPOSE_PROJECT_NAME` | `opencloud` | Prefixes Docker resource names: volumes become `opencloud_opencloud-data`, etc. |
| `OC_DOMAIN` | `cloud.km0digital.com` | Hostname público de OpenCloud (no usar `km0.amvara.de`, que es la web). |
| `OC_DOCKER_IMAGE` / `OC_DOCKER_TAG` | `opencloudeu/opencloud-rolling` / `7.0.0` | Pinned image. Change `OC_DOCKER_TAG` to upgrade. |
| `INSECURE` | `false` | TLS validation enabled. Use `true` only with self-signed certs during lab setup. |
| `INITIAL_ADMIN_PASSWORD` | *(ver `opencloud-compose/.env`)* | Solo en **primer arranque**. Después, cambiar en la UI (no en `.env`). |
| `LOG_DRIVER` | `json-file` | Matches `/etc/docker/daemon.json`; limits log size to 10 MB × 3 files. |
| `LOG_LEVEL` | `info` | OpenCloud log verbosity (`trace`, `debug`, `info`, `warn`, `error`). |
| `DEMO_USERS` | `false` | Do not create demo accounts (alan, mary, etc.) with public password `demo`. |

---

## Nginx configuration

**Active site file:** `/etc/nginx/sites-available/opencloud`  
**Template for production (Let's Encrypt):** `/opt/opencloud/nginx/sites-available/opencloud`

### Current setup

**Web** (`/etc/nginx/sites-available/km0`): `server_name km0.amvara.de` → `127.0.0.1:9180`

**OpenCloud** (`/etc/nginx/sites-available/opencloud`):

- `server_name cloud.km0digital.com`
- `:80` — ACME webroot at `/var/www/certbot` + redirect to HTTPS
- `:443 ssl` — Let's Encrypt cert; forwards to `http://127.0.0.1:9200`
- HTTP/2 enabled (`http2 on` — nginx ≥ 1.25 syntax)
- `proxy_buffering off` — required for SSE real-time events
- `proxy_request_buffering off` — required for TUS resumable file uploads
- `Strict-Transport-Security` header enabled

### Validate and reload

```bash
nginx -t                        # Syntax check
systemctl reload nginx          # Zero-downtime reload
```

---

## TLS certificates (Let's Encrypt)

**Dominios:**

| Host | Certificado |
|------|-------------|
| `km0.amvara.de` | `/etc/letsencrypt/live/km0.amvara.de/` |
| `cloud.km0digital.com` | `/etc/letsencrypt/live/cloud.km0digital.com/` |

**ACME contact:** ver comentarios en `opencloud-compose/.env`  
**Issued:** 2026-05-21 · **Expires:** 2026-08-19

Check certificate:

```bash
openssl x509 -in /etc/letsencrypt/live/km0.amvara.de/fullchain.pem -noout -dates -issuer
```

Renewal (automatic via systemd timer):

```bash
systemctl status certbot.timer
certbot renew --dry-run
```

Nginx must keep `location /.well-known/acme-challenge/` on port 80 for renewals to succeed.

### OpenCloud host (`cloud.km0digital.com`)

1. Create DNS **A** record: `cloud.km0digital.com` → server public IP (must resolve on 8.8.8.8 before Certbot).
2. Ensure nginx port 80 serves `server_name cloud.km0digital.com` with webroot `/.well-known/acme-challenge/` (template in `nginx/sites-available/opencloud`).
3. Run:

```bash
/opt/opencloud/scripts/issue-cloud-km0digital-cert.sh
```

This requests the certificate, installs the production vhost (TLS paths under `/etc/letsencrypt/live/cloud.km0digital.com/`), and reloads nginx.

### Re-issue or add a subdomain (web)

Use the bootstrap site at `/etc/nginx/sites-available/opencloud-acme-bootstrap` (HTTP-only) if you need to obtain a cert before enabling the full HTTPS vhost, then follow the same webroot flow:

```bash
certbot certonly --webroot -w /var/www/certbot \
  -d km0.amvara.de \
  --email TU_EMAIL_ACME --agree-tos --no-eff-email
```

---

## Firewall (UFW)

```
Default: deny incoming, allow outgoing
22/tcp (OpenSSH)  — ALLOW from anywhere
80/tcp            — ALLOW from anywhere (redirect to HTTPS)
443/tcp           — ALLOW from anywhere (HTTPS)
[all other ports] — DENY
```

Port **9200 is not in UFW** — it is bound to `127.0.0.1` by Docker, so it is inaccessible externally even without a firewall rule.

Verify:

```bash
ufw status verbose
ss -tulpn | grep -E ':22|:80|:443|:9200'
```

---

## SSH brute-force protection (Fail2ban)

Fail2ban watches `ssh.service` via **systemd journal** and bans offending IPs with **nftables** (Debian default).

| Setting | Value |
|---------|-------|
| Jail | `sshd` |
| `maxretry` | 5 failed logins |
| `findtime` | 10 minutes |
| `bantime` | 1 hour |
| Config | `/etc/fail2ban/jail.d/sshd.local` |

Verify:

```bash
systemctl status fail2ban
fail2ban-client status sshd
```

Useful commands:

```bash
# List banned IPs
fail2ban-client status sshd

# Unban one IP (if you locked yourself out from a new address)
fail2ban-client set sshd unbanip <IP>

# Reload after editing jail config
fail2ban-client reload
```

Fail2ban complements UFW: UFW allows SSH from the Internet; Fail2ban blocks repeated failed authentication from specific sources.

---

## Backups

### Automated script

```bash
BACKUP_ROOT=/var/backups/opencloud /opt/opencloud/scripts/backup-volumes.sh
```

The script:
1. Reads `COMPOSE_PROJECT_NAME` from `.env` to determine volume names.
2. Lists volumes via `docker compose config --volumes`.
3. For each volume, runs an Alpine container to create a `.tar.gz` archive.
4. Outputs archives to `/var/backups/opencloud/<YYYYMMDD-HHMMSS>/`.

**Volumes backed up:** `opencloud-data` (user files, IDM, search) and `opencloud-config` (secrets, config).

### Schedule with cron (recommended)

```bash
# Daily backup at 02:00
echo '0 2 * * * root BACKUP_ROOT=/var/backups/opencloud /opt/opencloud/scripts/backup-volumes.sh >> /var/log/opencloud-backup.log 2>&1' \
  > /etc/cron.d/opencloud-backup
```

### Restore procedure

```bash
# 1. Stop the stack
cd /opt/opencloud/opencloud-compose
docker compose down

# 2. Restore data volume (adjust timestamp)
docker run --rm \
  -v opencloud_opencloud-data:/to \
  -v /var/backups/opencloud/20260101-020000:/backup:ro \
  alpine:3.19 \
  sh -c 'rm -rf /to/* /to/.[!.]* /to/..?* 2>/dev/null; tar xzf /backup/opencloud-data-20260101-020000.tar.gz -C /to'

# 3. Restore config volume (same pattern)
docker run --rm \
  -v opencloud_opencloud-config:/to \
  -v /var/backups/opencloud/20260101-020000:/backup:ro \
  alpine:3.19 \
  sh -c 'rm -rf /to/* /to/.[!.]* /to/..?* 2>/dev/null; tar xzf /backup/opencloud-config-20260101-020000.tar.gz -C /to'

# 4. Restart
docker compose up -d
```

> After restore, verify file ownership: OpenCloud runs as UID/GID 1000. The volume data should be owned by `1000:1000`.

---

## Upgrades

### Upgrade OpenCloud image

```bash
cd /opt/opencloud/opencloud-compose

# 1. Review changelog: https://github.com/opencloud-eu/opencloud/tree/main/changelog
# 2. Update OC_DOCKER_TAG in .env
nano .env

# 3. Pull and restart
docker compose pull
docker compose up -d

# 4. Verify
docker compose ps
docker compose logs --tail=50 opencloud | grep '"level":"(error|fatal)"'
```

### Upgrade compose definitions (upstream)

```bash
git -C /opt/opencloud/opencloud-compose pull
# Review diff before applying: git -C /opt/opencloud/opencloud-compose diff HEAD@{1}
docker compose up -d
```

### Upgrade Debian packages

```bash
apt update && apt upgrade -y
# Reboot if kernel was updated: systemctl reboot
```

---

## Deployment history

| Date | Action | Notes |
|------|--------|-------|
| 2026-05-21 | Initial deployment | Debian 13, Docker CE 29.5.2, OpenCloud 6.2.0, self-signed cert on IP |
| 2026-05-21 | Fixed IDP startup crash | OIDC requires `OC_URL=https://`. Self-signed cert on :443 |
| 2026-05-21 | Production domain | `km0.amvara.de` Let's Encrypt (web) |
| 2026-05-21 | Split hostnames | Web `km0.amvara.de`; OpenCloud `cloud.km0.amvara.de`, `OC_DOMAIN` actualizado |
| 2026-05-26 | Cloud domain migration | `cloud.km0.amvara.de` → `cloud.km0digital.com`; TLS via `scripts/issue-cloud-km0digital-cert.sh` after DNS A record |
| 2026-05-21 | Reverted UI branding | Removed `km0` theme overlay; default OpenCloud logo/name in Web UI |
| 2026-05-22 | Upgraded OpenCloud | `6.2.0` → `7.0.0`; added `sharing.service_account` in `opencloud.yaml` (7.x requirement) |

---

## Multi-provider OIDC (Google + Apple, no Keycloak)

Authentication uses **Dex** as the sole OIDC issuer. **All** tokens (Google, Apple, local password) are Dex-issued so the OpenCloud proxy can verify them via Dex’s JWKS. The built-in `idp` stays running for internal service-to-service use but is no longer the end-user auth path.

**Why all auth must go through Dex:** `OC_OIDC_ISSUER=Dex` means the proxy verifies access tokens against Dex’s JWKS only. Tokens issued directly by the built-in idp (LibreGraph Connect) have a different `kid` and are rejected with `"key not found in JWKS"`, causing an infinite re-auth loop. Dex’s built-in local password connector (`enablePasswordDB: true`) solves this.

| Component | Role |
|-----------|------|
| nginx `cloud.km0digital.com` | TLS, `/dex/` → Dex, `/` → OpenCloud |
| Dex (`127.0.0.1:5556`) | Unified issuer; connectors: Google, Apple (optional) |
| OpenCloud built-in `idp` | Local LDAP users (admin, manually created accounts) |
| OpenCloud | `OC_OIDC_ISSUER=https://cloud.km0digital.com/dex`, `WEB_OIDC_CLIENT_ID=opencloud-web` |

**Single login landing:** https://cloud.km0digital.com/login.html (repo: `host-www/opencloud-auth/login.html`). CA | ES | EN | DE via `/dex/theme/i18n.js`.

| Action on landing | Sets cookie | Redirect target |
|-------------------|-------------|-----------------|
| Google / Apple | `oc_auth_mode=dex` | `/dex/auth?connector_id=google` or `apple` → provider → `/?code=…` |
| Local username/password | `oc_auth_mode=dex` | `/dex/auth?connector_id=local` → Dex password form → `/oidc-callback.html?code=…` |

Legacy `/?oidc=1` still passes nginx to OpenCloud (bookmarks) but is not linked from the landing page.

**Local Dex users** (add more in `dex/config.yaml` `staticPasswords` with `htpasswd -bnBC 12 '' <pw>` + new UUID for `userID`):

| Email | Password | Dex `userID` |
|-------|----------|--------------|
| `admin@cloud.km0.amvara.de` or `admin` | `OC-Temp-2026!` | `9f333c9a-86f3-45bd-a3bd-efd6f28fd726` |

**Default landing:** unauthenticated visits to `/` redirect to `/login.html` (nginx). OAuth callbacks (`/?code=…`) pass through to OpenCloud. `WEB_OPTION_LOGIN_URL` points at `/login.html`.

Config: `/opt/opencloud/dex/`. Dex themed picker remains a fallback for direct `/dex/auth` hits; primary UX is `login.html`.

**Deploy auth UI changes:**

```bash
rsync -a /opt/opencloud/host-www/opencloud-auth/ /var/www/opencloud-auth/
# If nginx template changed:
sudo cp /opt/opencloud/nginx/sites-available/opencloud /etc/nginx/sites-available/opencloud
sudo nginx -t && sudo systemctl reload nginx
cd /opt/opencloud/dex && docker compose up -d
```

**Verify:**

```bash
curl -sI https://cloud.km0digital.com/login.html | head -3
curl -s https://cloud.km0digital.com/oidc/local-metadata.json | jq -r .authorization_endpoint
# expect: .../signin/v1/identifier/_/authorize
curl -sI "https://cloud.km0digital.com/dex/auth?client_id=opencloud-web&redirect_uri=https%3A%2F%2Fcloud.km0digital.com%2F&response_type=code&scope=openid%20profile%20email&connector_id=google&state=test" | grep -i location
# expect: /dex/auth/google (no Dex picker)
```

Manual: private window — local login reaches `/files` without `/dex/auth`; Google button skips Dex picker; DE language on landing.

### Temporary: Google OAuth via `cloud.km0.amvara.de`

While Google Cloud Console still lists the **old** hostname, test OpenCloud only at **https://cloud.km0.amvara.de** (not `cloud.km0digital.com`). Align:

- `opencloud-compose/.env`: `OC_DOMAIN`, `OC_URL`, `OC_OIDC_ISSUER` → `cloud.km0.amvara.de`
- `dex/.env`: `DEX_DOMAIN`, `DEX_ISSUER` → `https://cloud.km0.amvara.de/dex`
- `host-www/opencloud-auth/config-*.json` and `local-metadata.json` URLs → same host
- Nginx: TLS vhost for `cloud.km0.amvara.de` (cert under `/etc/letsencrypt/live/cloud.km0.amvara.de/`)

Dex Google connector callback (must match Console): `https://cloud.km0.amvara.de/dex/callback`

Revert to `cloud.km0digital.com` after adding that URI in Google Console for the new domain.

**Google Cloud Console:** authorized redirect URI for the Dex Google connector (required; domain migration often leaves the old hostname here):

```
https://cloud.km0digital.com/dex/callback
```

Remove legacy entries such as `https://cloud.km0.amvara.de/dex/callback` unless you still use that host. A Google error `redirect_uri_mismatch` almost always means this list does not match Dex’s `redirectURI` in `dex/config.yaml` (check with `docker exec opencloud-dex grep redirectURI /etc/dex/config.yaml`).

**Local login is now routed through Dex** (`connector_id=local`), not the identifier form. `local-metadata.json` and `config-local.json` are kept for reference but are no longer used for end-user authentication. All tokens are Dex-issued and verified via Dex’s JWKS.

**Apple:** create `/opt/apple-signin-credentials.json` from the example, then run:

```bash
sudo /opt/opencloud/dex/setup-apple.sh
```

See `/opt/opencloud/dex/README.md` for Apple Developer portal steps.

Dex logs: `docker logs -f opencloud-dex`

**Blank local login page:** the idp UI loads `./static/` from `/signin/v1/identifier/` but assets live under `/signin/v1/static/`. Nginx rewrites `identifier/static/` → `static/` (see `nginx/sites-available/opencloud`).

Users with stale tokens (issued before a Dex container restart) will see `"key not found in JWKS"` errors on every API call and enter a re-auth loop. Fix: clear all site data (cookies + localStorage) for the domain and log in fresh.

---

## Troubleshooting

### Container keeps restarting

```bash
docker compose logs --tail=50 opencloud | grep '"level":"fatal"'
```

Common causes:
- `INITIAL_ADMIN_PASSWORD` not set → container exits immediately.
- `OC_URL` does not start with `https://` → IDP service fails with `invalid iss value`.
- Volume permission mismatch → files not writable by UID 1000.

### Nginx returns 502 Bad Gateway

OpenCloud is not responding on port 9200. Check:

```bash
ss -tulpn | grep 9200         # Is docker-proxy listening?
docker compose ps             # Is the container Up or Restarting?
docker compose logs opencloud # Any startup errors?
```

### Cannot log in (redirect loop)

`OC_DOMAIN` does not match the browser's address bar hostname. They must be identical.

### Google login OK but “inactive or not yet authorized” (`/access-denied`)

Typical causes:

1. **Email whitelist in `opencloud.yaml`** — `role_assignment.driver: oidc` with `role_mapping` only allows listed emails. Anyone else gets `/access-denied` after Dex/Google succeeds. Fix: use `driver: default` (all first-time users get role `user`) or add every allowed email to `role_mapping`.
2. **Docker DNS** — OpenCloud cannot resolve `OC_DOMAIN` from inside the container (`lookup … server misbehaving`). Fix: `extra_hosts` in `external-proxy/opencloud.yml` mapping `${OC_DOMAIN}` to `host-gateway`, then `docker compose up -d --force-recreate opencloud`.
3. **Stale browser session** — old tabs still call built-in `/signin/` (502). Clear site data for `cloud.km0digital.com` or use a private window.

After changing role assignment, users who already logged in once may need a fresh login. Promote admins in **Settings → Users** (not only via email mapping).

### Admin password forgotten

The `INITIAL_ADMIN_PASSWORD` env var only applies on **first init**. To reset after deployment:

```bash
docker exec -it opencloud-opencloud-1 opencloud idm resetpassword
```

---

## References

- [Official docs — Behind External Proxy](https://docs.opencloud.eu/docs/admin/getting-started/container/docker-compose/external-proxy)
- [Production considerations](https://docs.opencloud.eu/docs/admin/getting-started/container/docker-compose/docker-compose-production-considerations)
- [OpenCloud release notes](https://docs.opencloud.eu/opencloud_release_notes.html)
- [Changelog](https://github.com/opencloud-eu/opencloud/tree/main/changelog)
- [Upstream compose repo](https://github.com/opencloud-eu/opencloud-compose)
