---
## Closing summary (TOP)

- **What happened:** GitHub issue #5 requested an investigation of Facebook Login via Dex (sole OIDC issuer, email identity, config model, Meta production requirements) without enabling Facebook in production.
- **What was done:** Delivered `docs/facebook-login-dex-investigation.md`, `dex/config.facebook.oauth.example.yaml`, env-gated Facebook connector injection in `dex/docker-entrypoint.sh`, and operator updates in `dex/README.md`, `docs/runbook.md`, and `docs/CHANGELOG.md`; UI/CSP and live credentials remain out of scope.
- **What was tested:** Automated checks (no Facebook connector without env, login.html 200, Dex issuer, Google redirect, Dex logs) and documentation/secrets review all **PASS**; optional staging Facebook enablement skipped (no Meta test credentials).
- **Why closed:** All acceptance criteria and tester checklist passed; investigation deliverables complete.
- **Closed at (UTC):** 2026-06-03 11:23
---

# Facebook Login Integration — Updated Investigation Issues (km0-opencloud)

## GitHub Issue
- **Issue:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/5
- **Number:** #5
- **Labels:** agent:wip
- **Created:** 2026-06-03T11:18:00Z

## Problem / goal

Investigation (Issues 1–2 in #5): validate Facebook Login via Dex as sole OIDC issuer, email-based identity compatibility, configuration/deployment model, and Meta production requirements — without enabling Facebook in production.

## Implementation summary

| Deliverable | Location |
|-------------|----------|
| Architecture + identity + risk + Meta requirements | `docs/facebook-login-dex-investigation.md` |
| Dex OAuth connector example | `dex/config.facebook.oauth.example.yaml` |
| Env-gated connector injection (off until credentials set) | `dex/docker-entrypoint.sh` |
| Env template | `dex/.env.example` (`FACEBOOK_CLIENT_ID`, `FACEBOOK_CLIENT_SECRET`) |
| Operator docs | `dex/README.md`, `docs/runbook.md`, `docs/CHANGELOG.md` |

**Conclusion:** Use Dex `type: oauth` (not deprecated `facebook` type). Dex remains sole issuer. OpenCloud `PROXY_USER_OIDC_CLAIM=email` requires Facebook `email` permission; missing email must fail or use explicit product mitigation. Production needs Meta App Review.

**Not in scope (future FEAT):** `login.html` button, CSP updates, live Meta app credentials.

## References
- Repo: https://github.com/AMVARA-CONSULTING/km0-opencloud
- Runbook: docs/runbook.md

## Testing instructions

### Automated (server)

```bash
# Dex healthy; no facebook connector without env
docker exec opencloud-dex grep -c 'id: facebook' /etc/dex/config.yaml
# expect: 0

curl -sI https://cloud.km0digital.com/login.html | head -1
# expect: HTTP/2 200

curl -s https://cloud.km0digital.com/dex/.well-known/openid-configuration | jq -r .issuer
# expect: https://cloud.km0digital.com/dex

curl -sI "https://cloud.km0digital.com/dex/auth?client_id=opencloud-web&redirect_uri=https%3A%2F%2Fcloud.km0digital.com%2F&response_type=code&scope=openid%20profile%20email&connector_id=google&state=test" | grep -i '^location:'
# expect: /dex/auth/google
```

### Documentation review (tester)

1. Read `docs/facebook-login-dex-investigation.md` — confirm acceptance criteria in #5 are addressed (Dex sole issuer, oauth path, email requirement, Meta checklist, config mapping).
2. Confirm `dex/README.md` Facebook section matches investigation doc.
3. Confirm no secrets committed (`FACEBOOK_*` only in `.env.example` placeholders).

### Optional staging enablement (NOT required for PASS)

Only if Meta test app credentials exist:

```bash
# dex/.env: FACEBOOK_CLIENT_ID=... FACEBOOK_CLIENT_SECRET=...
cd /opt/opencloud/dex && docker compose up -d
docker exec opencloud-dex grep -A5 'id: facebook' /etc/dex/config.yaml
curl -sI "https://cloud.km0digital.com/dex/auth?client_id=opencloud-web&redirect_uri=https%3A%2F%2Fcloud.km0digital.com%2Foidc-callback.html&response_type=code&scope=openid+profile+email&connector_id=facebook&state=test&code_challenge=x&code_challenge_method=S256" | grep -i '^location:'
# expect: redirect toward facebook.com (Meta app + test user required for full E2E)
```

### Regression

- Google connector redirect unchanged (see automated curl above).
- Dex logs after restart: `docker logs opencloud-dex 2>&1 | tail -10` — no fatal errors.

### Operator (deferred)

- Facebook E2E login to `/files` after UI + CSP + Meta Live mode — separate future task.

---

## Test report

**Date/time (UTC):** 2026-06-03T11:23:07Z – 2026-06-03T11:23:17Z  
**Log window:** Dex and OpenCloud logs from 2026-06-03T11:22:24Z onward (container timestamps).

### Environment

| Item | Value |
|------|-------|
| Branch | `main` (synced via `./scripts/git-sync-main.sh`) |
| Compose | `opencloud-compose/` — opencloud, collabora, collaboration Up 4 days |
| Dex | `opencloud-dex` container (separate `dex/` stack) |
| URLs | `https://cloud.km0digital.com/` |

**Stack readiness:** Verified immediately via `docker compose ps` (all services Up/healthy) and live HTTP responses (302/200) without fixed sleeps.

### What was tested

1. Automated server checks (Facebook connector absent, login.html, OIDC issuer, Google redirect).
2. Dex regression logs (no fatal errors).
3. Documentation review (`docs/facebook-login-dex-investigation.md`, `dex/README.md`, secrets scan).
4. Optional Facebook enablement — **skipped** (no Meta test credentials; not required for PASS).

### Results

| Criterion | Result | Evidence |
|-----------|--------|----------|
| No `facebook` connector without env | **PASS** | `docker exec opencloud-dex grep -c 'id: facebook' /etc/dex/config.yaml` → `0` |
| `login.html` returns 200 | **PASS** | `curl -sI …/login.html` → `HTTP/2 200` |
| Dex OIDC issuer correct | **PASS** | `curl …/.well-known/openid-configuration \| jq -r .issuer` → `https://cloud.km0digital.com/dex` |
| Google connector redirect unchanged | **PASS** | `location: /dex/auth/google?client_id=opencloud-web&…` |
| OpenCloud root reachable | **PASS** | `curl -w '%{http_code}' https://cloud.km0digital.com/` → `302` |
| Dex logs — no fatal errors | **PASS** | Last 10 lines: `config connector ldap`, `config connector google`, `listening on …:5556`; no ERROR/FATAL |
| Investigation doc covers #5 acceptance criteria | **PASS** | Dex sole issuer (§1), oauth path (§2), email requirement + mitigation (§3–4), Meta checklist (§6), config mapping (§7) |
| `dex/README.md` Facebook section aligned | **PASS** | Matches investigation: `type: oauth`, env-gated enablement, email claim requirement, CSP/UI deferred |
| No secrets committed | **PASS** | `FACEBOOK_*` only in `dex/.env.example` (empty), `docker-compose.yml` env refs, example placeholders |

**Overall: PASS**

### URLs tested

- https://cloud.km0digital.com/ (302)
- https://cloud.km0digital.com/login.html (200)
- https://cloud.km0digital.com/dex/.well-known/openid-configuration (200)
- https://cloud.km0digital.com/dex/auth?…&connector_id=google (302 → `/dex/auth/google`)

### Relevant log excerpts

```
opencloud-dex:
{"time":"2026-06-03T11:22:27.885840496Z","level":"INFO","msg":"config connector","connector_id":"ldap"}
{"time":"2026-06-03T11:22:27.885860986Z","level":"INFO","msg":"config connector","connector_id":"google"}
{"time":"2026-06-03T11:22:27.958091866Z","level":"INFO","msg":"listening on","server":"http","address":"0.0.0.0:5556"}
```

**GitHub labels:** `agent:testing` added at test start; removed on pass.
