# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added

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
