---
## Closing summary (TOP)

- **What happened:** After OpenCloud 7.3.0, collaboration crash-looped on NATS loopback (`127.0.0.1:9233`) so WOPI returned nginx 502.
- **What was done:** Added `overrides/.../collabora.yml` pointing events/store endpoints at `opencloud:9233`, wired apply script + docs, recreated collaboration.
- **What was tested:** Cold gate PASS — NATS errors 0, register line present, WOPI 404 (not 502) with `X-Collaboration-Version: 7.3.0`, Collabora/auth/cloud OK; browser editor skipped.
- **Why closed:** All mandatory acceptance criteria passed.
- **Closed at (UTC):** 2026-07-18 17:06
---

# Fix collaboration NATS / WOPI 502 after OpenCloud 7.3.0

## Context
- **Related:** upgrade task `UNTESTED-20-…` (OpenCloud **7.3.0** already live: `status.php` → `productversion: 7.3.0`).
- **This task is separate:** core Cloud works; **WOPI / collaboration** does not.
- **Do not** roll back to 7.0.0. Fix networking/config so collaboration joins the OpenCloud NATS registry on 7.3.0.
- Prefer **overrides + `scripts/apply-opencloud-compose-overrides.sh`**. Do not edit upstream `opencloud-compose/` clone directly except via that apply path.
- Never commit secrets (`.env`, volume yaml secrets, tokens).

## Problem / goal
After the 7.0.0 → 7.3.0 upgrade, `opencloud-collaboration-1` crash-loops / backoff-retries on NATS and never serves HTTP on `:9300`. Nginx `wopi.km0digital.com` returns **502**.

## What was done

### Root cause
- `MICRO_REGISTRY_ADDRESS=opencloud:9233` (weboffice overlay) **worked** — logs showed `registering external service eu.opencloud.api.collaboration-…`.
- OpenCloud **7.3.0** added `COLLABORATION_EVENTS_ENDPOINT` (default **`127.0.0.1:9233`**). The events JetStream client inside the collaboration container kept retrying loopback → WOPI HTTP never healthy → nginx **502**.
- Store nodes (`COLLABORATION_STORE_NODES`) also default to loopback; set them as well for consistency.

### Fix (overrides only)
- Added `overrides/opencloud-compose/external-proxy/collabora.yml` with:
  - `OC_EVENTS_ENDPOINT` / `COLLABORATION_EVENTS_ENDPOINT` → `opencloud:9233`
  - `OC_PERSISTENT_STORE_NODES` / `COLLABORATION_STORE_NODES` → `opencloud:9233`
  - (keeps existing loopback port publishes for `:9300` / `:9980`)
- `scripts/apply-opencloud-compose-overrides.sh` now copies that file into the compose clone.
- Documented in `docs/runbook.md`, `overrides/opencloud-compose/README.md`, `docs/CHANGELOG.md`.
- Applied + `docker compose up -d --force-recreate collaboration` (no volume wipe).

### Cold evidence (coder)
- productversion **7.3.0**; image `opencloudeu/opencloud-rolling:7.3.0`
- collaboration Up; **0** matches for `error connecting to nats` / `127.0.0.1:9233` after recreate
- register line present; `curl -sI http://127.0.0.1:9300/` and `https://wopi.km0digital.com/` → **404** with `X-Collaboration-Version: 7.3.0` (not 502)
- Collabora discovery **200**; cloud login → auth hub; auth **200**

## Acceptance criteria
- [x] `opencloud-collaboration-1` Up, not restart-looping on NATS
- [x] Logs (last 5m): **no** repeating `error connecting to nats at 127.0.0.1:9233`
- [x] Prefer a successful register line for `eu.opencloud.api.collaboration` (or equivalent 7.3.0 registry success)
- [x] `curl -sI http://127.0.0.1:9300/` returns a real HTTP status (not connection refused); `https://wopi.km0digital.com/` is **not** 502
- [x] `https://collabora.km0digital.com/hosting/discovery` still 200; Cloud still `productversion: 7.3.0`
- [x] Dex/auth and `https://cloud.km0digital.com/` still OK (no login regression)
- [x] No secrets committed

## Testing instructions (cold gate for tester)

Tester must run these **after** a fresh `docker compose up -d` / recreate of collaboration (or full opencloud+collaboration). Soft “container Up” alone is **FAIL**.

1. **Version still 7.3.0**
   ```bash
   curl -s http://127.0.0.1:9200/status.php | grep productversion
   docker inspect opencloud-opencloud-1 --format '{{.Config.Image}}'
   # expect: productversion 7.3.0 ; opencloudeu/opencloud-rolling:7.3.0
   ```

2. **Compose health**
   ```bash
   cd /opt/opencloud/opencloud-compose
   docker compose ps opencloud collaboration collabora
   # expect: all Up; collabora healthy
   ```

3. **Override env present on collaboration**
   ```bash
   docker exec opencloud-collaboration-1 sh -c 'env | grep -E "EVENTS_ENDPOINT|STORE_NODES|MICRO_REGISTRY_ADDRESS"'
   # expect: OC_EVENTS_ENDPOINT / COLLABORATION_EVENTS_ENDPOINT / STORE_NODES = opencloud:9233
   #         MICRO_REGISTRY_ADDRESS=opencloud:9233
   ```

