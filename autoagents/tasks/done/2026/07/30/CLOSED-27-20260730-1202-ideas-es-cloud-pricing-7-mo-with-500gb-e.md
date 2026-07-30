---
## Closing summary (TOP)

- **What happened:** Pricing idea #27 (7€/mo + 500GB; extra packs at 1.99€) assessed; no product change while `waiting for human validation` remains.
- **What was done:** Confirmed live marketing and Dex auth notice still show €1.99/500GB; documented that adoption needs a human pricing decision first in km0-web, then sync of `registerPricingNotice` here. No edits under overrides/, dex/, nginx/, host-www/, scripts/, or docs/.
- **What was tested:** Tester overall PASS — human-validation gate present, no product-file diff, public pricing and Dex notice still €1.99, OpenCloud stack smoke OK.
- **Why closed:** Agent criteria passed; GitHub issue intentionally left open for human pricing validation (not a full product delivery).
- **Closed at (UTC):** 2026-07-30 12:04
---

# [ideas/es] Cloud pricing: 7€/mo with 500GB, extra packs at 1.99€

## GitHub Issue
- **Issue:** https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/27
- **Number:** #27
- **Labels:** waiting for human validation, agent:wip
- **Created:** 2026-07-30T11:58:46Z

## Problem / goal
Submitter proposes a per-account price for cloud.km0digital: **7€/month including 500GB**, with each additional **500GB at 1.99€/month**. Product packaging idea (not a bug).

## High-level instructions for coder
- Read the full issue at https://github.com/AMVARA-CONSULTING/km0-opencloud/issues/27
- Identify affected paths under overrides/, dex/, nginx/, host-www/, scripts/, docs/
- Implement minimal, on-scope changes for km0-opencloud
- Add **Testing instructions** before renaming to UNTESTED-

## References
- Repo: https://github.com/AMVARA-CONSULTING/km0-opencloud
- Runbook: docs/runbook.md
- Public pricing: https://km0digital.com/en/pricing/ (and locale variants)

## Implementation notes (2026-07-30)

**Outcome: no product code change in km0-opencloud.**

### Current published pricing (verified live)

| Surface | Price | Storage |
|---------|-------|---------|
| https://km0digital.com/en/pricing/ | **€1.99/month** | 500 GB |
| Login/register notice (`registerPricingNotice` in `dex/web/themes/km0/i18n.js`) | **€1.99/month** after testing phase | (aligned with marketing) |

### Proposed tiers (issue #27)

| Tier | Price | Storage |
|------|-------|---------|
| Base account | **7€/month** | 500 GB included |
| Extra pack | **1.99€/month** each | +500 GB |

### Why no code change

1. **Human gate still open:** Issue retains label `waiting for human validation`. Issue body states a human must remove that label before agents implement. Adopting a ~3.5× base-price change is a business decision, not an engineering default.
2. **Canonical price page is outside this repo:** Marketing copy lives in **km0-web** (`src/i18n/*.json` pricing keys, pricing page). km0-opencloud only mirrors a short disclaimer on auth pages.
3. **Consistency:** Updating only `registerPricingNotice` to 7€ while km0digital.com still shows €1.99 would mislead users on login/register.
4. **Tests assume €1.99:** `tests/auth/auth-pages.spec.ts` markers are `1,99` / `1.99` / `€1.99`.

### If a human approves the new tiers later

1. Update **km0-web** pricing page + i18n (all locales) to 7€/500GB + 1.99€ extra packs.
2. Then update **km0-opencloud** `dex/web/themes/km0/i18n.js` `registerPricingNotice` (es/ca/en/de), `docs/github-issue-self-registration.md`, and Playwright `PRICING_MARKERS`.
3. Redeploy Dex theme / host-www auth pages; keep notice and marketing site in lockstep.

### Paths reviewed (no edits)

