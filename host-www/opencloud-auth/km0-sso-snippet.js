(function () {
  'use strict';
  try {
    if (document.cookie.indexOf('km0_sso_continue=1') === -1) return;
    document.cookie = 'km0_sso_continue=;domain=.km0digital.com;path=/;max-age=0;SameSite=Lax';
    location.replace('https://auth.km0digital.com/sso-continue');
  } catch (_) {}
})();
