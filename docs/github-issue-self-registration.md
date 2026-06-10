# GitHub issue draft — public email/password self-registration

Create this issue on **AMVARA-CONSULTING/km0-opencloud**.

---

## Title

```
feat(auth): public email/password self-registration (Dex + Graph API)
```

## Labels

- `enhancement`

(autoagents will add `agent:planned` when picked up)

---

## Issue body

Copy everything below this line into the GitHub issue description.

---

## Summary

Add **public self-registration** with **email + password** on `cloud.km0digital.com`. No Keycloak or other external IdP. Keep **Dex + nginx** as today.

Google OIDC already auto-provisions users on first login (`PROXY_AUTOPROVISION_ACCOUNTS=true`). Local LDAP login only authenticates **existing** IDM users. Registration must **create the user in IDM first**, then the user signs in via the existing Dex LDAP flow (`connector_id=ldap`).

---

## Product decisions (fixed)

| Decision | Value |
|----------|--------|
| Registration model | **Public** — no invites |
| Username | **Email as uid** (`onPremisesSamAccountName` = full email; `mail` = same) — aligns with `PROXY_USER_OIDC_CLAIM=email` and avoids duplicates if the user later uses Google |
| Email verification | **None** for now — account active immediately after registration |
| Extra infrastructure | **No Keycloak** — small registration backend in this repo, proxied by nginx |
| Pricing notice on register page | Visible disclaimer: service is in **testing**, **free for now**, **€1.99/month later** + link to pricing (locale-aware) |

**Pricing URLs (per locale):**

- `es` → https://km0digital.com/pricing/
- `ca` → https://km0digital.com/ca/pricing/
- `en` → https://km0digital.com/en/pricing/
- `de` → https://km0digital.com/de/pricing/

---

## Architecture context

```
User → register.html → POST /api/register → Graph API POST /users → IDM
User → login.html → Dex connector_id=ldap → OpenCloud (existing flow)
Google → Dex connector_id=google → autoprov on first login (unchanged)
```

**Do not** re-enable the built-in `idp` signup UI (`/signin/…`). All end-user tokens must remain **Dex-issued** (`OC_OIDC_ISSUER=https://cloud.km0digital.com/dex`).

**Relevant repo paths:**

| Path | Role |
|------|------|
| `host-www/opencloud-auth/login.html` | Login landing — add “Create account” link |
| `host-www/opencloud-auth/` | Deploy target: `/var/www/opencloud-auth/` |
| `nginx/snippets/opencloud-locations.conf` | Serve `register.html`, proxy `/api/register`, rate limit |
| `dex/config.yaml` | LDAP connector (auth only — no changes expected) |
| `dex/web/themes/km0/i18n.js` | Shared i18n (CA, ES, EN, DE) — extend for register strings |
| `overrides/opencloud-compose/.env.debian-core-external-proxy.example` | Reference OIDC/autoprov env |
| `docs/runbook.md` | Update after implementation |

**OpenCloud identity env (already set):**

- `PROXY_AUTOPROVISION_ACCOUNTS=true`
- `PROXY_USER_OIDC_CLAIM=email`
- `PROXY_AUTOPROVISION_CLAIM_USERNAME=email`
- `GRAPH_USERNAME_MATCH=none`

---

## Implementation requirements

### 1. Registration page — `host-www/opencloud-auth/register.html`

- **Visual style:** Match `login.html` — same navy background, Inter font, gradient heading, card layout, language switcher (CA | ES | EN | DE).
- Reuse `/dex/theme/i18n.js`; add register-specific strings in `dex/web/themes/km0/i18n.js`.
- **Form fields:** email, password, confirm password (client-side match check).
- **Pricing/testing notice** (all 4 locales): testing phase, free now, €1.99/month later, link to locale pricing URL.
- **Links:** “Already have an account? Sign in” → `/login.html`.
- **Favicon / OG:** Same pattern as `login.html` (`/favicon.svg`, KM0 branding).

### 2. Login page update — `login.html`

- Add “Create account” / equivalent (i18n) → `/register.html`.
- Keep Google / Apple / local login unchanged.

### 3. Registration API — `POST /api/register`

Minimal backend in this repo (e.g. `register-api/` with Docker Compose on `127.0.0.1`, or equivalent — **no Keycloak**).

**Request (JSON):** `{ "email": "...", "password": "..." }`

**Behaviour:**

1. Validate email format (server-side).
2. Validate password (align with OpenCloud policy: min length, special chars per compose env; reject banned passwords if feasible).
3. Call OpenCloud **LibreGraph API**:

   `POST https://cloud.km0digital.com/graph/v1.0/users`

   ```json
   {
     "displayName": "<derived from email local-part or email>",
     "mail": "<email>",
     "onPremisesSamAccountName": "<email>",
     "passwordProfile": { "password": "<password>" }
   }
   ```

4. **Auth to Graph:** Service account credentials from server-only config (e.g. `register-api/.env` — **never commit**). Provide `register-api/.env.example` with placeholders. Document in runbook: admin creates an app token or uses a dedicated service user.

