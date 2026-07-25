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
