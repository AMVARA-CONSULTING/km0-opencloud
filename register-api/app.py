#!/usr/bin/env python3
"""Minimal registration API — creates OpenCloud IDM users via Graph API."""

import base64
import json
import logging
import os
import re
import secrets
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
LISTEN_PORT = int(os.environ.get("PORT", "8091"))

MAIL_DOMAIN = os.environ.get("MAIL_DOMAIN", "km0digital.com")
MAIL_PROVISION_URL = os.environ.get(
    "MAIL_PROVISION_API_URL", "http://host.docker.internal:8092"
).rstrip("/")
MAIL_PROVISION_TOKEN = os.environ.get("MAIL_PROVISION_API_TOKEN", "")

ALLOWED_ORIGINS = frozenset(
    origin.strip()
    for origin in os.environ.get(
        "ALLOWED_ORIGINS",
        os.environ.get("ALLOWED_ORIGIN", "https://cloud.km0digital.com"),
    ).split(",")
    if origin.strip()
)

FREEMAIL_DOMAINS = frozenset(
    d.strip().lower()
    for d in os.environ.get(
        "FREEMAIL_DOMAINS",
        "gmail.com,googlemail.com,outlook.com,hotmail.com,live.com,yahoo.com,"
        "icloud.com,proton.me,protonmail.com,aol.com,gmx.com,mail.com,yandex.com",
    ).split(",")
    if d.strip()
)


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


