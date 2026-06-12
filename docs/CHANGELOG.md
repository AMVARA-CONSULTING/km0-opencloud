# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Changed

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
