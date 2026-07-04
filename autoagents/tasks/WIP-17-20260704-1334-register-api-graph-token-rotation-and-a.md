# Register API Graph token rotation and auto-renewal

## GitHub Issue
- **Issue:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/17
- **Number:** #17
- **Labels:** agent:wip
- **Created:** 2026-07-04T13:33:25Z

## Problem / goal

The `register-api` requires a valid OpenCloud Graph App Token in `GRAPH_SERVICE_APP_TOKEN`. Tokens expire (default was 72h); expired tokens cause `graph_auth_ok: false` and registration 503s while Google OAuth remains unaffected. Implement 3-month token lifetime, manual rotation, and safe auto-renewal (14-day threshold) scoped to register-api only.

## Implementation

| Path | Change |
|------|--------|
| `scripts/setup-register-api-graph-token.sh` | `--expires-in 90d` (default), `--no-restart`; writes `GRAPH_SERVICE_APP_TOKEN_EXPIRES_AT`; passes `--expiration` to `opencloud auth-app create` |
| `scripts/renew-register-api-graph-token.sh` | New — checks expiry/health; renews when `<14` days or `graph_auth_ok` false; restarts register-api only |
| `scripts/register-api-token-renewal.cron` | Cron template — Mondays 03:00 UTC |
| `scripts/verify-register-api.sh` | Require `graph_auth_ok: true` (not just key present) |
| `register-api/.env.example` | Document expiry metadata field |
| `register-api/README.md` | Rotation and auto-renewal operator docs |
| `docs/runbook.md` | Manual/auto renewal + safety constraints |
| `docs/register-api-graph-token-rotation-20260715.red` | Blog/Redmine summary (English Textile) |
| `docs/CHANGELOG.md` | Unreleased entry |

## References
- Repo: https://github.com/AMVARA-CONSULTING/km0-opencloud
- Runbook: docs/runbook.md
- Incident: docs/register-incident-20260704-fundaalicates-yahoo.md

## Testing instructions

1. **Syntax / help**
   ```bash
   bash -n scripts/setup-register-api-graph-token.sh
   bash -n scripts/renew-register-api-graph-token.sh
   ./scripts/setup-register-api-graph-token.sh --help
   ./scripts/renew-register-api-graph-token.sh --help
   ```

2. **Manual token setup** (requires valid Graph service user, e.g. admin or delegated uid):
   ```bash
   ./scripts/setup-register-api-graph-token.sh --expires-in 90d
   grep GRAPH_SERVICE_APP_TOKEN_EXPIRES_AT register-api/.env
   ./scripts/verify-register-api.sh
   curl -s http://127.0.0.1:8091/health | jq .
   # expect graph_auth_ok: true
   ```

3. **Renewal skip path** — after successful setup, with expiry >14 days away:
   ```bash
   ./scripts/renew-register-api-graph-token.sh
   # expect INFO ... skipping renewal
   ```

4. **Renewal trigger** — simulate near-expiry by setting `GRAPH_SERVICE_APP_TOKEN_EXPIRES_AT` to 7 days ahead in `register-api/.env`, then:
   ```bash
   ./scripts/renew-register-api-graph-token.sh
   # expect renewal + verify pass
   ```

5. **Force renewal**
   ```bash
   ./scripts/renew-register-api-graph-token.sh --force
   ```

6. **Fail-safe** — confirm renewal failure (e.g. invalid `--user`) exits non-zero without touching opencloud/dex volumes or unrelated `.env`:
   ```bash
   ./scripts/setup-register-api-graph-token.sh --user nonexistent 2>&1; echo exit:$?
   docker compose -f opencloud-compose/docker-compose.yml ps
   docker ps --filter name=opencloud-opencloud
   ```

7. **Cron template** — verify file installs cleanly:
   ```bash
   cat scripts/register-api-token-renewal.cron
   ```

8. **Regression** — Google OAuth login path unchanged (Dex/opencloud not restarted by renewal scripts).

**Note:** Live token creation requires a valid OpenCloud user with user-create permission. Dev host may show `graph_auth_ok: false` until operator runs setup with correct `--user`.

---

## Test report

**Date/time (UTC):** 2026-07-04 13:36:15 – 13:37:10 UTC  
**Log window:** register-api gunicorn 13:13:52 / 13:37:02 UTC; opencloud logs through 13:37:05 UTC

### Environment

| Item | Value |
|------|-------|
| Branch | `main` @ `e1d1e40` (synced, up to date) |
| register-api | `opencloud-register-api` Up on `127.0.0.1:8091` |
| opencloud-compose | opencloud, collabora, collaboration — all Up |
| dex | `opencloud-dex` Up (not in opencloud-compose stack; separate container) |
| Stack ready | Polled `GET http://127.0.0.1:8091/health` until JSON 200; `docker compose ps` all Up |

