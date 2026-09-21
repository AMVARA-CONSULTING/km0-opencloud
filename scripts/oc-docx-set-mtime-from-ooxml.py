#!/usr/bin/env python3
"""Set OpenCloud user.oc.mtime from embedded file dates (many formats).

Reads a date from the file content (local POSIX tree when present, else S3
blob) and writes user.oc.mtime on the space-node .mpk.

Supported sources (auto-detected):
  - OOXML  docx/xlsx/pptx(+m): docProps/core.xml dcterms:created|modified
  - ODF    odt/ods/odp: meta.xml meta:creation-date / dc:date
  - Images jpeg/jpg/png/tif/webp/heic*: EXIF / XMP (Pillow)
  - PDF: Info /CreationDate|/ModDate and XMP CreateDate/ModifyDate
  - MP4/MOV/M4V: ISO BMFF mvhd creation/modification times
  - Fallback: none → SKIP (does not invent dates from inode mtime)

* HEIC only if the local Pillow build can open it.

--from modified (default): "last change" style field when available
--from created: capture/create style field when available
For images, modified prefers DateTime(+offset); created prefers DateTimeOriginal.
If only one EXIF date exists, both fields fall back to it.

Default: dry-run. Use --apply to write.
--bak: with --apply, also write a sibling .mpk.bak-<stamp> (off by default;
volume backups are enough for rollback).
--test PATH: process only that one POSIX file under storage/users/users/.

Requires root on amvara10, msgpack, Pillow; S3 (amazon/aws-cli image + creds)
only when the bytes are not available on the local users/ tree.
"""
from __future__ import annotations

import argparse
import os
import re
import struct
import subprocess
import sys
import tempfile
import warnings
import zipfile
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from xml.etree import ElementTree as ET

import msgpack

STORAGE_USERS = Path(
    "/var/lib/docker/volumes/opencloud_opencloud-data/_data/storage/users"
)
SPACES = STORAGE_USERS / "spaces"
USERS_POSIX = STORAGE_USERS / "users"
COMPOSE_ENV = Path("/opt/opencloud/opencloud-compose/.env")
S3_CRED = Path("/root/secrets/hetzner-s3.cred")
OOXML_NS = {
    "cp": "http://schemas.openxmlformats.org/package/2006/metadata/core-properties",
    "dc": "http://purl.org/dc/elements/1.1/",
    "dcterms": "http://purl.org/dc/terms/",
}
_UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
    re.I,
)
_OOXML_SUFFIXES = {".docx", ".xlsx", ".pptx", ".docm", ".xlsm", ".pptm"}
_ODF_SUFFIXES = {".odt", ".ods", ".odp"}
_IMAGE_SUFFIXES = {
    ".jpg",
    ".jpeg",
    ".png",
    ".tif",
    ".tiff",
    ".webp",
    ".heic",
    ".heif",
}
_MP4_SUFFIXES = {".mp4", ".m4v", ".mov", ".m4a"}
_PDF_SUFFIXES = {".pdf"}
# QuickTime epoch: 1904-01-01 UTC
_QT_EPOCH = datetime(1904, 1, 1, tzinfo=timezone.utc)
# PDF date: D:YYYYMMDDHHmmSS+HH'mm'  or  D:YYYYMMDDHHmmSSZ
_PDF_DATE_RE = re.compile(
    r"D:(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})"
    r"(?:(Z)|([+-])(\d{2})'?(\d{2})'?)?"
)


@dataclass
class EmbeddedDates:
    created: str | None  # raw strings before normalize
    modified: str | None
    source: str
    note: str = ""


def load_env() -> dict[str, str]:
    vals: dict[str, str] = {}
    for path in (COMPOSE_ENV, S3_CRED):
        if not path.is_file():
            continue
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            vals[k] = v.strip().strip('"').strip("'")
    return vals


def gmeta(meta: dict, key: str) -> Any:
    for k in (key, key.encode()):
        if k in meta:
            v = meta[k]
            if isinstance(v, bytes):
                try:
                    return v.decode()
                except Exception:
                    return v
            return v
    return None


