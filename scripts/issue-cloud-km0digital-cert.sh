#!/usr/bin/env bash
# Issue Let's Encrypt cert for cloud.km0digital.com and activate nginx TLS paths.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOMAIN="cloud.km0digital.com"
WEBROOT="/var/www/certbot"
NGINX_SITE="${REPO_ROOT}/nginx/sites-available/opencloud"
ACME_EMAIL="${ACME_EMAIL:-admin@amvara.de}"
EXPECTED_IP="$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || curl -fsS --max-time 5 https://icanhazip.com)"

resolved="$(dig +short "@8.8.8.8" "${DOMAIN}" A | head -1 || true)"
if [[ -z "${resolved}" ]]; then
  echo "DNS A record missing for ${DOMAIN}." >&2
  echo "Create: ${DOMAIN} A ${EXPECTED_IP} (at Joker / km0digital.com zone), then re-run this script." >&2
  exit 1
fi
if [[ "${resolved}" != "${EXPECTED_IP}" ]]; then
  echo "DNS for ${DOMAIN} is ${resolved}, expected ${EXPECTED_IP}." >&2
  exit 1
fi

echo "DNS OK (${DOMAIN} → ${resolved}). Requesting certificate..."
certbot certonly --webroot -w "${WEBROOT}" \
  -d "${DOMAIN}" \
  --email "${ACME_EMAIL}" \
  --agree-tos --no-eff-email --non-interactive

install -D -m 0644 "${NGINX_SITE}" /etc/nginx/sites-available/opencloud
nginx -t
systemctl reload nginx

echo "TLS active for https://${DOMAIN}/"
openssl x509 -in "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" -noout -dates -issuer
