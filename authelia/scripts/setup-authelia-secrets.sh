#!/usr/bin/env bash
# Genera/reutiliza los secretos de Authelia y renderiza configuration.gen.yml.
#
# Idempotente: los secretos se persisten en secrets/authelia.secrets.env y se
# reutilizan en ejecuciones posteriores (no rotan salvo --rotate).
#
# Requisitos de entrada (LDAP bind pw y SMTP):
#   - LDAP: se toma de AUTHELIA_LDAP_PASSWORD, o de /opt/opencloud/dex/.env
#     (OPENCLOUD_IDM_BIND_PW), o de opencloud.yaml idm_password.
#   - SMTP: SMTP_USERNAME / SMTP_PASSWORD (buzón noreply@km0digital.com).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS_DIR="${ROOT}/secrets"
SECRETS_ENV="${SECRETS_DIR}/authelia.secrets.env"
JWKS_KEY="${SECRETS_DIR}/oidc.jwks.key.pem"
TEMPLATE="${ROOT}/configuration.yml"
RENDERED="${ROOT}/configuration.gen.yml"
ENV_FILE="${ROOT}/.env"
DEX_ENV="${DEX_ENV:-/opt/opencloud/dex/.env}"
ROTATE=0

for arg in "$@"; do
  case "$arg" in
    --rotate) ROTATE=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

mkdir -p "${SECRETS_DIR}"
chmod 700 "${SECRETS_DIR}"

rand_hex() { openssl rand -hex 32; }

# 1) Secretos persistentes (generar solo si faltan o --rotate).
if [[ ! -f "${SECRETS_ENV}" || "${ROTATE}" -eq 1 ]]; then
  cat > "${SECRETS_ENV}" <<EOF
SESSION_SECRET=$(rand_hex)
STORAGE_ENCRYPTION_KEY=$(rand_hex)
OIDC_HMAC_SECRET=$(rand_hex)
RESET_JWT_SECRET=$(rand_hex)
REDIS_PASSWORD=$(rand_hex)
OIDC_DEX_CLIENT_SECRET=$(rand_hex)
EOF
  chmod 600 "${SECRETS_ENV}"
  echo "Generados secretos en ${SECRETS_ENV}"
fi
# shellcheck disable=SC1090
source "${SECRETS_ENV}"

# 2) Clave RSA para firmar tokens OIDC (JWKS).
if [[ ! -f "${JWKS_KEY}" || "${ROTATE}" -eq 1 ]]; then
  openssl genrsa -out "${JWKS_KEY}" 2048 >/dev/null 2>&1
  chmod 600 "${JWKS_KEY}"
  echo "Generada clave OIDC en ${JWKS_KEY}"
fi

# 3) LDAP bind password.
ldap_pw="${AUTHELIA_LDAP_PASSWORD:-}"
if [[ -z "${ldap_pw}" && -f "${DEX_ENV}" ]]; then
  ldap_pw="$(grep -E '^OPENCLOUD_IDM_BIND_PW=' "${DEX_ENV}" | head -1 | cut -d= -f2- || true)"
fi
if [[ -z "${ldap_pw}" ]]; then
  echo "ERROR: falta la password de bind LDAP. Exporta AUTHELIA_LDAP_PASSWORD o define OPENCLOUD_IDM_BIND_PW en ${DEX_ENV}." >&2
  exit 1
fi

# 4) SMTP (recuperación por email).
smtp_user="${SMTP_USERNAME:-noreply@km0digital.com}"
smtp_pass="${SMTP_PASSWORD:-}"
if [[ -z "${smtp_pass}" ]]; then
  echo "AVISO: SMTP_PASSWORD vacío — el arranque de Authelia fallará la verificación SMTP." >&2
  echo "       Crea el buzón noreply@km0digital.com y re-ejecuta con SMTP_PASSWORD=..." >&2
fi

# 5) Render configuration.gen.yml (sed con delimitador | y escape seguro).
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# Hash pbkdf2 del secreto de cliente OIDC (Authelia deprecia el texto plano).
# Dex sigue usando el secreto EN PLANO; Authelia guarda solo el hash.
AUTHELIA_IMAGE="${AUTHELIA_IMAGE:-authelia/authelia:4.38}"
hash_client_secret() {
  if command -v docker >/dev/null 2>&1; then
    local out
    out=$(docker run --rm "${AUTHELIA_IMAGE}" authelia crypto hash generate pbkdf2 \
      --variant sha512 --password "$1" 2>/dev/null | awk -F': ' '/Digest/{print $2}')
    if [ -n "${out}" ]; then printf '%s' "${out}"; return 0; fi
  fi
  echo "AVISO: docker no disponible — usando client_secret en texto plano (deprecado)." >&2
  printf '$plaintext$%s' "$1"
}
client_secret_hash="$(hash_client_secret "${OIDC_DEX_CLIENT_SECRET}")"

cp "${TEMPLATE}" "${RENDERED}"
sed -i \
  -e "s|__SESSION_SECRET__|$(esc "${SESSION_SECRET}")|g" \
  -e "s|__STORAGE_ENCRYPTION_KEY__|$(esc "${STORAGE_ENCRYPTION_KEY}")|g" \
  -e "s|__OIDC_HMAC_SECRET__|$(esc "${OIDC_HMAC_SECRET}")|g" \
  -e "s|__RESET_JWT_SECRET__|$(esc "${RESET_JWT_SECRET}")|g" \
  -e "s|__REDIS_PASSWORD__|$(esc "${REDIS_PASSWORD}")|g" \
  -e "s|__LDAP_BIND_PW__|$(esc "${ldap_pw}")|g" \
  -e "s|__SMTP_USERNAME__|$(esc "${smtp_user}")|g" \
  -e "s|__SMTP_PASSWORD__|$(esc "${smtp_pass}")|g" \
  -e "s|__OIDC_DEX_CLIENT_SECRET_HASH__|$(esc "${client_secret_hash}")|g" \
  "${RENDERED}"

# La clave OIDC (JWKS) debe ir EN LÍNEA en el YAML (bloque literal `key: |`).
# Inyectamos el PEM indentado 10 espacios y borramos el placeholder.
INDENTED_KEY="$(mktemp)"
awk '{ print "          " $0 }' "${JWKS_KEY}" > "${INDENTED_KEY}"
sed -i -e "/__OIDC_JWKS_KEY_PEM__/{
  r ${INDENTED_KEY}
  d
}" "${RENDERED}"
rm -f "${INDENTED_KEY}"

chmod 600 "${RENDERED}"
echo "Renderizado ${RENDERED}"

# 6) .env para docker compose (solo la password de Redis).
cat > "${ENV_FILE}" <<EOF
AUTHELIA_REDIS_PASSWORD=${REDIS_PASSWORD}
EOF
chmod 600 "${ENV_FILE}"

# 7) Copiar branding KM0 al portal si existe el tema de Dex.
if [[ -f /opt/opencloud/dex/web/themes/km0/logo.png ]]; then
  cp /opt/opencloud/dex/web/themes/km0/logo.png "${ROOT}/assets/logo.png" || true
fi

echo
echo "=== SIGUIENTE PASO (Dex) ==="
echo "Añade este secreto al conector 'authelia' en /opt/opencloud/dex/.env:"
echo "  AUTHELIA_OIDC_CLIENT_SECRET=${OIDC_DEX_CLIENT_SECRET}"
echo "y aplica: cd /opt/opencloud/dex && docker compose up -d"
