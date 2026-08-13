#!/usr/bin/env bash
# Emite el certificado TLS de id.km0digital.com y activa el vhost de Authelia.
set -euo pipefail

ID_SITE="${ID_SITE:-/opt/opencloud/authelia/nginx/sites-available/id}"
DOMAIN="id.km0digital.com"
WEBROOT="/var/www/certbot"
ACME_EMAIL="${ACME_EMAIL:-admin@amvara.de}"
EXPECTED_IP="$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || curl -fsS --max-time 5 https://icanhazip.com)"

resolved="$(dig +short "@8.8.8.8" "${DOMAIN}" A | head -1 || true)"
[[ -n "${resolved}" ]] || { echo "DNS missing for ${DOMAIN}" >&2; exit 1; }
[[ "${resolved}" == "${EXPECTED_IP}" ]] || { echo "DNS ${resolved} != ${EXPECTED_IP}" >&2; exit 1; }

BOOT="/etc/nginx/sites-available/id-bootstrap"
if [[ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
  cat > "${BOOT}" <<'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name id.km0digital.com;
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        allow all;
        try_files $uri =404;
    }
    location / { return 404; }
}
EOF
  ln -sf "${BOOT}" /etc/nginx/sites-enabled/id
  nginx -t && systemctl reload nginx
fi

certbot certonly --webroot -w "${WEBROOT}" \
  -d "${DOMAIN}" \
  --email "${ACME_EMAIL}" \
  --agree-tos --no-eff-email --non-interactive

install -D -m 0644 "${ID_SITE}" /etc/nginx/sites-available/id
ln -sf /etc/nginx/sites-available/id /etc/nginx/sites-enabled/id
rm -f "${BOOT}"
nginx -t && systemctl reload nginx
echo "TLS active for https://${DOMAIN}/"
