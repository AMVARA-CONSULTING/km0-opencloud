---
## Closing summary (TOP)

- **What happened:** GitHub issue #14 reported outdated Open Graph and Twitter Card previews still using the old KM0 wordmark logo.
- **What was done:** Regenerated `host-www/opencloud-auth/brand/og-preview.png` with the new pin logo (1200×630), added missing Twitter Card meta tags to `register.html`, and deployed assets to production; existing login, Dex, and nginx crawler paths already referenced the correct preview URL.
- **What was tested:** Tester verified all automated criteria on production—preview PNG headers/dimensions, login/register OG/Twitter tags, Twitterbot share-link injection, Dex LDAP `og:image`, and stack health—all **PASS**.
- **Why closed:** All acceptance criteria passed; new pin-logo preview is live and referenced consistently across auth and share surfaces.
- **Closed at (UTC):** 2026-06-23 15:01
---

# Open Graph Update

## GitHub Issue
- **Issue:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/14
- **Number:** #14
- **Labels:** none
- **Created:** 2026-06-23T11:31:35Z

## Problem / goal
El open graph y seguramtene el twitter card están desactualziados y utilzian el logo antiguo.  Actualizalos para que utilicen el nuevo logo

## High-level instructions for coder
- Read the full issue at https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/14
- Identify affected paths under overrides/, dex/, nginx/, host-www/, scripts/, docs/
- Implement minimal, on-scope changes for km0-opencloud
- Add **Testing instructions** before renaming to UNTESTED-

## References
- Repo: https://github.com/AMVARA-CONSULTING/km0-opencloud
- Runbook: docs/runbook.md

## Implementation summary
- **`host-www/opencloud-auth/brand/og-preview.png`** — Regenerated OG/Twitter preview image (1200×630) with new KM0 pin logo on navy background; replaces old wordmark PNG (428 KB → ~22 KB).
- **`host-www/opencloud-auth/register.html`** — Added missing `twitter:title`, `twitter:description`, and `twitter:image` meta tags (aligned with `login.html`).
- Existing OG/Twitter meta tags in `login.html`, Dex templates (`header.html`, `header-card.html`), and nginx crawler injection (`opencloud-social-preview-proxy.conf`) already point to `/brand/og-preview.png`; no URL changes required.

Deploy on host:
```bash
install -m 0644 host-www/opencloud-auth/brand/og-preview.png /var/www/opencloud-auth/brand/
install -m 0644 host-www/opencloud-auth/register.html /var/www/opencloud-auth/
```

## Testing instructions

### 1. Preview image is public and updated
```bash
curl -sI https://cloud.km0digital.com/brand/og-preview.png | head -5
# expect HTTP/2 200, content-type: image/png, content-length ~22391 (new pin-logo image)
```

### 2. Login page OG/Twitter tags
```bash
curl -s https://cloud.km0digital.com/login.html | grep -E 'og:image|twitter:image|twitter:card'
# expect og:image and twitter:image → https://cloud.km0digital.com/brand/og-preview.png
# expect twitter:card summary_large_image
```

### 3. Register page OG/Twitter tags
```bash
curl -s https://cloud.km0digital.com/register | grep -E 'og:image|twitter:title|twitter:image'
# expect full Twitter Card tags including twitter:image → …/brand/og-preview.png
```

### 4. Social crawler injection (public share links)
```bash
curl -s -A "Twitterbot/1.0" "https://cloud.km0digital.com/s/testtoken" | grep -E 'og:image|twitter:image'
# expect branded og:image and twitter:image URLs
```

### 5. Dex LDAP page OG tags
```bash
curl -sL "https://cloud.km0digital.com/dex/auth?client_id=opencloud-web&redirect_uri=https%3A%2F%2Fcloud.km0digital.com%2F&response_type=code&scope=openid%20profile%20email&connector_id=ldap&state=test&code_challenge=x&code_challenge_method=S256" | grep 'og:image'
# expect og:image → …/brand/og-preview.png
```

