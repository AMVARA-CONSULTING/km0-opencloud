#!/usr/bin/env bash
# HTTP smoke checks for KM0 authentication pages (no Node required).
set -euo pipefail

BASE_URL="${KM0_AUTH_BASE_URL:-https://cloud.km0digital.com}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

check_status() {
  local path="$1"
  local expected="${2:-200}"
  local code
  code="$(curl -sS -o /tmp/km0-auth-body.html -w '%{http_code}' "${BASE_URL}${path}")"
  [[ "$code" == "$expected" ]] || fail "${path} returned HTTP ${code}, expected ${expected}"
  pass "${path} HTTP ${code}"
}

check_contains() {
  local needle="$1"
  grep -q "$needle" /tmp/km0-auth-body.html || fail "Expected '${needle}' in ${BASE_URL} response body"
  pass "body contains '${needle}'"
}

check_not_contains() {
  local needle="$1"
  if grep -q "$needle" /tmp/km0-auth-body.html; then
    fail "Did not expect '${needle}' in ${BASE_URL} response body"
  fi
  pass "body does not contain '${needle}'"
}

echo "Verifying auth pages at ${BASE_URL}"

check_status "/login.html"
check_contains 'pricing-notice'
check_contains 'registerPricingNotice\|1,99\|1.99'

check_status "/register"
check_contains 'pricing-notice'

check_status "/logout?from_dex=1"
check_contains 'logout-actions\|btn-primary'
check_not_contains 'splash-banner'

check_status "/dex/auth?client_id=OpenCloudAndroid&redirect_uri=oc%3A%2F%2Fandroid.opencloud.eu&response_type=code&scope=openid%20profile%20email%20offline_access&prompt=login&code_challenge=test&code_challenge_method=S256&state=test"
check_contains 'km0-card\|theme-panel'
check_not_contains 'theme-navbar'

web_redirect="$(curl -sS -o /dev/null -w '%{redirect_url}' \
  "${BASE_URL}/dex/auth?client_id=opencloud-web&redirect_uri=https%3A%2F%2Fcloud.km0digital.com%2Foidc-callback.html&response_type=code&scope=openid%20profile%20email&code_challenge=test&code_challenge_method=S256&state=web")"
[[ "$web_redirect" == *"/login.html?"* ]] || fail "Web /dex/auth did not redirect to /login.html (${web_redirect})"
pass "web /dex/auth redirects to /login.html"

echo "All auth page smoke checks passed."
