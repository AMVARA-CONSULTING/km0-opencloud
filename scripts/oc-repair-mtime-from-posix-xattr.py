#!/usr/bin/env python3
"""Repair OpenCloud user.oc.mtime from local POSIX user.oc.mtime xattr.

Targets space-node .mpk files still on the 2026-08-20 reimport stamp, for
supported extensions, when the matching local file has a usable xattr.

Default: dry-run. Use --apply to write + restart opencloud.
Skips xattr years before 1990 (zip/epoch junk).
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
LIB = ROOT / "oc-docx-set-mtime-from-ooxml.py"
SPACES = Path("/var/lib/docker/volumes/opencloud_opencloud-data/_data/storage/users/spaces")
USERS = Path("/var/lib/docker/volumes/opencloud_opencloud-data/_data/storage/users/users")
COMPOSE_DIR = Path("/opt/opencloud/opencloud-compose")
REIMPORT_PREFIX = "2026-08-20T"
MIN_YEAR = 1990


def _load_lib():
    spec = importlib.util.spec_from_file_location("oc_mtime_lib", LIB)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load %s" % LIB)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["oc_mtime_lib"] = mod
    spec.loader.exec_module(mod)
    return mod


lib = _load_lib()
SUPPORTED = (
    lib._OOXML_SUFFIXES
    | lib._ODF_SUFFIXES
    | lib._IMAGE_SUFFIXES
    | lib._PDF_SUFFIXES
    | lib._MP4_SUFFIXES
)


def space_id_from_path(mpk: Path) -> str:
    # .../spaces/<xx>/<uuid-rest>/nodes/...
    parts = mpk.parts
    i = parts.index("spaces")
    return parts[i + 1] + parts[i + 2]


def space_label(sid: str) -> str:
    nodes = SPACES / sid[:2] / sid[2:] / "nodes"
    if not nodes.is_dir():
        return sid[:8]
    for p in nodes.rglob("*.mpk"):
        try:
            meta = lib.unpack_mpk(p)
        except Exception:
            continue
        name = lib.gmeta(meta, "user.oc.space.name")
        if name:
            return str(name)
    return sid[:8]


def xattr_usable(raw: str) -> bool:
    if not raw or raw.startswith(REIMPORT_PREFIX):
        return False
    try:
        # tolerate nanoseconds / Z
        s = raw.replace("Z", "+00:00")
        if "." in s:
            head, rest = s.split(".", 1)
            frac = "".join(c for c in rest if c.isdigit())[:6].ljust(6, "0")
            tz = rest[len("".join(c for c in rest if c.isdigit())) :] or "+00:00"
            if not tz.startswith(("+", "-")):
                tz = "+00:00"
            s = "%s.%s%s" % (head, frac, tz)
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.year >= MIN_YEAR
    except Exception:
        return False


def index_local() -> dict[str, dict[str, Path]]:
    out: dict[str, dict[str, Path]] = {}
    if not USERS.is_dir():
        return out
    for udir in USERS.iterdir():
        if not udir.is_dir():
            continue
        by_name: dict[str, Path] = {}
        for root, dirs, files in os.walk(udir):
            dirs[:] = [d for d in dirs if d != ".oc-nodes"]
            for f in files:
                by_name.setdefault(f, Path(root) / f)
        out[udir.name] = by_name
    return out


def collect_candidates(local: dict[str, dict[str, Path]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for space_dir in sorted(SPACES.glob("*/*")):
        nodes = space_dir / "nodes"
        if not nodes.is_dir():
            continue
        sid = space_dir.parts[-2] + space_dir.parts[-1]
        for mpk in nodes.rglob("*.mpk"):
            try:
                meta = lib.unpack_mpk(mpk)
            except Exception:
                continue
            if lib.gmeta(meta, "user.oc.trash.origin"):
                continue
            name = lib.gmeta(meta, "user.oc.name")
            blob = lib.gmeta(meta, "user.oc.blobid")
            mtime = str(lib.gmeta(meta, "user.oc.mtime") or "")
            if not name or not blob or not mtime.startswith(REIMPORT_PREFIX):
                continue
            suf = Path(str(name)).suffix.lower()
            if suf not in SUPPORTED:
                continue
            lp = local.get(sid, {}).get(str(name))
            if not lp or not lp.is_file():
                continue
            try:
                xraw = os.getxattr(lp, "user.oc.mtime").decode()
            except OSError:
                continue
            if not xattr_usable(xraw):
                continue
            try:
                new_mtime = lib.normalize_oc_mtime(xraw)
            except Exception:
                new_mtime = xraw if xraw.endswith("Z") else xraw
            if new_mtime.startswith(REIMPORT_PREFIX):
                continue
            if new_mtime == mtime:
                continue
            try:
                rel = str(lp.relative_to(USERS / sid))
            except Exception:
                rel = str(lp)
            rows.append(
                {
                    "mpk": mpk,
                    "space_id": sid,
                    "name": str(name),
                    "old": mtime,
                    "new": new_mtime,
                    "xattr": xraw,
                    "rel": rel,
                    "meta": meta,
                }
            )
    return rows


def apply_one(row: dict[str, Any]) -> None:
    meta = row["meta"]
    mpk: Path = row["mpk"]
    lib.set_mtime_key(meta, row["new"])
    tmp = mpk.with_suffix(mpk.suffix + ".tmp")
    tmp.write_bytes(lib.pack_mpk(meta))
    os.replace(tmp, mpk)
    try:
        os.chown(mpk, 1000, 1000)
        os.chmod(mpk, 0o600)
    except OSError as e:
        print("WARN   chown/chmod failed: %s" % e)
    verify = lib.gmeta(lib.unpack_mpk(mpk), "user.oc.mtime")
    if verify != row["new"]:
        raise RuntimeError("verify failed: got %r want %r" % (verify, row["new"]))


def restart_opencloud() -> tuple[bool, str]:
    try:
        r = subprocess.run(
            ["docker", "compose", "restart", "opencloud"],
            cwd=str(COMPOSE_DIR),
            capture_output=True,
            text=True,
            timeout=180,
        )
        if r.returncode != 0:
            return False, (r.stderr or r.stdout or "restart failed")[-500:]
        return True, "ok"
    except Exception as e:
        return False, str(e)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--apply",
        action="store_true",
        help="write .mpk and restart opencloud (default is dry-run)",
    )
    ap.add_argument(
        "--no-restart",
        action="store_true",
        help="with --apply, skip docker compose restart",
    )
    args = ap.parse_args()
    mode = "APPLY" if args.apply else "DRY-RUN"

    print("MODE   %s" % mode)
    print("SCAN   indexing local POSIX…")
    local = index_local()
    print("SCAN   local spaces=%d" % len(local))
    print("SCAN   collecting reimport+supported with usable xattr…")
    rows = collect_candidates(local)
    by_space = Counter(r["space_id"] for r in rows)
    labels = {sid: space_label(sid) for sid in by_space}

    print()
    print("=== CANDIDATES (%d) ===" % len(rows))
    updated = 0
    for r in sorted(rows, key=lambda x: (labels[x["space_id"]], x["name"])):
        tag = "UPDATE" if args.apply else "WOULD "
        print(
            "%s [%s] %s\n       %s -> %s\n       path=%s"
            % (
                tag,
                labels[r["space_id"]],
                r["name"],
                r["old"][:28],
                r["new"][:28],
                r["rel"],
            )
        )
        if args.apply:
            apply_one(r)
            updated += 1

    print()
    print("=== SUMMARY ===")
    print("mode           %s" % mode)
    if args.apply:
        print("updated        %d" % updated)
    else:
        print("would_update   %d" % len(rows))
    print("by_space       %s" % {labels[s]: c for s, c in by_space.most_common()})
    print("skipped_note   xattr year<%d or reimport xattr or no local file" % MIN_YEAR)

    if args.apply and rows and not args.no_restart:
        print("restarting opencloud…")
        ok, msg = restart_opencloud()
        print("restart        %s" % msg)
        if not ok:
            return 1
    elif not args.apply:
        print("next           re-run with --apply to write + restart")
    print("=== END ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