def mail_request(method: str, path: str, data: dict | None = None) -> tuple[int, dict]:
    if not MAIL_PROVISION_TOKEN:
        return 503, {"error": "mail_provision_not_configured"}
    body = json.dumps(data or {}).encode() if data is not None else None
    req = urllib.request.Request(
        f"{MAIL_PROVISION_URL}{path}",
        data=body,
        method=method,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {MAIL_PROVISION_TOKEN}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            payload = json.loads(raw) if raw else {"error": "mail_provision_error"}
        except json.JSONDecodeError:
            payload = {"error": raw[:200] or "mail_provision_error"}
        return exc.code, payload
    except urllib.error.URLError as exc:
        log.warning("mail-provision-api unreachable: %s", exc.reason)
        return 503, {"error": "mail_provision_unreachable"}


def check_origin() -> bool:
    origin = request.headers.get("Origin")
    if not origin:
        return True
    return origin in ALLOWED_ORIGINS


def domain_of(email: str) -> str:
    return email.split("@", 1)[1].lower()


def is_freemail_domain(domain: str) -> bool:
    return domain.lower() in FREEMAIL_DOMAINS


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


def graph_create_user(email: str, password: str) -> tuple[int, str | None, str | None]:
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
            opencloud_uuid = None
            try:
                data = json.loads(body)
                opencloud_uuid = data.get("openCloudUUID") or data.get("id")
            except json.JSONDecodeError:
                pass
            return 201, None, opencloud_uuid
        code = graph_error_code(status, body)
        if code == "auth_failed":
            log.error(
                "Graph API auth failed (401) — set GRAPH_SERVICE_APP_TOKEN "
                "(password auth requires PROXY_ENABLE_BASIC_AUTH=true)"
            )
            return 503, "service_unavailable", None
        if code == "duplicate":
            return 409, "duplicate", None
        if code == "validation":
            return 400, "validation", None
        log.warning("Graph API error status=%s body=%s", status, body[:200])
        return 500, "internal", None
    except urllib.error.URLError as exc:
        log.warning("Graph API unreachable: %s", exc.reason)
        return 503, "service_unavailable", None
    except Exception:
        log.exception("Graph API request failed")
        return 500, "internal", None


def infer_mail_mode(mailbox_email: str) -> str:
    if domain_of(mailbox_email) == MAIL_DOMAIN.lower():
        return "km0"
    return "custom"


def validate_mail_request(
    login_email: str,
    data: dict,
) -> tuple[str | None, str | None, str | None, str | None]:
    """Returns (mailbox_email, mail_mode, contact_email, error_code)."""
    if not data.get("create_mail"):
        return None, None, None, None

    mailbox_email = (data.get("desired_email") or login_email).strip().lower()
    err = validate_email(mailbox_email)
    if err:
        return None, None, None, err

    mail_mode = (data.get("mail_mode") or infer_mail_mode(mailbox_email)).strip().lower()
    if mail_mode not in ("km0", "custom"):
        return None, None, None, "invalid_mail_mode"

    mailbox_domain = domain_of(mailbox_email)
    if mail_mode == "km0" and mailbox_domain != MAIL_DOMAIN.lower():
        return None, None, None, "invalid_domain"
    if mail_mode == "custom":
        if mailbox_domain == MAIL_DOMAIN.lower():
            return None, None, None, "invalid_domain"
        if is_freemail_domain(mailbox_domain):
            return None, None, None, "freemail_blocked"

    contact_email = (data.get("contact_email") or "").strip().lower() or None
    if contact_email:
        err = validate_email(contact_email)
        if err:
            return None, None, None, "invalid_contact_email"

    return mailbox_email, mail_mode, contact_email, None


def provision_mailbox(
    mailbox_email: str,
    password: str,
    opencloud_uuid: str | None,
    mail_mode: str,
    contact_email: str | None,
) -> tuple[bool, dict]:
    payload = {
        "email": mailbox_email,
        "desired_email": mailbox_email,
        "password": password,
        "mail_mode": mail_mode,
        "opencloud_uuid": opencloud_uuid,
        "send_verification": True,
    }
    if contact_email:
        payload["contact_email"] = contact_email

    status, body = mail_request("POST", "/provision", payload)
    if status in (200, 201):
        return True, body
    log.warning(
        "mail provision failed for %s status=%s body=%s",
        mailbox_email,
        status,
        body,
    )
    return False, body


@app.route("/health", methods=["GET"])
def health():
    configured = graph_configured()
    auth_ok = graph_auth_ok() if configured else False
    mail_ok = False
    if MAIL_PROVISION_TOKEN:
        status, body = mail_request("GET", "/health")
        mail_ok = status == 200 and body.get("ok") is True
    return jsonify(
        {
            "ok": True,
            "graph_configured": configured,
            "graph_auth_ok": auth_ok,
            "mail_provision_configured": bool(MAIL_PROVISION_TOKEN),
            "mail_provision_ok": mail_ok,
        }
    )


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

    mailbox_email, mail_mode, contact_email, mail_err = validate_mail_request(email, data)
    if mail_err:
        return jsonify({"error": mail_err}), 400

    if not graph_configured():
        log.error("GRAPH_SERVICE_USER and GRAPH_SERVICE_APP_TOKEN not configured")
        return jsonify({"error": "service_unavailable"}), 503

    if not graph_auth_ok():
        log.error("Graph API credentials rejected — run scripts/setup-register-api-graph-token.sh")
        return jsonify({"error": "service_unavailable"}), 503

    if mailbox_email and not MAIL_PROVISION_TOKEN:
        return jsonify({"error": "mail_provision_not_configured"}), 503

    status, reason, opencloud_uuid = graph_create_user(email, password)
    if status != 201:
        return jsonify({"error": reason or "internal"}), status

    response = {"ok": True}
    if mailbox_email:
        ok, mail_body = provision_mailbox(
            mailbox_email, password, opencloud_uuid, mail_mode, contact_email
        )
        response["mail"] = {
            "ok": ok,
            "email": mailbox_email,
            "mail_mode": mail_mode,
        }
        if ok:
            response["mail"].update(
                {
                    k: mail_body[k]
                    for k in ("status", "verification_status")
                    if k in mail_body
                }
            )
        else:
            response["mail"]["error"] = mail_body.get("error", "mail_provision_failed")
            log.error(
                "IDM user %s created but mail provision failed: %s",
                email,
                mail_body,
            )

    return jsonify(response), 201


@app.route("/update-password", methods=["POST"])
def update_password():
    if not check_origin():
        return jsonify({"error": "forbidden"}), 403

    if not MAIL_PROVISION_TOKEN:
        return jsonify({"error": "mail_provision_not_configured"}), 503

    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""

    err = validate_email(email)
    if err:
        return jsonify({"error": err}), 400
    err = validate_password(password)
    if err:
        return jsonify({"error": err}), 400

    status, body = mail_request(
        "POST",
        "/update-password",
        {"email": email, "password": password},
    )
    if status == 200:
        return jsonify({"ok": True, "email": email}), 200
    return jsonify({"error": body.get("error", "mail_update_failed")}), status


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=LISTEN_PORT)
