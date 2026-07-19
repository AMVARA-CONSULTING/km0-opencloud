---
## Closing summary (TOP)

- **What happened:** Documented OpenCloud public-link subfolder ZIP/`download.zip` failure as a vendor archiver bug with an operator workaround (docs-only).
- **What was done:** Added runbook troubleshooting section, CHANGELOG Unreleased note, and upstream draft `docs/issue-public-share-folder-zip-archiver.md` (placeholders only; no OpenCloud/nginx patches).
- **What was tested:** Live WebDAV single-file GET 200 and `/archiver` subfolder 404 match runbook; site/Dex healthy; no live tokens in docs; no compose/nginx diffs — overall PASS.
- **Why closed:** All acceptance criteria and tester checks passed.
- **Closed at (UTC):** 2026-07-19 19:27
---

# Document public-link subfolder ZIP workaround (OpenCloud archiver)

## Context
- **Source:** Operator report + parked evidence under `autoagents/tasks/triage/TRIAGE-20260719-1854-public-share-folder-zip-*.md`.
- **Public link (repro):** operator-held share on `cloud.km0digital.com` (token not stored in this task).
- **Stack:** OpenCloud **7.3.0** (`opencloudeu/opencloud-rolling:7.3.0`, reva `v2.47.0`).
- **Verdict:** Product bug in OpenCloud `/archiver` + public-share scope — **not** KM0 nginx. Do **not** patch OpenCloud / reva / upstream compose sources.

## Problem / goal
Document the known limitation and operator/user **workaround** so staff know why `download.zip` fails on public subfolder downloads and what to tell users until OpenCloud fixes it.

## High-level instructions for coder
- Sync: `./scripts/git-sync-main.sh` on `main`.
- **Docs / ops only** — no OpenCloud code changes, no nginx “fix” for `/archiver`.
- Add a short English subsection to `docs/runbook.md` (and `docs/CHANGELOG.md` one-liner if that matches repo habit):
  - Symptom: passwordless public folder link — files OK; subfolder ZIP → browser “`download.zip` wasn’t available on site”; no console error.
  - Cause (high level): `GET /archiver?id=…&public-token=…` returns **404** with `Content-Disposition: download.zip`; gateway logs `request is not for a nested resource` / `could not find space`. Related: opencloud-eu/opencloud#2401, #1712.
  - Workaround: download files one-by-one, or use WebDAV/sync while logged in.
  - Optional curl check (redact tokens in docs examples).
- Optionally leave a short English draft upstream issue body under `docs/` (e.g. `docs/issue-public-share-folder-zip-archiver.md`) for humans to file on `opencloud-eu/opencloud` — **no live share tokens**.
- Do not open GitHub issues unless the operator asks in a later step.
- Never commit `.env`, tokens, or passwords.

## Acceptance criteria
- [x] Runbook documents symptom, vendor ownership, and workaround
- [x] No OpenCloud / reva / compose upstream source patches
- [x] No secrets or live public-share tokens in git
- [x] CHANGELOG note if other ops notes usually get one

## Implementation notes (coder)
- Added `docs/runbook.md` § Troubleshooting → **Public link: subfolder ZIP download fails (`download.zip`)**.
- Added `docs/CHANGELOG.md` Unreleased note.
- Added upstream draft `docs/issue-public-share-folder-zip-archiver.md` (placeholders only).

## Testing instructions
- [x] Confirm runbook section is accurate against a live `curl` of `/archiver` on a public subfolder (expect 404 + disposition) and a single-file WebDAV GET (expect 200).
- [x] Confirm `https://cloud.km0digital.com/` / Dex login still OK (docs-only change should not affect runtime).
- [x] Confirm committed docs use `<PUBLIC_TOKEN>` / `<FILE_ID>` placeholders only (no live share token).
- [x] Confirm no changes under `opencloud-compose/` upstream sources or nginx `/archiver` locations.

### Coder pre-check evidence (2026-07-19)
- `GET …/remote.php/dav/public-files/<token>/LICENSE` → **200** `application/octet-stream`.
- `GET /archiver?id=<assets-fileid>&public-token=<token>` → **404** with `Content-Disposition: attachment; filename*=UTF-8''download.zip` and body `error: not found: gateway could not find space for ref=…`.
- Same 404 for subfolder `de/`.
- `https://cloud.km0digital.com/` → **200**; Dex `/dex/auth` → **302**.
- `docker compose ps`: opencloud / collaboration / collabora Up (docs-only; no recreate).

## Test report

1. **Date/time (UTC) / log window:** 2026-07-19 19:26:19Z start (UNTESTED→TESTING); live checks 19:26:39Z–19:26:55Z; report close ~19:27:30Z. Log window: opencloud compose logs `--since 5m` covering archiver calls at 19:26:54Z–19:26:55Z.
2. **Environment:** branch `main` (synced, up to date with `origin/main`). Compose: `opencloudeu/opencloud-rolling:7.3.0` — opencloud / collaboration / collabora **Up** (no recreate; stack readiness = `docker compose ps` Up + HTTP responses). URLs: `https://cloud.km0digital.com/`, Dex `/dex/auth`, public WebDAV + `/archiver` (operator share; token not recorded here).
3. **What was tested:** Runbook accuracy vs live single-file GET and subfolder `/archiver`; site/Dex health; placeholder-only docs; no compose/nginx product diffs for this change.
4. **Results:**
   - Runbook vs live archiver/WebDAV — **PASS.** `GET …/public-files/<PUBLIC_TOKEN>/LICENSE` → **200** `application/octet-stream`. `GET/HEAD /archiver?id=<assets-fileid>&public-token=<PUBLIC_TOKEN>` → **404** with `Content-Disposition: attachment; filename*=UTF-8''download.zip` and body `error: not found: gateway could not find space for ref=…`. Same **404** + disposition for `de/`. Matches runbook § Troubleshooting.
   - Cloud / Dex still OK — **PASS.** `https://cloud.km0digital.com/` → **302** → `/km0-session-gate.html`; follow redirects → **200**. Dex `/dex/auth` → **200**. Docs-only; no stack recreate.
   - Docs placeholders / no live tokens — **PASS.** `docs/runbook.md`, `docs/CHANGELOG.md`, `docs/issue-public-share-folder-zip-archiver.md` use `<PUBLIC_TOKEN>` / `<FILE_ID>` / redaction notes only; grep found no live public-share token in those files.
   - No compose/nginx `/archiver` patches — **PASS.** `git status` clean for `opencloud-compose/`, `nginx/`, `overrides/`, `dex/`. Diff limited to docs (+ task/triage untracked).
5. **Overall:** **PASS**
6. **URLs tested:** `https://cloud.km0digital.com/` (302→gate→200); Dex `/dex/auth` (200); `…/remote.php/dav/public-files/<PUBLIC_TOKEN>/LICENSE` (200); `/archiver?id=<FILE_ID>&public-token=<PUBLIC_TOKEN>` for `assets/` and `de/` (404).
7. **Log excerpts** (public-token redacted):
   - gateway: `permission denied: request is not for a nested resource` (`scope.go`, reva `v2.47.0`) at `2026-07-19T19:26:54Z` / `19:26:55Z`.
   - frontend archiver: `gateway could not find space for ref=… path:"."` (`archiver/handler.go:257`).
   - proxy access-log: `method=HEAD|GET path=/archiver status=404` request-ids `…-015594` / `…-015598`.

**GitHub labels:** N/A (task issue `0`; no GH issue to label).

**Stack ready how:** `docker compose ps` showed services Up; HTTP probes returned expected codes before and after archiver repro (no sleep-based wait).
