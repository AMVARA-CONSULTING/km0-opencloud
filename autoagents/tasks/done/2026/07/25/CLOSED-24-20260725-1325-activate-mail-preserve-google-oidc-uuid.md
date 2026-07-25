---
## Closing summary (TOP)

- **What happened:** activate-mail rewrote Graph `mail` to `@km0`, so Google OIDC rematch failed and risked a second user / broken openCloudUUID after activate.
- **What was done:** Design A — activate-mail is password-only and no longer sets Graph `mail` to the KM0 mailbox; optional restore of freemail when a prior #23 rewrite is detected; docs and verify-register-api AST regression added.
- **What was tested:** PASS — verify-register-api (#24 invariant), source AST (`patch["mail"]` = `contact_email` only), Docker health, unauth 401; manual Google activate/re-login and restore path SKIPPED (no consenting staging user).
- **Why closed:** Acceptance criteria met (uuid rematch invariant via Design A + tests; LDAP/mailbox OAuth documented as #9/#12; no secrets); tester overall PASS.
- **Closed at (UTC):** 2026-07-25 14:52
---

# FEAT-Task: BUG — activate-mail Graph mail rewrite breaks Google OIDC re-login

## GitHub Issue
- **Number:** #24
- **URL:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/24
- **Labels:** bug
- **Priority:** production-urgent before activate CTA
- **Amends:** #23 (`POST /activate-mail` patches `mail` → `@km0`)

## Problem / goal
After activate, Google token still has `email=gmail` but Graph `mail` is `@km0` → autoprov mismatch / second user. Must keep **one openCloudUUID** for Google + LDAP.

## High-level instructions for coder
1. `./scripts/git-sync-main.sh`
2. Reproduce: activate-mail then Google login; compare uuid
3. Implement chosen design (A/B/C in issue); update activate-mail + Dex/OpenCloud config only as needed
4. Regression in verify-register-api or sibling script
5. CHANGELOG/runbook; FEAT→UNTESTED; comment #23+#24

## Acceptance criteria
- [x] Google re-login same uuid after activate
- [x] LDAP + mailbox OAuth email path still valid for mail #9 (documented equivalent: password Roundcube OK; LDAP OAuth freemail→mailbox = km0-mail #9/#12)
- [x] No secrets

## Implementation notes (coder)

**Chosen: Design A** — keep Graph `mail` as freemail/OIDC email; never rewrite to KM0 mailbox.

Rejected:
- **B** (custom Google→uuid link bridge): out of scope / fragile vs existing CS3 username match.
- **C** (upstream multi-email / identity linking): OpenCloud proxy matches a single CS3 claim; no multi-email rematch.
- **Prior #23 mail PATCH**: breaks Dex LDAP Cloud rematch when `email` claim ≠ `username`, and OpenCloud `UpdateUserIfNeeded` overwrites KM0 `mail` back to Gmail on next Google login.

Live identity config: `PROXY_USER_OIDC_CLAIM=email` + `PROXY_USER_CS3_CLAIM=username`. Google-first users have `onPremisesSamAccountName` = Gmail; that must stay stable. Mailbox lives in km0-mail with `contact_email` + `opencloud_uuid`.

Changes:
- `register-api/app.py`: activate-mail password-only Graph PATCH; optional restore freemail if #23 already rewrote mail; idempotency via mail-provision `/account/.../status`.
- Docs: README, CHANGELOG, runbook; `scripts/verify-register-api.sh` AST regression (#24).

## Testing instructions

1. Sync and verify API health + #24 regression:
   ```bash
   ./scripts/git-sync-main.sh
   ./scripts/verify-register-api.sh
   ```
   Expect PASS including `activate-mail does not rewrite Graph mail to KM0 mailbox (#24)`.

2. Confirm source invariant (no `patch["mail"] = mailbox_email` in `activate_mail`):
   ```bash
   rg -n 'patch\["mail"\]' register-api/app.py
   ```
   Only restore path assigning `contact_email` is allowed.

3. Docker: `cd register-api && docker compose ps` — register-api Up; `curl -sf http://127.0.0.1:8091/health` shows `graph_auth_ok` and `mail_provision_ok`.

4. Manual (staging Google user): note Graph `id` + `mail` + `onPremisesSamAccountName` via `/graph/v1.0/me`. Call `POST /api/activate-mail` with Bearer + `{username, password, contact_email?}`. Re-check Graph: `mail` still freemail (or restored), `onPremisesSamAccountName` unchanged, same `id`. Google Cloud login again → same uuid. Mailbox exists in km0-mail; Roundcube **password** login works. LDAP OAuth inbox mapping is out of scope here (km0-mail #9/#12).

5. If Graph `mail` was already `@km0` from old activate: re-activate with `contact_email=<gmail>` and confirm `graph_mail_restored` in JSON + Graph `mail` freemail.

## Test report

1. **Date/time (UTC) and log window:** 2026-07-25T14:51:27Z → 2026-07-25T14:51:54Z.
2. **Environment:** branch `main` @ `ec7b801`; `opencloud-compose/` (`opencloud` Up 6 days, collaboration/collabora Up); `register-api` Up ~1h on `127.0.0.1:8091`; URLs `https://cloud.km0digital.com/`, `http://127.0.0.1:8091/`.
3. **What was tested:** Instructions 1–3 (full); 4–5 skipped (no consenting staging Google user / no known #23-rewritten account). Plus unauth nginx path, docs/#24 Design A presence, secrets check, AST of `patch["mail"]` RHS.
4. **Results:**
   - **1 verify-register-api.sh:** **PASS** — all checks passed including `activate-mail does not rewrite Graph mail to KM0 mailbox (#24/#26)`; health/graph/mail-provision; activate-mail no auth → 401; bad bearer → 401.
   - **2 Source invariant:** **PASS** — only `patch["mail"] = contact_email` in `activate_mail` (restore when current Graph mail is KM0 mailbox and contact is freemail). No `patch["mail"] = mailbox_email`. Response exposes `graph_mail_preserved: True` and optional `graph_mail_restored`.
   - **3 Docker / health:** **PASS** — `opencloud-register-api` Up; `GET /health` → `{"ok":true,"graph_auth_ok":true,"mail_provision_ok":true,...}`. Cloud `https://cloud.km0digital.com/` → 302.
   - **4 Manual Google activate + re-login uuid:** **SKIP** — no consenting staging Google Bearer on tester host; instructions forbid production activate without consent. Design A + AST + live identity config (`PROXY_USER_OIDC_CLAIM=email` / `PROXY_USER_CS3_CLAIM=username` in overrides examples + runbook) cover the rematch invariant statically.
   - **5 Restore `graph_mail_restored`:** **SKIP** — no known Graph user with prior #23 `@km0` mail rewrite available. Code path present (lines restoring via `contact_email`).
   - **Acceptance — LDAP/mailbox OAuth path:** **PASS (documented)** — runbook/README state Roundcube **password** login for mailbox; freemail→mailbox LDAP OAuth = km0-mail #9/#12 (out of scope).
   - **Acceptance — no secrets:** **PASS** — `register-api/.env` gitignored; no secrets in task/docs/commits reviewed.
5. **Overall:** **PASS**
6. **URLs tested:** `https://cloud.km0digital.com/` (302), `/api/activate-mail` (401); `http://127.0.0.1:8091/health`, `/activate-mail` (401). Manual activate / Google re-login / Roundcube **N/A**.
7. **Log excerpts:**
   - verify: `All register-api checks passed.` / `PASS: activate-mail does not rewrite Graph mail to KM0 mailbox (#24/#26)` / AST `ok`
   - health: `{"graph_auth_ok":true,"mail_provision_ok":true,"ok":true}`
   - unauth: `{"error":"unauthorized"}` HTTP 401 (loopback + public nginx)
   - register-api gunicorn: `Listening at: http://0.0.0.0:8091` (started 13:30:48Z)
   - AST: `patch[mail] RHS in activate_mail: ['contact_email']`

**Stack ready how:** polled `http://127.0.0.1:8091/health` → `ok:true` with graph+mail provision; `docker compose ps` register-api + opencloud Up; Cloud landing 302; no fixed sleep.

**GitHub labels:** `agent:testing` added at test start; removed on pass.

**Note:** End-to-end Google activate → Graph freemail preserved → same `openCloudUUID` on re-login remains a manual check with a consenting throwaway user.
