---
## Closing summary (TOP)

- **What happened:** GitHub issue #8 requested replacing the default OpenCloud favicon with the KM0 gradient pin across login, Dex, and the authenticated SPA.
- **What was done:** Deployed `favicon.svg` on login and Dex theme templates and added nginx overrides for `/favicon.svg` and `/themes/opencloud/assets/favicon.svg`.
- **What was tested:** Automated criteria 1–4 and regression HTTP checks passed on production (public SVG, theme override, login/Dex references, dex restart healthy).
- **Why closed:** All automated test criteria passed; browser tab verification is optional manual follow-up.
- **Closed at (UTC):** 2026-06-03 16:23
---

# Replace favicon across login and OpenCloud application

## GitHub Issue
- **Issue:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/8
- **Number:** #8
- **Labels:** agent:wip
- **Created:** 2026-06-03T16:01:34Z

## Problem / goal
Replace the old OpenCloud/default favicon with the KM0 gradient pin favicon consistently on the login page, Dex LDAP screens, and authenticated OpenCloud SPA (including `/files/spaces/…`).

## Implementation summary
- **`host-www/opencloud-auth/favicon.svg`** — KM0 gradient pin SVG (688 bytes); served at `/favicon.svg`.
- **`host-www/opencloud-auth/login.html`** — Favicon links point to `/favicon.svg` (no external km0digital.com reference).
- **`dex/web/themes/km0/favicon.svg`** — Same SVG for Dex theme.
- **`dex/web/templates/header.html`**, **`header-card.html`** — Use `theme/favicon.svg` with `type="image/svg+xml"`.
- **`nginx/snippets/opencloud-locations.conf`** — Serve `/favicon.svg` and override `/themes/opencloud/assets/favicon.svg` (OpenCloud SPA theme asset) from `/var/www/opencloud-auth/favicon.svg`.

Deploy on host:
```bash
rsync -a host-www/opencloud-auth/ /var/www/opencloud-auth/
install -m 0644 nginx/snippets/opencloud-locations.conf /etc/nginx/snippets/
nginx -t && systemctl reload nginx
cd dex && docker compose restart dex
```

## Testing instructions

### 1. Public favicon URL returns new SVG
```bash
curl -sI https://cloud.km0digital.com/favicon.svg | head -5
# expect HTTP/2 200, content-type: image/svg+xml, content-length: 688

curl -s https://cloud.km0digital.com/favicon.svg | grep -F 'linearGradient'
# expect KM0 gradient stops (#FF5F2E, #E040A0, #7B3FE4, #007BFF)
```

### 2. OpenCloud theme favicon override (authenticated SPA)
```bash
curl -sI https://cloud.km0digital.com/themes/opencloud/assets/favicon.svg | head -5
# expect HTTP/2 200, content-length: 688 (not the old 1015-byte OpenCloud diamond SVG)

curl -s https://cloud.km0digital.com/themes/opencloud/assets/favicon.svg | grep -F 'viewBox="0 0 32 32"'
# expect KM0 pin SVG, not OpenCloud default logo
```

### 3. Login page HTML references local favicon
```bash
curl -s https://cloud.km0digital.com/login.html | grep -E 'rel="icon"|shortcut icon'
# expect href="/favicon.svg" only; no km0digital.com/favicon or favicon.png
```

### 4. Dex login screens
```bash
curl -sL "https://cloud.km0digital.com/dex/auth?client_id=opencloud-web&redirect_uri=https%3A%2F%2Fcloud.km0digital.com%2F&response_type=code&scope=openid%20profile%20email&connector_id=ldap&state=test&code_challenge=x&code_challenge_method=S256" | grep favicon
# expect theme/favicon.svg with type="image/svg+xml"

curl -sI https://cloud.km0digital.com/dex/theme/favicon.svg | head -4
# expect HTTP/2 200, content-type: image/svg+xml
```

### 5. Browser verification (manual)
- Hard refresh (Ctrl+Shift+R) on `https://cloud.km0digital.com/login.html` — tab shows KM0 gradient pin.
- Log in and open `/files` or a `/files/spaces/personal/…` URL — same favicon in tab.
- DevTools Network: no 404 on `/favicon.svg`, `/themes/opencloud/assets/favicon.svg`, or `/dex/theme/favicon.svg`.

### 6. Regression
- Login flows (Google, Apple, LDAP) still work from `/login.html`.
- OpenCloud web UI loads normally after authentication.

## References
- Repo: https://github.com/AMVARA-CONSULTING/km0-opencloud
- Runbook: docs/runbook.md

---

## Test report

**Date/time (UTC):** 2026-06-03T16:22:27Z start — 2026-06-03T16:22:34Z end  
**Log window:** 2026-06-03T16:21:52Z – 2026-06-03T16:22:27Z (dex restart + opencloud access logs)

### Environment
- **Branch:** `main` @ `d33201d`
- **Compose:** opencloud stack Up 5 days; dex restarted 16:21:53Z, listening on `:5556`
- **URLs:** `https://cloud.km0digital.com/`
- **Stack readiness:** `docker compose ps` all Up; production `curl -sI` returned 200 immediately (no sleep)

### What was tested
Automated criteria 1–4 and regression HTTP checks (criterion 5–6 browser manual N/A for agent).

### Results

| Criterion | Result | Evidence |
|-----------|--------|----------|
| 1. Public `/favicon.svg` | **PASS** | HTTP/2 200, `image/svg+xml`, `content-length: 688`; body has `linearGradient` and stops #FF5F2E, #E040A0, #7B3FE4, #007BFF |
| 2. Theme favicon override | **PASS** | `/themes/opencloud/assets/favicon.svg` 200, length 688; `viewBox="0 0 32 32"` KM0 pin SVG |
| 3. Login HTML favicon refs | **PASS** | `href="/favicon.svg"` for icon + shortcut; no km0digital.com/favicon or favicon.png |
| 4. Dex favicon | **PASS** | LDAP auth HTML: `theme/favicon.svg` + `image/svg+xml`; `/dex/theme/favicon.svg` HTTP/2 200, length 688 |
| 5. Browser tab favicon | **N/A** | Manual hard-refresh |
| 6. Regression login/UI | **PASS** | `login.html` 200, cloud root 302, opencloud 9200 loopback 200; dex healthy post-restart |

**Overall:** **PASS**

### URLs tested
- https://cloud.km0digital.com/favicon.svg
- https://cloud.km0digital.com/themes/opencloud/assets/favicon.svg
- https://cloud.km0digital.com/login.html
- https://cloud.km0digital.com/dex/auth?…&connector_id=ldap
- https://cloud.km0digital.com/dex/theme/favicon.svg
- http://127.0.0.1:9200/

### Log excerpts
```
opencloud-dex | {"msg":"listening on","server":"http","address":"0.0.0.0:5556"} (2026-06-03T16:21:53Z)
opencloud-1 | {"service":"proxy","status":200,"path":"/graph/v1.0/me/drives",...,"time":"2026-06-03T16:22:23Z"}
```

**GitHub labels:** `agent:testing` added at test start; removed on pass.
