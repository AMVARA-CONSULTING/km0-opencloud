---
## Closing summary (TOP)

- **What happened:** `POST /api/register` returned HTTP 500 because register-api used user-password Basic auth while OpenCloud Graph requires an app token when `PROXY_ENABLE_BASIC_AUTH=false`.
- **What was done:** register-api now authenticates to Graph with `GRAPH_SERVICE_APP_TOKEN`, exposes `graph_auth_ok` in `/health`, maps auth failures to 503, and adds operator scripts plus runbook docs to prevent recurrence.
- **What was tested:** Automated verification passed — health (`graph_auth_ok: true`), smoke script, valid registration (201), public invalid-email (400), register page (200), duplicate registration (409), and stack/nginx baseline checks.
- **Why closed:** All automated test criteria passed; manual browser E2E deferred to operator follow-up.
- **Closed at (UTC):** 2026-06-10 21:23
---

# Register page POST /api/register returns 500 (Graph auth misconfiguration)

## GitHub Issue
- **Issue:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/10
- **Number:** #10
- **Labels:** agent:wip
- **Created:** 2026-06-10T21:19:33Z

## Problem / goal

`POST /api/register` returned HTTP 500. register-api used password Basic auth, but OpenCloud has `PROXY_ENABLE_BASIC_AUTH=false` (default), so Graph returned 401 and the API surfaced a generic 500.

Also requested: prevent this class of misconfiguration from slipping through again.

## Implementation summary

| Area | Changes |
|------|---------|
| `register-api/app.py` | Use `GRAPH_SERVICE_APP_TOKEN` (app token Basic auth); health reports `graph_auth_ok`; 401/auth failures → 503; pre-flight auth check on `/register` |
| `register-api/.env.example` | Document app token requirement; remove password as primary auth |
| `register-api/docker-compose.yml` | Pass `GRAPH_SERVICE_APP_TOKEN` |
| `scripts/setup-register-api-graph-token.sh` | Operator script: create app token, update `.env`, restart register-api |
| `scripts/verify-register-api.sh` | Smoke test (health + validation) — run after deploy |
| `docs/runbook.md`, `register-api/README.md` | Updated operator setup |

**Root cause:** OpenCloud Graph requires app-token Basic auth in production; user passwords only work when `PROXY_ENABLE_BASIC_AUTH=true`.

## Testing instructions

### Deploy

```bash
./scripts/git-sync-main.sh
./scripts/setup-register-api-graph-token.sh   # one-time or when token expires
cd /opt/opencloud/register-api && docker compose up -d --build
./scripts/verify-register-api.sh
```

### Automated (coder verified 2026-06-10)

```bash
# Health — must show graph_auth_ok: true (not just graph_configured)
curl -s http://127.0.0.1:8091/health
# expect: {"graph_auth_ok":true,"graph_configured":true,"ok":true}

# Smoke test script
./scripts/verify-register-api.sh

# Valid registration (loopback)
curl -s -w '\nHTTP:%{http_code}\n' -X POST http://127.0.0.1:8091/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"test-'$(date +%s)'@example.com","password":"Test123!"}'
# expect: {"ok":true} HTTP:201

# Public path (via nginx)
curl -s -w '\nHTTP:%{http_code}\n' -X POST https://cloud.km0digital.com/api/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"invalid","password":"x"}'
# expect: {"error":"invalid_email"} HTTP:400

# Register page still served
curl -sI https://cloud.km0digital.com/register | head -3
# expect: HTTP/2 200
```

### Manual (operator)

1. Private window → https://cloud.km0digital.com/register
2. Register with new email + strong password → redirect to `/login.html?registered=1`
3. Sign in via Dex LDAP → `/files`
4. Duplicate registration → duplicate error (409)

### Notes

- Without a valid app token, `/health` returns `graph_auth_ok: false` and `/register` returns 503 (not 500).
- App tokens expire (default 72h); re-run `setup-register-api-graph-token.sh` or create a long-lived token via OpenCloud Settings.
- Do not enable `PROXY_ENABLE_BASIC_AUTH` in production; use app tokens.

## References
- Repo: https://github.com/AMVARA-CONSULTING/km0-opencloud
- Runbook: docs/runbook.md (Public self-registration section)
- OpenCloud app tokens: https://docs.opencloud.eu/docs/dev/server/services/auth-app/information

---

## Test report

**Date/time (UTC):** 2026-06-10T21:22:16Z – 2026-06-10T21:22:28Z

### Environment
- **Branch:** `main` @ `ebba0b1`
- **Compose:** opencloud stack Up 12 days (opencloud, collabora, collaboration); register-api Up ~45s at test start (127.0.0.1:8091, rebuilt 21:21:35Z)
- **URLs:** `https://cloud.km0digital.com/`, loopback `http://127.0.0.1:9200/`, `http://127.0.0.1:8091/`
- **Stack readiness:** Polled `docker compose ps` (all Up), `GET /health` returned `graph_auth_ok: true` immediately — no fixed sleep

### What was tested
Automated criteria from Testing instructions; `./scripts/verify-register-api.sh`; duplicate registration (API); Docker/nginx baseline checks. Manual operator browser E2E deferred.

### Results

| Criterion | Result | Evidence |
|-----------|--------|----------|
| Health — `graph_auth_ok: true` | **PASS** | `{"graph_auth_ok":true,"graph_configured":true,"ok":true}` |
| Smoke test script | **PASS** | All 4 checks passed (health, graph configured, graph auth ok, invalid email → 400) |
| Valid registration (loopback) | **PASS** | `{"ok":true}` HTTP 201 |
| Public path — invalid email | **PASS** | `POST https://cloud.km0digital.com/api/register` → `{"error":"invalid_email"}` HTTP 400 |
| Register page served | **PASS** | `GET https://cloud.km0digital.com/register` → HTTP/2 200, `content-type: text/html` |
| Duplicate registration | **PASS** | Second POST same email → `{"error":"duplicate"}` HTTP 409 |
| OpenCloud loopback health | **PASS** | `http://127.0.0.1:9200/` → 200 |
| OpenCloud production root | **PASS** | `https://cloud.km0digital.com/` → 302 (redirect, expected) |
| Docker compose (opencloud) | **PASS** | All services Up; recent proxy/auth-app logs show 200 on Graph paths |
| Nginx error log | **PASS** | No register-api upstream errors in test window; prior rate-limit entries only (21:07–21:11Z) |
| Manual: browser registration + LDAP login | **N/A** | Operator follow-up |
| Manual: redirect to `/login.html?registered=1` | **N/A** | Operator follow-up |

**Overall:** **PASS**

### URLs tested
- https://cloud.km0digital.com/
- https://cloud.km0digital.com/register
- https://cloud.km0digital.com/api/register
- http://127.0.0.1:8091/health
- http://127.0.0.1:8091/register
- http://127.0.0.1:9200/

### Log excerpts
```
opencloud-register-api | [2026-06-10 21:21:35 +0000] [1] [INFO] Listening at: http://0.0.0.0:8091 (1)
opencloud-1 | {"service":"proxy","method":"GET","status":200,"path":"/graph/v1.0/users",...,"time":"2026-06-10T21:21:57Z"}
```

**GitHub labels:** `agent:testing` added at test start; removed on pass.
