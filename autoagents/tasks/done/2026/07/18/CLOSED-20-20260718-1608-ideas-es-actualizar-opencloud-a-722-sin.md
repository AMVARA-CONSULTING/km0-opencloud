---
## Closing summary (TOP)

- **What happened:** Upgrade OpenCloud from 7.0.0 to 7.3.0 was requested without data loss and with custom nginx + Dex login intact.
- **What was done:** Volume backups, pinned `OC_DOCKER_TAG=7.3.0`, set required IDM LDAPS cert/key overrides for 7.3+, applied overrides, and documented the upgrade path.
- **What was tested:** Cold gate PASS — image/productversion 7.3.0, no ldaps_addr/fatal, Dex/login redirects OK, backups present, Collabora discovery 200; browser file listing skipped.
- **Why closed:** All mandatory acceptance criteria passed (issue #20 fully delivered).
- **Closed at (UTC):** 2026-07-18 17:06
---

# [ideas/es] Actualizar OpenCloud a 7.3.0 sin perder datos

## GitHub Issue
- **Issue:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/20
- **Number:** #20
- **Labels:** agent:wip
- **Created:** 2026-07-18T16:06:15Z

## Problem / goal
Upgrade OpenCloud from `7.0.0` to **`7.3.0`** (human note: target 7.3.0, not 7.2.2) without losing volume data, keeping custom nginx + Dex login working.

## What was done

### Ops (live, not in git)
- Volume backup before upgrade: `/var/backups/opencloud/20260718-181001/` (and script re-run `20260718-181059/`).
- `opencloud-compose/.env`: `OC_DOCKER_TAG=7.3.0`; quoted `SMTP_SENDER` so `backup-volumes.sh` can `source` `.env`.
- `docker compose pull` + `up -d` for `opencloud` and `collaboration` → image `opencloudeu/opencloud-rolling:7.3.0`.
- Confirmed `sharing.service_account` already present in config volume (from 6→7 upgrade); no OpenSearch reindex (embedded search).

### Repo
- `overrides/opencloud-compose/.env.*.example`: pin `OC_DOCKER_TAG=7.3.0`.
- `overrides/opencloud-compose/external-proxy/opencloud.yml`: set `IDM_LDAPS_CERT` / `IDM_LDAPS_KEY` — **required on 7.3+** when `IDM_LDAPS_ADDR` is set (Dex → IDM `:9235`). Without this, OpenCloud crash-loops with `ldaps_addr is set but cert is not set`.
- Docs: `README.md`, `docs/runbook.md` (inventory, upgrade steps, 7.3 LDAPS note, deployment history), `docs/CHANGELOG.md`.
- Applied overrides via `./scripts/apply-opencloud-compose-overrides.sh`.

### Verified locally (coder smoke)
- `status.php` → `productversion: 7.3.0`, installed, not maintenance.
- Dex OIDC discovery 200; LDAP auth start → 302 `/dex/auth/ldap`.
- Cloud `/login.html` → 302 auth hub; register-api `/health` → `graph_auth_ok: true`.

## Testing instructions

1. **Compose / image**
   ```bash
   cd /opt/opencloud/opencloud-compose
   docker compose ps
   docker inspect opencloud-opencloud-1 --format '{{.Config.Image}}'
   # expect: opencloudeu/opencloud-rolling:7.3.0 (opencloud + collaboration)
   ```

2. **Product version + health**
   ```bash
   curl -s http://127.0.0.1:9200/status.php
   curl -sI https://cloud.km0digital.com/status.php
   # expect productversion 7.3.0, installed true, maintenance false, HTTP 200
   ```

3. **No fatal OpenCloud errors after upgrade window**
   ```bash
   docker logs --since 15m opencloud-opencloud-1 2>&1 | grep -E '"level":"(error|fatal)"|ldaps_addr' || true
   # expect: no ldaps_addr cert errors; no fatal restart loop
   ```

4. **Custom login (nginx + Dex) still works**
   ```bash
   curl -sI https://cloud.km0digital.com/login.html | grep -iE '^(HTTP|location:)'
   # expect 302 → auth.km0digital.com
   curl -sI https://cloud.km0digital.com/dex/.well-known/openid-configuration | head -3
   curl -sI "https://cloud.km0digital.com/dex/auth?client_id=OpenCloudWeb&redirect_uri=https://cloud.km0digital.com/oidc-callback.html&response_type=code&scope=openid&connector_id=ldap" | grep -iE '^(HTTP|location:)'
   # expect 302 → /dex/auth/ldap
   docker logs --since 10m opencloud-dex 2>&1 | grep -iE 'error|fatal' || true
   ```

5. **Data preserved (spot-check)**
   - Confirm backup dirs exist under `/var/backups/opencloud/20260718-*`.
   - Browser: sign in via auth hub / Dex LDAP or Google; existing files/spaces still listed.

6. **Collabora / WOPI still up**
   ```bash
   docker compose ps collabora collaboration
   curl -sI http://127.0.0.1:9980/hosting/discovery | head -3
   ```

7. **Override pin present**
   ```bash
   grep -E 'IDM_LDAPS_(ADDR|CERT|KEY)|OC_DOCKER_TAG' \
     overrides/opencloud-compose/external-proxy/opencloud.yml \
     overrides/opencloud-compose/.env.debian-collabora-external-proxy.example
   ```

## References
- Repo: https://github.com/AMVARA-CONSULTING/km0-opencloud
- Runbook: docs/runbook.md
- Upstream: https://github.com/opencloud-eu/opencloud/releases/tag/v7.3.0

## Test report

1. **Date/time (UTC) and log window:** 2026-07-18T17:05:43Z start → 2026-07-18T17:05:56Z end. Log window: `docker logs --since 15m` (opencloud), `--since 10m` (dex).
2. **Environment:** branch `main` (synced). Compose in `/opt/opencloud/opencloud-compose`. URLs: `https://cloud.km0digital.com`, `https://auth.km0digital.com`, `https://collabora.km0digital.com`, loopback `:9200` / `:9980`. Stack ready: `status.php` returned `productversion: 7.3.0` with `installed: true` / `maintenance: false`; `opencloud-opencloud-1` Up since 2026-07-18T16:14:34Z, RestartCount=0.
3. **What was tested:** Acceptance items 1–7 from Testing instructions (compose/image, status.php, error/fatal/ldaps_addr scan, Dex login redirects, backup dirs, Collabora discovery, override pins). Browser file listing skipped (no test user in session).
4. **Results:**
   - Compose / image **PASS** — `opencloudeu/opencloud-rolling:7.3.0` on opencloud + collaboration; all three services Up (collabora healthy).
   - Product version + health **PASS** — loopback and public `status.php`: `productversion: 7.3.0`, installed true, maintenance false; public HTTP 200.
   - No fatal / ldaps_addr after upgrade **PASS** — 0× `ldaps_addr`, 0× `"level":"fatal"` in 15m; RestartCount=0. Note: recurring proxy OIDC JWKS “key ID was not found” on `/notifications/sse` from a browser client (stale token), not upgrade/LDAPS failure.
   - Custom login (nginx + Dex) **PASS** — `/login.html` → 302 `https://auth.km0digital.com/login?service=cloud`; OIDC discovery HTTP 200; Dex LDAP auth start → 302 `/dex/auth/ldap`; auth hub HTTP 200; no dex error/fatal in 10m.
   - Data preserved (spot-check) **PASS** (backups) / **SKIP** (browser) — `/var/backups/opencloud/20260718-181001/` and `…-181059/` contain config + ~1.7GB data tarballs; no interactive login to list spaces.
   - Collabora / WOPI still up **PASS** — collabora Up (healthy); collaboration Up; `http://127.0.0.1:9980/hosting/discovery` and public collabora discovery HTTP 200.
   - Override pin present **PASS** — `IDM_LDAPS_ADDR/CERT/KEY` in `opencloud.yml`; `OC_DOCKER_TAG=7.3.0` in collabora external-proxy example.
5. **Overall: PASS**
6. **URLs tested:** `http://127.0.0.1:9200/status.php`, `https://cloud.km0digital.com/status.php`, `/login.html`, `/dex/.well-known/openid-configuration`, `/dex/auth?…connector_id=ldap`, `https://auth.km0digital.com/`, `http://127.0.0.1:9980/hosting/discovery`, `https://collabora.km0digital.com/hosting/discovery`.
7. **Log excerpts:** No `ldaps_addr` / fatal. Sample non-blocking noise: `failed to verify access token… key ID was not found in the JWKS` on notifications SSE (client). NATS parser ERROR lines when HTTP hit NATS port (noise from probes).
