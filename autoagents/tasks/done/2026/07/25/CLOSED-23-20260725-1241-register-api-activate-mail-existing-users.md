---
## Closing summary (TOP)

- **What happened:** Existing Google-first OpenCloud users needed a way to activate `username@km0digital.com` without re-running `/register`.
- **What was done:** Added authenticated `POST /activate-mail` on register-api (Bearer Graph `/me` or optional service token), nginx `/api/activate-mail`, password/provision sync, and docs; Design A avoids rewriting Graph mail (#24).
- **What was tested:** Tester PASS — verify-register-api.sh, unauthenticated 401 (loopback + public nginx), session-gate #22 non-clash, docs/secrets; happy-path Bearer activate skipped (no consenting user).
- **Why closed:** All acceptance criteria checked; automated/smoke tests passed; E2E activate deferred to manual/#24/#25 follow-up.
- **Closed at (UTC):** 2026-07-25 14:44
---

# FEAT-Task: register-api activate-mail for existing OpenCloud (Google) users

## GitHub Issue
- **Number:** #23
- **URL:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/23
- **Labels:** enhancement
- **Coordinates with:** km0-mail #10 (provision API), #11 (hub UI)
- **Must not clash:** #22 session-gate mail→sso-continue

## Problem / goal
Google-first Cloud users already exist in Graph/IDM but never ran `/register` with `create_mail`. Need `activate-mail`: choose username → `username@km0digital.com`, link uuid, set/sync password for Dex LDAP + mailbox, `contact_email` may be Gmail.

## High-level instructions for coder
1. `./scripts/git-sync-main.sh`.
2. Add `POST /activate-mail` (or equivalent) on register-api: no duplicate Graph user; freemail mailbox rejected; contact freemail OK; idempotent per uuid.
3. Call km0-mail provision with `mail_mode=km0`; reuse `/update-password` sync pattern.
4. Authz: document how hub proves caller owns the OpenCloud user (do not ship open unauthenticated provision).
5. README + CHANGELOG; FEAT→WIP→UNTESTED; label #23.

## Acceptance criteria
- [x] Existing Cloud user activates `foo@km0digital.com` once
- [x] Duplicate username clear error; freemail mailbox blocked
- [x] Idempotent for same uuid; password sync path works
- [x] No secrets committed

## Implementation notes
- `register-api/app.py`: `POST /activate-mail` — Graph PATCH password + mail, km0-mail `/provision` + `/update-password` on re-activate.
- Authz: Bearer OpenCloud access token → Graph `/me`; optional `ACTIVATE_MAIL_SERVICE_TOKEN` + `opencloud_uuid` (hub must prove ownership first).
- Nginx: `POST /api/activate-mail` (same rate-limit zone as register).
- Docs: `register-api/README.md`, `docs/CHANGELOG.md`, `docs/runbook.md`, `.env.example`.

## Testing instructions

1. **Health / smoke**
   ```bash
   ./scripts/verify-register-api.sh
   # expect activate-mail no auth → 401 and bad bearer → 401
   curl -s http://127.0.0.1:8091/health   # graph_auth_ok + mail_provision_ok true
   ```

2. **Unauthenticated / public nginx**
   ```bash
   curl -sS -w '%{http_code}\n' -X POST http://127.0.0.1:8091/activate-mail \
     -H 'Content-Type: application/json' \
     -d '{"username":"demo","password":"Test!234"}'
   # expect 401 {"error":"unauthorized"}
   curl -sS -w '%{http_code}\n' -X POST https://cloud.km0digital.com/api/activate-mail \
     -H 'Content-Type: application/json' \
     -d '{"username":"demo","password":"Test!234"}'
   # expect 401
   ```

3. **Validation + duplicate (service token, optional)**
   Set a temporary `ACTIVATE_MAIL_SERVICE_TOKEN` in the register-api container env (do not commit), recreate, then:
   ```bash
   # missing uuid → 400 missing_opencloud_uuid
   # unknown uuid → 404
   # username admin → 400 username_reserved
   # username taken by another Graph user → 409 duplicate
   ```

4. **Happy path (manual — use a throwaway / consenting test user)**
   - Sign in to Cloud (Google OIDC).
   - `POST /api/activate-mail` with `Authorization: Bearer <access_token from oc_oAuth.user>` and body
     `{"username":"<unique>","password":"<policy-ok>","contact_email":"<gmail>"}`.
   - Expect `201` with `mail.ok=true`, mailbox `<username>@km0digital.com`.
   - Repeat same request → `200` / `status=exists`, password_sync true.
   - Confirm Graph user `mail` is the KM0 mailbox; Roundcube password login works.
   - Do **not** run activate against production accounts without consent (Graph password + mail are updated).

5. **Non-clash**
   - Session-gate `?service=mail` still goes to hub `/sso-continue` (#22).
   - Public `/register` unchanged for new users.


## Blocker update (20260725-1325)
- **#24 required** before promoting activate-mail to users: Graph mail PATCH breaks Google OIDC rematch.

## Test report

1. **Date/time (UTC) and log window:** 2026-07-25T14:43:22Z → 2026-07-25T14:43:59Z.
2. **Environment:** branch `main` @ `f36162b`; `opencloud-compose/` (`opencloud` Up 6 days, collaboration/collabora Up); `register-api` Up ~1h on `127.0.0.1:8091`; URLs `https://cloud.km0digital.com/`, `https://auth.km0digital.com/`.
3. **What was tested:** Testing instructions 1–2, 5 (full); instruction 3 skipped (`ACTIVATE_MAIL_SERVICE_TOKEN` unset — optional); instruction 4 happy path skipped (no consenting production user). Plus health/status, #24 AST regression in verify script, session-gate #22 non-clash, `/register` still live, docs/nginx presence, no secrets committed.
4. **Results:**
   - **1 Health / smoke:** **PASS** — `./scripts/verify-register-api.sh` all checks passed (`health`, graph auth, mail provision, invalid email 400, activate-mail no auth → 401, bad bearer → 401, `#24/#26` Graph mail rewrite AST). `GET /health` → `ok:true`, `graph_auth_ok:true`, `mail_provision_ok:true`.
   - **2 Unauthenticated / public nginx:** **PASS** — `POST http://127.0.0.1:8091/activate-mail` → `401 {"error":"unauthorized"}`; `POST https://cloud.km0digital.com/api/activate-mail` → `401 {"error":"unauthorized"}`. Nginx `location = /api/activate-mail` proxies to `127.0.0.1:8091/activate-mail`.
   - **3 Validation + duplicate (service token):** **SKIP** — container env has no `ACTIVATE_MAIL_SERVICE_TOKEN` (optional). Static/AST: `activate_mail` enforces `freemail_blocked`, `validate_username` / reserved, duplicate → 409, provision + `/update-password` sync; Design A (no `patch["mail"]=mailbox`). Live reserved/unknown-uuid paths not exercised without token.
   - **4 Happy path (Bearer user):** **SKIP** — instructions forbid activate against production accounts without consent; no throwaway token available on tester host.
   - **5 Non-clash:** **PASS** — live `km0-session-gate.html` md5 matches repo (`2b8bade4…`); `service=mail` → `https://auth.km0digital.com/sso-continue` (HTTP 200); else `/files`. `POST /register` still responds (empty body → `400 password_too_short`). Cloud `/` → 302; `status.php` installed `7.3.0`.
   - **Acceptance — no secrets:** **PASS** — `ACTIVATE_MAIL_SERVICE_TOKEN` only in `.env.example` (commented); `register-api/.env` gitignored; CHANGELOG/runbook/README document endpoint.
   - **Blocker #24:** **PASS (mitigated in tree)** — verify AST `activate-mail does not rewrite Graph mail to KM0 mailbox (#24/#26)`; Design A already on `main` (full uuid rematch still needs consenting Google re-login under task #24).
5. **Overall:** **PASS**
6. **URLs tested:** `https://cloud.km0digital.com/` (302), `/api/activate-mail` (401); `http://127.0.0.1:8091/health`, `/activate-mail`, `/register`; `http://127.0.0.1:9200/status.php`; `https://auth.km0digital.com/sso-continue` (200). Happy-path activate **N/A**.
7. **Log excerpts:**
   - verify: `All register-api checks passed.` / `PASS: activate-mail no auth → 401` / `PASS: activate-mail bad bearer → 401` / `PASS: activate-mail does not rewrite Graph mail to KM0 mailbox (#24/#26)`
   - health: `{"graph_auth_ok":true,"mail_provision_ok":true,"ok":true}`
   - unauth: `{"error":"unauthorized"}` HTTP 401 (loopback + public)
   - gate: `if (params.get('service') === 'mail') { location.replace(MAIL_SSO_CONTINUE); … }`
   - register-api gunicorn: `Listening at: http://0.0.0.0:8091` (started 13:30:48Z); request body not logged by default
   - status.php: `"installed": true`, `"productversion": "7.3.0"`

**Stack ready how:** polled `http://127.0.0.1:8091/health` → `ok:true` with graph+mail provision; `docker compose ps` opencloud + register-api Up; `status.php` 200 installed; no fixed sleep.

**GitHub labels:** `agent:testing` added at test start; removed on pass.

**Note:** End-to-end activate (201/200 idempotent + Roundcube) remains a manual check with a consenting throwaway user; covered further by UNTESTED #24/#25.
