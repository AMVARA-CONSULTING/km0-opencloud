#!/bin/bash
# Configure Apple Sign In for Dex → OpenCloud.
# Usage:
#   1. Place credentials in /opt/apple-signin-credentials.json (see example)
#   2. Run: sudo /opt/opencloud/dex/setup-apple.sh
set -euo pipefail

DEX_DIR="/opt/opencloud/dex"
CREDS_FILE="${APPLE_CREDS_FILE:-/opt/apple-signin-credentials.json}"
ENV_FILE="${DEX_DIR}/.env"

if [ ! -f "$CREDS_FILE" ]; then
  echo "Missing $CREDS_FILE" >&2
  echo "Copy /opt/apple-signin-credentials.example.json and fill in Apple Developer values." >&2
  exit 1
fi

read_cred() {
  python3 - "$CREDS_FILE" "$1" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
key = sys.argv[2]
val = data.get(key) or (data.get("web") or {}).get(key)
if not val:
    sys.exit(f"Missing key: {key}")
print(val.strip())
PY
}

APPLE_CLIENT_ID="$(read_cred services_id)"
APPLE_TEAM_ID="$(read_cred team_id)"
APPLE_KEY_ID="$(read_cred key_id)"
KEY_PATH="$(read_cred private_key_file)"

if [ ! -f "$KEY_PATH" ]; then
  echo "Private key not found: $KEY_PATH" >&2
  exit 1
fi

install -m 600 "$KEY_PATH" "${DEX_DIR}/apple-key.p8"

echo "Generating Apple client secret JWT (valid ~180 days)..."
APPLE_CLIENT_SECRET="$(
  docker run --rm \
    -v "${DEX_DIR}/apple-key.p8:/key.p8:ro" \
    -e APPLE_TEAM_ID -e APPLE_KEY_ID -e APPLE_CLIENT_ID \
    python:3.12-alpine sh -c '
      pip install -q pyjwt cryptography >/dev/null 2>&1
      python3 - <<PY
import jwt, time
with open("/key.p8") as f:
    key = f.read()
now = int(time.time())
print(jwt.encode(
    {"iss": "'"${APPLE_TEAM_ID}"'", "iat": now, "exp": now + 86400 * 180,
     "aud": "https://appleid.apple.com", "sub": "'"${APPLE_CLIENT_ID}"'"},
    key, algorithm="ES256", headers={"alg": "ES256", "kid": "'"${APPLE_KEY_ID}"'"},
))
PY
    '
)"

# Update dex .env (preserve other lines)
update_env() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
}

update_env APPLE_CLIENT_ID "$APPLE_CLIENT_ID"
update_env APPLE_TEAM_ID "$APPLE_TEAM_ID"
update_env APPLE_KEY_ID "$APPLE_KEY_ID"
update_env APPLE_CLIENT_SECRET "$APPLE_CLIENT_SECRET"
chmod 600 "$ENV_FILE"

echo "Restarting Dex..."
cd "$DEX_DIR"
docker compose up -d
sleep 2

if docker logs opencloud-dex 2>&1 | tail -20 | grep -q 'connector_id":"apple"'; then
  echo "Apple connector registered."
else
  echo "Warning: Apple connector not found in Dex logs. Check: docker logs opencloud-dex" >&2
fi

if curl -fsS "https://cloud.km0.amvara.de/dex/auth?client_id=opencloud-web&redirect_uri=https%3A%2F%2Fcloud.km0.amvara.de%2Foidc-callback.html&response_type=code&scope=openid+profile+email&state=test&code_challenge=E9Melhoa2OwvFrEMTIguAEAOvqlb6vJxRFnGlK4K3k&code_challenge_method=S256" 2>/dev/null | grep -q Apple; then
  echo "Dex login page lists Apple."
else
  echo "Open https://cloud.km0.amvara.de/ and confirm Apple appears on the login screen."
fi

echo ""
echo "Apple Developer — Services ID Return URL must include:"
echo "  https://cloud.km0.amvara.de/dex/callback"
echo ""
echo "Done. Re-test login at https://cloud.km0.amvara.de/"