def unpack_mpk(path: Path) -> dict:
    return msgpack.unpackb(path.read_bytes(), raw=True, strict_map_key=False)


def pack_mpk(meta: dict) -> bytes:
    return msgpack.packb(meta, use_bin_type=True)


def space_id_from_path(mpk: Path) -> str:
    parts = mpk.parts
    i = parts.index("spaces")
    return parts[i + 1] + parts[i + 2]


def space_name(space_id: str) -> str:
    sp = SPACES / space_id[:2] / space_id[2:]
    shard = (
        sp
        / "nodes"
        / space_id[0:2]
        / space_id[2:4]
        / space_id[4:6]
        / space_id[6:8]
        / ("-" + space_id[9:] + ".mpk")
    )
    if not shard.is_file():
        return "?"
    return str(gmeta(unpack_mpk(shard), "user.oc.name") or "?")


def find_files(name: str, space_filter: str | None) -> list[Path]:
    want = name.lower()
    hits: list[Path] = []
    for root, _dirs, files in os.walk(SPACES):
        for f in files:
            if not f.endswith(".mpk"):
                continue
            p = Path(root) / f
            try:
                meta = unpack_mpk(p)
            except Exception:
                continue
            n = gmeta(meta, "user.oc.name")
            if not n or str(n).lower() != want:
                continue
            if gmeta(meta, "user.oc.trash.origin"):
                continue
            sid = space_id_from_path(p)
            if space_filter and space_filter not in (sid, space_name(sid)):
                continue
            hits.append(p)
    return hits


def resolve_test_path(raw: str) -> tuple[Path, str, str]:
    """Map a POSIX storage path to (resolved_file, exact_name, space_id)."""
    p = Path(raw).expanduser()
    if not p.is_absolute():
        s = str(p).lstrip("./")
        if s.startswith("storage/users/"):
            p = STORAGE_USERS.parent.parent / s
        elif s.startswith("users/"):
            p = STORAGE_USERS / s
        else:
            p = (Path.cwd() / p).resolve()
    p = p.resolve()

    if not p.is_file():
        raise FileNotFoundError("test path is not a file: %s" % p)

    try:
        rel = p.relative_to(USERS_POSIX)
    except ValueError as e:
        raise ValueError(
            "test path must be under %s (got %s)" % (USERS_POSIX, p)
        ) from e

    parts = rel.parts
    if len(parts) < 2 or not _UUID_RE.match(parts[0]):
        raise ValueError(
            "expected .../users/<space-uuid>/.../filename, got %s" % rel
        )
    return p, parts[-1], parts[0]


def find_posix_bytes(space_id: str, name: str) -> Path | None:
    """Best-effort: same basename under users/<space_id>/ (first match)."""
    root = USERS_POSIX / space_id
    if not root.is_dir():
        return None
    want = name.lower()
    for dirpath, _dirs, files in os.walk(root):
        for f in files:
            if f.lower() == want:
                return Path(dirpath) / f
    return None


def blob_s3_key(space_id: str, blob_id: str) -> str:
    return (
        f"{space_id}/{blob_id[0:2]}/{blob_id[2:4]}/{blob_id[4:6]}/{blob_id[6:8]}"
        f"/-{blob_id[9:]}"
    )


def s3_download(env: dict[str, str], key: str, dest: Path) -> None:
    endpoint = env["DECOMPOSEDS3_ENDPOINT"]
    bucket = env["DECOMPOSEDS3_BUCKET"]
    cmd = [
        "docker",
        "run",
        "--rm",
        "-e",
        "AWS_ACCESS_KEY_ID=" + env["DECOMPOSEDS3_ACCESS_KEY"],
        "-e",
        "AWS_SECRET_ACCESS_KEY=" + env["DECOMPOSEDS3_SECRET_KEY"],
        "-e",
        "AWS_DEFAULT_REGION=" + env.get("DECOMPOSEDS3_REGION", "fsn1"),
        "-v",
        str(dest.parent) + ":/out",
        "amazon/aws-cli",
        "--endpoint-url",
        endpoint,
        "s3",
        "cp",
        "s3://" + bucket + "/" + key,
        "/out/" + dest.name,
    ]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("s3 cp failed for %s: %s" % (key, r.stderr[-500:]))