### What was tested

All eight criteria from Testing instructions: script syntax/help, manual token setup, renewal skip/trigger/force paths, fail-safe invalid user, cron template, verify script, and opencloud/dex regression (no unintended restarts).

### Results

| Criterion | Result | Evidence |
|-----------|--------|----------|
| 1. Syntax / help | **PASS** | `bash -n` both scripts OK; `--help` shows `--expires-in 90d`, 14-day threshold, `--force` |
| 2. Manual token setup | **PASS** (with `--user`) | Default `admin` user not in IDM (`user not found username admin`). `./scripts/setup-register-api-graph-token.sh --user yoelberjaga@gmail.com --expires-in 90d` → wrote `GRAPH_SERVICE_APP_TOKEN_EXPIRES_AT`, restarted register-api; final `/health` → `graph_auth_ok:true`; `./scripts/verify-register-api.sh` → all PASS |
| 3. Renewal skip (>14d) | **PASS** | After setup: `[2026-07-04T13:36:52Z] INFO Token valid for 89 more day(s) (threshold 14); skipping renewal` exit 0 |
| 4. Renewal trigger (<14d) | **FAIL** | Set expiry +7d; renew detected `7 day(s) remaining (< 14)` but called setup with default `admin` (not `GRAPH_SERVICE_USER` from `.env`) → `user not found username admin`, exit 1. With `GRAPH_SERVICE_USER=yoelberjaga@gmail.com` exported, renewal succeeded but script exit 1 (verify race, see below) |
| 5. Force renewal | **FAIL** | `./scripts/renew-register-api-graph-token.sh --force` → `Creating app token for user: admin` → exit 1 (same missing `.env` user propagation) |
| 6. Fail-safe invalid user | **PASS** | `./scripts/setup-register-api-graph-token.sh --user nonexistent` → exit 1; `opencloud-opencloud-1` started `2026-06-14T13:02:36Z` unchanged |
| 7. Cron template | **PASS** | `scripts/register-api-token-renewal.cron` — Monday 03:00 UTC, `flock`, logs to `/var/log/register-api-token-renewal.log` |
| 8. Regression (Dex/opencloud) | **PASS** | opencloud container start time unchanged (2 weeks); dex Up separately; `https://cloud.km0digital.com/` → 302; `http://127.0.0.1:9200/` → 200 |

### Defects found

1. **`renew-register-api-graph-token.sh` does not pass service user from `register-api/.env`** — calls `setup-register-api-graph-token.sh` without `--user`, so setup defaults to `admin` even when `.env` has a different `GRAPH_SERVICE_USER`. Breaks renewal trigger, force renewal, and cron auto-renewal on hosts without an `admin` IDM user.
2. **Verify race after register-api restart** — renew script runs `verify-register-api.sh` immediately after `docker compose up -d`; health empty → verify fails → renew exits 1 even when token renewal succeeded (manual verify 2s later passes).

### Overall

**FAIL** — Renewal paths (criteria 4–5) broken when service user ≠ `admin`; cron would hit the same bug. Setup, skip logic, fail-safe, docs artifacts, and stack isolation work as intended.

### URLs tested

- http://127.0.0.1:8091/health
- http://127.0.0.1:8091/register
- http://127.0.0.1:9200/
- https://cloud.km0digital.com/

### Log excerpts

```text
# Initial state (expired token)
GET /health → {"graph_auth_ok":false,"graph_configured":true,"ok":true}
opencloud-register-api | ERROR Graph API credentials rejected — run scripts/setup-register-api-graph-token.sh

# Setup with valid OAuth admin user
Creating app token for user: yoelberjaga@gmail.com (expiration: 90d → 2160h)
Updated register-api/.env (GRAPH_SERVICE_APP_TOKEN set; expires 2026-10-02T13:37:00Z)

# Renewal skip
[2026-07-04T13:36:52Z] INFO Token valid for 89 more day(s) (threshold 14); skipping renewal

# Renewal trigger failure (bug)
[2026-07-04T13:36:56Z] INFO Starting register-api Graph token renewal (7 day(s) remaining (< 14))
Creating app token for user: admin (expiration: 90d → 2160h)
Error: user not found username admin

# Fail-safe
./scripts/setup-register-api-graph-token.sh --user nonexistent → exit:1
opencloud-opencloud-1 started 2026-06-14T13:02:36.935255363Z (unchanged)
```

**GitHub labels:** `agent:testing` added at test start; reverted to `agent:wip` on fail.
