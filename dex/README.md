# Dex OIDC gateway (Google + Apple)

Lightweight OIDC broker behind nginx at `https://cloud.km0digital.com/dex/`.
OpenCloud uses Dex as its single external issuer (no Keycloak).

## OIDC static clients

OpenCloud requires **fixed** public client IDs in Dex. Do not rename them.

| Client | ID | Redirect URIs |
|--------|-----|---------------|
| Web | `opencloud-web` (override via `OPENCLOUD_WEB_CLIENT_ID`) | `https://<host>/`, `/oidc-callback.html`, `/oidc-silent-redirect.html` |
| Desktop | `OpenCloudDesktop` | Loopback: any port on `http://127.0.0.1` or `http://localhost` (Dex ≥2.42, **empty** `redirectURIs` in config). OpenCloud upstream docs list port-less URIs for other IdPs; Dex requires an empty list. |
| Android | `OpenCloudAndroid` | `oc://android.opencloud.eu` |
| iOS | `OpenCloudIOS` | `oc://ios.opencloud.eu` |

Verify live config:

```bash
docker exec opencloud-dex grep -E 'OpenCloudDesktop|OpenCloudAndroid|OpenCloudIOS|opencloud-web' /etc/dex/config.yaml
```

Nginx sends `/dex/auth` without `connector_id` to `/login.html` **only** for `client_id=opencloud-web` (web SPA). Native apps hit Dex directly.

## Google (working)

Authorized redirect URI in Google Cloud Console:

```text
https://cloud.km0digital.com/dex/callback
```

Also add the OpenCloud web client redirect URIs shown in Google Console (`/`, `/oidc-callback.html`, `/oidc-silent-redirect.html`). A `redirect_uri_mismatch` error means the Console list does not match Dex’s `redirectURI` (check with `docker exec opencloud-dex grep redirectURI /etc/dex/config.yaml`).

## Local username/password (OpenCloud IDM LDAP)

Dex connector `ldap` authenticates against the built-in OpenCloud IDM (`ldaps://opencloud:9235`, base `ou=users,o=libregraph-idm`). Users sign in with the same **uid** and password as in OpenCloud Settings.

Requirements:

- OpenCloud override sets `IDM_LDAPS_ADDR=0.0.0.0:9235` (see `overrides/opencloud-compose/external-proxy/opencloud.yml`).
- Dex joins Docker network `opencloud_opencloud-net` and mounts `opencloud_opencloud-config` + `opencloud_opencloud-data` (for `idm/ldap.crt`).
- `OPENCLOUD_IDM_BIND_PW` in `dex/.env` **or** auto-read from `opencloud.yaml` `idm_password` via the mounted config volume.
- IDM LDAPS cert must include **`DNS:opencloud`** in the SAN (Dex connects to `opencloud:9235`). Auto-generated certs only list `localhost`. Run once after deploy or when Dex logs `certificate is valid for localhost, not opencloud`:

  ```bash
  ./scripts/regenerate-opencloud-idm-ldap-cert.sh --restart
  ```

Verify from the Dex container:

```bash
docker exec opencloud-dex grep -A2 'type: ldap' /etc/dex/config.yaml
```

## Apple Sign In

### 1. Apple Developer portal

1. [Identifiers → Services IDs](https://developer.apple.com/account/resources/identifiers/list/serviceId) — create a Services ID (e.g. `de.amvara.km0.cloud`).
2. Enable **Sign in with Apple** → Configure:
   - **Domains:** `cloud.km0digital.com`
   - **Return URLs:** `https://cloud.km0digital.com/dex/callback`
3. Link the Services ID to your **App ID** (primary app with Sign in with Apple enabled).
4. [Keys](https://developer.apple.com/account/resources/authkeys/list) — create key with **Sign in with Apple**, download `AuthKey_XXXXXXXXXX.p8` (once only).
5. Note **Team ID** (Membership details), **Key ID**, and **Services ID** (client ID).

### 2. Server credentials file

```bash
cp /opt/apple-signin-credentials.example.json /opt/apple-signin-credentials.json
chmod 600 /opt/apple-signin-credentials.json
nano /opt/apple-signin-credentials.json
```

Copy the `.p8` key to the path in `private_key_file` (e.g. `/opt/opencloud/dex/AuthKey_XXX.p8`, mode `600`).

Example:

```json
{
  "services_id": "de.amvara.km0.cloud",
  "team_id": "AB12CD34EF",
  "key_id": "A1B2C3D4E5",
  "private_key_file": "/opt/opencloud/dex/AuthKey_A1B2C3D4E5.p8"
}
```

### 3. Apply configuration

```bash
chmod +x /opt/opencloud/dex/setup-apple.sh
sudo /opt/opencloud/dex/setup-apple.sh
```

This generates the Apple JWT client secret (~180 days), updates `dex/.env`, and restarts Dex.

### 4. Verify

- Dex login should list **Google** and **Apple**: open https://cloud.km0digital.com/
- Logs: `docker logs opencloud-dex 2>&1 | grep apple`

### Renew Apple client secret

Apple JWT secrets expire. Re-run `setup-apple.sh` before expiry (or add a cron job every ~150 days).

## Facebook Login (investigation — not enabled by default)

Facebook is **not** OIDC-native. km0 uses Dex `type: oauth` with the Graph API (Dex v2.42 has no maintained `type: facebook` connector).

**Full report:** [`docs/facebook-login-dex-investigation.md`](../docs/facebook-login-dex-investigation.md)  
**Example config:** `dex/config.facebook.oauth.example.yaml`

To enable after Meta App Review:

1. Create a Meta app with **Facebook Login**; add redirect URI `https://cloud.km0digital.com/dex/callback`.
2. Set in `dex/.env` (chmod 600): `FACEBOOK_CLIENT_ID`, `FACEBOOK_CLIENT_SECRET`.
3. `cd /opt/opencloud/dex && docker compose up -d`
4. Verify connector: `docker exec opencloud-dex grep -A3 'id: facebook' /etc/dex/config.yaml`
5. Add CSP entries for `https://www.facebook.com` and `https://graph.facebook.com` in `overrides/opencloud-compose/config/opencloud/csp.yaml`, apply overrides, restart OpenCloud.
6. Add a Facebook button on `host-www/opencloud-auth/login.html` (`connector_id=facebook`) and rsync to `/var/www/opencloud-auth/`.

**Identity requirement:** OpenCloud uses `PROXY_USER_OIDC_CLAIM=email`. Facebook must return `email`; logins without email will fail autoprov.

## Commands

```bash
cd /opt/opencloud/dex
docker compose up -d
docker compose logs -f dex
```

## Login UI (KM0 theme)

Dex uses a custom frontend theme aligned with [km0.amvara.de](https://km0.amvara.de): navy background, Inter font, brand gradient, KM0 logo.

Login UI languages: **CA | ES | EN | DE** (aligned with km0-web). Preference stored in `localStorage`; override with `?lang=ca|es|en|de`.

Files: `/opt/opencloud/dex/web/themes/km0/` (`styles.css`, `i18n.js`), templates in `/opt/opencloud/dex/web/templates/`.

Dex password and error pages load `dex-auth.js` from `/dex/static/dex-auth.js`. Keep it in sync with the canonical `host-www/opencloud-auth/dex-auth.js` (copy into `dex/web/static/` when editing), restart Dex, and rsync `host-www/opencloud-auth/` to `/var/www/opencloud-auth/` for the login landing.

Optional landing: https://cloud.km0digital.com/login.html