def require_s3_env(env: dict[str, str]) -> None:
    for k in (
        "DECOMPOSEDS3_ENDPOINT",
        "DECOMPOSEDS3_BUCKET",
        "DECOMPOSEDS3_ACCESS_KEY",
        "DECOMPOSEDS3_SECRET_KEY",
    ):
        if k not in env:
            raise RuntimeError("missing %s (needed for S3 download)" % k)


def parse_offset(off: str | None) -> timezone | None:
    if not off:
        return None
    s = off.strip()
    if s in ("Z", "z", "+00:00", "-00:00"):
        return timezone.utc
    m = re.fullmatch(r"([+-])(\d{2}):?(\d{2})", s)
    if not m:
        return None
    sign = 1 if m.group(1) == "+" else -1
    hours, mins = int(m.group(2)), int(m.group(3))
    return timezone(sign * timedelta(hours=hours, minutes=mins))


def normalize_oc_mtime(raw: str, default_tz: timezone | None = None) -> str:
    """Normalize many date encodings to OpenCloud UTC Zulu without fractional seconds."""
    s = raw.strip()
    if not s:
        raise ValueError("empty date")

    # EXIF: "YYYY:MM:DD HH:MM:SS"
    m = re.fullmatch(r"(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})", s)
    if m:
        dt = datetime(
            int(m.group(1)),
            int(m.group(2)),
            int(m.group(3)),
            int(m.group(4)),
            int(m.group(5)),
            int(m.group(6)),
            tzinfo=default_tz or timezone.utc,
        )
        return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # Photoshop/XMP often omit timezone: 2026-07-12T20:09:02
    if s.endswith("Z"):
        body = s[:-1]
        if "." in body:
            body = body.split(".", 1)[0]
        return body + "Z"

    if re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}", s):
        dt = datetime.fromisoformat(s).replace(tzinfo=default_tz or timezone.utc)
        return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=default_tz or timezone.utc)
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_ooxml_dates(path: Path) -> EmbeddedDates:
    with zipfile.ZipFile(path) as z:
        if "docProps/core.xml" not in z.namelist():
            raise RuntimeError("no docProps/core.xml")
        root = ET.fromstring(z.read("docProps/core.xml"))
    created = root.findtext("dcterms:created", default=None, namespaces=OOXML_NS)
    modified = root.findtext("dcterms:modified", default=None, namespaces=OOXML_NS)
    creator = root.findtext("dc:creator", default=None, namespaces=OOXML_NS)
    return EmbeddedDates(
        created=created,
        modified=modified,
        source="ooxml",
        note="creator=%s" % (creator or "?"),
    )


def read_odf_dates(path: Path) -> EmbeddedDates:
    """OpenDocument (odt/ods/odp): meta.xml creation-date + dc:date (last edit)."""
    odf_ns = {
        "office": "urn:oasis:names:tc:opendocument:xmlns:office:1.0",
        "meta": "urn:oasis:names:tc:opendocument:xmlns:meta:1.0",
        "dc": "http://purl.org/dc/elements/1.1/",
    }
    with zipfile.ZipFile(path) as z:
        if "meta.xml" not in z.namelist():
            raise RuntimeError("no meta.xml")
        root = ET.fromstring(z.read("meta.xml"))
    created = root.findtext(".//meta:creation-date", default=None, namespaces=odf_ns)
    modified = root.findtext(".//dc:date", default=None, namespaces=odf_ns)
    if not created and not modified:
        raise RuntimeError("ODF meta.xml has no creation-date/dc:date")
    return EmbeddedDates(
        created=created,
        modified=modified or created,
        source="odf-meta",
        note="creation-date=%s dc:date=%s" % (created, modified),
    )


def _exif_get(exif: Any, tag_name: str) -> Any:
    from PIL import ExifTags

    for k, v in exif.items():
        if ExifTags.TAGS.get(k) == tag_name:
            return v
    try:
        ifd = exif.get_ifd(0x8769)  # Exif IFD
    except Exception:
        return None
    for k, v in ifd.items():
        if ExifTags.TAGS.get(k) == tag_name:
            return v
    return None


