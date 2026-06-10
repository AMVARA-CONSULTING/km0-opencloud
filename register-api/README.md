# register-api

Minimal backend for public self-registration. Creates OpenCloud IDM users via `POST /graph/v1.0/users`.

## Setup

```bash
cp .env.example .env
chmod 600 .env
# Edit GRAPH_SERVICE_USER / GRAPH_SERVICE_PASSWORD (admin or dedicated service account)
```

The service user must be allowed to create users in OpenCloud Graph. Use an admin account or create a dedicated user with the appropriate role in OpenCloud Settings.

## Run

```bash
cd /opt/opencloud/register-api
docker compose up -d --build
curl -s http://127.0.0.1:8091/health
```

## Endpoints

| Path | Method | Description |
|------|--------|-------------|
| `/health` | GET | Liveness + `graph_configured` flag |
| `/register` | POST | JSON `{ "email", "password" }` → create user |

Nginx proxies public `POST /api/register` to `http://127.0.0.1:8091/register`.

## Logs

```bash
docker logs -f opencloud-register-api
```
