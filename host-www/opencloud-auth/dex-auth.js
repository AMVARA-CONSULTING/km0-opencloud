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

  function clearAllAuthState() {
    clearOidcBrowserState();
    var authPat = /^oc_oAuth\.|^oidc\.|^oidc\.user:/i;
    try {
      [sessionStorage, localStorage].forEach(function (store) {
        Object.keys(store).forEach(function (k) {
          if (authPat.test(k)) store.removeItem(k);
        });
      });
    } catch (_) {}
    try {
      document.cookie = 'oc_auth_mode=;path=/;max-age=0;SameSite=Lax';
    } catch (_) {}
  }

  function getStoredIdToken() {
    var stores = [localStorage, sessionStorage];
    var keyPrefixes = ['oc_oAuth.user:', 'oidc.user:'];
    for (var s = 0; s < stores.length; s++) {
      var store = stores[s];
      var keys;
      try { keys = Object.keys(store); } catch (_) { continue; }
      for (var i = 0; i < keys.length; i++) {
        var k = keys[i];
        var matched = false;
        for (var p = 0; p < keyPrefixes.length; p++) {
          if (k.indexOf(keyPrefixes[p]) === 0) { matched = true; break; }
        }
        if (!matched) continue;
        try {
          var v = JSON.parse(store.getItem(k));
          if (v && v.id_token) return v.id_token;
        } catch (_) {}
      }
    }
    return null;
  }

  function postLogoutLoginUri() {
    return 'https://auth.km0digital.com/login?service=cloud&signed_out=1&from_dex=1';
  }

  function completeLogoutIfNeeded() {
    try {
      var params = new URLSearchParams(location.search);
      if (params.get('from_dex')) {
        clearAllAuthState();
        if (location.pathname === '/logout' || location.pathname === '/logout.html') {
          location.replace('https://auth.km0digital.com/login?service=cloud&signed_out=1');
        }
        return false;
      }
      var idToken = getStoredIdToken();
      var postLogout = postLogoutLoginUri();
      var qs = new URLSearchParams({ post_logout_redirect_uri: postLogout });
      if (idToken) qs.set('id_token_hint', idToken);
      location.assign('/dex/logout?' + qs.toString());
      return true;
    } catch (_) {
      clearAllAuthState();
      return false;
    }
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

  function oidcParamsFromSearch(p) {
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

  function oidcParamsFromBackParam() {
    var back = new URLSearchParams(location.search).get('back');
    if (!back) return null;
    try {
      var u = new URL(back, location.origin);
      return oidcParamsFromSearch(new URLSearchParams(u.search));
    } catch (_) {
      return null;
    }
  }

  function oidcParamsFromUrl() {
    return oidcParamsFromSearch(new URLSearchParams(location.search)) || oidcParamsFromBackParam();
  }

  function startDexLogin(connectorId, extraParams) {
    var resumed = oidcParamsFromUrl();
    if (!resumed) clearOidcBrowserState();
    setAuthModeCookie('dex');

    if (resumed) {
      var resumeParams = Object.assign({}, resumed, { connector_id: connectorId }, extraParams || {});
      location.assign('/dex/auth?' + new URLSearchParams(resumeParams).toString());
      return;
    }

    var redirectUri = location.origin + '/oidc-callback.html';
    var authority   = location.origin + '/dex';

    generatePKCE().then(function (pkce) {
      var state = randomHex(16);
      storeSigninState(state, authority, 'opencloud-web', redirectUri, pkce.verifier);
      var authParams = {
        client_id:             'opencloud-web',
        redirect_uri:          redirectUri,
        response_type:         'code',
        scope:                 OIDC_SCOPE,
        connector_id:          connectorId,
        state:                 state,
        code_challenge:        pkce.challenge,
        code_challenge_method: 'S256'
      };
      if (extraParams) {
        Object.keys(extraParams).forEach(function (k) {
          if (extraParams[k]) authParams[k] = extraParams[k];
        });
      }
      location.assign('/dex/auth?' + new URLSearchParams(authParams).toString());
    });
  }

  function startDexLoginWithPrompt(connectorId, prompt) {
    var extra = {};
    if (prompt) extra.prompt = prompt;
    startDexLogin(connectorId, extra);
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
    startDexLoginWithPrompt: startDexLoginWithPrompt,
    setAuthModeCookie: setAuthModeCookie,
    clearOidcBrowserState: clearOidcBrowserState,
    clearAllAuthState: clearAllAuthState,
    completeLogoutIfNeeded: completeLogoutIfNeeded,
    oidcParamsFromUrl: oidcParamsFromUrl,
    storePendingLogin: storePendingLogin,
    autoSubmitPendingLogin: autoSubmitPendingLogin
  };
})(window);
