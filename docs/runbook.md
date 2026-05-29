# Operations Runbook — OpenCloud on Debian 13

**OpenCloud:** https://cloud.km0digital.com · **Web:** https://km0.amvara.de  
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
| Collabora CODE | 25.04.x | `opencloud-compose/.env` (`COLLABORA_*`) | `docker compose ps collabora` |
| WOPI (collaboration) | same as OpenCloud image | `opencloud-compose/.env` (`WOPISERVER_DOMAIN`) | `docker compose ps collaboration` |
| Nginx (web) | 1.26.3 | `/etc/nginx/sites-available/km0` | `km0.amvara.de` → :9180 |
| Nginx (OpenCloud) | 1.26.3 | `/etc/nginx/sites-available/opencloud` | `cloud.km0digital.com` → :9200 |
| Nginx (Collabora) | 1.26.3 | `/etc/nginx/sites-available/collabora` | `collabora.km0digital.com` → :9980 |
| Nginx (WOPI) | 1.26.3 | `/etc/nginx/sites-available/wopi` | `wopi.km0digital.com` → :9300 |
| UFW | system | `/etc/ufw/` | `ufw status verbose` |
| Fail2ban | 1.1.0 | `/etc/fail2ban/jail.d/sshd.local` | `fail2ban-client status sshd` |
| TLS (web) | Let's Encrypt | `/etc/letsencrypt/live/km0.amvara.de/` | Web landing |
| TLS (cloud) | Let's Encrypt | `/etc/letsencrypt/live/cloud.km0digital.com/` | OpenCloud |
| TLS (collabora) | Let's Encrypt | `/etc/letsencrypt/live/collabora.km0digital.com/` | Collabora CODE |
| TLS (wopi) | Let's Encrypt | `/etc/letsencrypt/live/wopi.km0digital.com/` | WOPI bridge |
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
/opt/opencloud/overrides/opencloud-compose/.env.debian-collabora-external-proxy.example
```

Core-only (no Collabora):

```
/opt/opencloud/overrides/opencloud-compose/.env.debian-core-external-proxy.example
```

The upstream template with all available options is:

```
/opt/opencloud/opencloud-compose/.env.example
```

### Key variables explained

| Variable | Current value | Effect |
|----------|--------------|--------|
| `COMPOSE_FILE` | `docker-compose.yml:weboffice/collabora.yml:external-proxy/opencloud.yml:external-proxy/collabora.yml` | Collabora + WOPI + external proxy overlays |
| `COLLABORA_DOMAIN` | `collabora.km0digital.com` | Public hostname for Collabora editor iframe |
| `WOPISERVER_DOMAIN` | `wopi.km0digital.com` | Public hostname for WOPI GetFile/PutFile |
| `COLLABORA_SSL_ENABLE` | `false` | Nginx terminates TLS; Collabora listens HTTP on loopback |
| `COLLABORA_SSL_VERIFICATION` | `false` | Collabora → WOPI over HTTPS via Nginx with valid certs |
| `COLLABORA_ADMIN_PASSWORD` | *(in `.env` only)* | Collabora admin UI at `/browser/dist/admin/admin.html` |
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

**Collabora** (`/etc/nginx/sites-available/collabora`):

- `server_name collabora.km0digital.com`
- `:443 ssl` — forwards to `http://127.0.0.1:9980`
- Shared snippet: `nginx/snippets/collabora-proxy.conf` (long timeouts, WebSocket upgrade)

**WOPI** (`/etc/nginx/sites-available/wopi`):

- `server_name wopi.km0digital.com`
- `:443 ssl` — forwards to `http://127.0.0.1:9300`

Templates live in `/opt/opencloud/nginx/sites-available/`. Enable with:

```bash
/opt/opencloud/scripts/issue-collabora-wopi-certs.sh
```

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
| `collabora.km0digital.com` | `/etc/letsencrypt/live/collabora.km0digital.com/` |
| `wopi.km0digital.com` | `/etc/letsencrypt/live/wopi.km0digital.com/` |

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

### Collabora + WOPI hostnames

1. Create DNS **A** records: `collabora.km0digital.com` and `wopi.km0digital.com` → same server IP as `cloud.km0digital.com`.
2. Copy `overrides/opencloud-compose/.env.debian-collabora-external-proxy.example` to `opencloud-compose/.env` (or merge `COMPOSE_FILE` + `COLLABORA_*` / `WOPISERVER_*` into the existing `.env`).
3. Run:

```bash
/opt/opencloud/scripts/issue-collabora-wopi-certs.sh
/opt/opencloud/scripts/enable-collabora-compose.sh
```

Smoke checks:

```bash
curl -sI https://collabora.km0digital.com/hosting/discovery | head -3
curl -sI https://wopi.km0digital.com | head -3
docker compose ps collabora collaboration
```

