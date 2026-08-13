# register-api

Minimal backend for public self-registration. Creates OpenCloud IDM users via `POST /graph/v1.0/users`.

Optional **KM0 Mail** provisioning: when `create_mail=true`, register-api calls km0-mail `mail-provision-api` on the shared Docker network (`km0-mail_mailnet`).

## Setup

OpenCloud disables password Basic auth by default (`PROXY_ENABLE_BASIC_AUTH=false`). Use an **app token**, not a user password:

```bash
./scripts/setup-register-api-graph-token.sh
# optional: --user admin --expires-in 90d  (default 90 days)
```

### Token rotation and auto-renewal

The Graph app token expires (default **90 days**). Rotate manually or enable weekly auto-renewal when fewer than **14 days** remain.

**Manual rotation** (register-api only — does not touch users, volumes, Dex, or OpenCloud config):

```bash
./scripts/setup-register-api-graph-token.sh --expires-in 90d
cd /opt/opencloud/register-api && docker compose up -d --build register-api
./scripts/verify-register-api.sh   # expect graph_auth_ok: true
```

**Auto-renewal** (install once on the host):

```bash
sudo cp /opt/opencloud/scripts/register-api-token-renewal.cron /etc/cron.d/register-api-token-renewal
sudo chmod 644 /etc/cron.d/register-api-token-renewal
```

Runs Mondays at 03:00 UTC; logs to `/var/log/register-api-token-renewal.log`. Force a check:

```bash
./scripts/renew-register-api-graph-token.sh
./scripts/renew-register-api-graph-token.sh --force   # renew regardless of expiry
```

**Safety:** renewal scripts only update `GRAPH_SERVICE_APP_TOKEN` / expiry metadata in `register-api/.env` and restart **register-api**. They must **not** run `docker compose down -v`, delete volumes, reset users, or change Dex/OIDC settings. A failed renewal leaves existing Google OAuth login unaffected.

Or manually:

```bash
cp .env.example .env
chmod 600 .env
docker exec opencloud-opencloud-1 opencloud auth-app create --user-name admin
# Set GRAPH_SERVICE_USER and GRAPH_SERVICE_APP_TOKEN in .env
```

## Run

```bash
cd /opt/opencloud/register-api
docker compose up -d --build
curl -s http://127.0.0.1:8091/health
# expect: {"graph_auth_ok": true, "graph_configured": true, "ok": true}
```

Verify after deploy:

```bash
./scripts/verify-register-api.sh
```

## Endpoints

| Path | Method | Description |
|------|--------|-------------|
| `/health` | GET | Liveness + Graph + mail-provision status |
| `/register` | POST | KM0 model: JSON `{ "username", "password", "create_mail?", "contact_email?" }`. Legacy/custom-domain: `{ "email", "password", "create_mail?", "mail_mode?", "desired_email?", "contact_email?" }` |
| `/activate-mail` | POST | Existing OpenCloud user → KM0 mailbox (no new Graph user). See below. |
| `/update-password` | POST | JSON `{ "email", "password" }` → sync mailbox password in km0-mail |
| `/enable-2fa` | POST | Bearer (Cloud session) → adds caller to IDM group `2fa-enabled` (opt-in 2FA in Authelia). |
| `/disable-2fa` | POST | Bearer (Cloud session) → removes caller from `2fa-enabled`. |
| `/2fa-status` | GET | Bearer (Cloud session) → `{ "enabled": bool }` for the caller. |

**Optional 2FA (opt-in):** the `2fa-enabled` group is auto-created on first use.
Users in it get the `two_factor` policy in Authelia (`/opt/opencloud/authelia`);
everyone else stays `one_factor` (password only). Authz is the same as
`/activate-mail` (end-user Bearer via Graph `/me`). Group name overridable with
`TWO_FA_GROUP_NAME`.

**KM0 model (username):** login uid = `username`; mailbox = `<username>@km0digital.com` (mail_mode `km0`); `contact_email` optional and may be freemail (Gmail, etc.). `username` must match `^[a-z0-9]([a-z0-9._-]{1,30}[a-z0-9])$` and not be reserved (`RESERVED_USERNAMES`).

**Legacy/custom fields:** when `username` is absent, `email` is both uid and IDM mail; `create_mail=true` provisions a mailbox via km0-mail (freemail domains blocked as mailbox). Set `MAIL_PROVISION_API_TOKEN` in `.env` (same value as km0-mail). Container joins external network `km0-mail_mailnet`.

### `POST /activate-mail` (existing Cloud users)

For OIDC-first users (Google, Apple, or any enabled freemail connector) who already exist in Graph/IDM and never ran `/register` with mail. Does **not** create a Graph user.

**Request JSON:** `{ "username", "password", "contact_email?", "opencloud_uuid?" }`

- Mailbox is always `<username>@km0digital.com` (`mail_mode=km0`). Freemail as mailbox is impossible/rejected.
- `contact_email` may be freemail (Gmail, iCloud, etc.). If omitted, current Graph `mail` is used as contact when it is not already a KM0 mailbox address.
- Sets/syncs Graph `passwordProfile` only. **Does not** set Graph `mail` to the KM0 mailbox (#24 Design A): OIDC-first users keep IdP email as Graph `mail` / `onPremisesSamAccountName` so `PROXY_USER_OIDC_CLAIM=email` still rematches the same `openCloudUUID`. Mailbox + `contact_email` live in km0-mail. If a prior activate rewrote Graph `mail` to `@km0`, passing `contact_email` (freemail) restores Graph `mail`.
- Calls km0-mail `POST /provision`; idempotency uses mail-provision account status; re-activate also `POST /update-password`.
- Roundcube **password** login uses the mailbox credentials. Roundcube **LDAP OAuth** with token `email`=mailbox needs km0-mail #9/#12 (uuid/contact map); do not rely on Graph `mail`=mailbox for Cloud OIDC rematch.

**Authz (do not call unauthenticated):**

1. **Preferred — end-user Bearer:** `Authorization: Bearer <OpenCloud access_token>` from the Cloud OIDC session (`oc_oAuth.user:`). register-api calls Graph `GET /me` with that token; the resolved `id` is the uuid. Optional body `opencloud_uuid` must match `/me` if present.
2. **Hub service token (optional):** set `ACTIVATE_MAIL_SERVICE_TOKEN` in `.env`. Hub may send `Authorization: Bearer <ACTIVATE_MAIL_SERVICE_TOKEN>` with required `opencloud_uuid` **only after** proving the browser session owns that uuid (e.g. decoded access token / Graph `/me` on the hub). Without that proof this mode must not be used.

**Responses:** `201` created · `200` exists/idempotent · `401` unauthorized · `409` duplicate username · `400` validation.

Nginx proxies public `POST /api/activate-mail` → `http://127.0.0.1:8091/activate-mail` (same rate limit zone as register).

**UI wizard (cloud origin):** `https://cloud.km0digital.com/activate-mail.html` (`host-www/opencloud-auth/activate-mail.html`). Hub cannot read Cloud OIDC storage; deep-link users here (km0-mail #14) for **any** Cloud IdP (Google, Apple when enabled, LDAP). Page requires a Cloud session Bearer; no unauthenticated activate. Same canonical URL for all providers.

Nginx proxies public `POST /api/register` to `http://127.0.0.1:8091/register` (cloud and mail hostnames).

## Logs

```bash
docker logs -f opencloud-register-api
```
