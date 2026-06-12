# [fix/en] LDAP login error when account uses Google OIDC

## GitHub Issue
- **Issue:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/12
- **Number:** #12
- **Labels:** agent:wip
- **Created:** 2026-06-12T15:08:18Z

## Problem / goal
When a user tries local LDAP login with an email already registered via Google OIDC, Dex returned HTTP 500 with a raw LDAP bind error (`Operations Error`) instead of guiding them to Google sign-in.

## Implementation
- Reworked `dex/web/templates/error.html` to use the KM0 card layout and detect LDAP bind `Operations Error` responses.
- Added i18n strings (ES/CA/EN/DE) for OIDC-account guidance and generic login errors.
- Extended `host-www/opencloud-auth/dex-auth.js` to resume an in-flight OIDC flow from Dex's `back` query parameter (so **Continue with Google** keeps PKCE/state).
- Styled error actions in `dex/web/themes/km0/styles.css`; technical LDAP messages stay hidden from users.

## High-level instructions for coder
- Read the full issue at https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/12
- Identify affected paths under overrides/, dex/, nginx/, host-www/, scripts/, docs/
- Implement minimal, on-scope changes for km0-opencloud
- Add **Testing instructions** before renaming to UNTESTED-

## References
- Repo: https://github.com/AMVARA-CONSULTING/km0-opencloud
- Runbook: docs/runbook.md

## Testing instructions

1. **Deploy templates**
   ```bash
   cd /opt/opencloud/dex && docker compose restart dex
   docker compose ps   # dex Up
   ```

2. **Google-only account (reported case)**
   - Open https://cloud.km0digital.com/login.html
   - Choose local username/password sign-in
   - Enter an email known to be registered via Google OIDC (e.g. `yoelberjaga@gmail.com`) and any password
   - **Expected:** KM0 card with heading *Use Google for this account*, friendly message in the page language, **Continue with Google** button, and **Back to sign-in** link — **not** the raw `ldap: failed to bind … Operations Error` text

3. **Normal wrong password (regression)**
   - Repeat with a local LDAP account and wrong password
   - **Expected:** LDAP form stays on screen with *Incorrect username or password* (HTTP 401), not the new error page

4. **Google button resumes OIDC**
   - From step 2, click **Continue with Google**
   - **Expected:** redirect to Google OAuth (not a fresh broken login); after Google auth, OpenCloud web session completes

5. **Logs (optional)**
   ```bash
   docker logs opencloud-dex --since 5m | grep -E 'failed to login user|invalid password'
   ```
   Google-only attempts may still log `failed to login user` server-side; users should only see the friendly UI.

## Test report

**Date/time (UTC):** 2026-06-12T15:11:19Z – 2026-06-12T15:13:00Z  
**Log window:** Dex and OpenCloud logs from 2026-06-12T15:10:00Z onward  
**Environment:** Production stack (`opencloud-compose/`, `dex/`), branch `main`, URL https://cloud.km0digital.com  
**Stack readiness:** Polled `http://127.0.0.1:5556/dex/.well-known/openid-configuration` → HTTP 200 on first attempt; restarted Dex (`docker compose restart dex`) and confirmed `opencloud-dex` Up before tests.

### What was tested

1. Dex deploy/restart (testing instruction §1)
2. Google-only account LDAP login → friendly OIDC guidance (§2)
3. Local LDAP account wrong password → regression (§3)
4. `dex-auth.js` deployment for OIDC resume via `back` param (§4)
5. Dex server logs for login failures (§5)

Automated LDAP flow via curl (session established through Dex redirect chain, POST to `/dex/auth/ldap/login?back=…&state=…`).

### Results

| Criterion | Result | Evidence |
|-----------|--------|----------|
| §1 Dex restart / Up | **PASS** | `opencloud-dex` Up after restart; OIDC discovery HTTP 200 |
| §2 Google-only friendly error | **PASS** | POST `yoelberjaga@gmail.com` + wrong password → HTTP 500, KM0 error template with `isLdapOidcConflict` JS, hidden `#dex-tech-error` containing LDAP bind message, `#dex-ldap-oidc-error` / `#km0-error-google` / `ldapBackLink` present; raw `Operations Error` not in user-visible text (hidden element excluded) |
| §3 Local wrong password regression | **PASS** | POST `luipy` + wrong password → HTTP 401, LDAP form retained with incorrect-password message; no error page |
| §4 Google button resumes OIDC | **FAIL** | Repo `host-www/opencloud-auth/dex-auth.js` includes `oidcParamsFromBackParam` (2 matches); live https://cloud.km0digital.com/dex-auth.js and nginx alias `/var/www/opencloud-auth/dex-auth.js` (mtime 2026-06-10) have **0** matches — updated JS not deployed via `rsync` per runbook §460 |
| §5 Server logs | **PASS** | `docker logs opencloud-dex`: `failed to login user` with Operations Error for Google-only account; `invalid password for user` for local account |
| OpenCloud health | **PASS** | `curl https://cloud.km0digital.com/` → 302; `/login.html` → 200 |

**Overall: FAIL** (criterion §4 — undeployed `dex-auth.js`)

### URLs tested

- https://cloud.km0digital.com/
- https://cloud.km0digital.com/login.html
- https://cloud.km0digital.com/dex-auth.js
- https://cloud.km0digital.com/dex/auth (LDAP connector flow, POST login)
- http://127.0.0.1:5556/dex/.well-known/openid-configuration

### Relevant log excerpts

```
{"time":"2026-06-12T15:12:42.489940956Z","level":"ERROR","msg":"failed to login user","err":"ldap: failed to bind as dn \"uid=yoelberjaga@gmail.com,ou=users,o=libregraph-idm\": LDAP Result Code 1 \"Operations Error\": "}
{"time":"2026-06-12T15:12:42.792475366Z","level":"ERROR","msg":"invalid password for user","connector":{"type":"ldap","id":"ldap"},"user_dn":"uid=luipy,ou=users,o=libregraph-idm"}
```

### Follow-up for coder

Deploy `host-www/opencloud-auth/` to nginx docroot before re-test:

```bash
rsync -a /opt/opencloud/host-www/opencloud-auth/ /var/www/opencloud-auth/
```

Then verify `curl -sS https://cloud.km0digital.com/dex-auth.js | grep -c oidcParamsFromBackParam` returns ≥1, and re-run §4 manually (Continue with Google from error page).