Rollback: revert `COMPOSE_FILE` to core-only overlay, disable nginx sites (`rm /etc/nginx/sites-enabled/{collabora,wopi}`), `docker compose up -d`.

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
ss -tulpn | grep -E ':22|:80|:443|:9200|:9980|:9300'
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
| 2026-05-27 | Google OAuth on new domain | `OC_DOMAIN`, Dex issuer, `host-www/opencloud-auth`, nginx production vhost; legacy `cloud.km0.amvara.de` → 301 to new host |
| 2026-05-21 | Reverted UI branding | Removed `km0` theme overlay; default OpenCloud logo/name in Web UI |
| 2026-05-22 | Upgraded OpenCloud | `6.2.0` → `7.0.0`; added `sharing.service_account` in `opencloud.yaml` (7.x requirement) |

---

## Multi-provider OIDC (Google + Apple, no Keycloak)

Authentication uses **Dex** as the sole OIDC issuer. **All** tokens (Google, Apple, local password) are Dex-issued so the OpenCloud proxy can verify them via Dex’s JWKS. The built-in `idp` stays running for internal service-to-service use but is no longer the end-user auth path.

**Why all auth must go through Dex:** `OC_OIDC_ISSUER=Dex` means the proxy verifies access tokens against Dex’s JWKS only. Tokens issued directly by the built-in idp (LibreGraph Connect) have a different `kid` and are rejected with `"key not found in JWKS"`, causing an infinite re-auth loop. Dex’s **LDAP** connector (`connector_id=ldap`) validates username/password against OpenCloud’s built-in IDM (port 9235) and still issues Dex tokens.

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
| Local username/password | `oc_auth_mode=dex` | `/dex/auth?connector_id=ldap` → Dex password form → `/oidc-callback.html?code=…` |

Legacy `/?oidc=1` still passes nginx to OpenCloud (bookmarks) but is not linked from the landing page.

**Local users:** any account in OpenCloud IDM (`ou=users,o=libregraph-idm`) — same username/password as the built-in login. Sign in with **uid** (e.g. `admin`, `luipy`) or full email when uid is an address. Dex maps `openCloudUUID` and `mail` into OIDC claims (`PROXY_USER_OIDC_CLAIM=email`).

Dex reaches IDM at `ldaps://opencloud:9235` on the Docker network `opencloud_opencloud-net` (`IDM_LDAPS_ADDR=0.0.0.0:9235` in `overrides/opencloud-compose/external-proxy/opencloud.yml`). Bind password: `idm_password` from `opencloud.yaml` (auto-read by `dex/docker-entrypoint.sh` via mounted config volume, or set `OPENCLOUD_IDM_BIND_PW` in `dex/.env`).

**IDM LDAPS certificate:** OpenCloud’s default `idm/ldap.crt` SAN is `localhost` only. Dex TLS hostname check requires `DNS:opencloud`. Regenerate once (backs up old files, restarts OpenCloud + Dex):

```bash
./scripts/regenerate-opencloud-idm-ldap-cert.sh --restart
```

**Default landing:** unauthenticated visits to `/` redirect to `/login.html` (nginx). OAuth callbacks (`/?code=…`) pass through to OpenCloud. `WEB_OPTION_LOGIN_URL` points at `/login.html`.

Config: `/opt/opencloud/dex/`. Nginx redirects `/dex/auth` without `connector_id` to `/login.html` (preserves OIDC query params). Dex themed picker is not shown in normal flows; primary UX is `login.html` only.

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
curl -sI "https://cloud.km0digital.com/dex/auth?client_id=opencloud-web&redirect_uri=https%3A%2F%2Fcloud.km0digital.com%2Foidc-callback.html&response_type=code&scope=openid%20profile%20email&state=test&code_challenge=x&code_challenge_method=S256" | grep -i '^location:'
# expect: /login.html?... (no Dex connector picker)
```

Manual: private window — local login reaches `/files` without `/dex/auth`; Google button skips Dex picker; DE language on landing.

**Google Cloud Console:** authorized redirect URIs for the Dex Google connector (must match Dex `redirectURI`):

```
https://cloud.km0digital.com/dex/callback
```

Remove legacy entries such as `https://cloud.km0.amvara.de/dex/callback` unless you still use that host. A Google error `redirect_uri_mismatch` almost always means this list does not match Dex’s `redirectURI` in `dex/config.yaml` (check with `docker exec opencloud-dex grep redirectURI /etc/dex/config.yaml`).

**Local login is routed through Dex** (`connector_id=ldap` → OpenCloud IDM), not the identifier form. `local-metadata.json` and `config-local.json` are kept for reference only. All tokens are Dex-issued and verified via Dex’s JWKS.

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

### Collabora editor does not load (CSP / frame errors)

Browser console shows `frame-src` or `frame-ancestors` violations:

1. Confirm `COLLABORA_DOMAIN` in `.env` matches `collabora.km0digital.com`.
2. Recreate OpenCloud after changing `.env`: `docker compose up -d --force-recreate opencloud`.
3. Check Collabora `extra_params` in `weboffice/collabora.yml` — `net.frame_ancestors` must include `OC_DOMAIN`.

### Collabora cannot reach WOPI

Collabora logs mention WOPI URL mismatch:

```bash
docker compose logs collabora collaboration | tail -50
```

Verify `WOPISERVER_DOMAIN`, Nginx `server_name` on the wopi vhost, and `aliasgroup1` in the collabora container env.

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
