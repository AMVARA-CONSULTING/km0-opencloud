# register-api

Minimal backend for public self-registration. Creates OpenCloud IDM users via `POST /graph/v1.0/users`.

## Setup

OpenCloud disables password Basic auth by default (`PROXY_ENABLE_BASIC_AUTH=false`). Use an **app token**, not a user password:

```bash
./scripts/setup-register-api-graph-token.sh
# optional: --user admin  (must have user-create permission)
```

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
| `/health` | GET | Liveness + `graph_configured` + `graph_auth_ok` |
| `/register` | POST | JSON `{ "email", "password" }` → create user |

Nginx proxies public `POST /api/register` to `http://127.0.0.1:8091/register`.

## Logs

```bash
docker logs -f opencloud-register-api
```
