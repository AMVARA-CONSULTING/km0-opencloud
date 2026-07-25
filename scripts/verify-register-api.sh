#!/usr/bin/env bash
# Smoke test for register-api — catches Graph auth misconfiguration before deploy.
set -euo pipefail

BASE="${REGISTER_API_URL:-http://127.0.0.1:8091}"
FAIL=0

check() {
  local name="$1" cmd="$2" expect="$3"
  local out
  out="$(eval "$cmd" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -q "$expect"; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (got: ${out:-empty})" >&2
    FAIL=1
  fi
}

check "health reachable" "curl -sf '${BASE}/health'" '"ok":'
check "graph configured" "curl -sf '${BASE}/health'" '"graph_configured":'
check "graph auth ok" "curl -sf '${BASE}/health'" '"graph_auth_ok"[[:space:]]*:[[:space:]]*true'
check "mail provision ok" "curl -sf '${BASE}/health'" '"mail_provision_ok"[[:space:]]*:[[:space:]]*true'
check "invalid email → 400" \
  "curl -sf -w '%{http_code}' -o /tmp/reg-verify.json -X POST '${BASE}/register' -H 'Content-Type: application/json' -d '{\"email\":\"bad\",\"password\":\"x\"}'" \
  '400'
check "activate-mail no auth → 401" \
  "curl -sS -w '%{http_code}' -o /tmp/activate-verify.json -X POST '${BASE}/activate-mail' -H 'Content-Type: application/json' -d '{\"username\":\"demo\",\"password\":\"Test!234\"}'" \
  '401'
check "activate-mail bad bearer → 401" \
  "curl -sS -w '%{http_code}' -o /tmp/activate-verify.json -X POST '${BASE}/activate-mail' -H 'Content-Type: application/json' -H 'Authorization: Bearer not-a-real-token' -d '{\"username\":\"demo\",\"password\":\"Test!234\"}'" \
  '401'

# Regression #24/#26: activate-mail must not assign Graph mail = KM0 mailbox (OIDC rematch).
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PY="${REPO_ROOT}/register-api/app.py"
if [[ -f "$APP_PY" ]]; then
  if python3 - "$APP_PY" <<'PY'
import ast, sys
path = sys.argv[1]
tree = ast.parse(open(path, encoding="utf-8").read())
fn = next(
    (n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "activate_mail"),
    None,
)
if fn is None:
    print("activate_mail missing")
    sys.exit(1)
# Fail if activate_mail assigns patch["mail"] = mailbox_email (KM0 rewrite).
src = ast.get_source_segment(open(path, encoding="utf-8").read(), fn) or ""
# Allow restoring freemail via contact_email; forbid setting mail to mailbox_email variable.
bad = False
for node in ast.walk(fn):
    if not isinstance(node, ast.Assign):
        continue
    for t in node.targets:
        if (
            isinstance(t, ast.Subscript)
            and isinstance(t.value, ast.Name)
            and t.value.id == "patch"
            and isinstance(t.slice, ast.Constant)
            and t.slice.value == "mail"
        ):
            # RHS must not be Name mailbox_email
            if isinstance(node.value, ast.Name) and node.value.id == "mailbox_email":
                bad = True
if bad:
    print("patch mail=mailbox_email")
    sys.exit(1)
if "graph_mail_preserved" not in src:
    print("missing graph_mail_preserved marker")
    sys.exit(1)
print("ok")
PY
  then
    echo "PASS: activate-mail does not rewrite Graph mail to KM0 mailbox (#24/#26)"
  else
    echo "FAIL: activate-mail Graph mail rewrite regression (#24/#26)" >&2
    FAIL=1
  fi
else
  echo "FAIL: register-api/app.py not found for #24 regression" >&2
  FAIL=1
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "register-api verification failed. Run: ./scripts/setup-register-api-graph-token.sh" >&2
  exit 1
fi

echo "All register-api checks passed."
