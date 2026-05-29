---
## Closing summary (TOP)

- **What happened:** The login page at `/login.html` (and root redirect) did not detect an existing OpenCloud OIDC session, so authenticated users saw the login card again in new tabs.
- **What was done:** Updated `host-www/opencloud-auth/login.html` so `hasActiveOidcSession()` scans `localStorage` and `sessionStorage` for `oc_oAuth.user:` (and legacy `oidc.user:`), validates tokens and `expires_at`, and skips auto-forward when OIDC resume query params are present.
- **What was tested:** Deploy, HTTP smoke, unauthenticated behavior, OIDC-resume guard, and mirrored session-detection logic all passed; browser E2E for authenticated auto-forward and post-logout deferred to operator (same pattern as issue #1).
- **Why closed:** Tester overall PASS — all automatable criteria met; operator spot-checks documented for interactive flows.
- **Closed at (UTC):** 2026-05-29 10:46
---

# Login Page Does Not Detect Existing Authenticated Session

## GitHub Issue
- **Issue:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/2
- **Number:** #2
- **Labels:** none
- **Created:** 2026-05-29T10:39:05Z

## Problem / goal
## Issue: Login Page Does Not Detect Existing Authenticated Session  The login page at `https://cloud.km0digital.com/login.html` — and also the root URL `https://cloud.km0digital.com/` (which redirects to the login page) — does not check whether the...

## High-level instructions for coder
- Read the full issue at https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/2
- Identify affected paths under overrides/, dex/, nginx/, host-www/, scripts/, docs/
- Implement minimal, on-scope changes for km0-opencloud
- Add **Testing instructions** before renaming to UNTESTED-

## References
- Repo: https://github.com/AMVARA-CONSULTING/km0-opencloud
- Runbook: docs/runbook.md

## Implementation

- **Root cause:** `login.html` auto-forward checked `oidc.user:` keys in `localStorage` only. OpenCloud web (`config-dex.json` → `tokenStorageLocal: true`) stores the session via oidc-client-ts with prefix **`oc_oAuth.user:`** (authority + client id).
- **Fix:** `host-www/opencloud-auth/login.html` — `hasActiveOidcSession()` scans `localStorage` and `sessionStorage` for `oc_oAuth.user:` (and legacy `oidc.user:`), accepts `access_token` or `id_token`, honors `expires_at`, skips redirect when OIDC resume query params are present (`oidcParamsFromUrl()`).

## Testing instructions

1. **Deploy landing page**
   ```bash
   rsync -a /opt/opencloud/host-www/opencloud-auth/login.html /var/www/opencloud-auth/login.html
   curl -s https://cloud.km0digital.com/login.html | grep -q 'oc_oAuth.user' && echo OK
   ```

2. **Unauthenticated (private window)** — open `https://cloud.km0digital.com/login.html` and `https://cloud.km0digital.com/`; both should show the KM0 login card (root → 302 → login.html), not redirect to `/files`.

3. **Authenticated new tab (issue repro)** — in a normal window, log in and open `/files/spaces/personal/...`. Open a **new tab** and visit `https://cloud.km0digital.com/login.html` → should **302/replace to `/files`** without showing login buttons. Repeat with `https://cloud.km0digital.com/` → same (nginx → login.html → auto-forward).

4. **OIDC resume** — unauthenticated, trigger OpenCloud sign-in so nginx sends you to `/login.html?client_id=...&state=...&code_challenge=...`; login page must **stay** on the picker (no auto-forward) until a provider is chosen.

5. **After logout** — sign out from OpenCloud; visiting `/login.html` must show the login page again.

6. **Smoke**
   ```bash
   curl -sI https://cloud.km0digital.com/ | grep -i '^location:.*login.html'
   curl -sI https://cloud.km0digital.com/login.html | head -1   # HTTP/2 200
   ```

## Test report

**Date/time (UTC):** 2026-05-29T10:43:31Z – 2026-05-29T10:45:11Z  
**Log window:** OpenCloud proxy logs 2026-05-29T10:31:38Z – 2026-05-29T10:43:21Z (container healthy throughout).

### Environment

| Item | Value |
|------|--------|
| Branch / commit | `main` @ `0a042db` |
| Compose | `opencloud-compose/` — `opencloud-opencloud-1` Up 45h, `127.0.0.1:9200→9200` |
| URLs | https://cloud.km0digital.com/, https://cloud.km0digital.com/login.html, http://127.0.0.1:9200/ |
| Stack readiness | `docker compose ps` → opencloud Up; `curl` loopback 200 and production root 302 before checks; `rsync` deployed `login.html` and `diff` confirmed `/var/www/opencloud-auth/login.html` matches repo |

### Results

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | Deploy landing page | **PASS** | `rsync -a …/login.html /var/www/opencloud-auth/login.html`; `grep -q 'oc_oAuth.user'` on live HTML → OK; `diff -q` repo vs deployed → identical |
| 2 | Unauthenticated shows login card | **PASS** | `curl -sI /` → `302` `location: …/login.html`; `curl` login.html → HTTP 200; body contains `id="km0-login-google"` and login card markup (no server-side redirect to `/files`) |
| 3 | Authenticated new tab auto-forwards to `/files` | **NOT VERIFIED** | Requires browser with real OIDC session in `localStorage` (`oc_oAuth.user:…`). No headless browser or user credentials on test host. **Operator:** log in, open new tab to `/login.html` and `/` — expect client-side `location.replace('/files')`. |
| 4 | OIDC resume stays on picker | **PASS** (logic + HTTP) | Python mirror of `hasActiveOidcSession`/`oidcParamsFromUrl`: session + `?client_id&state&code_challenge` → no auto-forward. Live URL with OIDC params → HTTP 200, picker buttons + `startDexLogin` handlers present |
| 5 | After logout shows login again | **NOT VERIFIED** | Requires interactive sign-out in browser. Logic test: empty storage → no auto-forward. **Operator:** sign out, revisit `/login.html` → login card visible |
| 6 | Smoke curls | **PASS** | Root: `location: https://cloud.km0digital.com/login.html`; login.html: `HTTP/2 200`; `root_http_code=302`, `login_http_code=200` |

**Logic unit tests (Python, mirrors live JS):** 5/5 PASS — `oc_oAuth.user:` valid token, expired token rejected, legacy `oidc.user:` accepted, empty storage, OIDC resume blocks forward.

### Overall: **PASS**

Deploy, HTTP smoke, unauthenticated behaviour, OIDC-resume guard, and session-detection logic all pass. Browser E2E for authenticated auto-forward (criterion 3) and post-logout (criterion 5) deferred to operator — same pattern as issue #1 closing report.

### URLs tested

- https://cloud.km0digital.com/ (302 → login.html)
- https://cloud.km0digital.com/login.html (200)
- https://cloud.km0digital.com/login.html?client_id=opencloud-web&state=abc&code_challenge=xyz (200, picker)
- http://127.0.0.1:9200/ (200)

### Log excerpts

```
# docker compose ps
opencloud-opencloud-1   opencloudeu/opencloud-rolling:7.0.0   Up 45 hours   127.0.0.1:9200->9200/tcp

# opencloud proxy (10:40:52Z – active users)
{"service":"proxy","method":"GET","status":200,"path":"/files","time":"2026-05-29T10:40:52Z"}
{"service":"proxy","method":"GET","status":200,"path":"/js/oidc-client-ts-BYLfBBBn.mjs","time":"2026-05-29T10:41:05Z"}
```

**GitHub labels:** `agent:testing` added at test start; removed on pass (issue #2 retains `agent:wip` until closing reviewer).
