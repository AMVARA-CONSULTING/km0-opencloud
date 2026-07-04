---
## Closing summary (TOP)

- **What happened:** The register-api Graph app token expired on a short default lifetime, causing `graph_auth_ok: false` and registration 503s while Google OAuth remained unaffected.
- **What was done:** Added 90-day token setup and renewal scripts with 14-day auto-renewal threshold, health polling after restart, cron template, verify checks, and operator/runbook documentation scoped to register-api only.
- **What was tested:** All eight criteria passed — syntax/help, manual setup, renewal skip/trigger/force paths, fail-safe on invalid user, cron template, and OAuth regression (opencloud/dex not restarted).
- **Why closed:** All test criteria passed after post-fix verification of `.env` user propagation and health wait behavior.
- **Closed at (UTC):** 2026-07-04 16:22
---

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
| `scripts/renew-register-api-graph-token.sh` | Checks expiry/health; renews when `<14` days or `graph_auth_ok` false; passes `--user` from `register-api/.env`; waits for health after restart |
| `scripts/setup-register-api-graph-token.sh` | Reads `GRAPH_SERVICE_USER` from `.env` when `--user` omitted; health wait after restart |
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

**Note:** Live token creation requires a valid OpenCloud user with user-create permission. Setup and renewal read `GRAPH_SERVICE_USER` from `register-api/.env` when `--user` is not passed (default `admin` only when unset).

## Fixes (2026-07-04, post-test)

- **Renewal user propagation:** `renew-register-api-graph-token.sh` passes `--user` from `GRAPH_SERVICE_USER` in `register-api/.env` (setup script also reads `.env` when `--user` omitted).
- **Health wait:** Both renewal and setup scripts poll `/health` for up to 30s (`REGISTER_API_HEALTH_WAIT_SEC`) after register-api restart before verify/exit.

---

## Prior test report (superseded — defects fixed above)

<details>
<summary>2026-07-04 tester FAIL (criteria 4–5) — fixed</summary>

Defects: (1) renew did not pass service user from `.env`; (2) verify race after restart. Both addressed in this WIP iteration.

</details>

---

## Test report

**Date/time (UTC):** 2026-07-04T16:21:31Z – 2026-07-04T16:21:47Z  
**Log window:** register-api container restarts during criteria 4–5 only; opencloud/dex logs unchanged in window.

### Environment

- **Branch:** `main` @ `f0cc107` (feat(register-api): Graph app token rotation and auto-renewal)
- **Compose:** `opencloud-opencloud-1` Up 2 weeks (9200), `opencloud-collabora-1` Up 5 weeks (healthy), `opencloud-collaboration-1` Up 5 weeks, `opencloud-register-api` Up (restarted during renewal tests)
- **Service user:** `GRAPH_SERVICE_USER=yoelberjaga@gmail.com` (from `register-api/.env`)
- **URLs:** http://127.0.0.1:8091/health, http://127.0.0.1:9200/

### Stack readiness

Polled `http://127.0.0.1:8091/health` until `graph_auth_ok: true` (scripts use `REGISTER_API_HEALTH_WAIT_SEC=30` with 2s interval). No fixed sleeps; renewal scripts reported health within ~2s after register-api restart.

### What was tested

1. Syntax / help for setup and renew scripts
2. Health + verify (graph_auth_ok, expiry metadata)
3. Renewal skip when expiry >14 days
4. Renewal trigger with simulated 7-day expiry
5. Force renewal (`--force`)
6. Fail-safe with invalid `--user nonexistent`
7. Cron template content
8. Regression — opencloud/dex not restarted by renewal scripts

### Results

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | Syntax / help | **PASS** | `bash -n` OK on both scripts; `--help` shows `--expires-in 90d`, `--no-restart`, threshold 14 days |
| 2 | Manual setup / verify | **PASS** | `GRAPH_SERVICE_APP_TOKEN_EXPIRES_AT=2026-10-02T16:20:46Z`; health `{"graph_auth_ok":true,"graph_configured":true,"ok":true}`; all 4 verify checks PASS |
| 3 | Renewal skip (>14 days) | **PASS** | `[2026-07-04T16:21:35Z] INFO Token valid for 89 more day(s) (threshold 14); skipping renewal` |
| 4 | Renewal trigger (<14 days) | **PASS** | Set expiry to +7 days; renewed for user `yoelberjaga@gmail.com` (from `.env`); new expiry `2026-10-02T16:21:37Z`; verify PASS after health wait |
| 5 | Force renewal | **PASS** | `--force` completed; verify PASS; `register-api Graph token renewal completed successfully` |
| 6 | Fail-safe (invalid user) | **PASS** | `setup ... --user nonexistent` exit 1; `opencloud-opencloud-1` still Up 2 weeks; health/verify still PASS afterward |
| 7 | Cron template | **PASS** | Valid crontab: Mondays 03:00 UTC, `flock`, scoped to renew script + log file |
| 8 | OAuth regression | **PASS** | `opencloud-opencloud-1` Up 2 weeks; `opencloud-dex` Up 3 hours; loopback OpenCloud HTTP 200 — not restarted by renewal scripts |

### Overall: **PASS**

All criteria pass. Post-fix verification confirms renewal user propagation from `.env` and health polling after restart work correctly.

### URLs tested

- http://127.0.0.1:8091/health (200, graph_auth_ok: true)
- http://127.0.0.1:9200/ (200)

### Log excerpts

```
# renewal skip (16:21:35Z)
[2026-07-04T16:21:35Z] INFO Token valid for 89 more day(s) (threshold 14); skipping renewal

# renewal trigger — user from .env (16:21:37Z)
[2026-07-04T16:21:37Z] INFO Starting register-api Graph token renewal (7 day(s) remaining (< 14))
[2026-07-04T16:21:37Z] INFO Generating new token for user yoelberjaga@gmail.com (expires-in 90d)
Creating app token for user: yoelberjaga@gmail.com (expiration: 90d → 2160h)
Health: {"graph_auth_ok":true,"graph_configured":true,"ok":true}

# fail-safe (16:21:48Z)
Creating app token for user: nonexistent (expiration: 90d → 2160h)
exit:1

# docker compose ps
opencloud-opencloud-1       Up 2 weeks   127.0.0.1:9200->9200/tcp
opencloud-register-api      Up (restarted during tests 4–5 only)
```

**GitHub labels:** `agent:testing` added at test start; removed on pass.
