---
## Closing summary (TOP)

- **What happened:** GitHub issue #1 requested local login for any OpenCloud IDM user while still issuing Dex OIDC tokens for the proxy.
- **What was done:** Dex LDAP connector to built-in IDM, OpenCloud/Dex networking and cert overrides, `login.html` local flow via `connector_id=ldap`, and `scripts/regenerate-opencloud-idm-ldap-cert.sh` so the IDM LDAP cert SAN includes `opencloud` (TLS fix after test failure).
- **What was tested:** Automated criteria passed (cert SAN, Dex LDAP config, HTTP smoke, wrong-password 401 with LDAP bind and no x509 errors, Google connector smoke). Manual two-user OIDC happy-path not verified by agent (no credentials); deferred to operator.
- **Why closed:** Tester overall **PASS** on automated scope; implementation and cert/TLS fix verified in production stack.
- **Closed at (UTC):** 2026-05-27 13:38
---

# Mejora del login para que funcione con todos los usuarios de OpenCloud

## GitHub Issue
- **Issue:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/1
- **Number:** #1
- **Labels:** agent:wip
- **Created:** 2026-05-27T13:14:34Z

## Problem / goal
Local login must accept **any OpenCloud IDM user** (same uid/password as built-in OpenCloud), while still issuing **Dex** OIDC tokens for the proxy (`OC_OIDC_ISSUER`).

## Implementation summary
- Dex **LDAP** connector (`connector_id=ldap`) against OpenCloud built-in IDM (`ldaps://opencloud:9235`, `ou=users,o=libregraph-idm`).
- OpenCloud override: `IDM_LDAPS_ADDR=0.0.0.0:9235` so Dex on `opencloud_opencloud-net` can reach IDM.
- Dex: join `opencloud_opencloud-net`, mount `opencloud_opencloud-config` + `opencloud_opencloud-data` (LDAP CA), entrypoint reads `idm_password` safely.
- `login.html`: local button uses `connector_id=ldap`.
- **Fix (test fail):** auto-generated IDM `ldap.crt` SAN was `localhost` only; Dex TLS check failed for hostname `opencloud`. Added `scripts/regenerate-opencloud-idm-ldap-cert.sh` to regenerate cert with `DNS:localhost,DNS:opencloud,IP:127.0.0.1`.

## References
- Repo: https://github.com/AMVARA-CONSULTING/km0-opencloud
- Runbook: docs/runbook.md (Multi-provider OIDC section)
- Dex: dex/README.md
- Cert script: scripts/regenerate-opencloud-idm-ldap-cert.sh

## Testing instructions

1. **Apply overrides, regenerate IDM cert, restart stacks**
   ```bash
   ./scripts/apply-opencloud-compose-overrides.sh
   ./scripts/regenerate-opencloud-idm-ldap-cert.sh --restart
   rsync -a /opt/opencloud/host-www/opencloud-auth/ /var/www/opencloud-auth/
   ```

2. **IDM cert SAN (must include opencloud)**
   ```bash
   openssl x509 -in /var/lib/docker/volumes/opencloud_opencloud-data/_data/idm/ldap.crt \
     -noout -ext subjectAltName
   # expect: DNS:localhost, DNS:opencloud, IP Address:127.0.0.1
   ```

3. **Dex LDAP connector**
   ```bash
   docker logs opencloud-dex 2>&1 | tail -5
   docker exec opencloud-dex grep -A2 'type: ldap' /etc/dex/config.yaml
   # expect: host: opencloud:9235
   ```

4. **HTTP smoke**
   ```bash
   curl -sI "https://cloud.km0digital.com/dex/auth?client_id=opencloud-web&redirect_uri=https%3A%2F%2Fcloud.km0digital.com%2Foidc-callback.html&response_type=code&scope=openid%20profile%20email&connector_id=ldap&state=test&code_challenge=x&code_challenge_method=S256" | grep -i '^location:'
   # expect: /dex/auth/ldap?...
   ```

5. **LDAP path (automated, invalid password — proves TLS + bind work)**
   - Open LDAP login form via `connector_id=ldap`, POST wrong password.
   - Expect **HTTP 401** and Dex log `invalid password for user` (not `x509: certificate is valid for localhost, not opencloud`).

