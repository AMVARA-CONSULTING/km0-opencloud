# Upstream issue draft: public-share subfolder ZIP via `/archiver`

> **Purpose:** English draft for humans to file on [`opencloud-eu/opencloud`](https://github.com/opencloud-eu/opencloud).  
> **Do not** paste live public-share tokens into GitHub.  
> **KM0 stance:** documentation / workaround only — no fork of OpenCloud or reva in this repo.

---

## Title

Public folder share: subfolder ZIP (`GET /archiver`) returns 404 `download.zip` while single-file WebDAV works

## Environment

| Item | Value |
|------|--------|
| OpenCloud | `opencloudeu/opencloud-rolling:7.3.0` (`x-web-version: 7.3.0`) |
| reva | `v2.47.0` (from gateway logs) |
| Deploy | external Nginx proxy, public URL `https://example.com` |
| Share type | Passwordless **public folder** link |

## Steps to reproduce

1. Create a folder with at least one nested subfolder containing files.
2. Share the parent folder as a public link (no password).
3. Open the link anonymously; confirm a **single file** downloads successfully.
4. From the public UI, download the **subfolder** as ZIP (or call `/archiver` with that folder’s file id and the public token).

## Expected

Subfolder archive downloads as ZIP for the public share (within the share scope).

## Actual

- Browser may show that `download.zip` was not available on the site; no useful SPA console error.
- `GET /archiver?id=<folder-file-id>&public-token=<redacted>` → **HTTP 404** with  
  `Content-Disposition: attachment; filename*=UTF-8''download.zip`.
- Response body (example):  
  `error: not found: gateway could not find space for ref=… path:"."`
- Gateway logs: `permission denied: request is not for a nested resource`, then archiver `could not find space`.

## Contrast (control)

- `PROPFIND /remote.php/dav/public-files/<token>/` lists the subfolder.
- `GET /remote.php/dav/public-files/<token>/<file>` → **200**.

## Related upstream

- https://github.com/opencloud-eu/opencloud/issues/2401
- https://github.com/opencloud-eu/opencloud/issues/1712
- Public-share scope hardening after CVE-2026-23989 (reva commit family around nested-resource checks).

## Workaround (operators / end users)

Download files one-by-one from the public link, or use an authenticated WebDAV/sync client until a vendor fix ships.

## Notes for reporters

- Redact `public-token` and any real file ids that encode tenant paths if required by your policy.
- Confirm Nginx is only reverse-proxying (no custom `/archiver` location) so the failure is attributable to OpenCloud/reva.
