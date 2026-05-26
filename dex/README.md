# Dex OIDC gateway (Google + Apple)

Lightweight OIDC broker behind nginx at `https://cloud.km0.amvara.de/dex/`.
OpenCloud uses Dex as its single external issuer (no Keycloak).

## Google (working)

Authorized redirect URI in Google Cloud Console:

```text
https://cloud.km0.amvara.de/dex/callback
```

## Apple Sign In

### 1. Apple Developer portal

1. [Identifiers → Services IDs](https://developer.apple.com/account/resources/identifiers/list/serviceId) — create a Services ID (e.g. `de.amvara.km0.cloud`).
2. Enable **Sign in with Apple** → Configure:
   - **Domains:** `cloud.km0.amvara.de`
   - **Return URLs:** `https://cloud.km0.amvara.de/dex/callback`
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

- Dex login should list **Google** and **Apple**: open https://cloud.km0.amvara.de/
- Logs: `docker logs opencloud-dex 2>&1 | grep apple`

### Renew Apple client secret

Apple JWT secrets expire. Re-run `setup-apple.sh` before expiry (or add a cron job every ~150 days).

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

Optional landing: https://cloud.km0.amvara.de/login.html