6. **Manual (private window)**
   - Open https://cloud.km0digital.com/login.html → **Iniciar sesión con usuario y contraseña**.
   - Sign in as an existing OpenCloud user (**uid**, e.g. `admin`, `luipy`) with that user’s OpenCloud password.
   - Expect redirect to `/oidc-callback.html` then `/files` without `key not found in JWKS` or `/graph/v1.0/me` 500.
   - Repeat with a second user account to confirm not limited to a single static Dex password.

7. **Regression**
   - Google login from the same landing page still works.
   - Clear site data if testing after a Dex restart (stale JWKS).

---

## Test report

**Date/time (UTC):** 2026-05-27T13:36:32Z – 2026-05-27T13:37:47Z  
**Log window:** Dex/OpenCloud logs from 2026-05-27T13:35:21Z onward (stack restarted ~13:35 UTC per container logs).

### Environment

| Item | Value |
|------|--------|
| Branch / commit | `main` @ `cf5a561` (feat(auth): Dex LDAP login against OpenCloud IDM for all users) |
| Compose | `opencloud-compose/` — `opencloud-opencloud-1` Up; `opencloud-dex` Up (separate compose) |
| URLs | https://cloud.km0digital.com/, http://127.0.0.1:9200/ |
| Stack readiness | Polled `docker compose ps` (opencloud Up), `curl` 302/200 on cloud URL and loopback; Dex logs show `listening on` at 13:35:21Z before HTTP checks |

### Results

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | Apply overrides / cert / deploy | **PASS** (pre-applied) | Production stack running; cert SAN and Dex LDAP logs confirm prior deploy. Tester did not re-run apply scripts (no code change during test). |
| 2 | IDM cert SAN includes `opencloud` | **PASS** | `openssl x509 … -ext subjectAltName` → `DNS:localhost, DNS:opencloud, IP Address:127.0.0.1` |
| 3 | Dex LDAP connector `host: opencloud:9235` | **PASS** | `docker exec opencloud-dex grep` → `host: opencloud:9235`, `rootCA: /etc/dex/opencloud-idm-ldap.crt`; startup logs list `connector_id":"ldap"` |
| 4 | HTTP smoke → `/dex/auth/ldap?` | **PASS** | `curl -sI …connector_id=ldap…` → `location: /dex/auth/ldap?…` |
| 5 | Wrong password → 401 + LDAP bind (no x509) | **PASS** | `POST` to `/dex/auth/ldap/login` with `Referer` → **HTTP 401**; Dex: `performing ldap search`, `username mapped to entry`, `invalid password for user` (13:37:32Z). No `x509` lines in Dex logs (`grep -i x509` empty). |
| 6 | Manual sign-in (two users) | **NOT VERIFIED** | Agent has no OpenCloud user passwords; cannot run private-window OIDC E2E. LDAP path to IDM verified via criterion 5. **Operator:** confirm login → `/oidc-callback.html` → `/files` for two distinct uids. |
| 7 | Google regression | **PASS** (smoke) | Dex config has `connector_id":"google"`; `curl …connector_id=google…` → `location: /dex/auth/google?…`; live `login.html` exposes `startDexLogin('google')` and `startDexLogin('ldap')`. Full Google OAuth not exercised (needs user Google account). |

### Overall: **PASS**

Automated criteria for the cert/TLS fix and Dex LDAP connector pass. Manual multi-user happy-path (criterion 6) deferred to operator with valid credentials.

### URLs tested

- https://cloud.km0digital.com/ (302)
- http://127.0.0.1:9200/ (200)
- https://cloud.km0digital.com/login.html (200)
- https://cloud.km0digital.com/dex/auth?…&connector_id=ldap (302 → ldap)
- https://cloud.km0digital.com/dex/auth?…&connector_id=google (302 → google)
- https://cloud.km0digital.com/dex/auth/ldap/login (POST, 401 on bad password)

### Log excerpts

```
# Dex startup (13:35:21Z)
{"msg":"config connector","connector_id":"ldap"}
{"msg":"listening on","server":"http","address":"0.0.0.0:5556"}

# LDAP wrong password (13:37:32Z) — TLS OK, bind reached IDM
{"msg":"performing ldap search","connector":{"type":"ldap","id":"ldap"},"filter":"(&(objectClass=inetOrgPerson)(uid=admin))"}
{"msg":"username mapped to entry","username":"admin","user_dn":"uid=admin,ou=users,o=libregraph-idm"}
{"msg":"invalid password for user","connector":{"type":"ldap","id":"ldap"}}
```

**GitHub labels:** `agent:testing` label missing in repo (gh edit failed); issue still shows `agent:wip`.
