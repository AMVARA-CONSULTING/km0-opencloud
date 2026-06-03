h1. KM0 OpenCloud — deployment repository (Redmine)

h2. Purpose

Version-controlled *operations* configuration for *OpenCloud* at @cloud.km0digital.com@ on Debian 13: external Nginx TLS, Dex OIDC (Google/Apple), hybrid local login, backup scripts, and minimal patches to upstream @opencloud-compose@ — *not* a fork of OpenCloud EU.

Marketing site @km0.amvara.de@ lives in a separate repo (@km0-web@).

---

h2. URLs

|_.Service|_.URL|_.Repo|
| OpenCloud | "https://cloud.km0digital.com":https://cloud.km0digital.com | @km0-opencloud@ (this) |
| Corporate web | "https://km0.amvara.de":https://km0.amvara.de | @km0-web@ |
| Dex OIDC | @https://cloud.km0digital.com/dex@ | @dex/@ in this repo |
| Upstream compose | "opencloud-eu/opencloud-compose":https://github.com/opencloud-eu/opencloud-compose | Cloned on server as @opencloud-compose/@ (gitignored) |

---

h2. Traffic flow

<pre><code>
Browser --443--> Host nginx (TLS)
                    |-- /dex/*     --> 127.0.0.1:5556 (Dex)
                    |-- /login.html, config-*.json --> /var/www/opencloud-auth/
                    +-- /*         --> 127.0.0.1:9200 (OpenCloud container)
</code></pre>

* OpenCloud publishes @127.0.0.1:9200@ only (external-proxy overlay).
* UFW: @22@, @80@, @443@; Fail2ban on SSH.

---

h2. Git

|_.Field|_.Value|
| Remote | git@github.com:AMVARA-CONSULTING/km0-opencloud.git |
| Branch | @main@ |
| Clone | @git clone git@github.com:AMVARA-CONSULTING/km0-opencloud.git /opt/opencloud@ |

"GitHub (browser)":"https://github.com/AMVARA-CONSULTING/km0-opencloud"

---

h2. What is tracked vs not

*h3. In Git*

* @overrides/opencloud-compose/@ — CSP, external-proxy, OIDC patch, @.env.debian-core-external-proxy.example@
* @dex/@ — Dex compose, KM0 theme (@web/themes/km0/@), templates (no @.env@)
* @nginx/@, @host-www/opencloud-auth/@, @scripts/@, @docs/@

*h3. On server only (never commit)*

* @opencloud-compose/@ full upstream clone
* @opencloud-compose/.env@, @dex/.env@ (@chmod 600@)
* @/opt/google-client-secret.json@, Apple @AuthKey_*.p8@
* Docker volumes @opencloud_opencloud-*@, @dex_dex-data@
* @/etc/letsencrypt/@, live TLS keys

Secrets and operational notes (VPS IP, ACME email, initial admin password) are kept in @.env@ file *comments* on the server.

---

h2. Delivery summary (2026-05-26)

* Debian 13 core stack: OpenCloud @7.0.0@ rolling image, Nginx reverse proxy, Let's Encrypt.
* Dex @v2.42.0@ as OIDC broker; Google connector live; Apple Sign In documented (@setup-apple.sh@).
* Hybrid login: Google/Apple via Dex + local username/password (@idp@ kept; nginx routes @config-local.json@ vs @config-dex.json@).
* KM0-branded Dex login UI (CA | ES | EN | DE) aligned with @km0-web@.
* Minimal upstream footprint: @scripts/apply-opencloud-compose-overrides.sh@ after @git pull@ in @opencloud-compose/@.
* Backups: volume tarball script + full installation backup (nginx, www, certs, volumes).

---

h2. Common commands

<pre><code class="shell">
cd /opt/opencloud
git pull
./scripts/apply-opencloud-compose-overrides.sh
cd opencloud-compose && docker compose ps && docker compose pull && docker compose up -d
cd /opt/opencloud/dex && docker compose ps
</code></pre>

---

h2. Related documents

* "Repository guide":"docs/REPOSITORY.md"
* "Operations runbook":"docs/runbook.md"
* "Architecture README":"README.md"
* "Dex setup":"dex/README.md"

---

This file — @docs/km0-opencloud-resumen.red@ — uses *Textile* for Redmine wikis. Copy into OPS wiki or blog source. Do not paste live passwords.
