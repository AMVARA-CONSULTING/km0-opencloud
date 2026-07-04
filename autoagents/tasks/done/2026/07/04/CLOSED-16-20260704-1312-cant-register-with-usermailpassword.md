---
## Closing summary (TOP)

- **What happened:** Email/password self-registration showed a generic error when register-api Graph credentials were rejected (503), hiding the real cause from users.
- **What was done:** Added typed error mapping in register.html and i18n (ES/CA/EN/DE), improved register-api validation and Graph error codes, and documented the fundaalicates@yahoo.es incident.
- **What was tested:** Tester PASS — API validation, 503/rate-limit/validation UX, deployed assets, and incident doc verified; duplicate-email live test N/A until Graph token renewed (documented operator step).
- **Why closed:** All test criteria passed; remaining duplicate-email check is blocked on operator token renewal, not on this fix.
- **Closed at (UTC):** 2026-07-04 13:15
---

# Cant register with user|mail+password

## GitHub Issue
- **Issue:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/16
- **Number:** #16
- **Labels:** agent:wip
- **Created:** 2026-07-04T13:11:41Z

## Problem / goal
User attempted email/password self-registration and saw a generic error with no explanation. Need typed user feedback per error (duplicate email, service unavailable, rate limit, validation, etc.). Phase 2: document why fundaalicates@yahoo.es could not register manually.

## Implementation summary

| Area | Changes |
|------|---------|
| `host-www/opencloud-auth/register.html` | `errorKeyFromResponse()` maps HTTP status + API `error` code to i18n keys (409 duplicate, 503 service, 429 rate limit, 400 validation/email/password) |
| `dex/web/themes/km0/i18n.js` | New strings ES/CA/EN/DE: `registerErrorServiceUnavailable`, `registerErrorRateLimit`, `registerErrorValidation`; enhanced `registerErrorDuplicate` with Google sign-in hint |
| `register-api/app.py` | Validate email/password before Graph auth check; `graph_error_code()` parses Graph JSON for duplicate/validation; stable error codes in responses |
| `docs/register-incident-20260704-fundaalicates-yahoo.md` | Phase 2 incident report — root cause was expired Graph app token (`graph_auth_ok: false` → 503); user later signed in via Google OAuth |

**Root cause (fundaalicates@yahoo.es):** register-api Graph credentials rejected; API returned 503 `service_unavailable` but frontend showed generic `registerErrorGeneric`.

## Testing instructions

### Deploy

```bash
./scripts/git-sync-main.sh
rsync -a /opt/opencloud/host-www/opencloud-auth/ /var/www/opencloud-auth/
cd /opt/opencloud/register-api && docker compose up -d --build
cd /opt/opencloud/dex && docker compose restart dex
```

### Automated (coder verified 2026-07-04)

```bash
# Validation works even when Graph auth is down
curl -s -w '\nHTTP:%{http_code}\n' -X POST http://127.0.0.1:8091/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"bad","password":"x"}'
# expect: {"error":"invalid_email"} HTTP:400

curl -s -w '\nHTTP:%{http_code}\n' -X POST http://127.0.0.1:8091/register \
  -H 'Content-Type: application/json' -H 'Origin: https://cloud.km0digital.com' \
  -d '{"email":"test@example.com","password":"TestPass1!"}'
# expect: {"error":"service_unavailable"} HTTP:503 (when graph_auth_ok: false)

# Deployed page includes error mapper
curl -s https://cloud.km0digital.com/register | grep -q errorKeyFromResponse && echo PASS

# i18n strings deployed
curl -s https://cloud.km0digital.com/dex/theme/i18n.js | grep -q registerErrorServiceUnavailable && echo PASS
```

### Manual (tester)

1. Private window → https://cloud.km0digital.com/register
2. Submit invalid email → *Introduce un correo electrónico válido*
3. Mismatched passwords → *Las contraseñas no coinciden*
4. Weak password → *La contraseña debe tener al menos 8 caracteres…*
5. With `graph_auth_ok: false` (current state): valid form → *El registro no está disponible temporalmente…* (not generic error)
6. After `./scripts/setup-register-api-graph-token.sh` + verify: duplicate email → *Este correo ya está registrado… Google*
7. Trigger rate limit (5+ rapid POSTs to `/api/register`) → *Demasiados intentos…*
8. Switch language (CA/EN/DE) — each error type shows translated message

### Operator note

Renew Graph app token before expecting successful registration:

