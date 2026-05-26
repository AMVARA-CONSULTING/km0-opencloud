#!/bin/sh
set -eu

: "${DEX_ISSUER:?DEX_ISSUER required}"
: "${GOOGLE_CLIENT_ID:?GOOGLE_CLIENT_ID required}"
: "${GOOGLE_CLIENT_SECRET:?GOOGLE_CLIENT_SECRET required}"
: "${OPENCLOUD_WEB_CLIENT_ID:=opencloud-web}"

ISSUER_HOST="${DEX_ISSUER#https://}"
ISSUER_HOST="${ISSUER_HOST%%/*}"

cp /etc/dex/config.yaml.template /etc/dex/config.yaml

sed -i "s|ISSUER_PLACEHOLDER|${DEX_ISSUER}|g" /etc/dex/config.yaml
sed -i "s|ISSUER_HOST_PLACEHOLDER|${ISSUER_HOST}|g" /etc/dex/config.yaml
sed -i "s|GOOGLE_CLIENT_ID_PLACEHOLDER|${GOOGLE_CLIENT_ID}|g" /etc/dex/config.yaml
sed -i "s|GOOGLE_CLIENT_SECRET_PLACEHOLDER|${GOOGLE_CLIENT_SECRET}|g" /etc/dex/config.yaml
sed -i "s|OPENCLOUD_WEB_CLIENT_ID_PLACEHOLDER|${OPENCLOUD_WEB_CLIENT_ID}|g" /etc/dex/config.yaml

# Apple Sign In via generic OIDC connector (Dex v2.41 has no native "apple" type)
if [ -n "${APPLE_CLIENT_ID:-}" ] && [ -n "${APPLE_CLIENT_SECRET:-}" ]; then
  # YAML-safe single-quoted secret
  apple_secret=$(printf '%s' "${APPLE_CLIENT_SECRET}" | sed "s/'/''/g")
  cat >> /etc/dex/config.yaml <<EOF
  - type: oidc
    id: apple
    name: Apple
    config:
      issuer: https://appleid.apple.com
      clientID: ${APPLE_CLIENT_ID}
      clientSecret: '${apple_secret}'
      redirectURI: ${DEX_ISSUER}/callback
      scopes:
        - openid
        - email
        - name
      insecureSkipEmailVerified: true
      getUserInfo: true
EOF
fi

exec /usr/local/bin/dex serve /etc/dex/config.yaml
