# OpenCloud on Debian 13 — Core deployment (no Collabora/WOPI)

**OpenCloud:** https://cloud.km0.amvara.de · **Web:** https://km0.amvara.de · **OS:** Debian 13 (Trixie)

> A developer-oriented overview of the full stack. Read [`docs/runbook.md`](docs/runbook.md) for day-to-day operations.

---

## Architecture

```
Browser → https://km0.amvara.de     → Nginx (km0)      → 127.0.0.1:9180  (web corporativa)
Browser → https://cloud.km0.amvara.de → Nginx (opencloud) → 127.0.0.1:9200  (OpenCloud)
```

OpenCloud path in detail:

```
Browser
   │  HTTPS :443  cloud.km0.amvara.de (Let's Encrypt)
   ▼
Nginx  (/etc/nginx/sites-available/opencloud)
   │  HTTP  http://127.0.0.1:9200  (loopback only)
   ▼
OpenCloud container  (opencloudeu/opencloud-rolling:7.0.0, UID 1000:1000)
   │  internal gRPC + HTTP on 127.0.0.1 (ports 9140–9300 range, inside container only)
   ▼
Docker volumes  (opencloud_opencloud-data  /  opencloud_opencloud-config)
```

UFW enforces: **22, 80, 443** open to the Internet. Port **9200 is loopback-only** — not reachable externally. **Fail2ban** (`sshd` jail) bans IPs after repeated SSH login failures (see runbook).

---

## Repository layout

```
/opt/opencloud/                    # Git: km0-opencloud (este repo)
├── overrides/opencloud-compose/   # Parches KM0 sobre upstream (no fork)
├── opencloud-compose/             # Clon local upstream (gitignored; ver overrides/)
├── dex/                           # OIDC Dex + tema KM0
├── nginx/                         # Plantillas → /etc/nginx/
├── host-www/opencloud-auth/       # Plantillas → /var/www/opencloud-auth/
├── scripts/                       # Backups y apply-opencloud-compose-overrides.sh
└── docs/
    ├── runbook.md
    └── REPOSITORY.md              # Qué se versiona y qué no
```

---

## Key configuration files

| File | Purpose |
|------|---------|
| `/opt/opencloud/opencloud-compose/.env` | **Single source of truth** for deployment variables. `chmod 600`. |
| `/etc/nginx/sites-available/opencloud` | Active Nginx vhost (TLS termination + reverse proxy). |
| `/etc/nginx/sites-available/km0` | Web corporativa (`km0.amvara.de` → :9180) |
| `/etc/letsencrypt/live/km0.amvara.de/` | Certificado web |
| `/etc/letsencrypt/live/cloud.km0.amvara.de/` | Certificado OpenCloud |
| `/var/www/certbot` | ACME HTTP-01 webroot for certificate renewal |
| `/etc/docker/daemon.json` | Docker log rotation policy (`json-file`, max 10 MB × 3 files). |
| `/var/lib/docker/volumes/opencloud_opencloud-data/` | All user data (files, search index, NATS state, IDM database). |
| `/var/lib/docker/volumes/opencloud_opencloud-config/` | OpenCloud runtime config (`opencloud.yaml` with auto-generated secrets). |

---

## Active `.env` variables

La configuración activa está en `opencloud-compose/.env` (`chmod 600`, **no** en Git). Plantilla versionada:

`overrides/opencloud-compose/.env.debian-core-external-proxy.example`

Tras clonar upstream, copiar la plantilla y rellenar `INITIAL_ADMIN_PASSWORD`, OIDC y demás. Valores operativos del servidor (IP, contacto ACME, notas de contraseña) van documentados en comentarios del `.env` local.

`COMPOSE_PROJECT_NAME=opencloud` fija los volúmenes `opencloud_opencloud-data` y `opencloud_opencloud-config`.

---

## Where user files are stored

All persistent data lives in two Docker volumes on the host:

```
/var/lib/docker/volumes/
├── opencloud_opencloud-data/_data/
│   ├── idm/          # Internal LDAP directory (idm.boltdb + TLS key pair for LDAP)
│   ├── idp/          # OIDC Identity Provider state
│   ├── nats/         # Embedded NATS JetStream (event bus between microservices)
│   ├── search/       # Full-text search index (Bleve)
│   ├── storage/
│   │   ├── metadata/ # CS3 metadata (shares, spaces, locks)
│   │   ├── ocm/      # Open Cloud Mesh federation data
│   │   └── users/    # Actual user files (one directory per user UUID)
│   │       └── users/<user-uuid>/
│   │           └── .oc-nodes/   # File nodes (decomposed storage driver)
│   └── web/          # Static web assets cache
└── opencloud_opencloud-config/_data/
    ├── opencloud.yaml      # Auto-generated runtime config (secrets, service UUIDs)
    ├── csp.yaml            # Content Security Policy overrides
    └── banned-password-list.txt
```

**User files** are stored using the **Decomposed Storage** driver: each file is stored as a node (blob) referenced by UUID under `storage/users/users/<user-uuid>/.oc-nodes/`. There is no traditional directory tree on disk; the logical structure is reconstructed from metadata.

