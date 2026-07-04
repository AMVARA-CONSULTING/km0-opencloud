#!/usr/bin/env python3
"""Minimal registration API — creates OpenCloud IDM users via Graph API."""

import base64
import json
import logging
import os
import re
import urllib.error
import urllib.request

from flask import Flask, jsonify, request

app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
log = logging.getLogger("register-api")

EMAIL_RE = re.compile(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")
SPECIAL_RE = re.compile(r'[!@#$%^&*(),.?":{}|<>\[\]\\/_+=\-~`]')

MIN_LEN = int(os.environ.get("MIN_PASSWORD_LENGTH", "8"))
MIN_SPECIAL = int(os.environ.get("MIN_SPECIAL_CHARACTERS", "1"))
GRAPH_URL = os.environ.get("GRAPH_BASE_URL", "http://127.0.0.1:9200").rstrip("/")
GRAPH_USER = os.environ.get("GRAPH_SERVICE_USER", "")
GRAPH_APP_TOKEN = os.environ.get("GRAPH_SERVICE_APP_TOKEN", "")
GRAPH_PASS = os.environ.get("GRAPH_SERVICE_PASSWORD", "")
ALLOWED_ORIGIN = os.environ.get("ALLOWED_ORIGIN", "https://cloud.km0digital.com")
LISTEN_PORT = int(os.environ.get("PORT", "8091"))


def graph_secret() -> str:
    """App token (production) or password (dev only when PROXY_ENABLE_BASIC_AUTH=true)."""
    return GRAPH_APP_TOKEN or GRAPH_PASS


def graph_configured() -> bool:
    return bool(GRAPH_USER and graph_secret())


def graph_auth_header() -> str:
    creds = f"{GRAPH_USER}:{graph_secret()}"
    return "Basic " + base64.b64encode(creds.encode()).decode()


def graph_request(method: str, path: str, data: bytes | None = None) -> tuple[int, str]:
    req = urllib.request.Request(
        f"{GRAPH_URL}{path}",
        data=data,
        method=method,
        headers={
            "Content-Type": "application/json",
            "Authorization": graph_auth_header(),
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", errors="replace")


def check_origin() -> bool:
    origin = request.headers.get("Origin")
    if origin and origin != ALLOWED_ORIGIN:
        return False
    return True


def validate_email(email: str) -> str | None:
    if not email or not EMAIL_RE.match(email):
        return "invalid_email"
    if len(email) > 254:
        return "invalid_email"
    return None


def validate_password(password: str) -> str | None:
    if len(password) < MIN_LEN:
        return "password_too_short"
    if MIN_SPECIAL and len(SPECIAL_RE.findall(password)) < MIN_SPECIAL:
        return "password_needs_special"
    return None


def display_name_from_email(email: str) -> str:
    local = email.split("@", 1)[0]
    name = local.replace(".", " ").replace("_", " ").strip()
    return name.title() if name else email


def graph_auth_ok() -> bool:
    if not graph_configured():
        return False
    status, _ = graph_request("GET", "/graph/v1.0/me")
    return status == 200


def graph_error_code(status: int, body: str) -> str:
    """Map Graph API response to a stable register-api error code."""
    body_lower = body.lower()
    if status in (409, 422) or "already exists" in body_lower or "namealreadyexists" in body_lower:
        return "duplicate"
    if status == 400:
        try:
            data = json.loads(body)
            err = data.get("error", {})
            if isinstance(err, dict):
                code = str(err.get("code", "")).lower()
                message = str(err.get("message", "")).lower()
                if "alreadyexists" in code or "conflict" in code or "already exists" in message:
                    return "duplicate"
        except (json.JSONDecodeError, TypeError, AttributeError):
            pass
        return "validation"
    if status == 401:
        return "auth_failed"
    if status >= 500:
        return "graph_error"
    return "graph_error"


def graph_create_user(email: str, password: str) -> tuple[int, str | None]:
    payload = json.dumps(
        {
            "displayName": display_name_from_email(email),
            "mail": email,
            "onPremisesSamAccountName": email,
            "passwordProfile": {"password": password},
        }
    ).encode()

    try:
        status, body = graph_request("POST", "/graph/v1.0/users", payload)
        if status == 201:
            return 201, None
        code = graph_error_code(status, body)
        if code == "auth_failed":
            log.error(
                "Graph API auth failed (401) — set GRAPH_SERVICE_APP_TOKEN "
                "(password auth requires PROXY_ENABLE_BASIC_AUTH=true)"
            )
            return 503, "service_unavailable"
        if code == "duplicate":
            return 409, "duplicate"
        if code == "validation":
            return 400, "validation"
        log.warning("Graph API error status=%s body=%s", status, body[:200])
        return 500, "internal"
    except urllib.error.URLError as exc:
        log.warning("Graph API unreachable: %s", exc.reason)
        return 503, "service_unavailable"
    except Exception:
        log.exception("Graph API request failed")
        return 500, "internal"


@app.route("/health", methods=["GET"])
def health():
    configured = graph_configured()
    auth_ok = graph_auth_ok() if configured else False
    return jsonify({"ok": True, "graph_configured": configured, "graph_auth_ok": auth_ok})


@app.route("/register", methods=["POST"])
def register():
    if not check_origin():
        return jsonify({"error": "forbidden"}), 403

    if request.content_type and "application/json" not in request.content_type:
        return jsonify({"error": "invalid_content_type"}), 400

    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""

    err = validate_email(email)
    if err:
        return jsonify({"error": err}), 400

    err = validate_password(password)
    if err:
        return jsonify({"error": err}), 400

    if not graph_configured():
        log.error("GRAPH_SERVICE_USER and GRAPH_SERVICE_APP_TOKEN not configured")
        return jsonify({"error": "service_unavailable"}), 503

    if not graph_auth_ok():
        log.error("Graph API credentials rejected — run scripts/setup-register-api-graph-token.sh")
        return jsonify({"error": "service_unavailable"}), 503

    status, reason = graph_create_user(email, password)
    if status == 201:
        return jsonify({"ok": True}), 201
    return jsonify({"error": reason or "internal"}), status


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=LISTEN_PORT)
