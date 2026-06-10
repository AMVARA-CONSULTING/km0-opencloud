# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Fixed

- Self-registration: `POST /api/register` returned HTTP 500 because register-api used password Basic auth while OpenCloud Graph requires an app token when `PROXY_ENABLE_BASIC_AUTH=false` (default). register-api now uses `GRAPH_SERVICE_APP_TOKEN`, reports `graph_auth_ok` in `/health`, and returns 503 on auth failures.
- Registration canonical URL `/register` (301 from `/register.html`); Dex password page link to register; ES/CA/EN/DE copy updates on login and register flows.
- Login landing: hide Apple OIDC button until `APPLE_CLIENT_*` is configured; update ES/CA/EN/DE copy to reference Google only (not Google/Apple).

### Added

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
