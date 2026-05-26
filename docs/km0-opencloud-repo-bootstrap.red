h1. KM0 OpenCloud — Git repository bootstrap (Redmine)

h2. Context

The @/opt/opencloud/@ directory held the operational OpenCloud installation (Dex, Nginx, web templates, backup scripts) plus a local clone of @opencloud-eu/opencloud-compose@ with KM0 patches. Goal: publish on GitHub *only KM0-owned assets*, without forking upstream, and keep secrets out of Git history.

Work date: *26 May 2026*.

---

h2. Design decisions

* *No fork* of OpenCloud Compose: the upstream clone (@opencloud-compose/@) stays on the server but is *gitignored*.
* Minimal patches versioned under @overrides/opencloud-compose/@ (CSP, external-proxy, OIDC patch, @.env@ template).
* @scripts/apply-opencloud-compose-overrides.sh@ reapplies patches after @git pull@ in upstream.
* *Nothing deleted* from disk (no @rm@): @README.red@, upstream clone, and local @.env@ files remain on the server, excluded from Git.
* @/opt/containerd/@ and @/opt/km0-web/@ stay *outside* this repo (host runtime and corporate web, respectively).

---

h2. Step 0 — Secrets removed from documentation

Before the first commit, passwords, operational IPs, and ACME contact emails were removed from @README.md@ and @docs/runbook.md@.

|_.Previously in docs|_.Now on server|
| @INITIAL_ADMIN_PASSWORD@, admin notes | Comments in @opencloud-compose/.env@ |
| VPS IP, Certbot contact | Comments in @opencloud-compose/.env@ |
| Google/Apple OAuth paths | Comments in @dex/.env@ (real values only there) |

New template files:

* @dex/.env.example@ — Dex without secrets
* @overrides/opencloud-compose/.env.debian-core-external-proxy.example@ — OpenCloud + Dex OIDC

@README.red@ (draft with historical secrets) → @.gitignore@, not pushed.

---

h2. Steps 1–2 — Versioned layout

*h3. In Git (63 files, initial commit)*

|_.Path|_.Content|
| @overrides/opencloud-compose/@ | @csp.yaml@, @external-proxy/opencloud.yml@, @patches/docker-compose.oidc-env.patch@, @.env@ template |
| @dex/@ | Compose stack, KM0 theme (@web/themes/km0/@), HTML templates, @setup-apple.sh@ |
| @nginx/@ | Vhost @cloud.km0digital.com@, @opencloud-map.conf@, Certbot example |
| @host-www/opencloud-auth/@ | @login.html@, @config-dex.json@, @config-local.json@, @local-metadata.json@ |
| @scripts/@ | Backups + @apply-opencloud-compose-overrides.sh@ |
| @docs/@ | Runbook, @REPOSITORY.md@, @.red@ exports |

*h3. Outside Git (still on disk under @/opt/opencloud/@)*

* @opencloud-compose/@ — full upstream clone (with its own @.git@)
* @opencloud-compose/.env@, @dex/.env@ (@chmod 600@)
* @/opt/google-client-secret.json@, @AuthKey_*.p8@, Docker volumes, @/etc/letsencrypt/@

---

h2. Steps 3–4 — GitHub and push

|_.Field|_.Value|
| Organisation | AMVARA-CONSULTING |
| Repository | @km0-opencloud@ |
| SSH remote | git@github.com:AMVARA-CONSULTING/km0-opencloud.git |
| Branch | @main@ |
| Initial commit message | @Initial KM0 OpenCloud deployment repository.@ |

First push completed after registering the server SSH key on GitHub.

---

h2. Commit author

The commit was initially created as @root@ (VPS hostname). Corrected with @git commit --amend@:

|_.Field|_.Value|
| Author / committer | Luipy56 @yoelberjaga@gmail.com@ |
| Push | @git push --force-with-lease origin main@ |

*Local* repo identity (@/opt/opencloud/.git/config@):

<pre><code class="shell">
user.name=Luipy56
user.email=yoelberjaga@gmail.com
</code></pre>

(Repo-local only; @git config --global@ was not changed.)

---

h2. Upstream patches (detail)

After cloning @opencloud-compose@, @apply-opencloud-compose-overrides.sh@:

# Copies @overrides/.../config/opencloud/csp.yaml@ — CSP for Google, Dex, and Apple.
# Copies @overrides/.../external-proxy/opencloud.yml@ — hybrid login, @extra_hosts@, port @127.0.0.1:9200@.
# Applies @patches/docker-compose.oidc-env.patch@ — OIDC/autoprovision env vars in @docker-compose.yml@.

Upstream reference: "opencloud-eu/opencloud-compose":https://github.com/opencloud-eu/opencloud-compose

---

h2. Secret verification

Before push, the committed tree was checked and must *not* contain:

* Documented admin password placeholders (e.g. @OC-Temp-*@)
* @GOCSPX-*@ (Google client secret)
* VPS IP @116.202.10.106@ in tracked files

Real values remain only in gitignored local @.env@ files.

---

h2. Documentation produced

|_.File|_.Purpose|
| @docs/REPOSITORY.md@ | Markdown guide: what to version, deploy, update upstream |
| @docs/km0-opencloud-resumen.red@ | Operational stack summary (Redmine / blog) |
| @docs/km0-opencloud-repo-bootstrap.red@ | *This file* — Git bootstrap summary |

@README.md@ and @docs/runbook.md@ updated to point at @.env@ templates and the overrides script.

---

h2. Post-bootstrap commands

<pre><code class="shell">
cd /opt/opencloud
git pull
./scripts/apply-opencloud-compose-overrides.sh
git -C opencloud-compose pull
cd opencloud-compose && docker compose pull && docker compose up -d
</code></pre>

Fresh server clone:

<pre><code class="shell">
git clone git@github.com:AMVARA-CONSULTING/km0-opencloud.git /opt/opencloud
</code></pre>

---

h2. Related

* "GitHub repository":"https://github.com/AMVARA-CONSULTING/km0-opencloud"
* "Repository guide":"docs/REPOSITORY.md"
* "Operations runbook":"docs/runbook.md"
* "Stack summary":"docs/km0-opencloud-resumen.red"

---

This file — @docs/km0-opencloud-repo-bootstrap.red@ — uses *Textile* (Redmine syntax). Copy into the OPS wiki or blog source. *English prose only.* Do not paste live passwords or OAuth keys.
