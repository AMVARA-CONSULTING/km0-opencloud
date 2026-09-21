#!/usr/bin/env python3
"""Bulk-set OpenCloud user.oc.mtime from embedded file dates (all spaces).

Designed for fleet runs (photos + office + pdf + video):
  - One pass over space .mpk nodes (skip trash)
  - Prefer local POSIX bytes; else S3 via SigV4 (no per-file Docker)
  - Images: Range-GET first 1 MiB first; fall back to full object
  - Other types: full object GET (concurrent)
  - Default: APPLY writes + restart opencloud (use --dry-run to preview)
  - Logs to /tmp/oc-mtime-bulk-<timestamp>.log (override with --log)
  - Prints a final SUMMARY (also in the log)

Run detached (screen is NOT installed here — use tmux):

  LOG=/tmp/oc-mtime-bulk-$(date +%Y%m%d-%H%M%S).log
  tmux new -s mtime-bulk "sudo python3 /opt/opencloud/scripts/oc-bulk-set-mtime-from-embedded.py --workers 24 --log $LOG"
  # detach: Ctrl-b d    reattach: tmux attach -t mtime-bulk    tail: tail -f $LOG

Examples:
  sudo python3 /opt/opencloud/scripts/oc-bulk-set-mtime-from-embedded.py --dry-run
  sudo python3 /opt/opencloud/scripts/oc-bulk-set-mtime-from-embedded.py --log /tmp/oc-mtime-bulk.log
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import importlib.util
import os
import re
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
import warnings
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, TextIO
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent
LIB = ROOT / "oc-docx-set-mtime-from-ooxml.py"


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
IMAGE_RANGE = 1 * 1024 * 1024  # 1 MiB
COMPOSE_DIR = Path("/opt/opencloud/opencloud-compose")
DEFAULT_LOG_DIR = Path("/tmp")


class Tee:
    """Write lines to stdout and a log file."""

    def __init__(self, log_path: Path):
        self.log_path = log_path
        self._fh: TextIO = log_path.open("a", encoding="utf-8")
        self._lock = threading.Lock()

    def write(self, msg: str = "") -> None:
        line = msg if msg.endswith("\n") or msg == "" else msg + "\n"
        if msg == "":
            line = "\n"
        with self._lock:
            sys.__stdout__.write(line)
            sys.__stdout__.flush()
            self._fh.write(line)
            self._fh.flush()

    def close(self) -> None:
        try:
            self._fh.close()
        except Exception:
            pass


def log(msg: str = "") -> None:
    _LOG.write(msg)


_LOG: Tee


def init_logging(log_path: Path) -> Tee:
    global _LOG
    log_path.parent.mkdir(parents=True, exist_ok=True)
    _LOG = Tee(log_path)
    return _LOG


@dataclass
class Stats:
    scanned_mpk: int = 0
    candidates: int = 0
    skipped_trash: int = 0
    skipped_unsupported: int = 0
    skipped_no_blob: int = 0
    skipped_no_date: int = 0
    skipped_already_match: int = 0
    updated: int = 0
    failed: int = 0
    bytes_local: int = 0
    bytes_s3_range: int = 0
    bytes_s3_full: int = 0
    by_ext: Counter = field(default_factory=Counter)
    by_space_updated: Counter = field(default_factory=Counter)
    by_source: Counter = field(default_factory=Counter)
    failures: list = field(default_factory=list)
    lock: threading.Lock = field(default_factory=threading.Lock)

    def add_failure(self, msg: str) -> None:
        with self.lock:
            self.failed += 1
            if len(self.failures) < 30:
                self.failures.append(msg)


def _sign(key: bytes, msg: str) -> bytes:
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def s3_get_object(
    env: dict[str, str],
    key: str,
    *,
    byte_range: str | None = None,
) -> bytes:
    """GET object (optional Range) via AWS SigV4 — no boto3 / no Docker."""
    endpoint = env["DECOMPOSEDS3_ENDPOINT"].rstrip("/")
    region = env.get("DECOMPOSEDS3_REGION", "fsn1")
    bucket = env["DECOMPOSEDS3_BUCKET"]
    ak = env["DECOMPOSEDS3_ACCESS_KEY"]
    sk = env["DECOMPOSEDS3_SECRET_KEY"]
    host = endpoint.split("://", 1)[-1]
    # path-style: /bucket/key
    path = "/" + bucket + "/" + quote(key, safe="/-_.~")
    t = datetime.now(timezone.utc)
    amzdate = t.strftime("%Y%m%dT%H%M%SZ")
    datestamp = t.strftime("%Y%m%d")
    payload_hash = "UNSIGNED-PAYLOAD"
    headers = {
        "host": host,
        "x-amz-content-sha256": payload_hash,
        "x-amz-date": amzdate,
    }
    if byte_range:
        headers["range"] = byte_range
    signed_header_keys = sorted(headers)
    canonical_headers = "".join("%s:%s\n" % (k, headers[k]) for k in signed_header_keys)
    signed_headers = ";".join(signed_header_keys)
    canonical_request = "\n".join(
        [
            "GET",
            path,
            "",
            canonical_headers,
            signed_headers,
            payload_hash,
        ]
    )
    scope = "%s/%s/s3/aws4_request" % (datestamp, region)
    string_to_sign = "\n".join(
        [
            "AWS4-HMAC-SHA256",
            amzdate,
            scope,
            hashlib.sha256(canonical_request.encode()).hexdigest(),
        ]
    )
    k_date = _sign(("AWS4" + sk).encode(), datestamp)
    k_region = _sign(k_date, region)
    k_service = _sign(k_region, "s3")
    k_signing = _sign(k_service, "aws4_request")
    signature = hmac.new(
        k_signing, string_to_sign.encode(), hashlib.sha256
    ).hexdigest()
    headers["Authorization"] = (
        "AWS4-HMAC-SHA256 Credential=%s/%s, SignedHeaders=%s, Signature=%s"
        % (ak, scope, signed_headers, signature)
    )
    req = urllib.request.Request(endpoint + path, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        body = e.read()[:300].decode("utf-8", "replace")
        raise RuntimeError("S3 GET %s -> HTTP %s: %s" % (key, e.code, body)) from e


def build_local_index() -> dict[str, dict[str, Path]]:
    """space_id -> {basename: path} (first wins)."""
    index: dict[str, dict[str, Path]] = {}
    root = lib.USERS_POSIX
    if not root.is_dir():
        return index
    for space_dir in root.iterdir():
        if not space_dir.is_dir() or not lib._UUID_RE.match(space_dir.name):
            continue
        names: dict[str, Path] = {}
        for dirpath, _dirs, files in os.walk(space_dir):
            for f in files:
                if f not in names:
                    names[f] = Path(dirpath) / f
        index[space_dir.name] = names
    return index


def normalize_mtime_value(raw: str) -> str:
    if re.match(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", raw):
        return raw
    return lib.normalize_oc_mtime(raw)


def pick_field(dates: Any, field: str) -> str | None:
    raw = dates.created if field == "created" else dates.modified
    if not raw:
        raw = dates.modified or dates.created
    return str(raw) if raw else None


def extract_from_bytes(data: bytes, name: str) -> Any:
    suf = Path(name).suffix.lower() or ".bin"
    with tempfile.NamedTemporaryFile(prefix="oc-bulk-", suffix=suf, delete=False) as tf:
        tf.write(data)
        path = Path(tf.name)
    try:
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("ignore")
            result = lib.extract_embedded_dates(path, archive_name=name)
        for w in caught:
            try:
                log("WARN   %s: %s" % (name, w.message))
            except Exception:
                print("WARN   %s: %s" % (name, w.message), file=sys.stderr)
        return result
    finally:
        try:
            path.unlink()
        except OSError:
            pass


def fetch_for_extract(
    env: dict[str, str],
    *,
    space_id: str,
    blob_id: str,
    blobsize: int | None,
    name: str,
    local: Path | None,
    stats: Stats,
) -> tuple[Any, str]:
    """Return (EmbeddedDates, origin_tag)."""
    if local is not None and local.is_file():
        if blobsize is None or local.stat().st_size == int(blobsize):
            with warnings.catch_warnings(record=True) as caught:
                warnings.simplefilter("ignore")
                dates = lib.extract_embedded_dates(local, archive_name=name)
            for w in caught:
                try:
                    log("WARN   %s: %s" % (name, w.message))
                except Exception:
                    print("WARN   %s: %s" % (name, w.message), file=sys.stderr)
            with stats.lock:
                stats.bytes_local += local.stat().st_size
            return dates, "local"

    key = lib.blob_s3_key(space_id, blob_id)
    suf = Path(name).suffix.lower()

    if suf in lib._IMAGE_SUFFIXES:
        end = IMAGE_RANGE - 1
        if blobsize is not None:
            end = min(end, max(int(blobsize) - 1, 0))
        data = s3_get_object(env, key, byte_range="bytes=0-%d" % end)
        with stats.lock:
            stats.bytes_s3_range += len(data)
        try:
            return extract_from_bytes(data, name), "s3-range"
        except Exception:
            data = s3_get_object(env, key)
            with stats.lock:
                stats.bytes_s3_full += len(data)
            return extract_from_bytes(data, name), "s3-full-fallback"

    # PDF: prefer tail (Info dict / XMP often near end) + small head
    if suf in lib._PDF_SUFFIXES and blobsize and int(blobsize) > 1_500_000:
        size = int(blobsize)
        tail_from = max(0, size - 1_048_576)
        head = s3_get_object(env, key, byte_range="bytes=0-65535")
        tail = s3_get_object(
            env, key, byte_range="bytes=%d-%d" % (tail_from, size - 1)
        )
        with stats.lock:
            stats.bytes_s3_range += len(head) + len(tail)
        # Scanner only searches for date markers; concatenation is enough
        try:
            return extract_from_bytes(head + b"\n" + tail, name), "s3-range-pdf"
        except Exception:
            pass

    data = s3_get_object(env, key)
    with stats.lock:
        stats.bytes_s3_full += len(data)
    return extract_from_bytes(data, name), "s3-full"


def write_mpk(mpk: Path, meta: dict, new_mtime: str, write_bak: bool) -> str:
    if write_bak:
        bak = mpk.with_suffix(
            mpk.suffix + ".bak-" + datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
        )
        bak.write_bytes(mpk.read_bytes())
    lib.set_mtime_key(meta, new_mtime)
    tmp = mpk.with_suffix(mpk.suffix + ".tmp")
    tmp.write_bytes(lib.pack_mpk(meta))
    os.replace(tmp, mpk)
    try:
        os.chown(mpk, 1000, 1000)
        os.chmod(mpk, 0o600)
    except OSError:
        pass
    verify = lib.gmeta(lib.unpack_mpk(mpk), "user.oc.mtime")
    if verify != new_mtime:
        raise RuntimeError("verify failed: got %r want %r" % (verify, new_mtime))
    return new_mtime


def process_item(
    item: dict[str, Any],
    env: dict[str, str],
    field: str,
    apply: bool,
    write_bak: bool,
    local_index: dict[str, dict[str, Path]],
    stats: Stats,
) -> None:
    mpk: Path = item["mpk"]
    name: str = item["name"]
    space_id: str = item["space_id"]
    blob_id: str = item["blob_id"]
    blobsize = item["blobsize"]
    old = item["old_mtime"]
    suf = item["suffix"]

    local_map = local_index.get(space_id, {})
    local = local_map.get(name)

    try:
        dates, _origin = fetch_for_extract(
            env,
            space_id=space_id,
            blob_id=blob_id,
            blobsize=blobsize,
            name=name,
            local=local,
            stats=stats,
        )
        raw = pick_field(dates, field)
        if not raw:
            with stats.lock:
                stats.skipped_no_date += 1
            return
        new = normalize_mtime_value(raw)
        if "." in new and new.endswith("Z"):
            new = new.split(".", 1)[0] + "Z"
            new = normalize_mtime_value(new)

        old_n = None
        if old is not None:
            try:
                old_n = normalize_mtime_value(str(old))
            except Exception:
                old_n = str(old)
            if "." in str(old_n) and str(old_n).endswith("Z"):
                try:
                    old_n = normalize_mtime_value(str(old_n).split(".", 1)[0] + "Z")
                except Exception:
                    pass
        if old_n == new:
            with stats.lock:
                stats.skipped_already_match += 1
            return

        with stats.lock:
            stats.by_source[dates.source] += 1

        if not apply:
            with stats.lock:
                stats.updated += 1  # would-update in dry-run
                stats.by_ext[suf] += 1
                stats.by_space_updated[space_id] += 1
            return

        meta = lib.unpack_mpk(mpk)
        write_mpk(mpk, meta, new, write_bak)
        with stats.lock:
            stats.updated += 1
            stats.by_ext[suf] += 1
            stats.by_space_updated[space_id] += 1
    except Exception as e:
        stats.add_failure("%s (%s): %s" % (name, space_id[:8], e))


def collect_candidates(stats: Stats) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for p in lib.SPACES.rglob("*.mpk"):
        stats.scanned_mpk += 1
        try:
            meta = lib.unpack_mpk(p)
        except Exception:
            continue
        if lib.gmeta(meta, "user.oc.trash.origin"):
            stats.skipped_trash += 1
            continue
        name = lib.gmeta(meta, "user.oc.name")
        blob = lib.gmeta(meta, "user.oc.blobid")
        if not name:
            continue
        if not blob:
            stats.skipped_no_blob += 1
            continue
        suf = Path(str(name)).suffix.lower()
        if suf not in SUPPORTED:
            stats.skipped_unsupported += 1
            continue
        sid = lib.space_id_from_path(p)
        bsz = lib.gmeta(meta, "user.oc.blobsize")
        try:
            bsz_i = int(bsz) if bsz is not None else None
        except Exception:
            bsz_i = None
        items.append(
            {
                "mpk": p,
                "name": str(name),
                "space_id": sid,
                "blob_id": str(blob).lstrip("$"),
                "blobsize": bsz_i,
                "old_mtime": lib.gmeta(meta, "user.oc.mtime"),
                "suffix": suf,
            }
        )
    stats.candidates = len(items)
    return items


def restart_opencloud() -> tuple[bool, str]:
    cmd = ["docker", "compose", "restart", "opencloud"]
    try:
        r = __import__("subprocess").run(
            cmd,
            cwd=str(COMPOSE_DIR),
            capture_output=True,
            text=True,
            timeout=180,
        )
        if r.returncode != 0:
            return False, (r.stderr or r.stdout or "restart failed")[-500:]
        return True, "docker compose restart opencloud -> ok"
    except Exception as e:
        return False, str(e)


def print_summary(
    stats: Stats,
    *,
    duration_s: float,
    apply: bool,
    workers: int,
    restart_msg: str | None,
) -> None:
    log()
    log("=== SUMMARY ===")
    log("mode              %s" % ("APPLY" if apply else "DRY-RUN"))
    log("workers           %d" % workers)
    log("duration_sec      %.1f" % duration_s)
    log("scanned_mpk       %d" % stats.scanned_mpk)
    log("candidates        %d" % stats.candidates)
    log("skipped_trash     %d" % stats.skipped_trash)
    log("skipped_no_blob   %d" % stats.skipped_no_blob)
    log("skipped_unsupported %d" % stats.skipped_unsupported)
    log("skipped_no_date   %d" % stats.skipped_no_date)
    log("skipped_already_match %d" % stats.skipped_already_match)
    log("updated           %d%s" % (stats.updated, "" if apply else " (would update)"))
    log("failed            %d" % stats.failed)
    log("bytes_local       %.2f MiB" % (stats.bytes_local / (1024 * 1024)))
    log("bytes_s3_range    %.2f MiB" % (stats.bytes_s3_range / (1024 * 1024)))
    log("bytes_s3_full     %.2f MiB" % (stats.bytes_s3_full / (1024 * 1024)))
    log("by_ext_updated    %s" % dict(stats.by_ext.most_common()))
    log("by_source         %s" % dict(stats.by_source.most_common()))
    top_spaces = stats.by_space_updated.most_common(8)
    log("by_space_updated  %s" % top_spaces)
    if restart_msg is not None:
        log("restart           %s" % restart_msg)
    if stats.failures:
        log("failure_samples:")
        for line in stats.failures:
            log("  - %s" % line)
    log("=== END SUMMARY ===")


def default_log_path() -> Path:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return DEFAULT_LOG_DIR / ("oc-mtime-bulk-%s.log" % stamp)


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="Do not write .mpk and do not restart (preview only)",
    )
    ap.add_argument(
        "--workers",
        type=int,
        default=24,
        help="Parallel workers (default 24; stay under Hetzner ~256 sessions)",
    )
    ap.add_argument(
        "--from",
        dest="field",
        choices=("created", "modified"),
        default="modified",
    )
    ap.add_argument(
        "--bak",
        action="store_true",
        help="Also write .mpk.bak-* (default off)",
    )
    ap.add_argument(
        "--no-restart",
        action="store_true",
        help="Skip docker compose restart even when applying",
    )
    ap.add_argument(
        "--log",
        metavar="PATH",
        default=None,
        help="Log file path (default: /tmp/oc-mtime-bulk-<timestamp>.log)",
    )
    args = ap.parse_args()

    log_path = Path(args.log) if args.log else default_log_path()
    tee = init_logging(log_path)

    if os.geteuid() != 0:
        log("ERROR: run as root (needed for volume writes / chown)")
        tee.close()
        return 2
    if not lib.SPACES.is_dir():
        log("ERROR: spaces path missing")
        tee.close()
        return 2

    apply = not args.dry_run
    do_restart = apply and not args.no_restart
    workers = max(1, min(args.workers, 64))

    env = lib.load_env()
    try:
        lib.require_s3_env(env)
    except RuntimeError as e:
        log("ERROR: %s" % e)
        tee.close()
        return 2

    log("BULK   log_file=%s" % log_path)
    log(
        "BULK   starting (apply=%s restart=%s workers=%d)"
        % (apply, do_restart, workers)
    )
    t0 = time.time()
    stats = Stats()

    log("BULK   indexing local POSIX names…")
    local_index = build_local_index()
    log("BULK   local spaces indexed: %d" % len(local_index))

    log("BULK   scanning .mpk nodes…")
    items = collect_candidates(stats)
    log(
        "BULK   candidates=%d trash_skipped=%d unsupported=%d"
        % (stats.candidates, stats.skipped_trash, stats.skipped_unsupported)
    )

    done = 0
    total = len(items)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futs = [
            pool.submit(
                process_item,
                item,
                env,
                args.field,
                apply,
                args.bak,
                local_index,
                stats,
            )
            for item in items
        ]
        for fut in as_completed(futs):
            done += 1
            if done % 500 == 0 or done == total:
                log(
                    "BULK   progress %d/%d updated=%d failed=%d"
                    % (done, total, stats.updated, stats.failed)
                )
            fut.result()

    restart_msg = None
    if do_restart:
        log("BULK   restarting opencloud…")
        ok, restart_msg = restart_opencloud()
        if not ok:
            log("ERROR: restart failed: %s" % restart_msg)

    print_summary(
        stats,
        duration_s=time.time() - t0,
        apply=apply,
        workers=workers,
        restart_msg=restart_msg,
    )
    log("BULK   finished; log_file=%s" % log_path)
    tee.close()
    return 1 if stats.failed else 0


if __name__ == "__main__":
    sys.exit(main())
