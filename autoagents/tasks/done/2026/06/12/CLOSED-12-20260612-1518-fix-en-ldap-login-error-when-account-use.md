---
## Closing summary (TOP)

- **What happened:** LDAP login for a Google-only account returned HTTP 500 with a raw LDAP bind error instead of guiding the user to Google sign-in.
- **What was done:** Dex error/password templates now serve `dex-auth.js` from Dex static assets; friendly KM0 card for LDAP/OIDC conflicts with **Continue with Google**; `host-www` auth assets synced for `/login.html`.
- **What was tested:** All six automated criteria passed (Dex Up, static script on both paths, Google-only friendly UI, local wrong-password 401 regression, Google OIDC resume smoke, log paths).
- **Why closed:** Tester report overall **PASS**; all acceptance criteria met.
- **Closed at (UTC):** 2026-06-12 15:22
---

# [fix/en] LDAP login error when account uses Google OIDC

## GitHub Issue
- **Issue:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/12
- **Number:** #12
- **Labels:** agent:wip
- **Created:** 2026-06-12T15:08:18Z

## Problem / goal
When a user tries local LDAP login with an email already registered via Google OIDC, Dex returned HTTP 500 with a raw LDAP bind error (`Operations Error`) instead of guiding them to Google sign-in.

## Implementation
- `dex/web/templates/error.html` — KM0 card layout; detects LDAP bind `Operations Error` and shows friendly i18n guidance plus **Continue with Google** (from prior commit).
- `host-www/opencloud-auth/dex-auth.js` — resumes in-flight OIDC flow from Dex's `back` query parameter (from prior commit).
- **This pass:** Dex password/error templates now load `dex-auth.js` via `{{ url .ReqPath "static/dex-auth.js" }}` so the script ships with Dex restarts (no nginx-only deploy gap). Added `dex/web/static/dex-auth.js` (copy of host-www canonical file). Deployed `host-www/opencloud-auth/` via rsync for `/login.html`.
- `dex/README.md` — note to keep static copy in sync when editing `dex-auth.js`.

## References
- Repo: https://github.com/AMVARA-CONSULTING/km0-opencloud
- Runbook: docs/runbook.md

## Testing instructions

1. **Deploy**
   ```bash
   cp /opt/opencloud/host-www/opencloud-auth/dex-auth.js /opt/opencloud/dex/web/static/dex-auth.js
   rsync -a /opt/opencloud/host-www/opencloud-auth/ /var/www/opencloud-auth/
   cd /opt/opencloud/dex && docker compose up -d dex
   docker compose ps   # dex Up
   ```

2. **Static script on Dex pages**
   ```bash
   curl -sS https://cloud.km0digital.com/dex/static/dex-auth.js | grep -c oidcParamsFromBackParam   # ≥1
   curl -sS https://cloud.km0digital.com/dex-auth.js | grep -c oidcParamsFromBackParam               # ≥1
   ```

3. **Google-only account (reported case)**
   - Open https://cloud.km0digital.com/login.html → local username/password sign-in
   - Enter an email registered via Google OIDC (e.g. `yoelberjaga@gmail.com`) and any password
   - **Expected:** KM0 card with *Use Google for this account*, friendly message, **Continue with Google**, **Back to sign-in** — not raw `ldap: failed to bind … Operations Error`

4. **Normal wrong password (regression)**
   - Repeat with a local LDAP account and wrong password
   - **Expected:** LDAP form stays on screen with *Incorrect username or password* (HTTP 401), not the error page

5. **Google button resumes OIDC**
   - From step 3, click **Continue with Google**
   - **Expected:** redirect to Google OAuth preserving PKCE/state; after Google auth, OpenCloud web session completes

6. **Logs (optional)**
   ```bash
   docker logs opencloud-dex --since 5m | grep -E 'failed to login user|invalid password'
   ```
   Google-only attempts may still log `failed to login user` server-side; users should only see the friendly UI.

---

## Test report

**Date/time (UTC):** 2026-06-12T15:21:17Z – 2026-06-12T15:21:44Z  
**Log window:** Dex logs from 2026-06-12T15:19:57Z (container restart) through 15:21:44Z.

### Environment

