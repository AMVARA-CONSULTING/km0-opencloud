---
## Closing summary (TOP)

- **What happened:** Native OpenCloud sync clients (desktop, Android, iOS) failed OIDC with `invalid client_id` because Dex lacked static clients and nginx redirected all `/dex/auth` traffic to `/login.html`.
- **What was done:** Added Dex static clients `OpenCloudDesktop`, `OpenCloudAndroid`, `OpenCloudIOS`; nginx map only redirects web (`opencloud-web` or empty `client_id`) to `/login.html`; runbook and dex README updated.
- **What was tested:** Dex config grep, WebFinger per platform, `/dex/auth` smoke for all three native clients (HTTP 200) and web client (302 → `/login.html`); compose/Dex health; no `invalid client` in logs. Operator device/browser E2E deferred.
- **Why closed:** Tester overall **PASS** — all automatable server-side criteria met; operator checklist documented for real-device login/sync.
- **Closed at (UTC):** 2026-06-01 13:47
---

# Desktop and mobile sync clients fail OIDC login — Dex missing OpenCloudDesktop/Android/iOS clients

## GitHub Issue
- **Issue:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/4
- **Number:** #4
- **Labels:** none
- **Created:** 2026-06-01T13:41:59Z

## Problem / goal
Desktop and mobile sync clients fail OIDC login — Dex missing OpenCloudDesktop/Android/iOS clients. Native OpenCloud sync clients (Android, iOS, and desktop) cannot log in to `https://cloud.km0digital.com` with `invalid client_id` errors. Web UI works.

## High-level instructions for coder
- Read the full issue at https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/4
- Identify affected paths under overrides/, dex/, nginx/, host-www/, scripts/, docs/
- Implement minimal, on-scope changes for km0-opencloud
- Add **Testing instructions** before renaming to UNTESTED-

## References
- Repo: https://github.com/AMVARA-CONSULTING/km0-opencloud
- Runbook: docs/runbook.md

## Implementation

- **`dex/config.yaml`:** Added public static clients `OpenCloudDesktop`, `OpenCloudAndroid`, and `OpenCloudIOS` with OpenCloud-required redirect URIs (`http://127.0.0.1`, `http://localhost`, `oc://android.opencloud.eu`, `oc://ios.opencloud.eu`). No entrypoint changes needed (fixed IDs, not host placeholders).
- **`nginx/conf.d/opencloud-map.conf`:** `/dex/auth` → `/login.html` redirect now applies only when `connector_id` is empty **and** `client_id` is empty or `opencloud-web`. Native clients reach Dex directly.
- **`dex/README.md`:** Documented all four OIDC static clients and verify command.
- **`docs/runbook.md`:** New “Desktop and mobile sync clients” subsection with deploy steps, smoke curls, log grep, operator checklist.

**Deployed on server:** Dex restarted; nginx map copied and reloaded.

## Testing instructions

1. **Dex static clients (required)**
   ```bash
   cd /opt/opencloud/dex && docker compose up -d
   docker exec opencloud-dex grep -E 'OpenCloudDesktop|OpenCloudAndroid|OpenCloudIOS|opencloud-web' /etc/dex/config.yaml
   ```
   Expect four client IDs including the three native apps.

2. **Nginx map (if not already deployed)**
   ```bash
   sudo cp /opt/opencloud/nginx/conf.d/opencloud-map.conf /etc/nginx/conf.d/
   sudo nginx -t && sudo systemctl reload nginx
   ```

3. **Server-side smoke**
   ```bash
   curl -s "https://cloud.km0digital.com/.well-known/webfinger?resource=https://cloud.km0digital.com&rel=http://openid.net/specs/connect/1.0/issuer&platform=desktop" | jq -r '.properties["http://opencloud.eu/ns/oidc/client_id"]'
   # expect: OpenCloudDesktop

   curl -sI "https://cloud.km0digital.com/dex/auth?client_id=OpenCloudDesktop&redirect_uri=http%3A%2F%2F127.0.0.1&response_type=code&scope=openid+profile+email+offline_access&state=test&code_challenge=abc&code_challenge_method=S256" | grep -iE '^(HTTP|location:)'
   # expect: HTTP/2 200 (Dex auth page), NOT redirect to /login.html

   curl -sI "https://cloud.km0digital.com/dex/auth?client_id=opencloud-web&redirect_uri=https%3A%2F%2Fcloud.km0digital.com%2Foidc-callback.html&response_type=code&scope=openid+profile+email&state=test&code_challenge=abc&code_challenge_method=S256" | grep -i '^location:'
   # expect: /login.html?... (web flow unchanged)
   ```