`overrides/`, `dex/`, `nginx/`, `host-www/`, `scripts/`, `docs/` — no files changed for this task.

### Stack smoke (this host)

- `opencloud-opencloud-1` Up
- `https://cloud.km0digital.com/login.html` → HTTP 200
- Public pricing page still shows €1.99 / 500 GB

## Testing instructions

1. Confirm issue #27 is a pricing/product idea (7€/mo + 500GB; extra 500GB @ 1.99€), not a bug.
2. Confirm label **`waiting for human validation`** is still present (or was present at coding time) — no unilateral price change.
3. Confirm **no product-file diff** for this task under `overrides/`, `dex/`, `nginx/`, `host-www/`, `scripts/`, `docs/`.
4. Live check: `curl -s https://km0digital.com/en/pricing/` contains **€1.99** and **500 GB** (current public plan).
5. Live check: login notice still references **1,99 / 1.99** —  
   `curl -s https://cloud.km0digital.com/dex/theme/i18n.js | grep -A1 registerPricingNotice` (or open `/login.html` and inspect `.pricing-notice` after i18n apply).
6. Smoke: `cd opencloud-compose && docker compose ps` — opencloud up.
7. On pass: mark **CLOSED**; leave a GitHub comment that the idea is assessed and **blocked on human pricing decision**; keep or restore **`waiting for human validation`**; do **not** close the GitHub issue unless a human explicitly rejects the proposal. Note follow-up belongs first in **km0-web**, then sync auth notice here.

## Test report

1. **Date/time (UTC) and log window:** 2026-07-30T12:03:09Z – 2026-07-30T12:03:10Z (tester start ~12:02:58Z; opencloud logs sampled ~12:02:13Z–12:03:03Z).
2. **Environment:** branch `main` @ `ae4d973`; compose project `opencloud-compose` (`opencloud-opencloud-1` Up 11 days); URLs `https://km0digital.com/en/pricing/`, `https://cloud.km0digital.com/`, `/login.html`, `/dex/theme/i18n.js`.
3. **What was tested:** Issue #27 intent + human-validation gate; no product-path changes; live public pricing still €1.99/500 GB; Dex `registerPricingNotice` still 1,99/€1.99; OpenCloud stack smoke.
4. **Results:**
   - Criterion 1 (pricing idea, not bug): **PASS** — issue title/body: “7€ per month including 500GB… This is a pricing/product packaging idea… not a bug report.”
   - Criterion 2 (`waiting for human validation`): **PASS** — label present alongside `agent:testing` at test time (`gh issue view 27`).
   - Criterion 3 (no product-file diff): **PASS** — `git status --short` empty for `overrides/`, `dex/`, `nginx/`, `host-www/`, `scripts/`, `docs/`; no commits to those paths since task stamp.
   - Criterion 4 (public pricing €1.99 + 500 GB): **PASS** — HTTP 200; page contains `€1.99` and `500 GB` (hero + comparison table).
   - Criterion 5 (login/Dex notice 1,99 / 1.99): **PASS** — `/dex/theme/i18n.js` HTTP 200; es/ca `1,99 €/mes`, en `€1.99/month`, de `1,99 €/Monat`; `/login.html` HTTP 200.
   - Criterion 6 (compose smoke): **PASS** — `opencloud-opencloud-1` Up; root `https://cloud.km0digital.com/` → HTTP 302 (expected redirect); stack ready without deploy wait (containers already up; HTTP checks succeeded immediately).
5. **Overall:** **PASS**
6. **URLs tested:** https://km0digital.com/en/pricing/ (200); https://cloud.km0digital.com/ (302); https://cloud.km0digital.com/login.html (200); https://cloud.km0digital.com/dex/theme/i18n.js (200).
7. **Log excerpts:** `opencloud-opencloud-1` Up 11 days; recent access-log lines healthy (e.g. `/status.php` 200 at 12:03:03Z). No nginx template changes — nginx error log not required.
