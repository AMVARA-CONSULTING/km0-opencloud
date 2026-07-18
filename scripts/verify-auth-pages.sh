#!/usr/bin/env bash
# HTTP smoke checks for KM0 authentication (hub + redirects).
set -euo pipefail

HUB_URL="${KM0_AUTH_HUB_URL:-https://auth.km0digital.com}"
CLOUD_URL="${KM0_CLOUD_BASE_URL:-https://cloud.km0digital.com}"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

echo "Verifying auth at hub ${HUB_URL} and cloud redirects ${CLOUD_URL}"

code="$(curl -sS -o /tmp/km0-hub-login.html -w '%{http_code}' "${HUB_URL}/login?service=cloud")"
[[ "$code" == "200" ]] || fail "hub /login returned ${code}"
grep -q 'pricing-notice' /tmp/km0-hub-login.html || fail "hub login missing pricing-notice"
pass "hub /login HTTP 200 + pricing-notice"

# Login is global: no per-service "Cloud + Mail" button, title is KM0 (not OpenCloud).
grep -q 'km0-unified-login' /tmp/km0-hub-login.html && fail "hub /login still has redundant unified button"
grep -q 'startGlobalLogin' /tmp/km0-hub-login.html || fail "hub /login missing startGlobalLogin (global model)"
grep -q '>OpenCloud<' /tmp/km0-hub-login.html && fail "hub /login still branded OpenCloud"
pass "hub /login is global KM0 (no unified button, no OpenCloud brand)"

code="$(curl -sS -o /tmp/km0-hub-reg.html -w '%{http_code}' "${HUB_URL}/register")"
[[ "$code" == "200" ]] || fail "hub /register returned ${code}"
grep -q 'km0-username' /tmp/km0-hub-reg.html || fail "hub /register missing username field"
grep -q 'km0-contact-email' /tmp/km0-hub-reg.html || fail "hub /register missing contact email field"
pass "hub /register HTTP 200 + username/contact separation"

loc="$(curl -sS -o /tmp/km0-cloud-login.html -w '%{redirect_url}' "${CLOUD_URL}/login.html")"
login_code="$(curl -sS -o /tmp/km0-cloud-login.html -w '%{http_code}' "${CLOUD_URL}/login.html")"
[[ "$login_code" == "200" ]] || fail "cloud /login.html returned ${login_code}"
grep -q 'hasActiveOidcSession\|km0-session-gate\|Comprobando sesión' /tmp/km0-cloud-login.html || fail "cloud /login.html missing session gate"
pass "cloud /login.html → session gate (HTTP 200)"

gate_code="$(curl -sS -o /dev/null -w '%{http_code}' "${CLOUD_URL}/km0-session-gate.html")"
[[ "$gate_code" == "200" ]] || fail "cloud /km0-session-gate.html returned ${gate_code}"
pass "cloud /km0-session-gate.html HTTP 200"

loc="$(curl -sS -o /dev/null -w '%{redirect_url}' "${CLOUD_URL}/register")"
[[ "$loc" == *"auth.km0digital.com/register"* ]] || fail "cloud /register redirect: ${loc}"
pass "cloud /register → hub"

android_code="$(curl -sS -o /tmp/km0-dex-android.html -w '%{http_code}' \
  "${CLOUD_URL}/dex/auth?client_id=OpenCloudAndroid&redirect_uri=oc%3A%2F%2Fandroid.opencloud.eu&response_type=code&scope=openid%20profile%20email%20offline_access&prompt=login&code_challenge=test&code_challenge_method=S256&state=test")"
[[ "$android_code" == "200" ]] || fail "Android dex auth returned ${android_code}"
pass "native Android /dex/auth HTTP 200 (not hub redirect)"

web_loc="$(curl -sS -o /dev/null -w '%{redirect_url}' \
  "${CLOUD_URL}/dex/auth?client_id=opencloud-web&redirect_uri=https%3A%2F%2Fcloud.km0digital.com%2Foidc-callback.html&response_type=code&scope=openid%20profile%20email%20offline_access&code_challenge=test&code_challenge_method=S256&state=web")"
[[ "$web_loc" == *"km0-session-gate.html"* ]] || fail "web /dex/auth redirect: ${web_loc}"
pass "web /dex/auth → session gate"

logout_loc="$(curl -sS -o /dev/null -w '%{redirect_url}' "${CLOUD_URL}/logout")"
[[ "$logout_loc" == *"auth.km0digital.com/login"* ]] || fail "cloud /logout redirect: ${logout_loc}"
[[ "$logout_loc" == *"signed_out=1"* ]] || fail "cloud /logout missing signed_out=1: ${logout_loc}"
pass "cloud /logout → hub login (signed_out)"

config_post_logout="$(curl -sS "${CLOUD_URL}/config.json" | python3 -c "import json,sys; print(json.load(sys.stdin)['openIdConnect']['post_logout_redirect_uri'])")"
[[ "$config_post_logout" == *"auth.km0digital.com/login"* ]] || fail "config post_logout_redirect_uri: ${config_post_logout}"
pass "config.json post_logout → auth hub login"

config_login_url="$(curl -sS "${CLOUD_URL}/config.json" | python3 -c "import json,sys; print(json.load(sys.stdin)['options']['loginUrl'])")"
[[ "$config_login_url" == *"km0-session-gate.html"* ]] || fail "config loginUrl: ${config_login_url}"
pass "config.json loginUrl → session gate"

config_scope="$(curl -sS "${CLOUD_URL}/config.json" | python3 -c "import json,sys; print(json.load(sys.stdin)['openIdConnect']['scope'])")"
[[ "$config_scope" == *"offline_access"* ]] || fail "config scope missing offline_access: ${config_scope}"
pass "config.json scope includes offline_access"

bridge_code="$(curl -sS -o /dev/null -w '%{http_code}' "${CLOUD_URL}/km0-oidc-start.html")"
[[ "$bridge_code" == "200" ]] || fail "cloud km0-oidc-start.html returned ${bridge_code}"
pass "cloud km0-oidc-start.html HTTP 200"

sso_code="$(curl -sS -o /dev/null -w '%{http_code}' "${HUB_URL}/sso-continue")"
[[ "$sso_code" == "200" ]] || fail "hub /sso-continue returned ${sso_code}"
pass "hub /sso-continue HTTP 200"

echo "All auth page smoke checks passed."

