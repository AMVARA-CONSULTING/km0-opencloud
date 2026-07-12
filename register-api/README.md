# register-api

Minimal backend for public self-registration. Creates OpenCloud IDM users via `POST /graph/v1.0/users`.

Optional **KM0 Mail** provisioning: when `create_mail=true`, register-api calls km0-mail `mail-provision-api` on the shared Docker network (`km0-mail_mailnet`).

## Setup

OpenCloud disables password Basic auth by default (`PROXY_ENABLE_BASIC_AUTH=false`). Use an **app token**, not a user password:

```bash
./scripts/setup-register-api-graph-token.sh
# optional: --user admin --expires-in 90d  (default 90 days)
```

### Token rotation and auto-renewal

The Graph app token expires (default **90 days**). Rotate manually or enable weekly auto-renewal when fewer than **14 days** remain.

**Manual rotation** (register-api only — does not touch users, volumes, Dex, or OpenCloud config):

```bash
./scripts/setup-register-api-graph-token.sh --expires-in 90d
cd /opt/opencloud/register-api && docker compose up -d --build register-api
./scripts/verify-register-api.sh   # expect graph_auth_ok: true
```

**Auto-renewal** (install once on the host):

```bash
sudo cp /opt/opencloud/scripts/register-api-token-renewal.cron /etc/cron.d/register-api-token-renewal
sudo chmod 644 /etc/cron.d/register-api-token-renewal
```

Runs Mondays at 03:00 UTC; logs to `/var/log/register-api-token-renewal.log`. Force a check:

```bash
./scripts/renew-register-api-graph-token.sh
./scripts/renew-register-api-graph-token.sh --force   # renew regardless of expiry
```

**Safety:** renewal scripts only update `GRAPH_SERVICE_APP_TOKEN` / expiry metadata in `register-api/.env` and restart **register-api**. They must **not** run `docker compose down -v`, delete volumes, reset users, or change Dex/OIDC settings. A failed renewal leaves existing Google OAuth login unaffected.

Or manually:

```bash
cp .env.example .env
chmod 600 .env
docker exec opencloud-opencloud-1 opencloud auth-app create --user-name admin
# Set GRAPH_SERVICE_USER and GRAPH_SERVICE_APP_TOKEN in .env
```

## Run

```bash
cd /opt/opencloud/register-api
docker compose up -d --build
curl -s http://127.0.0.1:8091/health
# expect: {"graph_auth_ok": true, "graph_configured": true, "ok": true}
```

Verify after deploy:

```bash
./scripts/verify-register-api.sh
```

## Endpoints

| Path | Method | Description |
|------|--------|-------------|
| `/health` | GET | Liveness + Graph + mail-provision status |
| `/register` | POST | JSON `{ "email", "password", "create_mail?", "mail_mode?", "desired_email?", "contact_email?" }` |
| `/update-password` | POST | JSON `{ "email", "password" }` → sync mailbox password in km0-mail |

**Mail fields:** `create_mail=true` provisions a mailbox via km0-mail (freemail domains blocked as mailbox). Set `MAIL_PROVISION_API_TOKEN` in `.env` (same value as km0-mail). Container joins external network `km0-mail_mailnet`.

Nginx proxies public `POST /api/register` to `http://127.0.0.1:8091/register` (cloud and mail hostnames).

## Logs

```bash
docker logs -f opencloud-register-api
```
