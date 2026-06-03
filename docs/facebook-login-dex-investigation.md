# Facebook Login via Dex — Investigation Report (km0-opencloud)

**GitHub:** [AMVARA-CONSULTING/km0-opencloud#5](https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/5)  
**Status:** Investigation complete — **not enabled in production** (documentation + optional env-gated connector template).  
**Dex version:** `ghcr.io/dexidp/dex:v2.42.0`

---

## Executive summary

| Criterion | Result |
|-----------|--------|
| Dex remains sole OIDC issuer | **Yes** — Facebook is an upstream OAuth provider only; tokens are Dex-issued |
| No external IdP broker | **Yes** — no Keycloak, no parallel issuer |
| Facebook via Dex only | **Yes** — use Dex `type: oauth` (native `type: facebook` removed from modern Dex) |
| Email-based OpenCloud identity | **Conditional** — works when Facebook returns `email`; mitigation required when absent |
| Meta production readiness | **Documented** — App Review, privacy policy, domain verification required |

**Recommendation:** Enable Facebook only after Meta app review grants `email` for production users, with `insecureSkipEmailVerified: true` on the Dex connector (Facebook does not expose OIDC `email_verified`). Treat missing-email logins as operator-visible failures; do not weaken `PROXY_USER_OIDC_CLAIM=email` without an explicit product decision.

---

## 1. Current authentication baseline

### Architecture

```text
User → nginx (TLS) → Dex (OIDC issuer) → [Google | Apple OIDC | LDAP | (future) Facebook OAuth]
                              ↓
                    Dex-issued ID token / access token (JWKS at /dex/keys)
                              ↓
                    OpenCloud proxy (validates JWT against Dex JWKS only)
```

| Layer | Role | Repo path |
|-------|------|-----------|
| nginx | TLS termination, `/dex/` → Dex, `/` → OpenCloud, `/login.html` hybrid landing | `nginx/` |
| Dex | Sole end-user OIDC issuer; connectors issue upstream auth then mint Dex tokens | `dex/` |
| OpenCloud proxy | `OC_OIDC_ISSUER=https://cloud.km0digital.com/dex`, JWKS validation | `overrides/opencloud-compose/` |
| Built-in `idp` | Internal/service use; **not** end-user path when Dex is configured | upstream compose |
| Hybrid landing | Provider buttons → `/dex/auth?connector_id=…` | `host-www/opencloud-auth/login.html` |

### Existing connectors (live)

| Connector | Dex `type` | Identity source | Notes |
|-----------|------------|-----------------|-------|
| `ldap` | `ldap` | OpenCloud IDM (`openCloudUUID`, `mail`) | Local username/password |
| `google` | `google` | Google OIDC (via Dex native connector) | `redirectURI: {issuer}/callback` |
| `apple` | `oidc` | Apple ID (`issuer: https://appleid.apple.com`) | Injected by `docker-entrypoint.sh` when env set |

### OpenCloud identity constraints (mandatory)

From `overrides/opencloud-compose/.env.*.example` and OIDC env patch:

| Variable | Value | Implication for Facebook |
|----------|-------|---------------------------|
| `PROXY_USER_OIDC_CLAIM` | `email` | Dex ID token **must** include `email` |
| `PROXY_AUTOPROVISION_CLAIM_USERNAME` | `email` | New users keyed by email |
| `PROXY_AUTOPROVISION_ACCOUNTS` | `true` | First login creates user from claim |

Claim path: **Facebook profile → Dex oauth connector mapping → Dex ID token claims → OpenCloud user UUID**.

---

## 2. Facebook integration via Dex

### Why not `type: facebook` or `type: oidc`?

- Dex **v2.42** connector list ([dexidp.io/docs/connectors](https://dexidp.io/docs/connectors/)) has **no** maintained `facebook` connector.
- Historical `type: facebook` (PR #580, ~2016) is **not** in current releases.
- Facebook is **not** OIDC-compliant; `type: oidc` against `facebook.com` is invalid.

### Required approach: `type: oauth` (alpha)

Use the generic [OAuth 2.0 connector](https://dexidp.io/docs/connectors/oauth/) with Facebook Graph API endpoints.

Example (see also `dex/config.facebook.oauth.example.yaml`):

```yaml
- type: oauth
  id: facebook
  name: Facebook
  config:
    clientID: FACEBOOK_APP_ID
    clientSecret: FACEBOOK_APP_SECRET
    redirectURI: https://cloud.km0digital.com/dex/callback
    authorizationURL: https://www.facebook.com/v21.0/dialog/oauth
    tokenURL: https://graph.facebook.com/v21.0/oauth/access_token
    userInfoURL: https://graph.facebook.com/me?fields=id,name,email
    scopes:
      - email
      - public_profile
    insecureSkipEmailVerified: true
    claimMapping:
      userIDKey: id
      emailKey: email
      userNameKey: name
```

**Callback URL (Meta + Dex):** `https://cloud.km0digital.com/dex/callback` — same pattern as Google and Apple.

**km0 wiring:** Optional injection in `dex/docker-entrypoint.sh` when `FACEBOOK_CLIENT_ID` and `FACEBOOK_CLIENT_SECRET` are set (mirrors Apple block; disabled until env populated).

### Dex v2.42 constraints

| Topic | Impact |
|-------|--------|
| OAuth connector status | **alpha** — less battle-tested than `google` / `ldap` |
| Refresh tokens | OAuth connector: **no** refresh tokens per Dex docs |
| `alwaysShowLoginScreen: false` | Web flows use `login.html`; add `connector_id=facebook` button when enabling |
| Native clients | Desktop/mobile use Dex directly; Facebook button on landing optional for web only |

---

## 3. Identity compatibility (critical)

### Facebook attributes

| Attribute | Availability | OpenCloud impact |
|-----------|--------------|------------------|
| `id` | Always (app-scoped user id) | Stable per app; **not** used as OpenCloud key today |
| `email` | **Only if** user grants `email` permission and account has email | **Required** for autoprov |
| `email_verified` | Not provided by Facebook Graph in standard flow | Use `insecureSkipEmailVerified: true` on connector |
| `name` | Usually via `public_profile` | Display only; not used as identity key |
| Email change | User can change email in Meta account | Risk of duplicate or orphaned OpenCloud user if email changes post-provision |

### Cases where login must fail (by design)

1. User denies `email` permission.
2. Facebook account has no email (phone-only registration).
3. App in **Development** mode and user is not a role/test user.
4. `email` permission not approved in **App Review** (production).

**Mitigation options (product decision, not implemented):**

- Block Facebook connector until `email` present (Dex will error on missing claim).
- Operator manual user creation + LDAP for affected users.
- Future: custom claim mapper or `preferred_username` fallback — **conflicts** with current `PROXY_*_CLAIM=email` policy.

### Account linking risks

| Scenario | Behaviour |
|----------|-----------|
| Same email, first login Google then Facebook | Likely same OpenCloud user (email-keyed autoprov) — **verify in staging** |
| Same person, different emails across providers | **Two** OpenCloud accounts |
| Facebook `id` changes | Extremely rare (app deletion/recreation); email remains primary |

---

## 4. Claim mapping specification

| Facebook Graph field | Dex internal | Dex ID token (typical) | OpenCloud |
|---------------------|--------------|------------------------|-----------|
| `id` | `userID` | `sub` (via Dex) | Not primary key |
| `email` | `email` | `email` | **Identity + username** |
| `name` | `userName` | `name` | Display |
| — | — | `email_verified` | Skipped (`insecureSkipEmailVerified`) |

LDAP connector mapping (reference): `emailAttr: mail` → `email` claim. Facebook must produce equivalent `email` in Dex token output.

---

## 5. Security and OAuth behaviour

| Risk | Severity | Notes |
|------|----------|-------|
| Missing email → failed or partial auth | High | Fail closed; monitor Dex logs |
| OAuth connector alpha | Medium | Pin Dex version; test upgrades in staging |
| Token handling vs Google | Low | All consumer tokens still Dex-issued; proxy unchanged |
| CSRF / redirect | Low | Same `/dex/callback` as other connectors; rely on Dex state |
| App secret leakage | High | Store in `dex/.env` or `/opt/facebook-client-secret.json` (gitignored), mode `600` |

No change to OpenCloud JWT validation path: still Dex JWKS only.

---

## 6. Meta platform constraints

| Requirement | Action |
|-------------|--------|
| Facebook Login product | Add in Meta Developer App → Products |
| Permissions | `email`, `public_profile` (default); `email` needs **Advanced access** / App Review for production |
| Valid OAuth redirect URIs | `https://cloud.km0digital.com/dex/callback` |
| App domains | `cloud.km0digital.com` |
| Privacy Policy URL | Public HTTPS URL (e.g. km0digital.com legal page) |
| Data deletion | Meta requires callback URL or instructions URL |
| Development vs Live | Dev: test users only; Live: reviewed permissions |
| Business verification | May be required for some permission tiers |

---

## 7. Configuration model (Issue 2)

### Existing patterns

| Item | Location |
|------|----------|
| Dex template | `dex/config.yaml` → rendered to `/etc/dex/config.yaml` |
| Entrypoint / secrets | `dex/docker-entrypoint.sh`, `dex/.env` (from `.env.example`) |
| Google | Static in template; `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` |
| Apple | Appended in entrypoint when `APPLE_CLIENT_*` set; `setup-apple.sh` |
| Static OIDC clients | `opencloud-web`, `OpenCloudDesktop`, `OpenCloudAndroid`, `OpenCloudIOS` |
| OpenCloud OIDC env | `overrides/opencloud-compose/patches/docker-compose.oidc-env.patch` |

### Facebook parameters → mapping

| Meta / Facebook | km0 storage | Notes |
|-----------------|-------------|-------|
| App ID | `FACEBOOK_CLIENT_ID` in `dex/.env` | Or JSON at `/opt/facebook-client-secret.json` (document only) |
| App Secret | `FACEBOOK_CLIENT_SECRET` in `dex/.env` | Never commit |
| Redirect URI | Dex `redirectURI: ${DEX_ISSUER}/callback` | Register in Meta console |
| Scopes | `email`, `public_profile` in connector `scopes` | |
| Graph API version | `v21.0` in example URLs | Bump deliberately when Meta deprecates |

### Routing chain (unchanged for OpenCloud)

```text
User → nginx → /login.html → /dex/auth?connector_id=facebook&client_id=opencloud-web&...
     → Dex → www.facebook.com → /dex/callback → Dex token → /oidc-callback.html?code=...
     → OpenCloud
```

- **nginx:** No new vhost required; `/dex/` already proxied.
- **OpenCloud:** No routing changes; same `OC_OIDC_ISSUER`.
- **CSP:** When enabling, add to `overrides/opencloud-compose/config/opencloud/csp.yaml`:
  - `https://www.facebook.com`
  - `https://graph.facebook.com`

### UI changes (when enabling)

| File | Change |
|------|--------|
| `host-www/opencloud-auth/login.html` | Facebook button → `startDexLogin('facebook')` |
| `dex/web/themes/km0/i18n.js` | `continueFacebook` strings (CA/ES/EN/DE) |
| `dex/web/themes/km0/styles.css` | Optional `.theme-btn-provider--facebook` |
| Deploy | `rsync` to `/var/www/opencloud-auth/` per runbook |

---

## 8. Secret management

| Practice | km0 alignment |
|----------|---------------|
| Storage | `dex/.env` (chmod 600), gitignored; optional `/opt/facebook-client-secret.json` |
| Separation | Distinct Meta apps per dev/staging/prod recommended |
| Rotation | Regenerate App Secret in Meta → update `.env` → `docker compose up -d` in `dex/` |
| Backup | Include in `scripts/backup-opencloud-installation.sh` opt-credentials pattern (operator) |

---

## 9. Operational impact

| Area | Impact |
|------|--------|
| Deploy | `cd dex && docker compose up -d` after config/env change |
| Rollback | Remove Facebook env vars or connector block; restart Dex |
| Logs | `docker logs opencloud-dex 2>&1 \| grep -iE 'facebook\|oauth\|email'` |
| Failure modes | `redirect_uri_mismatch`, permission denied, missing email, dev-mode user restriction |
| Monitoring | Alert on Dex auth errors spike after enablement |

---

## 10. Implementation checklist (future FEAT, not done here)

1. Create Meta app; complete App Review for `email`.
2. Set `FACEBOOK_CLIENT_ID` / `FACEBOOK_CLIENT_SECRET` in `dex/.env`.
3. Confirm entrypoint injects `facebook` connector (or merge example into template).
4. Update CSP for Facebook domains.
5. Add landing + i18n button; rsync `host-www`.
6. Staging E2E: web login → `/files`; regression Google/Apple/LDAP.
7. Document operator runbook section (link this file).

---

## References

- Runbook: `docs/runbook.md` (Multi-provider OIDC)
- Dex README: `dex/README.md`
- Example connector: `dex/config.facebook.oauth.example.yaml`
- Dex OAuth docs: https://dexidp.io/docs/connectors/oauth/
- Meta Facebook Login: https://developers.facebook.com/docs/facebook-login/
