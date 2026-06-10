(function (global) {
  'use strict';

  var OIDC_SCOPE = 'openid profile email';
  var AUTH_COOKIE_MAX_AGE = 600;
  var PENDING_LOGIN_KEY = 'km0_pending_login';
  var PENDING_LOGIN_TTL_MS = 120000;

  function setAuthModeCookie(mode) {
    document.cookie = 'oc_auth_mode=' + mode +
      ';path=/;max-age=' + AUTH_COOKIE_MAX_AGE + ';SameSite=Lax';
  }

  function clearOidcBrowserState() {
    var pat = /^oidc\.|^oidc\.user:/i;
    try {
      Object.keys(sessionStorage).forEach(function (k) {
        if (pat.test(k)) sessionStorage.removeItem(k);
      });
    } catch (_) {}
    try {
      Object.keys(localStorage).forEach(function (k) {
        if (pat.test(k)) localStorage.removeItem(k);
      });
    } catch (_) {}
  }

  function base64url(buf) {
    return btoa(String.fromCharCode.apply(null, new Uint8Array(buf)))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  }

  function randomHex(bytes) {
    var a = new Uint8Array(bytes);
    crypto.getRandomValues(a);
    return Array.from(a, function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
  }

  function generatePKCE() {
    var arr = new Uint8Array(32);
    crypto.getRandomValues(arr);
    var verifier = base64url(arr.buffer);
    return crypto.subtle
      .digest('SHA-256', new TextEncoder().encode(verifier))
      .then(function (hash) { return { verifier: verifier, challenge: base64url(hash) }; });
  }

  function storeSigninState(state, authority, clientId, redirectUri, codeVerifier) {
    try {
      localStorage.setItem('oidc.' + state, JSON.stringify({
        id: state,
        created: Math.floor(Date.now() / 1000),
        request_type: 'si:r',
        code_verifier: codeVerifier,
        redirect_uri: redirectUri,
        authority: authority,
        client_id: clientId,
        scope: OIDC_SCOPE,
        extraTokenParams: {},
        skipUserInfo: false
      }));
    } catch (_) {}
  }

  function oidcParamsFromUrl() {
    var p = new URLSearchParams(location.search);
    if (!p.get('client_id') || !p.get('state') || !p.get('code_challenge')) return null;
    return {
      client_id:             p.get('client_id'),
      redirect_uri:          p.get('redirect_uri'),
      response_type:         p.get('response_type') || 'code',
      scope:                 p.get('scope') || OIDC_SCOPE,
      state:                 p.get('state'),
      code_challenge:        p.get('code_challenge'),
      code_challenge_method: p.get('code_challenge_method') || 'S256'
    };
  }

  function startDexLogin(connectorId) {
    var resumed = oidcParamsFromUrl();
    if (!resumed) clearOidcBrowserState();
    setAuthModeCookie('dex');

    if (resumed) {
      location.assign('/dex/auth?' + new URLSearchParams(Object.assign({}, resumed, {
        connector_id: connectorId
      })).toString());
      return;
    }

    var redirectUri = location.origin + '/oidc-callback.html';
    var authority   = location.origin + '/dex';

    generatePKCE().then(function (pkce) {
      var state = randomHex(16);
      storeSigninState(state, authority, 'opencloud-web', redirectUri, pkce.verifier);
      location.assign('/dex/auth?' + new URLSearchParams({
        client_id:             'opencloud-web',
        redirect_uri:          redirectUri,
        response_type:         'code',
        scope:                 OIDC_SCOPE,
        connector_id:          connectorId,
        state:                 state,
        code_challenge:        pkce.challenge,
        code_challenge_method: 'S256'
      }).toString());
    });
  }

  function storePendingLogin(login, password) {
    try {
      sessionStorage.setItem(PENDING_LOGIN_KEY, JSON.stringify({
        login: login,
        password: password,
        exp: Date.now() + PENDING_LOGIN_TTL_MS
      }));
    } catch (_) {}
  }

  function consumePendingLogin() {
    try {
      var raw = sessionStorage.getItem(PENDING_LOGIN_KEY);
      if (!raw) return null;
      sessionStorage.removeItem(PENDING_LOGIN_KEY);
      var data = JSON.parse(raw);
      if (!data || !data.login || !data.password || !data.exp || data.exp < Date.now()) {
        return null;
      }
      return { login: data.login, password: data.password };
    } catch (_) {
      return null;
    }
  }

  function autoSubmitPendingLogin(formSelector) {
    var pending = consumePendingLogin();
    if (!pending) return false;
    var form = document.querySelector(formSelector || 'form.km0-ldap-form');
    if (!form) return false;
    var loginEl = document.getElementById('login');
    var passEl = document.getElementById('password');
    if (!loginEl || !passEl) return false;
    loginEl.value = pending.login;
    passEl.value = pending.password;
    form.submit();
    return true;
  }

  global.KM0DexAuth = {
    startDexLogin: startDexLogin,
    setAuthModeCookie: setAuthModeCookie,
    clearOidcBrowserState: clearOidcBrowserState,
    oidcParamsFromUrl: oidcParamsFromUrl,
    storePendingLogin: storePendingLogin,
    autoSubmitPendingLogin: autoSubmitPendingLogin
  };
})(window);