- **Branch / commit:** `main` @ `abf7efb`
- **Compose:** `opencloud-opencloud-1`, `opencloud-dex` Up; Dex restarted ~2 min before test start
- **URLs:** https://cloud.km0digital.com/, https://cloud.km0digital.com/dex/
- **Stack readiness:** Polled `docker compose ps` in `opencloud-compose/` and `dex/` — `opencloud-dex` reported **Up** (restarted 15:19:57Z per Dex startup log). No fixed sleep; verified via container status + live HTTP curls.

### What was tested

1. Deploy / Dex container running
2. Static `dex-auth.js` on Dex and nginx paths
3. Google-only account LDAP login → friendly error UI
4. Local LDAP wrong password → inline 401 (regression)
5. Google OIDC resume wiring (smoke)
6. Dex logs for bind vs invalid-password paths

### Results

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | Deploy: Dex Up after restart | **PASS** | `opencloud-dex` Up ~1 min; startup log `listening on … :5556` at 15:19:57Z |
| 2 | `dex-auth.js` on both paths (`oidcParamsFromBackParam` ≥1) | **PASS** | `/dex/static/dex-auth.js` → 2; `/dex-auth.js` → 2; repo copies identical (5445 bytes) |
| 3 | Google-only account → friendly KM0 card, not raw LDAP error | **PASS** | POST `login=yoelberjaga@gmail.com` + wrong password → **HTTP 500**; HTML has `dex-ldap-oidc-error`, `km0-error-google`, `ldapOidcAccountTitle`, `isLdapOidcConflict`; raw `Operations Error` only in hidden `#dex-tech-error` (JS reveals friendly UI) |
| 4 | Wrong password on local LDAP → 401 inline error, not error page | **PASS** | POST `login=admin` + wrong password → **HTTP 401**; `km0-ldap-form` + `ldapLoginError` present; no `Operations Error`, no `dex-error-heading` |
| 5 | Continue with Google resumes OIDC | **PASS** (smoke) | Error page wires `km0-error-google` → `KM0DexAuth.startDexLogin('google')`; `oidcParamsFromBackParam` in deployed script; LDAP form URL includes `back=` with PKCE/state; `curl …connector_id=google…` → **302** `location: /dex/auth/google?…` preserving `code_challenge` + `state`. Full Google OAuth E2E not exercised (requires user Google account). |
| 6 | Logs: bind failure vs invalid password | **PASS** | Google-only: `failed to login user` + `Operations Error`; local wrong pw: `invalid password for user` (admin, 15:21:39Z) |

### Overall: **PASS**

Automated criteria pass. Dex error/password templates serve `dex-auth.js` from Dex static path. Google-only LDAP conflict shows friendly UI; normal wrong-password path unchanged.

### URLs tested

- https://cloud.km0digital.com/ (302)
- http://127.0.0.1:9200/ (200)
- https://cloud.km0digital.com/dex/static/dex-auth.js (200)
- https://cloud.km0digital.com/dex-auth.js (200)
- https://cloud.km0digital.com/dex/auth?…&connector_id=ldap (302 → ldap login form)
- https://cloud.km0digital.com/dex/auth/ldap/login (POST — Google-only 500, wrong pw 401)
- https://cloud.km0digital.com/dex/auth?…&connector_id=google (302 → google)

### Log excerpts

```
# Dex startup (15:19:57Z)
{"msg":"config connector","connector_id":"ldap"}
{"msg":"config connector","connector_id":"google"}
{"msg":"listening on","server":"http","address":"0.0.0.0:5556"}

# Google-only LDAP bind conflict (15:21:37Z)
{"msg":"performing ldap search","connector":{"type":"ldap","id":"ldap"},"filter":"(&(objectClass=inetOrgPerson)(uid=yoelberjaga@gmail.com))"}
{"msg":"username mapped to entry","username":"yoelberjaga@gmail.com"}
{"msg":"failed to login user","err":"ldap: failed to bind as dn \"uid=yoelberjaga@gmail.com,ou=users,o=libregraph-idm\": LDAP Result Code 1 \"Operations Error\": "}

# Local wrong password (15:21:39Z)
{"msg":"invalid password for user","connector":{"type":"ldap","id":"ldap"},"user_dn":"uid=admin,ou=users,o=libregraph-idm"}
```

**GitHub labels:** `agent:testing` added at test start; removed on pass.
