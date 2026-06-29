---
## Closing summary (TOP)

- **What happened:** Issue #15 requested aligning Dex/desktop auth views with the km0digital login experience, including payment messaging, branded logout, and test coverage.
- **What was done:** Desktop Dex login switched to card layout with pricing notice; host-www login/register pricing blocks added; new branded `/logout` page with Dex end_session support; nginx and Dex config updated; Playwright suite and curl smoke script added.
- **What was tested:** All automated smoke and functional criteria passed on production (`verify-auth-pages.sh`, OAuth param preservation, LDAP error state, Docker health); Playwright visual/a11y and manual E2E deferred (Node unavailable / interactive scope).
- **Why closed:** All in-scope automated test criteria passed; tester marked overall **PASS**.
- **Closed at (UTC):** 2026-06-29 23:59
---

# Align desktop login, payment messaging, logout styling, and test coverage

## GitHub Issue
- **Issue:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/15
- **Number:** #15
- **Labels:** agent:wip
- **Created:** 2026-06-29T23:53:28Z

## Problem / goal
Align authentication views with the main km0digital login experience: desktop Dex login card layout, payment explanation on login, branded logout page, and Playwright test coverage.

## Implementation summary

### Desktop Dex login alignment
- **`dex/web/templates/login.html`** — Switched from navbar + panel layout to card layout (`header-card.html`), matching `/login.html` and LDAP login. Added pricing notice and register link.

### Payment explanation on login
- **`host-www/opencloud-auth/login.html`** — Added `.pricing-notice` block reusing `registerPricingNotice` i18n key (same content as `/register`).

### Logout page
- **`host-www/opencloud-auth/logout.html`** — New KM0-branded logout confirmation page with i18n (ES/CA/EN/DE), return-to-login and km0digital.com actions.
- **`host-www/opencloud-auth/dex-auth.js`** — Added `clearAllAuthState`, `completeLogoutIfNeeded` (Dex end_session when tokens remain).
- **`nginx/snippets/opencloud-locations.conf`** — Serve static `/logout` before OpenCloud SPA proxy.
- **`host-www/opencloud-auth/config-dex.json`**, **`config-local.json`** — `post_logout_redirect_uri` → `/logout`.

### Styles & i18n
- **`dex/web/themes/km0/styles.css`** — Pricing notice styles.
- **`dex/web/themes/km0/i18n.js`** — Logout strings (ES/CA/EN/DE).
- **`dex/web/static/dex-auth.js`** — Synced from host-www.

### Tests
- **`tests/auth/`** — Playwright suite: visual regression, payment visibility, logout branding, desktop OAuth param preservation, LDAP error state, axe a11y scans (desktop + mobile viewports).
- **`scripts/verify-auth-pages.sh`** — Curl smoke checks (no Node required).

## References
- Repo: https://github.com/AMVARA-CONSULTING/km0-opencloud
- Runbook: docs/runbook.md

---

## Testing instructions

### Deploy

```bash
cd /opt/opencloud
rsync -a host-www/opencloud-auth/ /var/www/opencloud-auth/
cp host-www/opencloud-auth/dex-auth.js dex/web/static/dex-auth.js
cp nginx/snippets/opencloud-locations.conf /etc/nginx/snippets/opencloud-locations.conf
nginx -t && systemctl reload nginx
cd dex && docker compose restart dex
```

### Smoke (no Node)

```bash
./scripts/verify-auth-pages.sh
```

Expected: all `PASS` lines — login/register pricing notice, logout branding (no OpenCloud splash), Dex Android auth uses `.km0-card` (not `.theme-navbar`), web client `/dex/auth` still 302 → `/login.html`.

### Docker health

```bash
cd opencloud-compose && docker compose ps
docker logs --since 5m opencloud-dex
```

### Playwright (requires Node 18+)

```bash
cd tests/auth
npm install
npx playwright install chromium
KM0_AUTH_BASE_URL=https://cloud.km0digital.com npx playwright test
```

First run creates snapshot baselines under `tests/auth/*-snapshots/`. Commit snapshots after visual review.

Coverage:
- Payment notice on `/login.html` and `/register` (desktop + mobile)
- Logout page branding, actions, no default SPA splash
- Visual snapshots: login, register, logout, Dex auth picker, Dex LDAP login
- Desktop OAuth: connector links preserve `client_id`, `redirect_uri`, `state`, `code_challenge`, etc.
- Web client redirect to `/login.html` unchanged
- LDAP invalid credentials error visible
- axe-core a11y scans on login, register, logout

### Manual operator checks

1. **Desktop app login** — Open Android/desktop OAuth URL; confirm card layout matches `/login.html`, Google/LDAP buttons styled consistently, OAuth flow completes.
2. **Web logout** — Sign in via `/login.html`, sign out from OpenCloud; land on branded `/logout`, tokens cleared, “Return to sign in” works.
3. **Regression** — Web `/dex/auth` without `connector_id` + `client_id=opencloud-web` still redirects to `/login.html` with OIDC params intact.

### Evidence (2026-06-30 deploy)