def read_image_dates(path: Path, archive_name: str | None = None) -> EmbeddedDates:
    from PIL import Image

    label = archive_name or path.name
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("ignore")
        with Image.open(path) as img:
            exif = img.getexif()
            dt = _exif_get(exif, "DateTime")
            dto = _exif_get(exif, "DateTimeOriginal")
            dtd = _exif_get(exif, "DateTimeDigitized")
            off = _exif_get(exif, "OffsetTime")
            off_o = _exif_get(exif, "OffsetTimeOriginal")
            off_d = _exif_get(exif, "OffsetTimeDigitized")

            # XMP ModifyDate / DateCreated (PNG screenshots, etc.)
            xmp = img.info.get("xmp") or img.info.get("XML:com.adobe.xmp") or b""
            if isinstance(xmp, bytes):
                xmp_s = xmp.decode("utf-8", "replace")
            else:
                xmp_s = str(xmp)
            xmp_mod = None
            xmp_cre = None
            m = re.search(r"<xmp:ModifyDate>([^<]+)</xmp:ModifyDate>", xmp_s)
            if m:
                xmp_mod = m.group(1).strip()
            m = re.search(
                r"<photoshop:DateCreated>([^<]+)</photoshop:DateCreated>", xmp_s
            )
            if m:
                xmp_cre = m.group(1).strip()

    for w in caught:
        print("WARN   %s: %s" % (label, w.message), file=sys.stderr)

    created_raw = dto or dtd or xmp_cre or dt or xmp_mod
    modified_raw = dt or xmp_mod or dto or dtd or xmp_cre
    if not created_raw and not modified_raw:
        raise RuntimeError("no EXIF/XMP dates")

    def with_tz(raw: str | None, offset: str | None) -> str | None:
        if not raw:
            return None
        return normalize_oc_mtime(
            str(raw), parse_offset(offset if isinstance(offset, str) else None)
        )

    created = with_tz(
        str(created_raw) if created_raw else None,
        off_o or off_d or off if created_raw in (dto, dtd) else off or off_o,
    )
    modified = with_tz(
        str(modified_raw) if modified_raw else None,
        off if modified_raw == dt else (off_o or off),
    )
    return EmbeddedDates(
        created=created,
        modified=modified,
        source="image-exif/xmp",
        note="DateTime=%s DateTimeOriginal=%s OffsetTime=%s"
        % (dt, dto, off_o or off),
    )


def _iter_isobmff_boxes(data: bytes, start: int = 0, end: int | None = None):
    if end is None:
        end = len(data)
    pos = start
    while pos + 8 <= end:
        size, typ = struct.unpack(">I4s", data[pos : pos + 8])
        hdr = 8
        if size == 1:
            if pos + 16 > end:
                break
            size = struct.unpack(">Q", data[pos + 8 : pos + 16])[0]
            hdr = 16
        elif size == 0:
            size = end - pos
        if size < hdr or pos + size > end:
            break
        yield typ, pos + hdr, pos + size
        pos += size


def parse_pdf_date(raw: str) -> str:
    """Convert PDF date string to OpenCloud Zulu."""
    s = raw.strip().strip("()").strip()
    if s.startswith("D:"):
        m = _PDF_DATE_RE.match(s)
        if not m:
            raise ValueError("unrecognized PDF date: %r" % raw)
        y, mo, d, h, mi, se = (int(m.group(i)) for i in range(1, 7))
        if m.group(7) == "Z" or not m.group(8):
            tz = timezone.utc
        else:
            sign = 1 if m.group(8) == "+" else -1
            tz = timezone(
                sign * timedelta(hours=int(m.group(9)), minutes=int(m.group(10) or 0))
            )
        dt = datetime(y, mo, d, h, mi, se, tzinfo=tz)
        return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return normalize_oc_mtime(s)


