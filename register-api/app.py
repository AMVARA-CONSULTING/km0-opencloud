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
GRAPH_PASS = os.environ.get("GRAPH_SERVICE_PASSWORD", "")
ALLOWED_ORIGIN = os.environ.get("ALLOWED_ORIGIN", "https://cloud.km0digital.com")
LISTEN_PORT = int(os.environ.get("PORT", "8091"))


def graph_configured() -> bool:
    return bool(GRAPH_USER and GRAPH_PASS)


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


def graph_create_user(email: str, password: str) -> tuple[int, str | None]:
    payload = json.dumps(
        {
            "displayName": display_name_from_email(email),
            "mail": email,
            "onPremisesSamAccountName": email,
            "passwordProfile": {"password": password},
        }
    ).encode()

    auth = base64.b64encode(f"{GRAPH_USER}:{GRAPH_PASS}".encode()).decode()
    req = urllib.request.Request(
        f"{GRAPH_URL}/graph/v1.0/users",
        data=payload,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Basic {auth}",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, None
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace").lower()
        if exc.code in (409, 422) or "already exists" in body or "namealreadyexists" in body:
            return 409, "duplicate"
        if exc.code == 400:
            return 400, "validation"
        log.warning("Graph API error status=%s", exc.code)
        return 500, "graph_error"
    except urllib.error.URLError as exc:
        log.warning("Graph API unreachable: %s", exc.reason)
        return 503, "unavailable"
    except Exception:
        log.exception("Graph API request failed")
        return 500, "graph_error"


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"ok": True, "graph_configured": graph_configured()})


@app.route("/register", methods=["POST"])
def register():
    if not check_origin():
        return jsonify({"error": "forbidden"}), 403

    if not graph_configured():
        log.error("GRAPH_SERVICE_USER/PASSWORD not configured")
        return jsonify({"error": "service_unavailable"}), 503

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

    status, reason = graph_create_user(email, password)
    if status == 201:
        return jsonify({"ok": True}), 201
    if status == 409:
        return jsonify({"error": "duplicate"}), 409
    if status == 400:
        return jsonify({"error": "validation"}), 400
    if status == 503:
        return jsonify({"error": "service_unavailable"}), 503
    return jsonify({"error": "internal"}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=LISTEN_PORT)
