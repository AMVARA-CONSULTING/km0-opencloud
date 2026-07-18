---
## Closing summary (TOP)

- **What happened:** Ideas-form smoke test (#18) verified that submissions with product scope `cloud` route into km0-opencloud; no feature or bug was requested.
- **What was done:** Confirmed intake routing and stack health; no product-code changes (by design).
- **What was tested:** Issue body/scope/routing, no product-file diff, Docker up, login.html 302 — Overall PASS.
- **Why closed:** Intake test verified; nothing to implement.
- **Closed at (UTC):** 2026-07-18 06:58
---

# [ideas/en] Scope test for cloud product

## GitHub Issue
- **Issue:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/18
- **Number:** #18
- **Labels:** waiting for human validation, agent:wip
- **Created:** 2026-07-12T15:39:59Z

## Problem / goal
The submitter sent a short test message through the public ideas form to verify that submissions with the **cloud** product scope are routed correctly. There is no feature request or bug report beyond confirming intake for cloud.km0digital.

## High-level instructions for coder
- Read the full issue at https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/18
- Identify affected paths under overrides/, dex/, nginx/, host-www/, scripts/, docs/
- Implement minimal, on-scope changes for km0-opencloud
- Add **Testing instructions** before renaming to UNTESTED-

## References
- Repo: https://github.com/AMVARA-CONSULTING/km0-opencloud
- Runbook: docs/runbook.md

## Implementation notes (2026-07-18)

**Outcome: no product code change.**

| Check | Result |
|-------|--------|
| Issue body | Intake smoke test only (`Scope test cloud`); triage says close without action if intentional |
| Product scope | `cloud` — issue landed in **km0-opencloud** (correct routing) |
| Paths reviewed | `overrides/`, `dex/`, `nginx/`, `host-www/`, `scripts/`, `docs/` — nothing to change for an intake test |
| Docker | `opencloud-opencloud-1`, `collabora`, `collaboration` Up |
| HTTP | `curl -sI https://cloud.km0digital.com/login.html` → HTTP/2 302 → `auth.km0digital.com/login?service=cloud` |

No edits under product paths. Cloud-scope ideas intake already succeeded by creating this issue.

## Testing instructions

1. Confirm issue #18 body is only an ideas-form scope smoke test (no concrete feature/bug).
2. Confirm product scope `cloud` and that the issue lives in `AMVARA-CONSULTING/km0-opencloud` (routing OK).
3. Confirm git diff for this task has **no** product-file changes (task file / labels only).
4. Smoke: `cd opencloud-compose && docker compose ps` — opencloud healthy/up.
5. Smoke: `curl -sI https://cloud.km0digital.com/login.html` — expect 2xx/3xx (not 5xx).
6. On pass: mark **CLOSED**, comment that intake test is verified with no code action, remove `waiting for human validation` if still present, close GitHub issue #18.

## Test report

1. **Date/time (UTC):** 2026-07-18T06:58:08Z → 2026-07-18T06:58:24Z.
2. **Environment:** branch `main`; compose `opencloud-compose` — `opencloud-opencloud-1` Up 4 weeks; collabora healthy. Ready via compose `ps` + `curl -sSI https://cloud.km0digital.com/login.html` (no fixed sleep).
3. **What was tested:** Issue #18 intake smoke (body/scope/routing), no product-code claim for this task, Docker + HTTP smoke.
4. **Results:**
   - Issue body is ideas-form scope smoke only (`Scope test cloud`); no concrete feature/bug: **PASS** (`gh issue view 18`).
   - Product scope `cloud` in repo `AMVARA-CONSULTING/km0-opencloud`: **PASS**.
   - No product-file changes for this task (coder outcome: no edits under overrides/dex/nginx/host-www/scripts/docs for intake): **PASS**.
   - Docker opencloud up: **PASS**.
   - `https://cloud.km0digital.com/login.html` → HTTP/2 302 (not 5xx): **PASS**.
5. **Overall: PASS**
6. **URLs:** https://cloud.km0digital.com/login.html (302 → auth.km0digital.com); https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/18
7. **Log excerpts:** N/A (no deploy). Compose: opencloud Up 4 weeks.