def read_pdf_dates(path: Path) -> EmbeddedDates:
    """Best-effort scan for Info dict and XMP dates (no PDF library required)."""
    data = path.read_bytes()
    if not data.startswith(b"%PDF"):
        raise RuntimeError("not a PDF")

    def find_info(key: bytes) -> str | None:
        # /ModDate (D:...)   or   /ModDate(D:...)
        for pat in (
            key + rb"\s*\(([^)]+)\)",
            key + rb"\s*\[([^\]]+)\]",
        ):
            m = re.search(pat, data)
            if m:
                return m.group(1).decode("latin-1", "replace")
        return None

    created_raw = find_info(b"/CreationDate")
    modified_raw = find_info(b"/ModDate")

    # XMP (often present even when Info is missing)
    text = data.decode("latin-1", "replace")
    xmp_cre = None
    xmp_mod = None
    m = re.search(r"<xmp:CreateDate>([^<]+)</xmp:CreateDate>", text)
    if m:
        xmp_cre = m.group(1).strip()
    m = re.search(r"<xmp:ModifyDate>([^<]+)</xmp:ModifyDate>", text)
    if m:
        xmp_mod = m.group(1).strip()
    m = re.search(r"<photoshop:DateCreated>([^<]+)</photoshop:DateCreated>", text)
    if m and not xmp_cre:
        xmp_cre = m.group(1).strip()

    created = None
    modified = None
    if created_raw:
        created = parse_pdf_date(created_raw)
    elif xmp_cre:
        created = normalize_oc_mtime(xmp_cre)
    if modified_raw:
        modified = parse_pdf_date(modified_raw)
    elif xmp_mod:
        modified = normalize_oc_mtime(xmp_mod)

    if not created and not modified:
        raise RuntimeError("no PDF CreationDate/ModDate/XMP dates")

    return EmbeddedDates(
        created=created or modified,
        modified=modified or created,
        source="pdf-info/xmp",
        note="CreationDate=%s ModDate=%s xmpC=%s xmpM=%s"
        % (created_raw, modified_raw, xmp_cre, xmp_mod),
    )


def read_mp4_dates(path: Path) -> EmbeddedDates:
    data = path.read_bytes()
    # Limit scan size for huge files: prefer moov; if not found in first 8MiB + last 8MiB, full read already done
    created_ts = None
    modified_ts = None
    for typ, payload_start, payload_end in _iter_isobmff_boxes(data):
        if typ not in (b"moov", b"uuid"):
            continue
        if typ != b"moov":
            continue
        for ctyp, cstart, cend in _iter_isobmff_boxes(data, payload_start, payload_end):
            if ctyp != b"mvhd":
                continue
            version = data[cstart]
            if version == 1:
                created_ts, modified_ts = struct.unpack(
                    ">QQ", data[cstart + 4 : cstart + 20]
                )
            else:
                created_ts, modified_ts = struct.unpack(
                    ">II", data[cstart + 4 : cstart + 12]
                )
            break
        if created_ts is not None:
            break
    if created_ts is None:
        raise RuntimeError("no mvhd in MP4/MOV")

    def qt_to_iso(ts: int) -> str:
        # 0 often means unset
        if not ts:
            return None  # type: ignore
        dt = _QT_EPOCH + timedelta(seconds=int(ts))
        return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

    created = qt_to_iso(created_ts) if created_ts else None
    modified = qt_to_iso(modified_ts) if modified_ts else None
    if not created and not modified:
        raise RuntimeError("mvhd timestamps empty")
    return EmbeddedDates(
        created=created or modified,
        modified=modified or created,
        source="mp4-mvhd",
        note="creation=%s modification=%s" % (created_ts, modified_ts),
    )


