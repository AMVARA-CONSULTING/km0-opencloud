---
## Closing summary (TOP)

- **What happened:** Cloud auth HTML and Dex KM0 theme still used legacy Inter + purple-gradient chrome while marketing already shipped civic dark tokens and the K0 mark.
- **What was done:** Replaced scoped auth surfaces (login/register/logout/oidc-start, favicons/logos, Dex theme) with Paper/Snow/Mist/Ink/Signal + IBM Plex/Bricolage and the canonical K0 mark; deployed to `/var/www/opencloud-auth/` and restarted Dex.
- **What was tested:** Hard-gate token/mark parity, anti-slop greps, live Dex theme + LDAP password card, deployed HTML, register-api health — Overall PASS.
- **Why closed:** All acceptance criteria passed; no GitHub issue (operator NEW-0).
- **Closed at (UTC):** 2026-07-18 06:58
---

# WIP-Task: Sync Cloud auth surfaces to civic dark KM0

## Origin
- **Source:** Direct operator request (skip GitHub). Sibling sync with remodelled `km0-web`.
- **Brief:** `/opt/km0-web/docs/design/product-auth-surfaces-sync.md`
- **No GitHub issue** (`NEW-0` / `WIP-0`).

## Problem / goal
Cloud custom auth still uses legacy Inter + orange→pink→purple→blue chrome and gradient favicon/logo. Marketing site already ships civic dark tokens + K0 lettermark. Bring **login / register / related auth HTML + Dex KM0 theme + favicons** in line. Do not restyle the OpenCloud app after login.

## Scope (only)
1. `host-www/opencloud-auth/login.html`
2. `host-www/opencloud-auth/register.html`
3. Shared auth chrome that reuses the same look: `logout.html`, `km0-oidc-start.html`
4. Assets: `host-www/opencloud-auth/favicon.svg`, `logo.svg`, `brand/` (OG if present)
5. Dex theme `dex/web/themes/km0/` (`styles.css`, `favicon.svg`, `logo.svg`, regenerate PNG if still served)

## Out of scope
- OpenCloud web UI, Graph, IDM, register-api logic, nginx routes
- Inventing a second brand or cloning Stirling pixels

## Done (coder)
- Copied canonical K0 mark from `/opt/km0-web/public/` into `host-www/opencloud-auth/` (+ `brand/`) and `dex/web/themes/km0/` (SVG + PNG).
- Replaced Inter + purple gradient chrome with Paper/Snow/Mist/Ink/Signal + IBM Plex Sans (Bricolage on H1) on login, register, logout, km0-oidc-start, and Dex `styles.css`.
- Logo display sized to 72px plaque (was 192px map-pin).
- Deployed: `rsync` → `/var/www/opencloud-auth/`; `cd dex && docker compose restart dex`.
- Note: live nginx currently **302** `/login.html` and `/register` to `auth.km0digital.com` (auth hub). Cloud-served civic surfaces for this pass: `/favicon.svg`, `/logo.svg`, `/brand/`, `/km0-oidc-start.html`, `/dex/theme/*`, Dex LDAP password HTML.

## Acceptance (hard)
- [x] Login + register (+ logout / oidc-start) read as civic dark KM0, not legacy purple gradient (source + deployed files)
- [x] Favicon/logo are full-bleed **K0** (no purple gradient pin); readable at 16px (live `/favicon.svg` / `/logo.svg`)
- [x] Dex password theme matches the same tokens/mark (live `/dex/theme/styles.css` + LDAP card `width="72"`)
- [x] No purple/indigo brand chain hexes left in scoped files (`rg` clean)
- [x] Auth flows still work (register-api health `graph_auth_ok`; Dex LDAP auth endpoint 302 → `/dex/auth/ldap`)

## Testing instructions

### Hard gate protocol (required)
| Item | Value |
|------|-------|
| Reference | https://km0digital.com/ (tokens + K0 mark) |
| KM0 Cloud URLs | Live: https://cloud.km0digital.com/favicon.svg , `/logo.svg`, `/km0-oidc-start.html`, `/dex/theme/styles.css`, Dex LDAP password via `/dex/auth?...&connector_id=ldap`. Source/deployed: `/var/www/opencloud-auth/login.html` (+ register/logout). Public `/login.html` / `/register` currently 302 → auth hub. |
| Decisive viewport | Dex LDAP password card first paint + browser tab favicon on cloud |

**Parity claims (must hold vs km0digital.com):**
1. Paper canvas `#0B1220` + Snow card `#141B28` + Mist border `#2A3344` on Dex password card and deployed login/register HTML.
2. Sole accent Signal `#2DD4BF` (focus rings / primary CTA / text links) — not purple/indigo.
3. Tab favicon is full-bleed K0 on stamp `#0F766E` with figure `#EEF0F2` (same as marketing).

**Anti-slop claims (must hold):**
1. No orange→pink→purple→blue gradient chain (`#FF5F2E` / `#E040A0` / `#7B3FE4` / `#007BFF`) in scoped auth HTML/CSS/SVG.
2. No Inter-only stack, no purple glow orbs, no `background-clip: text` rainbow H1.
3. Primary submit is solid Signal (dark text on teal), not a multi-stop gradient pill.

