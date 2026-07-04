h1. Register API Graph token rotation — KM0 OpenCloud

h2. Why

Email/password self-registration at @https://cloud.km0digital.com/register.html@ depends on *register-api*, a small sidecar that creates users via OpenCloud Graph (@POST /graph/v1.0/users@). Graph rejects password Basic auth in production (@PROXY_ENABLE_BASIC_AUTH=false@), so register-api must authenticate with a dedicated *Graph App Token* (@GRAPH_SERVICE_APP_TOKEN@).

App tokens expire. When the token expired on 2026-07-04, register-api returned HTTP 503 (@graph_auth_ok: false@) and users saw a generic registration error — while Google OAuth (Dex) continued to work because it does not use register-api.

*Goal:* treat the register-api token as an operational secret with a *3-month lifetime*, manual rotation, and safe automatic renewal before expiry — without touching users, storage, volumes, Dex/OIDC, or global OpenCloud configuration.

---

h2. What we implemented

|_.Item|_.Purpose|
| @scripts/setup-register-api-graph-token.sh@ | Creates token via @opencloud auth-app create@; default @--expires-in 90d@; writes @GRAPH_SERVICE_APP_TOKEN@ and @GRAPH_SERVICE_APP_TOKEN_EXPIRES_AT@ to @register-api/.env@ |
| @scripts/renew-register-api-graph-token.sh@ | Weekly check: renew when @graph_auth_ok@ is false or fewer than 14 days remain; restarts *register-api only*; verifies @/health@ |
| @scripts/register-api-token-renewal.cron@ | Cron template — Mondays 03:00 UTC, flock lock, log @/var/log/register-api-token-renewal.log@ |
| @scripts/verify-register-api.sh@ | Smoke test — requires @graph_auth_ok: true@ |
| @docs/runbook.md@ | Operator procedures and explicit safety constraints |

---

h2. Safety boundaries

Renewal is limited to:

* Creating a new Graph App Token for register-api
* Updating @GRAPH_SERVICE_APP_TOKEN@ (and expiry metadata) in @register-api/.env@
* Restarting the @register-api@ container
* Running @/health@ verification

It must *never* delete or modify existing users, groups, storage, databases, Docker volumes, Dex/OIDC settings, or unrelated @.env@ values. It must not run @docker compose down -v@, @docker volume rm@, or OpenCloud user/config reset commands.

A failed renewal leaves Google OAuth and existing user data unchanged.

---

h2. Operator commands

Manual rotation:

<pre><code class="shell">
./scripts/setup-register-api-graph-token.sh --expires-in 90d
cd /opt/opencloud/register-api && docker compose up -d --build register-api
./scripts/verify-register-api.sh
</code></pre>

Install auto-renewal:

<pre><code class="shell">
sudo cp /opt/opencloud/scripts/register-api-token-renewal.cron /etc/cron.d/register-api-token-renewal
sudo chmod 644 /etc/cron.d/register-api-token-renewal
</code></pre>

Dry-run renewal check:

<pre><code class="shell">
./scripts/renew-register-api-graph-token.sh
</code></pre>

---

h2. References

* GitHub issue #17 — "Register API Graph token rotation and auto-renewal"
* Incident: @docs/register-incident-20260704-fundaalicates-yahoo.md@
* OpenCloud auth-app: "https://docs.opencloud.eu/docs/dev/server/services/auth-app/information":https://docs.opencloud.eu/docs/dev/server/services/auth-app/information

---

*2026-07-15 — km0-opencloud*
