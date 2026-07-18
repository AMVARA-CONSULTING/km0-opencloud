#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUTH_SITE="${AUTH_SITE:-/opt/km0-auth/nginx/sites-available/auth}"
DOMAIN="auth.km0digital.com"
WEBROOT="/var/www/certbot"
ACME_EMAIL="${ACME_EMAIL:-admin@amvara.de}"
EXPECTED_IP="$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || curl -fsS --max-time 5 https://icanhazip.com)"

resolved="$(dig +short "@8.8.8.8" "${DOMAIN}" A | head -1 || true)"
[[ -n "${resolved}" ]] || { echo "DNS missing for ${DOMAIN}" >&2; exit 1; }
[[ "${resolved}" == "${EXPECTED_IP}" ]] || { echo "DNS ${resolved} != ${EXPECTED_IP}" >&2; exit 1; }

BOOT="/etc/nginx/sites-available/auth-bootstrap"
if [[ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
  cat > "${BOOT}" <<'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name auth.km0digital.com;
    root /var/www/km0-auth;
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        allow all;
        try_files $uri =404;
    }
    location / { try_files $uri $uri/ /index.html; }
}
EOF
  ln -sf "${BOOT}" /etc/nginx/sites-enabled/auth
  nginx -t && systemctl reload nginx
fi

certbot certonly --webroot -w "${WEBROOT}" \
  -d "${DOMAIN}" \
  --email "${ACME_EMAIL}" \
  --agree-tos --no-eff-email --non-interactive

install -D -m 0644 "${AUTH_SITE}" /etc/nginx/sites-available/auth
ln -sf /etc/nginx/sites-available/auth /etc/nginx/sites-enabled/auth
rm -f "${BOOT}"
nginx -t && systemctl reload nginx
echo "TLS active for https://${DOMAIN}/"