### 6. Visual check (optional)
- Open https://cloud.km0digital.com/brand/og-preview.png in browser — navy background, gradient pin icon, “OpenCloud” + “Kilómetro 0 Digital” text.
- Use Facebook Sharing Debugger or Twitter Card Validator on a login/share URL to confirm preview shows new pin logo (may require cache refresh).

---

## Test report

**Date/time (UTC):** 2026-06-23T15:00:03Z – 2026-06-23T15:00:14Z

**Log window:** OpenCloud proxy logs 2026-06-23T14:59:49Z – 2026-06-23T15:00:08Z

### Environment

- **Branch:** `main` @ `cdafe19`
- **Compose:** `opencloud-opencloud-1` Up 9 days (9200), `opencloud-collabora-1` Up 3 weeks (healthy), `opencloud-collaboration-1` Up 3 weeks
- **URLs:** https://cloud.km0digital.com/

### Stack readiness

Production assets already deployed: `/var/www/opencloud-auth/brand/og-preview.png` (22391 bytes, mtime 2026-06-23T14:59:04Z) matches repo file. Confirmed ready via immediate HTTP 200 on `/brand/og-preview.png` and OpenCloud root 302 without polling delays.

### What was tested

1. Public OG preview PNG (headers, size, dimensions)
2. Login page OG/Twitter meta tags
3. Register page OG/Twitter meta tags
4. Social crawler injection on public share link
5. Dex LDAP auth page OG tags
6. Visual check (file metadata only)
7. OpenCloud health + Docker compose status

### Results

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | `/brand/og-preview.png` HTTP 200, `image/png`, ~22391 bytes | **PASS** | HTTP/2 200; `content-type: image/png`; `content-length: 22391`; `last-modified: Tue, 23 Jun 2026 14:59:04 GMT`; PNG 1200×630 |
| 2 | Login OG/Twitter tags point to og-preview.png, `summary_large_image` | **PASS** | `og:image` and `twitter:image` → `https://cloud.km0digital.com/brand/og-preview.png`; `twitter:card` → `summary_large_image` |
| 3 | Register page full Twitter Card tags | **PASS** | `og:image`, `twitter:title`, `twitter:description`, `twitter:image`, `twitter:card` all present; image URL correct |
| 4 | Twitterbot share-link crawler injection | **PASS** | `/s/testtoken` with `Twitterbot/1.0` returns branded `og:image` and `twitter:image` URLs |
| 5 | Dex LDAP page `og:image` | **PASS** | LDAP auth URL returns `og:image` → `https://cloud.km0digital.com/brand/og-preview.png` |
| 6 | Visual check (browser) | **N/A** | Automated: PNG 1200×630 RGB confirmed via `file`; manual browser/validator not exercised |
| 7 | OpenCloud health + compose | **PASS** | `https://cloud.km0digital.com/` → 302; all compose services Up; proxy `/status.php` 200 at 15:00:06Z |

### Overall: **PASS**

All automated criteria pass. New pin-logo OG preview image is deployed and referenced consistently across login, register, Dex LDAP, and social crawler injection.

### URLs tested

- https://cloud.km0digital.com/ (302)
- https://cloud.km0digital.com/brand/og-preview.png (200)
- https://cloud.km0digital.com/login.html (200)
- https://cloud.km0digital.com/register (200)
- https://cloud.km0digital.com/s/testtoken (200, Twitterbot UA)
- https://cloud.km0digital.com/dex/auth?…&connector_id=ldap (200)

### Log excerpts

```
# docker compose ps
opencloud-opencloud-1   Up 9 days   127.0.0.1:9200->9200/tcp
opencloud-collabora-1   Up 3 weeks (healthy)
opencloud-collaboration-1   Up 3 weeks

# opencloud proxy (15:00:06–15:00:08Z)
{"service":"proxy","method":"GET","status":200,"path":"/status.php","time":"2026-06-23T15:00:06Z"}
{"service":"proxy","method":"GET","status":200,"path":"/s/testtoken","time":"2026-06-23T15:00:08Z"}
```

**GitHub labels:** `agent:testing` added at test start; removed on pass.
