# FEAT-Task: Cloud-origin activate-mail wizard (Bearer /me) + hub deep-link

## GitHub Issue
- **Number:** #25
- **URL:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/25
- **Labels:** enhancement
- **Blocked until:** #24 identity approach decided/implemented enough for safe PATCH
- **Enables:** km0-mail #14 hub CTA

## Problem / goal
Hub cannot read Cloud OIDC storage. Wizard must run on cloud origin with Bearer → `/api/activate-mail`.

## High-level instructions for coder
1. Sync; implement `/activate-mail.html` (or final path) in `host-www/opencloud-auth/`
2. Bearer from `oc_oAuth.user:`; username/password/contact; i18n; nginx location
3. Document canonical URL for hub #14
4. Deploy pattern rsync; verify script; FEAT→UNTESTED

## Acceptance criteria
- [x] Wizard + Bearer happy path
- [x] Hub deep-link URL stable/documented
- [x] No unauthenticated activate; no secrets

## Implementation notes (coder)

- `host-www/opencloud-auth/activate-mail.html` — civic-dark wizard; reads Bearer via `KM0DexAuth.getStoredAccessToken()` (`oc_oAuth.user:`); `POST /api/activate-mail` with `{username,password,contact_email?}`; surfaces 401/409/validation; success copy honest (Cloud=Google/OIDC, Roundcube=password).
- `host-www/opencloud-auth/dex-auth.js` — `getStoredOidcUser` / `getStoredAccessToken` / `getStoredIdToken` helpers.
- `dex/web/themes/km0/i18n.js` — CA/ES/EN/DE `activateMail*` keys.
- Nginx: `location = /activate-mail.html` + short `302 /activate-mail` → html; existing `/api/activate-mail` unchanged.
- Docs: runbook canonical URL table; CHANGELOG; register-api README UI note.
- `scripts/verify-auth-pages.sh` — smoke for wizard + short redirect.
- Does **not** change session-gate `#22` mail→`sso-continue`. Hub deep-link CTA remains km0-mail #14 pointing at the documented URL.

**Canonical hub deep-link:** `https://cloud.km0digital.com/activate-mail.html`

## Testing instructions

1. Sync and deploy auth + nginx + Dex i18n:
   ```bash
   ./scripts/git-sync-main.sh
   rsync -a /opt/opencloud/host-www/opencloud-auth/ /var/www/opencloud-auth/
   sudo cp /opt/opencloud/nginx/snippets/opencloud-locations.conf /etc/nginx/snippets/
   sudo nginx -t && sudo systemctl reload nginx
   cd /opt/opencloud/dex && docker compose restart dex
   ```

2. Smoke scripts:
   ```bash
   ./scripts/verify-auth-pages.sh
   ./scripts/verify-register-api.sh
   ```
   Expect PASS including `cloud /activate-mail.html HTTP 200` and `activate-mail no auth → 401`.

3. Unauthenticated public API still blocked:
   ```bash
   curl -sS -w '%{http_code}\n' -X POST https://cloud.km0digital.com/api/activate-mail \
     -H 'Content-Type: application/json' \
     -d '{"username":"demo","password":"Test!234"}'
   # expect 401 {"error":"unauthorized"}
   ```

4. Manual happy path (consenting Google Cloud user, after #24):
   - Sign in to Cloud (Google).
   - Open `https://cloud.km0digital.com/activate-mail.html` — form visible; contact may prefill from OIDC profile.
   - Without session (incognito) — session banner + sign-in link; no silent activate.
   - Submit unique username + policy-ok password → success panel; Roundcube password login works; Graph `mail` still freemail (#24).
   - Duplicate username → UI shows duplicate error (409).
   - Session-gate `?service=mail` still → hub `/sso-continue` (#22).

5. Confirm Dex i18n: switch CA/ES/EN/DE on the wizard; title/labels update.