def extract_embedded_dates(
    path: Path, archive_name: str | None = None
) -> EmbeddedDates:
    suf = path.suffix.lower()
    label = archive_name or path.name

    if suf in _ODF_SUFFIXES:
        return read_odf_dates(path)

    if suf in _OOXML_SUFFIXES:
        return read_ooxml_dates(path)

    # Zip packages: try OOXML then ODF when suffix is missing/generic
    if zipfile.is_zipfile(path):
        try:
            return read_ooxml_dates(path)
        except Exception:
            pass
        try:
            return read_odf_dates(path)
        except Exception:
            pass
        if suf in _OOXML_SUFFIXES | _ODF_SUFFIXES:
            raise RuntimeError("zip package has no readable OOXML/ODF dates")

    if suf in _PDF_SUFFIXES:
        return read_pdf_dates(path)

    if suf in _IMAGE_SUFFIXES:
        return read_image_dates(path, archive_name=label)

    if suf in _MP4_SUFFIXES:
        return read_mp4_dates(path)

    # Content sniff
    head = path.read_bytes()[:12]
    if head.startswith(b"%PDF"):
        return read_pdf_dates(path)
    if head.startswith(b"\xff\xd8\xff") or head.startswith(b"\x89PNG"):
        return read_image_dates(path, archive_name=label)
    if len(head) >= 8 and head[4:8] == b"ftyp":
        return read_mp4_dates(path)

    raise RuntimeError("unsupported or undated format (%s)" % (suf or "unknown"))


def set_mtime_key(meta: dict, new_mtime: str) -> None:
    if b"user.oc.mtime" in meta:
        meta[b"user.oc.mtime"] = new_mtime.encode()
    elif "user.oc.mtime" in meta:
        meta["user.oc.mtime"] = new_mtime
    else:
        meta[b"user.oc.mtime"] = new_mtime.encode()
    meta.pop(b"user.oc.tmp.etag", None)
    meta.pop("user.oc.tmp.etag", None)


