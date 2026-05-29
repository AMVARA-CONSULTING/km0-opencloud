#!/usr/bin/env bash
# Issue Let's Encrypt certs for collabora.km0digital.com and wopi.km0digital.com,
# install nginx site templates, and reload nginx.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEBROOT="/var/www/certbot"
ACME_EMAIL="${ACME_EMAIL:-admin@amvara.de}"
EXPECTED_IP="$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || curl -fsS --max-time 5 https://icanhazip.com)"

DOMAINS=(collabora.km0digital.com wopi.km0digital.com)

for domain in "${DOMAINS[@]}"; do
  resolved="$(dig +short "@8.8.8.8" "${domain}" A | head -1 || true)"
  if [[ -z "${resolved}" ]]; then
    echo "DNS A record missing for ${domain}." >&2
    echo "Create: ${domain} A ${EXPECTED_IP}, then re-run this script." >&2
    exit 1
  fi
  if [[ "${resolved}" != "${EXPECTED_IP}" ]]; then
    echo "DNS for ${domain} is ${resolved}, expected ${EXPECTED_IP}." >&2
    exit 1
  fi
  echo "DNS OK (${domain} → ${resolved})"
done

echo "Requesting certificates..."
for domain in "${DOMAINS[@]}"; do
  certbot certonly --webroot -w "${WEBROOT}" \
    -d "${domain}" \
    --email "${ACME_EMAIL}" \
    --agree-tos --no-eff-email --non-interactive
done

install -D -m 0644 "${REPO_ROOT}/nginx/snippets/collabora-proxy.conf" \
  /etc/nginx/snippets/collabora-proxy.conf
install -D -m 0644 "${REPO_ROOT}/nginx/sites-available/collabora" \
  /etc/nginx/sites-available/collabora
install -D -m 0644 "${REPO_ROOT}/nginx/sites-available/wopi" \
  /etc/nginx/sites-available/wopi

ln -sfn /etc/nginx/sites-available/collabora /etc/nginx/sites-enabled/collabora
ln -sfn /etc/nginx/sites-available/wopi /etc/nginx/sites-enabled/wopi

nginx -t
systemctl reload nginx

for domain in "${DOMAINS[@]}"; do
  echo "TLS active for https://${domain}/"
  openssl x509 -in "/etc/letsencrypt/live/${domain}/fullchain.pem" -noout -dates -issuer
done
