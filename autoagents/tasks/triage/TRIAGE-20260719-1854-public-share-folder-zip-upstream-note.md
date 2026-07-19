---
status: evidence
---

# Evidence note (not a queue item)

Implementable docs work handed off: **`UNTESTED-0-20260719-1924-public-share-folder-zip-workaround-docs.md`**.  
This file stays under `triage/` so the loop does not pick it up as a second job.

---

# Note: escalate public-link folder ZIP (`/archiver`) to OpenCloud

## Related
- Evidence: `TRIAGE-20260719-1854-public-share-folder-zip-archiver.md`
- **Out of scope for KM0 agents:** patching OpenCloud, reva, or forking archiver/scope code.

## Summary for vendor
On OpenCloud **7.3.0**, public folder shares: single-file WebDAV download works; subfolder ZIP via `/archiver?id=…&public-token=…` returns **404** as `download.zip` with gateway error `request is not for a nested resource` / `could not find space`. Same class as opencloud-eu/opencloud#2401 / #1712 after public-share scope hardening (CVE-2026-23989).

## If a human escalates
1. File on `opencloud-eu/opencloud` with version, curl repro, log lines — **redact** live share tokens.
2. Optional runbook blurb: known limitation + per-file workaround.
3. Optional tracking issue on `AMVARA-CONSULTING/km0-opencloud` marked blocked on vendor — still **no** product code changes unless operator starts a real `FEAT-`/`NEW-` later.

## Workaround
Per-file download or authenticated client until OpenCloud ships a fix (or an ops IDP/metadata repair is confirmed separately by a human).