- `./scripts/verify-auth-pages.sh` — all checks PASS
- Dex Android auth HTML contains `km0-card`, `km0-pricing-notice`, no `theme-navbar`
- `/logout?from_dex=1` — KM0 card UI, no `splash-banner`

---

## Test report

**Date/time (UTC):** 2026-06-29T23:58:03Z – 2026-06-29T23:58:37Z  
**Log window:** Dex logs `--since 10m` (restart at 23:57:15Z); OpenCloud logs `--tail=30`

### Environment

- **Branch:** `main` (synced via `./scripts/git-sync-main.sh`)
- **Compose:** `opencloud-opencloud-1`, `opencloud-collaboration-1`, `opencloud-collabora-1` — all Up/healthy
- **Dex:** `opencloud-dex` restarted 2026-06-29T23:57:15Z, listening on 0.0.0.0:5556
- **URLs:** `https://cloud.km0digital.com`, loopback `http://127.0.0.1:9200`
- **Stack readiness:** Polled `curl https://cloud.km0digital.com/` → HTTP 302; `curl http://127.0.0.1:9200/` → HTTP 200; Dex logs show clean startup after restart; smoke script all PASS on first attempt

### What was tested

1. `./scripts/verify-auth-pages.sh` smoke suite
2. Docker compose health + Dex/OpenCloud logs
3. Nginx error log (nginx templates changed in this task)
4. Curl equivalents for Playwright functional criteria (OAuth param preservation, LDAP error state, logout branding, dex-auth.js helpers)
5. Playwright suite — **skipped** (Node not available on host; no new packages installed per policy)

### Results

| Criterion | Result | Evidence |
|-----------|--------|----------|
| `/login.html` pricing notice | **PASS** | HTTP 200; body contains `pricing-notice`, `registerPricingNotice`, price marker |
| `/register` pricing notice | **PASS** | HTTP 200; body contains `pricing-notice` |
| `/logout?from_dex=1` KM0 branding | **PASS** | logo, logout-actions, btn-primary present; Kilómetro branding text |
| Logout no OpenCloud splash | **PASS** | No `splash-banner` in body |
| Dex Android auth card layout | **PASS** | `km0-card` present (×2); `theme-navbar` absent; `pricing-notice` present |
| Google/LDAP connector OAuth params preserved | **PASS** | All 6 required params (`client_id`, `redirect_uri`, `response_type`, `scope`, `state`, `code_challenge`, `code_challenge_method`) in connector hrefs |
| Web `/dex/auth` → `/login.html` redirect | **PASS** | 302 to `/login.html?` with all OIDC params intact |
| LDAP login form (card layout) | **PASS** | Following LDAP connector: `km0-card`, `#login`, `#password`, `#submit-login` present |
| LDAP invalid credentials error | **PASS** | POST with bad creds → HTTP 401; `#login-error.dex-error-box` visible; "Usuario o contraseña incorrectos." |
| `dex-auth.js` helpers deployed | **PASS** | Served JS contains `clearAllAuthState`, `completeLogoutIfNeeded`, `oidcParamsFromUrl` |
| Docker stack health | **PASS** | All compose services Up; Dex clean restart |
| OpenCloud HTTP health | **PASS** | Public 302, loopback 200 |
| Nginx error log | **PASS** | No new errors in `/var/log/nginx/error.log` |
| Playwright visual regression | **DEFERRED** | Node 18+ not on host; layout verified via HTTP/curl |
| Playwright axe a11y scans | **DEFERRED** | Requires Playwright/Node |
| Manual: desktop OAuth flow completion | **NOT TESTED** | Requires interactive desktop client |
| Manual: web logout E2E token clearing | **NOT TESTED** | Requires signed-in browser session |

### Overall: **PASS**

All automated smoke and functional criteria pass on production. Playwright visual/a11y suites and manual operator E2E checks deferred (Node unavailable; interactive sessions out of scope for automated tester).

### URLs tested

- `https://cloud.km0digital.com/login.html`
- `https://cloud.km0digital.com/register`
- `https://cloud.km0digital.com/logout?from_dex=1`
- `https://cloud.km0digital.com/dex/auth?client_id=OpenCloudAndroid&…`
- `https://cloud.km0digital.com/dex/auth?client_id=opencloud-web&…`
- `https://cloud.km0digital.com/dex/auth/ldap/login?…`
- `https://cloud.km0digital.com/dex-auth.js`
- `http://127.0.0.1:9200/`

### Log excerpts

Dex restart (2026-06-29T23:57:15Z):
```
{"level":"INFO","msg":"config issuer","issuer":"https://cloud.km0digital.com/dex"}
{"level":"INFO","msg":"config static client","client_name":"OpenCloud Android"}
{"level":"INFO","msg":"listening on","server":"http","address":"0.0.0.0:5556"}
```

Smoke script output:
```
PASS: /login.html HTTP 200
PASS: body contains 'pricing-notice'
PASS: /logout?from_dex=1 HTTP 200
PASS: body does not contain 'splash-banner'
PASS: body contains 'km0-card\|theme-panel'
PASS: body does not contain 'theme-navbar'
PASS: web /dex/auth redirects to /login.html
All auth page smoke checks passed.
```
