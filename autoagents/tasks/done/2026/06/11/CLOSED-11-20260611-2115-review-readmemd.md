---
## Closing summary (TOP)

- **What happened:** GitHub issue #11 requested a README.md review to translate Spanish text, remove em dashes, and verify deployment notes were current.
- **What was done:** `README.md` was updated: remaining Spanish comments and notes translated to English, all em dashes replaced with standard punctuation, and deployment notes aligned with the runbook (Dex OIDC at `/dex/`, hybrid login URL, both `.env` templates, full TLS hostname coverage).
- **What was tested:** All five criteria passed — no em dashes, English-only content, runbook cross-check (ports, image tag, Dex/login), Docker sanity (opencloud/collabora/collaboration Up), and linked docs present.
- **Why closed:** All test criteria passed; documentation review complete.
- **Closed at (UTC):** 2026-06-11 21:17
---

# Review README.md

## GitHub Issue
- **Issue:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/11
- **Number:** #11
- **Labels:** none
- **Created:** 2026-06-11T18:22:56Z

## Problem / goal
Revisar README.md  Hay texto en castellano que hay que traducir al español  Hay carácteres em dash que hay que eliminar.  Hay que revisar si está al día.

## High-level instructions for coder
- Read the full issue at https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/11
- Identify affected paths under overrides/, dex/, nginx/, host-www/, scripts/, docs/
- Implement minimal, on-scope changes for km0-opencloud
- Add **Testing instructions** before renaming to UNTESTED-

## References
- Repo: https://github.com/AMVARA-CONSULTING/km0-opencloud
- Runbook: docs/runbook.md

## Implementation summary

Updated `README.md`:

- Translated remaining Spanish comments and deployment notes to English (repo convention; runbook is English).
- Removed all em dash (`—`) characters; replaced with colons, semicolons, or commas as appropriate.
- Brought deployment notes up to date: Dex OIDC at `/dex/`, hybrid login landing URL, both `.env` templates listed, `dex/.env` in key config table, TLS covers all public hostnames (not just two).

## Testing instructions

1. **No em dashes:** `grep -n '—' README.md` should return no matches.
2. **English only:** skim `README.md` for Spanish fragments (repository layout comments, `.env` section, deployment notes).
3. **Cross-check runbook:** compare URLs, ports (9180/9200/9980/9300), image tag `7.0.0`, and Dex/login references with `docs/runbook.md`.
4. **Docker (sanity):** `cd opencloud-compose && docker compose ps` — opencloud, collabora, collaboration running.
5. **Links:** open `docs/REPOSITORY.md` and `docs/runbook.md` links from README in GitHub preview or local viewer.

---

## Test report

**Date/time (UTC):** 2026-06-11 21:16:59 – 21:17:07 UTC  
**Log window:** OpenCloud proxy access logs 2026-06-11T21:16:35Z – 21:17:05Z

**Environment:**
- Branch: `main` @ `79c75da`
- Compose project: `opencloud` (`/opt/opencloud/opencloud-compose`)
- URLs: https://cloud.km0digital.com/, http://127.0.0.1:9200/

**What was tested:** README.md documentation review (em dashes, English-only, runbook cross-check, Docker sanity, linked docs).

### Results

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | No em dashes in README | **PASS** | `grep -n '—' README.md` → 0 matches |
| 2 | English only (no Spanish fragments) | **PASS** | Full skim of README; grep for common Spanish tokens → 0 matches |
| 3 | Cross-check runbook (URLs, ports, image tag, Dex/login) | **PASS** | README ports 9180/9200/9980/9300, image `7.0.0`, Dex at `/dex/`, login at `login.html` match `docs/runbook.md` |
| 4 | Docker sanity (opencloud, collabora, collaboration running) | **PASS** | `docker compose ps`: all three Up 13 days; opencloud/collaboration on `7.0.0`, collabora healthy |
| 5 | Linked docs exist | **PASS** | `docs/REPOSITORY.md` and `docs/runbook.md` present on disk |

**Overall: PASS**

**URLs tested:**
- https://cloud.km0digital.com/ → HTTP 302 (redirect; stack reachable)
- http://127.0.0.1:9200/ → HTTP 200

**Stack readiness:** Services were already running (`Up 13 days`); no deploy wait needed. Confirmed via `docker compose ps` and immediate HTTP responses.

### Log excerpts

```
opencloud-opencloud-1   opencloudeu/opencloud-rolling:7.0.0   Up 13 days   127.0.0.1:9200->9200/tcp
opencloud-collabora-1   collabora/code:25.04.9.4.1            Up 13 days (healthy)   127.0.0.1:9980->9980/tcp
opencloud-collaboration-1 opencloudeu/opencloud-rolling:7.0.0 Up 13 days   127.0.0.1:9300->9300/tcp
```

```
opencloud-1 | {"level":"info","service":"proxy","method":"GET","status":200,"path":"/","duration":2.757041,"time":"2026-06-11T21:17:05Z","message":"access-log"}
```

**GitHub labels:** `agent:testing` added at test start; removed on pass.
