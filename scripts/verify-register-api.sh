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
check "graph auth ok" "curl -sf '${BASE}/health'" '"graph_auth_ok":'
check "invalid email → 400" \
  "curl -sf -w '%{http_code}' -o /tmp/reg-verify.json -X POST '${BASE}/register' -H 'Content-Type: application/json' -d '{\"email\":\"bad\",\"password\":\"x\"}'" \
  '400'

if [[ "$FAIL" -ne 0 ]]; then
  echo "register-api verification failed. Run: ./scripts/setup-register-api-graph-token.sh" >&2
  exit 1
fi

echo "All register-api checks passed."