5. **Responses:**
   - `201` — user created; body may include `{ "ok": true }`.
   - `409` — email already registered (Graph/LDAP conflict).
   - `400` — validation error.
   - `429` — rate limited.
   - `500` — generic error (no secrets in response).

6. **Security (minimum):**
   - nginx `limit_req` on `/api/register`.
   - CORS: same origin only.
   - No credentials in repo, logs, or issue comments.
   - Generic errors where appropriate.

### 4. Post-registration UX

On success → redirect to `/login.html?registered=1` (or auto-start Dex LDAP via existing `startDexLogin('ldap')` pattern from `login.html`).

Optional: show a short success banner on login when `?registered=1`.

User then signs in with **email + password** via Dex LDAP (same as today).

### 5. Nginx

In `nginx/snippets/opencloud-locations.conf`:

- `location = /register.html` → alias `/var/www/opencloud-auth/register.html`
- `location /api/register` → proxy to registration backend on localhost
- Rate limiting on `/api/register`

### 6. Documentation

Update `docs/runbook.md`:

- Registration flow
- Deploy steps (`rsync`, nginx reload, register-api restart)
- Service account / app token setup (operator-only)
- Explicit **out of scope:** email verification, billing, invites

Optional: short `register-api/README.md`.

---

## UI / i18n copy (English reference — implement all 4 locales)

**Pricing notice (example EN):**

> This service is currently in testing and free to try. After the testing period, cloud storage will be **€1.99/month**. [See pricing →](https://km0digital.com/en/pricing/)

**Register CTA:** “Create account”  
**Sign-in link:** “Already have an account? Sign in”

---

## Out of scope

- Email verification / SMTP
- Payment / subscription enforcement
- Invite-only or admin approval workflows
- Keycloak or other external user directory
- Changing Dex LDAP connector behaviour
- Disabling Google autoprov

---

## References

- [OpenCloud Graph — create user (`POST /users`)](https://docs.opencloud.eu/docs/dev/server/apis/http/graph/users)
- [OpenCloud Graph API overview](https://docs.opencloud.eu/docs/dev/server/apis/http/graph/)
- [External IdP / autoprov](https://github.com/opencloud-eu/docs/blob/main/versioned_docs/version-4.0/admin/configuration/authentication-and-user-management/external-idp.md)
- Repo: `docs/runbook.md` (Multi-provider OIDC section)
- Repo: `dex/README.md`
- Prior auth work: issue #1 (Dex LDAP local login)

---

## Acceptance criteria

- [ ] `/register.html` is public, styled like `login.html`, i18n CA/ES/EN/DE
- [ ] Pricing/testing disclaimer with correct locale pricing links
- [ ] `POST /api/register` creates IDM user via Graph API (email as uid)
- [ ] Duplicate email returns clear error (409)
- [ ] New user can sign in via Dex LDAP (`connector_id=ldap`) immediately
- [ ] `login.html` links to registration; register page links back to login
- [ ] nginx serves page and proxies API with rate limiting
- [ ] No secrets committed; `.env.example` documents operator setup
- [ ] `docs/runbook.md` updated
- [ ] Google login regression still works

---

## Testing instructions (for tester agent)

### Deploy

```bash
./scripts/git-sync-main.sh
# apply code, then on server:
rsync -a /opt/opencloud/host-www/opencloud-auth/ /var/www/opencloud-auth/
install -m 0644 /opt/opencloud/nginx/snippets/opencloud-locations.conf /etc/nginx/snippets/
nginx -t && systemctl reload nginx
# restart register-api + dex if i18n changed:
cd /opt/opencloud/dex && docker compose restart dex
# register-api: per register-api/README.md
```

### Automated

```bash
# Register page served
curl -sI https://cloud.km0digital.com/register.html | head -5
# expect: 200

# Rate limit / API reachable (without valid service creds may 500/503 — document expected behaviour)
curl -sI -X POST https://cloud.km0digital.com/api/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"invalid","password":"x"}' | head -5
# expect: 400, not 404

# Login page has register link (grep deployed file or curl body)
curl -s https://cloud.km0digital.com/login.html | grep -i register
```

### Manual (operator — requires service account configured)

1. Private window → https://cloud.km0digital.com/register.html
2. Register with new email + strong password → success message / redirect
3. Sign in via “local username/password” on login → Dex LDAP → `/files`
4. Confirm pricing notice visible in ES and one other locale (e.g. DE)
5. Try duplicate registration → error
6. Regression: Google login still works
7. Optional: register with `user@gmail.com`, then sign in with Google same email → same OpenCloud account (no duplicate)

---

## Agent workflow notes

- Run `./scripts/git-sync-main.sh` before edits; branch **`main`**; author Luipy56.
- Minimal diff; match existing conventions in `host-www/`, `nginx/`, `dex/web/themes/km0/`.
- Do not edit `opencloud-compose/` upstream directly — use `overrides/` if OpenCloud env changes are needed.
- Do not commit `.env`, app tokens, or Graph service credentials.
- Bump `autoagents/VERSION` per loop policy when committing.