4. **Operator — iOS (NOT VERIFIED)** — Install OpenCloud iOS app; server `https://cloud.km0digital.com`; log in via Google/Apple/LDAP; confirm no `invalid client_id ("OpenCloudIOS")`; upload test file; verify sync to web.

5. **Operator — Android (NOT VERIFIED)** — Same with Android app and `OpenCloudAndroid`.

6. **Operator — Desktop (optional, NOT VERIFIED)** — OpenCloud Desktop; complete OIDC; confirm sync folder.

7. **Regression — web UI (NOT VERIFIED)** — Private window: Google, Apple, and LDAP login from `/login.html` still reach `/files`; logout returns to login page.

8. **Logs during operator tests**
   ```bash
   docker compose -f /opt/opencloud/opencloud-compose/docker-compose.yml logs -f opencloud 2>&1 | grep -iE 'OpenCloudDesktop|OpenCloudAndroid|OpenCloudIOS|oidc|invalid.client'
   docker logs -f opencloud-dex 2>&1 | grep -iE 'invalid|OpenCloud'
   ```

**Coder server-side verification (2026-06-01):** Dex grep lists all four clients after restart; WebFinger desktop → `OpenCloudDesktop`; desktop/mobile `/dex/auth` → HTTP 200; web client → 302 to `/login.html`.

---

## Test report

**Window (UTC):** 2026-06-01T13:46:16Z → 2026-06-01T13:46:47Z  
**Log window:** Dex/opencloud logs from `2026-06-01T13:45:00Z` (Dex restart at 13:45:42Z)

### Environment

| Item | Value |
|------|-------|
| Branch | `main` @ `522faea` |
| Compose | `opencloud-compose` — opencloud, collabora, collaboration Up 3d; dex Up (restarted ~38s before test) |
| Dex | `opencloud-dex` on `127.0.0.1:5556` |
| URLs | `https://cloud.km0digital.com/` |

**Stack readiness:** Polled `docker compose ps` (all services Up), `docker exec opencloud-dex grep` (four client IDs), then production curls — no fixed sleep; Dex startup confirmed via logs (`listening on` at 13:45:42Z).

### Results

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | Dex static clients (four IDs) | **PASS** | `docker exec opencloud-dex grep -E '...'` → `opencloud-web`, `OpenCloudDesktop`, `OpenCloudAndroid`, `OpenCloudIOS` |
| 2 | Nginx map deployed | **PASS** | `/etc/nginx/conf.d/opencloud-map.conf` contains `$arg_client_id` map; `nginx -t` ok |
| 3a | WebFinger desktop | **PASS** | `OpenCloudDesktop` |
| 3b | WebFinger android/ios | **PASS** | `OpenCloudAndroid`, `OpenCloudIOS` |
| 3c | `/dex/auth` OpenCloudDesktop | **PASS** | `HTTP/2 200` (no `location:` to login.html) |
| 3d | `/dex/auth` OpenCloudAndroid/IOS | **PASS** | Both `HTTP/2 200` |
| 3e | `/dex/auth` opencloud-web | **PASS** | `HTTP/2 302` → `location: .../login.html?...` |
| 4 | Operator iOS login/sync | **NOT VERIFIED** | Requires physical device + app; server prerequisites pass |
| 5 | Operator Android | **NOT VERIFIED** | Same |
| 6 | Operator Desktop (optional) | **NOT VERIFIED** | Same |
| 7 | Regression web UI (Google/Apple/LDAP) | **NOT VERIFIED** | Requires interactive browser; web `/dex/auth` redirect unchanged |
| 8 | Logs — no invalid client | **PASS** | Dex startup lists all four static clients; no `invalid client` in opencloud/dex window |

**OpenCloud health:** `curl https://cloud.km0digital.com/` → `302` (expected redirect).

### Overall: **PASS**

Automatable server-side OIDC client registration and nginx routing verified. Native app and browser E2E deferred to operator per testing instructions.

### URLs tested

- `https://cloud.km0digital.com/`
- `https://cloud.km0digital.com/.well-known/webfinger` (platform=desktop|android|ios)
- `https://cloud.km0digital.com/dex/auth` (OpenCloudDesktop, OpenCloudAndroid, OpenCloudIOS, opencloud-web)

### Log excerpts

```
# Dex restart 2026-06-01T13:45:42Z
{"level":"INFO","msg":"config static client","client_name":"OpenCloud Web"}
{"level":"INFO","msg":"config static client","client_name":"OpenCloud Desktop"}
{"level":"INFO","msg":"config static client","client_name":"OpenCloud Android"}
{"level":"INFO","msg":"config static client","client_name":"OpenCloud iOS"}
{"level":"INFO","msg":"listening on","server":"http","address":"0.0.0.0:5556"}
```

**GitHub labels:** `agent:testing` added at test start; removed on pass.