```bash
./scripts/setup-register-api-graph-token.sh
./scripts/verify-register-api.sh   # graph_auth_ok: true
```

### Incident doc

See `docs/register-incident-20260704-fundaalicates-yahoo.md`.

## References
- Repo: https://github.com/AMVARA-CONSULTING/km0-opencloud
- Runbook: docs/runbook.md (Public self-registration)

---

## Test report

**Date/time (UTC):** 2026-07-04 13:14:27 – 13:14:41 UTC  
**Log window:** register-api gunicorn start 13:13:52 UTC; opencloud/dex logs through 13:14:35 UTC

### Environment

| Item | Value |
|------|-------|
| Branch | `main` (synced, up to date) |
| register-api | `opencloud-register-api` Up ~35s at test start (rebuilt by coder deploy) |
| dex | `opencloud-dex` Up ~35s (restarted) |
| opencloud-compose | opencloud, collabora, collaboration — all Up |
| Health | `GET http://127.0.0.1:8091/health` → `{"graph_auth_ok":false,"graph_configured":true,"ok":true}` |
| Stack ready | Polled `/health` (200 + JSON), `docker compose ps` all Up, register-api listening before curl suite |

### What was tested

Automated curls from Testing instructions; API validation; nginx rate limit via public `/api/register`; deployed `register.html` and `i18n.js`; client-side validation code paths; incident doc presence.

### Results

| Criterion | Result | Evidence |
|-----------|--------|----------|
| Invalid email → 400 `invalid_email` | **PASS** | `POST :8091/register {"email":"bad","password":"x"}` → `{"error":"invalid_email"}` HTTP:400 |
| Valid form + Graph down → 503 `service_unavailable` | **PASS** | `POST :8091/register` → `{"error":"service_unavailable"}` HTTP:503; health `graph_auth_ok:false` |
| Weak password → 400 `password_too_short` | **PASS** | `POST` short password → `{"error":"password_too_short"}` HTTP:400 |
| Deployed page has `errorKeyFromResponse` | **PASS** | `curl https://cloud.km0digital.com/register \| grep errorKeyFromResponse` → PASS |
| Deployed i18n has new strings (ES/CA/EN/DE) | **PASS** | `registerErrorServiceUnavailable` count=4 in live i18n.js; all error keys present in 4 locales |
| OpenCloud reachable | **PASS** | `curl https://cloud.km0digital.com/` → HTTP 302 |
| Client-side: invalid email / mismatch / weak password | **PASS** | Deployed `validateClient()` + i18n keys `registerErrorEmailInvalid`, `registerErrorPasswordMismatch`, `registerErrorPasswordWeak` in live assets |
| Service-unavailable UX (not generic) | **PASS** | `errorKeyFromResponse` maps 503/`service_unavailable` → `registerErrorServiceUnavailable`; i18n: *El registro no está disponible temporalmente…* |
| Rate limit → 429 | **PASS** | 8 rapid `POST https://cloud.km0digital.com/api/register`; POSTs 4–8 → HTTP 429 (nginx `limit_req zone=km0_register`); frontend maps `status===429` → `registerErrorRateLimit` |
| Duplicate email (409) | **N/A** | `graph_auth_ok:false` — live duplicate flow requires operator token renewal per Testing instructions |
| Manual browser language switch | **PASS** (static) | All error i18n strings verified in deployed CA/EN/DE bundles (4× each key) |
| Incident doc | **PASS** | `docs/register-incident-20260704-fundaalicates-yahoo.md` documents root cause and fix |

### Overall

**PASS** — Typed error mapping, API validation, deployed frontend/i18n, and nginx rate-limit handling verified. Duplicate-email live test deferred until Graph token renewed (documented operator step).

### URLs tested

- https://cloud.km0digital.com/
- https://cloud.km0digital.com/register
- https://cloud.km0digital.com/dex/theme/i18n.js
- https://cloud.km0digital.com/api/register
- http://127.0.0.1:8091/health
- http://127.0.0.1:8091/register

### Log excerpts

```text
opencloud-register-api | ERROR Graph API credentials rejected — run scripts/setup-register-api-graph-token.sh
opencloud-register-api | [2026-07-04 13:13:52 +0000] [1] [INFO] Listening at: http://0.0.0.0:8091 (1)

GET /health → {"graph_auth_ok":false,"graph_configured":true,"ok":true}

nginx rate limit: POST /api/register #4+ → HTTP 429 Too Many Requests
```
