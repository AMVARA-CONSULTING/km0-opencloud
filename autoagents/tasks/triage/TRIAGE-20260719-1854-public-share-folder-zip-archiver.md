---
status: evidence
---

# Evidence note (not a queue item)

Implementable docs work handed off: **`UNTESTED-0-20260719-1924-public-share-folder-zip-workaround-docs.md`**.  
This file stays under `triage/` so the loop does not pick it up as a second job.

---

# Note: public share folder ZIP download fails (`download.zip`)

## Context
- **Source:** Operator report (direct chat), 2026-07-19.
- **Public link (repro):** `https://cloud.km0digital.com/s/spvgphZGoocPVcB`
- **Stack:** `opencloudeu/opencloud-rolling:7.3.0` (`x-web-version: 7.3.0`, reva `v2.47.0` in logs).
- **Ownership:** Almost certainly **OpenCloud / reva** (`/archiver` + public-share scope). KM0 nginx only proxies. Do not patch OpenCloud in this repo.

## Symptom
Anonymous users can download **individual files** on a public folder share, but downloading a **subfolder** (e.g. `assets`) as ZIP fails. Browser may say **`download.zip` does not exist**; console stays clean (HTTP attachment failure, not SPA crash).

## Evidence already reproduced
1. WebDAV list works: `PROPFIND /remote.php/dav/public-files/<token>/` includes `assets/`.
2. Single file OK: `GET …/LICENSE` → **200**.
3. Folder archive fails: `GET /archiver?id=…&public-token=…` → **404** with `Content-Disposition: download.zip` and body text  
   `error: not found: gateway could not find space for ref=… path:"."`
4. Logs: `permission denied: request is not for a nested resource` → archiver `could not find space`.
5. No nginx `/archiver` special case.
6. Upstream: [opencloud#2401](https://github.com/opencloud-eu/opencloud/issues/2401), [opencloud#1712](https://github.com/opencloud-eu/opencloud/issues/1712); CVE-2026-23989 scope hardening ([reva `9bb19f6`](https://github.com/opencloud-eu/reva/commit/9bb19f69efc3c40a8b077af9961a340f14205ef5)).

## Workaround
Download files one-by-one, or use a WebDAV/sync client while logged in.

## Next step
- Agents: implement docs via the **NEW-** workaround task only.
- Humans: escalate to OpenCloud if needed — see `TRIAGE-20260719-1854-public-share-folder-zip-upstream-note.md`.
