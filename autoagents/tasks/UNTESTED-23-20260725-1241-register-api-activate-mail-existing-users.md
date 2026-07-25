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
