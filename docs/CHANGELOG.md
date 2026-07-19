# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added

- Runbook: known OpenCloud limitation — public-link subfolder ZIP (`/archiver` → `download.zip` 404); per-file / logged-in WebDAV workaround; optional upstream issue draft `docs/issue-public-share-folder-zip-archiver.md`.
- Cloud session gate (`km0-session-gate.html`): `/`, `/login`, `/login.html`, and web `/dex/auth` check browser OIDC storage and forward to `/files` when a session exists, otherwise redirect to the auth hub.
- Auth hub (`auth.km0digital.com`): cloud `/login`, `/register`, and `/logout` redirect to the hub; OIDC bridge `km0-oidc-start.html`, `km0-sso-snippet.js` injection, and TLS helper `scripts/issue-auth-km0digital-cert.sh`.
- register-api: KM0 username registration model (`username` + optional `contact_email`, reserved-name checks) alongside legacy email/custom-domain flow; CORS allows `auth.km0digital.com`.

### Changed

- Dex session lifetime: ID tokens 24h; refresh tokens 30 days idle / 90 days absolute; Web OIDC scope includes `offline_access` (`WEB_OIDC_SCOPE`, `config-dex.json`, `dex-auth.js`).
- OpenCloud `loginUrl` points at the session gate; nginx login/Dex web redirects go through the gate before the auth hub; `verify-auth-pages.sh` asserts gate + `offline_access`.
- OpenCloud image pin `7.0.0` → `7.3.0` (`OC_DOCKER_TAG` in `.env` examples, runbook, README). Custom Dex + nginx login path unchanged; backup volumes before `docker compose up -d`. OpenCloud 7.3 requires explicit `IDM_LDAPS_CERT` / `IDM_LDAPS_KEY` when `IDM_LDAPS_ADDR` is set (Dex → IDM on :9235).
- Auth surfaces (login/register/logout, Dex KM0 theme, favicons/logos): civic dark tokens (Paper/Snow/Mist/Ink/Signal), IBM Plex Sans + Bricolage Grotesque, canonical K0 lettermark at 72px; Dex LDAP copy as unified KM0 Account.
- OpenCloud `post_logout_redirect_uri` and logout redirects remain on the auth hub; earlier hub login routing is superseded by the session gate above.

### Fixed

- WOPI / collaboration after OpenCloud 7.3.0: set `COLLABORATION_EVENTS_ENDPOINT` and store nodes to `opencloud:9233` in `overrides/opencloud-compose/external-proxy/collabora.yml` (loopback NATS default caused nginx 502 on `wopi.*`).
- Logout: Dex end-session redirects to hub login with `signed_out=1`; `id_token_hint` optional so logout still completes without a stored token.

### Added

- register-api: KM0 Mail provision hook (`create_mail`, `mail_mode`, `desired_email`, `contact_email`), freemail blocklist, `/update-password` forward to km0-mail; joins `km0-mail_mailnet` for `mail-provision-api:8092`.
- OpenCloud register page: optional **Create KM0 Mail account** checkbox (CA/ES/EN/DE i18n); custom-domain mail redirects to mail DNS wizard after signup.
- `scripts/verify-register-api.sh`: checks `mail_provision_ok` on `/health`.

### Fixed

- register-api Graph token renewal: pass `GRAPH_SERVICE_USER` from `register-api/.env` to setup (fixes cron/force renewal when IDM has no `admin` user); poll `/health` until `graph_auth_ok` after restart.
- Self-registration UX: register page maps API/HTTP errors to typed i18n messages (duplicate, validation, service unavailable, rate limit) instead of a generic failure; duplicate copy directs users who registered via Google to use Google sign-in (ES/CA/EN/DE).
- register-api: validate email/password before Graph auth probe; parse Graph JSON for duplicate/conflict; return stable error codes (`validation`, `duplicate`, `service_unavailable`, `internal`).

### Added

- register-api Graph app token rotation: `setup-register-api-graph-token.sh --expires-in 90d` (default 90 days), `renew-register-api-graph-token.sh` with 14-day threshold, cron template `register-api-token-renewal.cron`, runbook safety constraints.
- Incident report `docs/register-incident-20260704-fundaalicates-yahoo.md` — generic register error caused by rejected Graph app token (503); Google OAuth path unaffected.

### Added

- Branded `/logout` page with Dex OIDC end-session flow; `dex-auth.js` helpers `completeLogoutIfNeeded` and `clearAllAuthState`; nginx serves static logout before the OpenCloud SPA; `post_logout_redirect_uri` updated in auth configs.
- Payment/pricing notice on host `/login.html` and Dex desktop login card (reuses `registerPricingNotice` i18n).
- Playwright auth test suite (`tests/auth/`) and operator curl smoke script `scripts/verify-auth-pages.sh`.

### Changed

- Dex desktop login template switched to card layout (`header-card.html`) aligned with host login/register; register link added.

### Added

