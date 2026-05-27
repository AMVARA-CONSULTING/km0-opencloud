#!/bin/sh
set -eu

: "${DEX_ISSUER:?DEX_ISSUER required}"
: "${GOOGLE_CLIENT_ID:?GOOGLE_CLIENT_ID required}"
: "${GOOGLE_CLIENT_SECRET:?GOOGLE_CLIENT_SECRET required}"
: "${OPENCLOUD_WEB_CLIENT_ID:=opencloud-web}"

ISSUER_HOST="${DEX_ISSUER#https://}"
ISSUER_HOST="${ISSUER_HOST%%/*}"

cp /etc/dex/config.yaml.template /etc/dex/config.yaml

# OpenCloud IDM LDAP CA (generated on first opencloud init)
if [ -f /opencloud-data/idm/ldap.crt ]; then
  cp /opencloud-data/idm/ldap.crt /etc/dex/opencloud-idm-ldap.crt
elif [ ! -f /etc/dex/opencloud-idm-ldap.crt ]; then
  echo "opencloud-idm ldap.crt not found under /opencloud-data/idm/" >&2
  exit 1
fi

# IDM bind password: dex/.env OPENCLOUD_IDM_BIND_PW or opencloud.yaml idm_password
if [ -z "${OPENCLOUD_IDM_BIND_PW:-}" ] && [ -f /etc/opencloud-config/opencloud.yaml ]; then
  OPENCLOUD_IDM_BIND_PW=$(awk '/^idm:/{f=1} f&&/^[a-z]/&&!/^idm:/{exit} f&&/idm_password:/{print $2; exit}' /etc/opencloud-config/opencloud.yaml)
fi
: "${OPENCLOUD_IDM_BIND_PW:?OPENCLOUD_IDM_BIND_PW or opencloud.yaml idm_password required for LDAP login}"

OPENCLOUD_LDAP_HOST="${OPENCLOUD_LDAP_HOST:-opencloud}"
# YAML single-quoted; escape ' for YAML and \& for sed replacement (& in password breaks sed)
ldap_bind_pw=$(printf '%s' "${OPENCLOUD_IDM_BIND_PW}" | sed "s/'/''/g" | sed 's/[&/\]/\\&/g')

sed -i "s|ISSUER_PLACEHOLDER|${DEX_ISSUER}|g" /etc/dex/config.yaml
sed -i "s|ISSUER_HOST_PLACEHOLDER|${ISSUER_HOST}|g" /etc/dex/config.yaml
sed -i "s|GOOGLE_CLIENT_ID_PLACEHOLDER|${GOOGLE_CLIENT_ID}|g" /etc/dex/config.yaml
sed -i "s|GOOGLE_CLIENT_SECRET_PLACEHOLDER|${GOOGLE_CLIENT_SECRET}|g" /etc/dex/config.yaml
sed -i "s|OPENCLOUD_WEB_CLIENT_ID_PLACEHOLDER|${OPENCLOUD_WEB_CLIENT_ID}|g" /etc/dex/config.yaml
sed -i "s|OPENCLOUD_LDAP_HOST_PLACEHOLDER|${OPENCLOUD_LDAP_HOST}|g" /etc/dex/config.yaml
sed -i "s|OPENCLOUD_IDM_BIND_PW_PLACEHOLDER|'${ldap_bind_pw}'|g" /etc/dex/config.yaml

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
