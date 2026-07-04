# Registration incident — fundaalicates@yahoo.es (2026-07-04)

## Summary

On **2026-07-04**, user **fundaalicates@yahoo.es** attempted email/password self-registration at `/register`. The form showed a **generic error** with no explanation. The user later signed in successfully via **Google OAuth** at **13:08:07 UTC**.

## What the user saw

The register page displayed the generic message (*"No se pudo crear la cuenta. Inténtalo de nuevo más tarde."* / `registerErrorGeneric`) instead of a specific reason.

## Root cause

**register-api Graph credentials were rejected** at the time of the attempt. OpenCloud Graph requires an app token (`GRAPH_SERVICE_APP_TOKEN`); the token had expired or was invalid.

Evidence:

- `docker logs opencloud-register-api` — repeated `Graph API credentials rejected — run scripts/setup-register-api-graph-token.sh`
- `GET http://127.0.0.1:8091/health` — `graph_auth_ok: false` while `graph_configured: true`
- `POST /api/register` — HTTP **503** with `{"error":"service_unavailable"}` (not a duplicate or validation failure)

The frontend mapped HTTP 503 to the same generic string as other server errors, so the user could not tell that registration was temporarily unavailable vs. a problem with their email or password.

## Why Google OAuth worked

Google sign-in uses Dex + OIDC provisioning, **not** register-api. Dex created or linked the OpenCloud user when the user authenticated with Google at 13:08:07 UTC:

```text
login successful connector_id=google username=fundaalicates@yahoo.es email=fundaalicates@yahoo.es
```

No manual Graph user-creation step is required for the OAuth path.

## Fix applied (issue #16)

1. **register.html** — map API/HTTP errors to typed i18n messages: duplicate, validation, service unavailable, rate limit (429), plus existing client-side checks.
2. **register-api** — validate email/password before Graph auth check; clearer Graph error parsing.
3. **i18n (ES/CA/EN/DE)** — new strings for `registerErrorServiceUnavailable`, `registerErrorRateLimit`, `registerErrorValidation`; duplicate message mentions Google sign-in when the email is already taken.

## Operator action required

Renew the register-api Graph app token so email/password registration works again:

```bash
./scripts/setup-register-api-graph-token.sh
cd /opt/opencloud/register-api && docker compose up -d --build
./scripts/verify-register-api.sh
```

Confirm `graph_auth_ok: true` in `/health` before telling users manual registration is available.

## References

- GitHub issue: https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/16
- Runbook: `docs/runbook.md` (Public self-registration)
- Prior auth fix: issue #10 (register-api app token)
