#!/bin/sh
# Generate Apple OIDC client secret (JWT) for Dex — valid ~6 months.
# Usage: APPLE_TEAM_ID=... APPLE_KEY_ID=... APPLE_CLIENT_ID=... ./generate-apple-client-secret.sh /path/to/AuthKey.p8
set -eu
KEY_FILE="${1:?AuthKey .p8 path required}"
: "${APPLE_TEAM_ID:?}"
: "${APPLE_KEY_ID:?}"
: "${APPLE_CLIENT_ID:?}"

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl required" >&2
  exit 1
fi

# Requires python3 with PyJWT or use ruby/openssl — minimal JWT via python3
python3 <<PY
import json, time, sys
try:
    import jwt
except ImportError:
    sys.exit("pip install pyjwt cryptography (or add Apple secret manually in Dex)")

with open("${KEY_FILE}", "r") as f:
    key = f.read()

now = int(time.time())
payload = {
    "iss": "${APPLE_TEAM_ID}",
    "iat": now,
    "exp": now + 86400 * 180,
    "aud": "https://appleid.apple.com",
    "sub": "${APPLE_CLIENT_ID}",
}
headers = {"alg": "ES256", "kid": "${APPLE_KEY_ID}"}
token = jwt.encode(payload, key, algorithm="ES256", headers=headers)
print(token)
PY