- Dex: optional km0-mail webmail SSO — static OAuth clients `km0-mail-web` and `km0-mail-dovecot` with env-gated secrets in `docker-entrypoint.sh` (disabled until `KM0_MAIL_*_OAUTH_SECRET` set in `dex/.env`).
- Operator script `scripts/backup-user-data.sh` and cron template `scripts/opencloud-user-backup.cron` for rotated OpenCloud user-data volume backups to `/data`.

### Fixed

- Security: removed hardcoded Discord webhook URL from `scripts/backup-user-data.sh`; alerts require `DISCORD_WEBHOOK_URL` (rotate any webhook exposed in git history).
- Open Graph and Twitter Card previews: regenerated `og-preview.png` with the new KM0 pin logo; added missing Twitter Card meta tags on `register.html`.
- OpenCloud compose (external-proxy): map `host.docker.internal` to host gateway so the container can reach local km0-mail Postfix for SMTP relay from Docker networks.

### Changed

- Auth branding: double KM0 pin logo size on login, register, Dex card, and navbar views (96px → 192px).
- KM0 branding: new pin SVG logo on login, register, Dex navbar, and LDAP card views; local `/logo.svg` and `theme/logo.svg` replace external wordmark PNG; favicon updated (shadow ellipse removed); Dex `frontend.logoURL` set for v2.42.
- README: English-only content; removed em dashes; deployment notes aligned with runbook (Dex OIDC at `/dex/`, hybrid login landing, both `.env` templates, full TLS hostnames).

### Fixed

- Dex LDAP login for Google OIDC accounts: when a user tries username/password on an account registered via Google, Dex now shows a KM0-branded error page (ES/CA/EN/DE) with **Continue with Google** instead of a raw LDAP bind error; `dex-auth.js` resumes the in-flight OIDC flow from Dex's `back` query parameter. Dex password and error pages load the script from `/dex/static/dex-auth.js` so OIDC resume works after a Dex restart without a separate nginx rsync.
- Self-registration: `POST /api/register` returned HTTP 500 because register-api used password Basic auth while OpenCloud Graph requires an app token when `PROXY_ENABLE_BASIC_AUTH=false` (default). register-api now uses `GRAPH_SERVICE_APP_TOKEN`, reports `graph_auth_ok` in `/health`, and returns 503 on auth failures.
- Registration canonical URL `/register` (301 from `/register.html`); Dex password page link to register; ES/CA/EN/DE copy updates on login and register flows.
- Login landing: hide Apple OIDC button until `APPLE_CLIENT_*` is configured; update ES/CA/EN/DE copy to reference Google only (not Google/Apple).

### Added

- Shared `dex-auth.js` module for Dex OIDC/PKCE login flows (login, register, and Dex password pages); nginx serves it at `/dex-auth.js`, Dex serves a synced copy at `/dex/static/dex-auth.js`.
- Post-registration auto sign-in: successful registration stores credentials briefly in session storage, redirects through Dex LDAP, and the Dex password page auto-submits the pending login; i18n `registerSigningIn` strings (ES/CA/EN/DE).
- Operator scripts `setup-register-api-graph-token.sh` and `verify-register-api.sh` for register-api Graph app-token setup and deploy verification.
- Public email/password self-registration: `register.html`, `register-api` (Graph user creation on `127.0.0.1:8091`), nginx `/api/register` proxy with rate limiting, login page link and post-registration banner, i18n strings (ES/CA/EN/DE); runbook operator setup.
- KM0 branded favicon (SVG) on Dex login, static `login.html`, and OpenCloud SPA theme path; `/brand/og-preview.png` for share previews.
- Open Graph and Twitter Card metadata on Dex and login pages; nginx social-crawler detection injects branded title and OG tags into proxied OpenCloud HTML for link previews (Facebook, Slack, WhatsApp, etc.).

### Fixed

- Desktop OIDC loopback: Dex upgraded to v2.42.0; `OpenCloudDesktop` uses empty `redirectURIs` so ephemeral `http://127.0.0.1:<port>` callbacks are accepted (web/mobile clients unchanged).
- Desktop and mobile OpenCloud sync clients: Dex `staticClients` for `OpenCloudDesktop`, `OpenCloudAndroid`, and `OpenCloudIOS`; nginx `/dex/auth` redirect to `/login.html` applies only when `client_id=opencloud-web` so native apps reach Dex directly.

### Added

- Facebook Login investigation: `docs/facebook-login-dex-investigation.md`, Dex OAuth example config, env-gated `facebook` connector in `docker-entrypoint.sh` (disabled until `FACEBOOK_CLIENT_*` set).
- Self-hosted **Collabora Online CODE** and **WOPI** collaboration service for in-browser Office document editing (`.docx`, `.xlsx`, `.pptx`) in OpenCloud.
- Nginx vhost templates for `collabora.km0digital.com` and `wopi.km0digital.com` with shared proxy snippet.
- Compose env template `.env.debian-collabora-external-proxy.example` and enable scripts (`issue-collabora-wopi-certs.sh`, `enable-collabora-compose.sh`).
- Runbook and README updates for Collabora/WOPI deployment, TLS, smoke checks, and troubleshooting.
- Runbook and `dex/README.md` documentation for native sync client IDs, redirect URIs, deploy steps, and smoke checks.
