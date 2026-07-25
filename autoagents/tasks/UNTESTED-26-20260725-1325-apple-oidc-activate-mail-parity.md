# FEAT-Task: Apple (OIDC) parity for activate-mail + hub mail intent

## GitHub Issue
- **Number:** #26
- **URL:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/26
- **Labels:** enhancement
- **After:** #24 + #25

## Problem / goal
Activate/identity/hub paths must not be Google-only.

## High-level instructions for coder
1. Generalize copy + deep-links for Apple when connector enabled
2. Same uuid guarantee as #24 for Apple re-login
3. Runbook table; FEAT→UNTESTED

## Acceptance criteria
- [x] Apple-first activate works when Apple configured (same Bearer wizard + Design A identity; no Google hardcode in API)
- [x] Hidden when unset; no secrets (`probeDexConnector('apple')` → reveal only on 302)
- [x] Runbook Google | Apple | LDAP parity table
- [x] i18n activate-mail copy IdP-agnostic (ES/CA/EN/DE)

## Implementation notes (coder)

- **Identity (#24 Design A already provider-agnostic):** `activate-mail` never rewrites Graph `mail` to KM0 mailbox; comments/README now say OIDC-first (Google/Apple/…). Same `PROXY_USER_OIDC_CLAIM=email` rematch for Apple.
- **`host-www/opencloud-auth/dex-auth.js`:** `probeDexConnector(id)` — Dex live connector → redirect/opaque; unset Apple → HTTP 400.
- **`host-www/opencloud-auth/login.html`:** Apple row stays `hidden` until probe succeeds; landing copy switches to `landingDescriptionWithApple`.
- **Wizard + i18n:** `activate-mail.html` + `dex/web/themes/km0/i18n.js` — Cloud stays on IdP (Google/Apple/OIDC); contact hint mentions Gmail/iCloud; success body not Google-token-specific.
- **Docs:** runbook provider parity table; CHANGELOG #26; register-api README; `dex/setup-apple.sh` notes probe + activate deep-link.
- **Verify:** `verify-auth-pages.sh` (OIDC copy, probe, Apple 400/302, asset hidden); `verify-register-api.sh` (#24/#26 AST).
- **Hub CTA:** primary login is `auth.km0digital.com` (`km0-auth`, out of this repo). Canonical activate deep-link is unchanged for all IdPs: `https://cloud.km0digital.com/activate-mail.html`. Hub Apple button reveal is a km0-auth follow-up using the same probe pattern.

**Canonical hub deep-link (Google or Apple):** `https://cloud.km0digital.com/activate-mail.html`

## Testing instructions

1. Sync and deploy auth + Dex theme i18n:
   ```bash
   ./scripts/git-sync-main.sh
   rsync -a /opt/opencloud/host-www/opencloud-auth/ /var/www/opencloud-auth/
   cd /opt/opencloud/dex && docker compose restart dex
   ```

2. Smoke:
   ```bash
   ./scripts/verify-auth-pages.sh
   ./scripts/verify-register-api.sh
   ```
   Expect PASS including:
   - `activate-mail.html` OIDC/IdP-neutral copy
   - `probeDexConnector` in `/dex-auth.js`
   - Dex apple probe **400** when unset (CTA stays hidden) or **302** when live
   - `login.html` Apple row starts `hidden` + probe call
   - `#24/#26` Graph mail rewrite AST check

3. Confirm Apple unset behaviour (current prod):
   ```bash
   curl -sS -o /dev/null -w '%{http_code}\n' \
     "https://cloud.km0digital.com/dex/auth?client_id=opencloud-web&redirect_uri=https%3A%2F%2Fcloud.km0digital.com%2F&response_type=code&scope=openid%20profile%20email&connector_id=apple&state=t"
   # expect 400
   grep -n 'km0-login-apple-row' /var/www/opencloud-auth/login.html
   # expect: id="km0-login-apple-row" hidden
   ```

4. When Apple is configured (`dex/setup-apple.sh`):
   - Same curl → **302** to `/dex/auth/apple`
   - Hybrid `login.html` (if used) reveals Continuar con Apple; landing mentions Google + Apple
   - Sign in with Apple → open `https://cloud.km0digital.com/activate-mail.html` → activate mailbox
   - Graph `mail` / SAM remain IdP email; Apple re-login → **same** `openCloudUUID` (#24 Design A)
   - Hub deep-link unchanged (km0-mail #14)

5. i18n: switch CA/ES/EN/DE on activate wizard; intro/success mention IdP/OIDC not Google-only.

6. Docker: `cd opencloud-compose && docker compose ps`; `docker logs --since 10m opencloud-dex` shows `connector_id=google` (and `apple` only after setup).