### Smoke
```bash
# Live assets + Dex theme
curl -sI https://cloud.km0digital.com/favicon.svg https://cloud.km0digital.com/logo.svg https://cloud.km0digital.com/km0-oidc-start.html
curl -s https://cloud.km0digital.com/favicon.svg | grep -E '#0F766E|#EEF0F2'
curl -s https://cloud.km0digital.com/dex/theme/styles.css | grep -E '#0B1220|#2DD4BF|IBM Plex'
# Expect 0 matches:
grep -rnE '7[Bb]3[Ff][Ee]4|E040A0|FF5F2E|ff5f2e|e040a0|007[Bb][Ff][Ff]|b794f6|Inter:wght|background-clip:\s*text' \
  /opt/opencloud/host-www/opencloud-auth /opt/opencloud/dex/web/themes/km0 || true
# Dex LDAP entry (expect Location: /dex/auth/ldap)
curl -sI 'https://cloud.km0digital.com/dex/auth?client_id=opencloud-web&redirect_uri=https%3A%2F%2Fcloud.km0digital.com%2Foidc-callback.html&response_type=code&scope=openid+profile+email&state=test&code_challenge=x&code_challenge_method=S256&connector_id=ldap' | grep -iE '^(HTTP|location:)'
# Deployed HTML tokens (login currently proxied away; file must still be civic dark)
grep -E '#0B1220|#2DD4BF|IBM Plex Sans' /var/www/opencloud-auth/login.html /var/www/opencloud-auth/register.html
curl -s http://127.0.0.1:8091/health   # expect graph_auth_ok: true
```

### Manual (tester)
1. Open https://km0digital.com/ and Cloud Dex LDAP password screen side-by-side; confirm token/mark parity (3 claims above).
2. Confirm browser tab favicon on cloud is K0 plaque, not purple pin.
3. Optional: LDAP login with a test user still reaches `/files` (do not paste credentials into the task file).

## Test report

1. **Date/time (UTC):** 2026-07-18T06:57:13Z → 2026-07-18T06:57:46Z (log window).
2. **Environment:** branch `main` @ `4bf8f2b`; compose `opencloud-compose` (opencloud Up 4 weeks; collabora healthy); Dex `opencloud-dex` Up (restarted ~2026-07-18T06:55:48Z, listening :5556). Stack ready via `https://cloud.km0digital.com/status.php` → 200 and `http://127.0.0.1:9200/status.php` → installed/not maintenance (no fixed sleep).
3. **What was tested:** Hard-gate civic-dark parity (Paper/Snow/Mist/Signal + K0 favicon), anti-slop greps, live Dex theme + LDAP password card, deployed auth HTML, register-api health, Dex LDAP redirect.
4. **Results:**
   - Paper `#0B1220` + Snow `#141B28` + Mist `#2A3344` on Dex theme + deployed login/register: **PASS** (live `/dex/theme/styles.css` CSS vars; `/var/www/opencloud-auth/login.html` lines with `--paper/--snow/--mist`).
   - Sole accent Signal `#2DD4BF` (CTA/focus/links), not purple/indigo: **PASS** (`--signal` in Dex + auth HTML; `.theme-btn--primary { background: var(--signal); }` solid, not gradient).
   - Tab favicon full-bleed K0 on `#0F766E` / `#EEF0F2`: **PASS** (live `/favicon.svg` + `/dex/theme/favicon.svg` byte-identical to `https://km0digital.com/favicon.svg`).
   - Anti-slop (no `#FF5F2E`/`#E040A0`/`#7B3FE4`/`#007BFF`/`Inter:wght`/`background-clip:text`): **PASS** (`ANTI_SLOP_CLEAN`; `NO_INTER`; `NO_LINEAR_GRADIENT_IN_SCOPE`).
   - Dex LDAP password card: theme CSS + `width="72"` logo + `theme-btn--primary`: **PASS** (followed redirects to `/dex/auth/ldap/login` HTML 5208 bytes).
   - Auth flows: Dex LDAP entry 302 → `/dex/auth/ldap`; register-api `graph_auth_ok: true`: **PASS**.
   - Manual browser side-by-side: **PASS** (equivalent via HTML/CSS/SVG evidence; optional live LDAP→`/files` not exercised).
5. **Overall: PASS**
6. **URLs:** `https://cloud.km0digital.com/` (302), `/favicon.svg` (200), `/logo.svg` (200), `/km0-oidc-start.html` (200), `/dex/theme/styles.css`, `/dex/theme/favicon.svg`, Dex LDAP auth/login chain, `https://km0digital.com/favicon.svg`, `http://127.0.0.1:8091/health`, `https://cloud.km0digital.com/status.php` (200). Public `/login.html` still 302 → `auth.km0digital.com` (expected).
7. **Log excerpts:** Dex restart `listening on address=0.0.0.0:5556` at 06:55:48Z; opencloud access-log 200s on `/graph`/`/status.php` during window; health `{"graph_auth_ok":true,...,"ok":true}`.