---

## Data encryption

OpenCloud **does not encrypt data at rest by default** in the core deployment. Files are stored as plain blobs in the Docker volume. Options to add encryption:

- **Disk-level:** encrypt the host volume (`dm-crypt`/`LUKS`) before Docker mounts it — transparent to OpenCloud.
- **Object storage:** use S3 with server-side encryption (SSE-S3 or SSE-KMS) by adding the `storage/decomposeds3.yml` overlay.
- **Client-side:** OpenCloud supports end-to-end encryption via the desktop/mobile clients (keys never leave the client).

**Data in transit** is encrypted:
- Browser → Nginx: **TLS 1.2/1.3** (Let's Encrypt).
- Nginx → OpenCloud: **plain HTTP on loopback** (`127.0.0.1:9200`). This is safe because it never leaves the host and is a standard pattern for reverse-proxied services.
- Internal microservices (within the container): communicate over `127.0.0.1` gRPC/HTTP. Not exposed outside the container.
- IDM ↔ services: **LDAP over TLS** using the auto-generated cert pair in `idm/ldap.{crt,key}`.

---

## Nginx ↔ OpenCloud connection (reverse proxy)

```
Nginx (host)                   OpenCloud container
─────────────────────────────────────────────────────
listen 443 ssl                 PROXY_HTTP_ADDR=0.0.0.0:9200
  │                              │
  │  proxy_pass                  │  docker port mapping:
  └──► http://127.0.0.1:9200 ──►  127.0.0.1:9200 → container:9200
         ▲ loopback only
```

Key Nginx directives and why they matter:

| Directive | Value | Reason |
|-----------|-------|--------|
| `proxy_buffering off` | off | Required for SSE (Server-Sent Events used by OpenCloud's real-time updates) |
| `proxy_request_buffering off` | off | Required for TUS resumable uploads (data must stream, not buffer) |
| `proxy_pass` | `http://127.0.0.1:9200` | Plain HTTP on loopback; TLS is terminated at Nginx |
| `X-Forwarded-Proto: $scheme` | https | Tells OpenCloud the client used HTTPS, so it generates correct redirect URLs |
| `Upgrade` / `Connection` | passthrough | Required for WebSocket connections (used by the web UI) |
| `proxy_read_timeout` / `proxy_send_timeout` | 3600s | Long-running uploads and sync sessions |
| `client_max_body_size` | 10G | Maximum single upload size |
| `http2 on` | on | HTTP/2 multiplexing (nginx ≥ 1.25 syntax; this server runs 1.26.3) |

`PROXY_TLS=false` in the container environment tells OpenCloud's internal proxy service that the **external** Nginx handles TLS — so OpenCloud does not attempt to wrap its own HTTP listener in TLS.

---

## Port map

| Port | Listener | Accessible from | Purpose |
|------|----------|-----------------|---------|
| 22 | host (`sshd`) | Internet (UFW allow) | SSH admin access |
| 80 | host (`nginx`) | Internet (UFW allow) | HTTP → HTTPS redirect only |
| 443 | host (`nginx`) | Internet (UFW allow) | HTTPS — TLS termination + reverse proxy |
| 9200 | host → container | `127.0.0.1` only | OpenCloud HTTP proxy service |
| 9140–9300 | container internal | Inside container only | OpenCloud microservices (gRPC + HTTP) |

---

## Quick reference commands

```bash
# Status
cd /opt/opencloud/opencloud-compose
docker compose ps

# Logs (live)
docker compose logs -f opencloud

# Logs (errors only)
docker compose logs opencloud | grep '"level":"error"'

# Restart
docker compose restart opencloud

# Full stop / start
docker compose down
docker compose up -d

# Update image
docker compose pull && docker compose up -d

# Update upstream compose + re-apply KM0 overrides
git -C /opt/opencloud/opencloud-compose pull
/opt/opencloud/scripts/apply-opencloud-compose-overrides.sh

# Check open ports
ss -tulpn | grep -E ':22|:80|:443|:9200'

# Firewall status
ufw status verbose
```

---

## Current deployment notes

- **Web:** https://km0.amvara.de (Nginx `km0` → puerto 9180)
- **OpenCloud:** https://cloud.km0.amvara.de (Nginx `opencloud` → puerto 9200)
- **TLS:** Let's Encrypt en ambos hostnames (`certbot.timer`; contacto ACME en comentarios de `opencloud-compose/.env`).
- **`INSECURE=false`:** OpenCloud valida TLS en URLs públicas (OIDC requiere `https://` en `OC_URL`).
- **Admin password:** `INITIAL_ADMIN_PASSWORD` en `.env` solo en el primer arranque; después, UI (ver runbook).
- **Backups:** [`scripts/backup-volumes.sh`](scripts/backup-volumes.sh) o [`scripts/backup-opencloud-installation.sh`](scripts/backup-opencloud-installation.sh).

Repositorio Git: [`docs/REPOSITORY.md`](docs/REPOSITORY.md) · Operaciones: [`docs/runbook.md`](docs/runbook.md).