def process_one(
    mpk: Path,
    env: dict[str, str],
    field: str,
    apply: bool,
    posix_hint: Path | None = None,
    write_bak: bool = False,
) -> int:
    meta = unpack_mpk(mpk)
    name = gmeta(meta, "user.oc.name")
    blob = gmeta(meta, "user.oc.blobid")
    old = gmeta(meta, "user.oc.mtime")
    blobsize = gmeta(meta, "user.oc.blobsize")
    sid = space_id_from_path(mpk)
    sname = space_name(sid)

    local: Path | None = None
    origin = ""
    dates: EmbeddedDates | None = None
    with tempfile.TemporaryDirectory(prefix="oc-mtime-") as td_name:
        if posix_hint and posix_hint.is_file():
            local = posix_hint
            origin = "posix-hint"
        else:
            cand = find_posix_bytes(sid, str(name))
            if cand and cand.is_file():
                if blobsize is None or cand.stat().st_size == int(blobsize):
                    local = cand
                    origin = "posix-tree"
        if local is None:
            if not blob:
                print("SKIP %s (%s): no blobid and no local bytes" % (name, sname))
                return 1
            try:
                require_s3_env(env)
            except RuntimeError as e:
                print("SKIP %s (%s): %s" % (name, sname, e))
                return 1
            suf = Path(str(name)).suffix or ".bin"
            local = Path(td_name) / ("file" + suf)
            try:
                s3_download(env, blob_s3_key(sid, str(blob)), local)
            except RuntimeError as e:
                print("SKIP %s (%s): %s" % (name, sname, e))
                return 1
            origin = "s3"

        try:
            dates = extract_embedded_dates(local)
        except Exception as e:
            print("SKIP %s (%s): %s" % (name, sname, e))
            return 1

        # Capture display path before temp dir disappears
        bytes_path = str(local) if origin != "s3" else "(temp s3)"

        # Image/MP4 extractors may already return OC Zulu; OOXML usually still raw.
        raw = dates.created if field == "created" else dates.modified
        if not raw:
            raw = dates.modified or dates.created
        if not raw:
            print(
                "SKIP %s (%s): no %s date from %s"
                % (name, sname, field, dates.source)
            )
            return 1

        if re.match(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", raw):
            new = raw
        else:
            new = normalize_oc_mtime(raw)

        print("FILE   %s" % name)
        print("SPACE  %s (%s)" % (sname, sid))
        print("BYTES  via=%s path=%s" % (origin, bytes_path))
        print(
            "EMBED  source=%s created=%s modified=%s %s"
            % (dates.source, dates.created, dates.modified, dates.note)
        )
        print("OC     mtime=%s" % old)
        print("PLAN   set user.oc.mtime from %s:%s -> %s" % (dates.source, field, new))

        if old == new:
            print("RESULT already matches; nothing to write")
            return 0
        if not apply:
            print("RESULT dry-run only (pass --apply to write)")
            return 0

        bak_name = None
        if write_bak:
            bak = mpk.with_suffix(
                mpk.suffix
                + ".bak-"
                + datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
            )
            bak.write_bytes(mpk.read_bytes())
            bak_name = bak.name
        set_mtime_key(meta, new)
        tmp = mpk.with_suffix(mpk.suffix + ".tmp")
        tmp.write_bytes(pack_mpk(meta))
        os.replace(tmp, mpk)
        # OpenCloud runs as UID/GID 1000; keep node metadata owned correctly
        try:
            os.chown(mpk, 1000, 1000)
            os.chmod(mpk, 0o600)
        except OSError as e:
            print("WARN   chown/chmod mpk failed: %s" % e)
        verify = gmeta(unpack_mpk(mpk), "user.oc.mtime")
        if bak_name:
            print("RESULT wrote mpk; backup=%s; verify=%s" % (bak_name, verify))
        else:
            print("RESULT wrote mpk; verify=%s (no .bak; use volume backup)" % verify)
        print(
            "NOTE   external .mpk edits may not show in UI until OpenCloud "
            "reloads metadata (restart opencloud container or wait for cache expiry)"
        )
        return 0 if verify == new else 2

    # Unreachable; keep mypy quiet if flow changes
    return 1


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument(
        "name",
        nargs="?",
        default=None,
        help="Exact file name (omit when using -test)",
    )
    ap.add_argument("--space", help="Space id or display name filter", default=None)
    ap.add_argument(
        "-test",
        "--test",
        metavar="PATH",
        dest="test_path",
        default=None,
        help=(
            "Pilot: only the one file at this POSIX path under storage/users/users/"
            " (still dry-run unless --apply)"
        ),
    )
    ap.add_argument(
        "--from",
        dest="field",
        choices=("created", "modified"),
        default="modified",
        help="Which embedded date to copy into user.oc.mtime (default: modified)",
    )
    ap.add_argument("--apply", action="store_true", help="Write .mpk (default dry-run)")
    ap.add_argument(
        "--bak",
        action="store_true",
        help="With --apply, also write sibling .mpk.bak-<stamp> (default: off)",
    )
    args = ap.parse_args()

    if not SPACES.is_dir():
        print("ERROR: OpenCloud spaces path missing", file=sys.stderr)
        return 2

    env = load_env()
    space_filter = args.space
    name = args.name
    posix_hint: Path | None = None

    if args.test_path:
        try:
            posix_hint, name, space_id = resolve_test_path(args.test_path)
        except (OSError, ValueError) as e:
            print("ERROR: %s" % e, file=sys.stderr)
            return 2
        space_filter = space_id
        print("TEST   path=%s" % posix_hint)
        print("TEST   name=%s  space=%s" % (name, space_id))
        if args.space and args.space != space_id:
            print(
                "ERROR: --space %r conflicts with -test space %r"
                % (args.space, space_id),
                file=sys.stderr,
            )
            return 2
    elif not name:
        print("ERROR: provide a file name or -test PATH", file=sys.stderr)
        return 2

    hits = find_files(name, space_filter)
    if not hits:
        print("No live matches for %r" % name)
        return 1
    if args.test_path and len(hits) != 1:
        print(
            "ERROR: -test expected exactly 1 .mpk, found %d for %r in space %r"
            % (len(hits), name, space_filter),
            file=sys.stderr,
        )
        for h in hits:
            print("  %s" % h, file=sys.stderr)
        return 1
    print("Found %d match(es)\n" % len(hits))
    rc = 0
    for i, mpk in enumerate(hits):
        if i:
            print()
        rc = max(
            rc,
            process_one(
                mpk, env, args.field, args.apply, posix_hint, write_bak=args.bak
            ),
        )
    return rc


if __name__ == "__main__":
    sys.exit(main())