4. **NATS error absence (hard)**
   ```bash
   docker logs --since 5m opencloud-collaboration-1 2>&1 | tee /tmp/collab-nats-test.log
   grep -c 'error connecting to nats' /tmp/collab-nats-test.log || true
   grep -c '127.0.0.1:9233' /tmp/collab-nats-test.log || true
   grep 'registering external service' /tmp/collab-nats-test.log || true
   # expect: zero matches for both error greps after the fix window (allow startup race only in first ~15s; then stable)
   # expect: at least one registering external service eu.opencloud.api.collaboration-… line
   ```

5. **WOPI HTTP (hard)**
   ```bash
   curl -sI --max-time 10 http://127.0.0.1:9300/ | head -5
   curl -sI --max-time 10 https://wopi.km0digital.com/ | head -5
   # expect: loopback returns HTTP (404 on / is OK; header X-Collaboration-Version: 7.3.0)
   # expect: public WOPI must NOT be 502
   ```

6. **Collabora still up**
   ```bash
   curl -sI --max-time 10 https://collabora.km0digital.com/hosting/discovery | head -5
   # expect: 200
   ```

7. **Auth / Cloud regression**
   ```bash
   curl -sI --max-time 10 https://cloud.km0digital.com/login.html | grep -iE '^(HTTP|location:)'
   curl -sI --max-time 10 https://auth.km0digital.com/ | head -3
   # expect: cloud login redirects to auth hub; auth HTTP 200
   ```

8. **Optional browser spot-check (if tester has a test user)**  
   Open a `.docx` / `.xlsx` from Cloud → Collabora editor loads (not endless spinner / WOPI error). If no test user, document skip; criteria 1–7 remain mandatory.

## References
- Overlay: `opencloud-compose/weboffice/collabora.yml` (`MICRO_REGISTRY_ADDRESS`, `NATS_NATS_HOST`)
- KM0 fix: `overrides/opencloud-compose/external-proxy/collabora.yml`
- Runbook: `docs/runbook.md` (section “WOPI / collaboration NATS after OpenCloud 7.3.0 upgrade”)
- Prior Collabora enablement: archived `CLOSED-3-…-collabora-online-browser-document-editin.md`
- Nginx: `/etc/nginx/sites-enabled/wopi` → `127.0.0.1:9300`

## Test report

1. **Date/time (UTC) and log window:** 2026-07-18T17:06:18Z start → 2026-07-18T17:06:25Z end. Collaboration log window: `docker logs --since 5m` (container StartedAt 2026-07-18T17:04:22Z).
2. **Environment:** branch `main` (synced). Compose `/opt/opencloud/opencloud-compose`. Override `overrides/opencloud-compose/external-proxy/collabora.yml` applied. Ready signal: collaboration Up RestartCount=0 with register line + WOPI HTTP 404 (not 502) and `X-Collaboration-Version: 7.3.0`.
3. **What was tested:** Cold-gate criteria 1–7 from Testing instructions. Criterion 8 (browser .docx/.xlsx) skipped — no test user in this session.
4. **Results:**
   - Version still 7.3.0 **PASS** — `productversion: 7.3.0`; image `opencloudeu/opencloud-rolling:7.3.0`.
   - Compose health **PASS** — opencloud / collaboration / collabora all Up; collabora healthy.
   - Override env on collaboration **PASS** — `OC_EVENTS_ENDPOINT`, `COLLABORATION_EVENTS_ENDPOINT`, `OC_PERSISTENT_STORE_NODES`, `COLLABORATION_STORE_NODES`, `MICRO_REGISTRY_ADDRESS` all `opencloud:9233`.
   - NATS error absence **PASS** — `error connecting to nats` count **0**; `127.0.0.1:9233` count **0**; register line present: `registering external service eu.opencloud.api.collaboration-…@172.18.0.5:9301` at 17:04:23Z.
   - WOPI HTTP **PASS** — loopback `:9300` HTTP 404 + `X-Collaboration-Version: 7.3.0`; public `https://wopi.km0digital.com/` HTTP 404 (not 502) + same version header.
   - Collabora discovery **PASS** — `https://collabora.km0digital.com/hosting/discovery` HTTP 200.
   - Auth / Cloud regression **PASS** — `/login.html` → 302 auth hub; `https://auth.km0digital.com/` HTTP 200.
   - No secrets committed **PASS** — override has only host endpoints / loopback ports; no PASSWORD/SECRET/TOKEN keys.
   - Optional browser editor **SKIP** — no test user.
5. **Overall: PASS**
6. **URLs tested:** `http://127.0.0.1:9200/status.php`, `http://127.0.0.1:9300/`, `https://wopi.km0digital.com/`, `https://collabora.km0digital.com/hosting/discovery`, `https://cloud.km0digital.com/login.html`, `https://auth.km0digital.com/`.
7. **Log excerpts:** Register success at 17:04:23Z; subsequent access-log HEAD/GET `/` → status 404 (expected). Zero NATS connect errors in 5m window.
