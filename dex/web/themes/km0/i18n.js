(function () {
  'use strict';

  var STORAGE_KEY = 'km0-login-lang';
  var LOCALES = ['es', 'ca', 'en', 'de'];
  var DEFAULT_LOCALE = 'es';

  var strings = {
    es: {
      metaDescription: 'Inicio de sesión OpenCloud — Kilómetro 0 Digital',
      pageTitle: 'Kilómetro 0 Digital — OpenCloud',
      logoAlt: 'Kilómetro 0 Digital',
      langAria: 'Idioma',
      loginEyebrow: 'Kilómetro 0 Digital',
      loginSubtitle: 'Elige cómo quieres iniciar sesión en cloud.km0digital.com',
      continueGoogle: 'Continuar con Google',
      continueApple: 'Continuar con Apple',
      continueProvider: 'Iniciar sesión con {name}',
      footerTagline: 'Origen local. Impacto digital.',
      landingDescription:
        'Accede a tus archivos en la nube. Elige Google/Apple (OIDC) o usuario y contraseña local.',
      landingCta: 'Continuar al inicio de sesión',
      landingCtaOidc: 'Continuar con Google / Apple',
      landingCtaLocal: 'Iniciar sesión con usuario y contraseña',
      landingTagline: 'Origen local · Impacto digital',
      landingDividerOr: 'o',
      ldapLoginIntro: 'Inicia sesión con tu usuario y contraseña de OpenCloud.',
      ldapUsernamePlaceholder: 'Usuario o correo',
      ldapPasswordLabel: 'Contraseña',
      ldapPasswordPlaceholder: 'Contraseña',
      ldapSubmit: 'Iniciar sesión',
      ldapLoginError: 'Usuario o contraseña incorrectos.',
      ldapBackLink: 'Volver al inicio de sesión',
    },
    ca: {
      metaDescription: "Inici de sessió OpenCloud — Kilòmetre 0 Digital",
      pageTitle: 'Kilòmetre 0 Digital — OpenCloud',
      logoAlt: 'Kilòmetre 0 Digital',
      langAria: 'Idioma',
      loginEyebrow: 'Kilòmetre 0 Digital',
      loginSubtitle: 'Tria com vols iniciar sessió a cloud.km0digital.com',
      continueGoogle: 'Continuar amb Google',
      continueApple: 'Continuar amb Apple',
      continueProvider: "Iniciar sessió amb {name}",
      footerTagline: 'Origen local. Impacte digital.',
      landingDescription:
        "Accedeix als teus fitxers al núvol. Tria Google/Apple (OIDC) o usuari i contrasenya local.",
      landingCta: "Continuar a l'inici de sessió",
      landingCtaOidc: 'Continuar amb Google / Apple',
      landingCtaLocal: "Iniciar sessió amb usuari i contrasenya",
      landingTagline: 'Origen local · Impacte digital',
      landingDividerOr: 'o',
      ldapLoginIntro: "Inicia sessió amb el teu usuari i contrasenya d'OpenCloud.",
      ldapUsernamePlaceholder: 'Usuari o correu',
      ldapPasswordLabel: 'Contrasenya',
      ldapPasswordPlaceholder: 'Contrasenya',
      ldapSubmit: 'Iniciar sessió',
      ldapLoginError: 'Usuari o contrasenya incorrectes.',
      ldapBackLink: "Tornar a l'inici de sessió",
    },
    en: {
      metaDescription: 'OpenCloud sign-in — Kilometer 0 Digital',
      pageTitle: 'Kilometer 0 Digital — OpenCloud',
      logoAlt: 'Kilometer 0 Digital',
      langAria: 'Language',
      loginEyebrow: 'Kilometer 0 Digital',
      loginSubtitle: 'Choose how you want to sign in to cloud.km0digital.com',
      continueGoogle: 'Continue with Google',
      continueApple: 'Continue with Apple',
      continueProvider: 'Sign in with {name}',
      footerTagline: 'Local origin. Digital impact.',
      landingDescription:
        'Access your files in the cloud. Choose Google/Apple (OIDC) or local username and password.',
      landingCta: 'Continue to sign in',
      landingCtaOidc: 'Continue with Google / Apple',
      landingCtaLocal: 'Sign in with username and password',
      landingTagline: 'Local origin · Digital impact',
      landingDividerOr: 'or',
      ldapLoginIntro: 'Sign in with your OpenCloud username and password.',
      ldapUsernamePlaceholder: 'Username or email',
      ldapPasswordLabel: 'Password',
      ldapPasswordPlaceholder: 'Password',
      ldapSubmit: 'Sign in',
      ldapLoginError: 'Incorrect username or password.',
      ldapBackLink: 'Back to sign-in',
    },
    de: {
      metaDescription: 'OpenCloud-Anmeldung — Kilometer 0 Digital',
      pageTitle: 'Kilometer 0 Digital — OpenCloud',
      logoAlt: 'Kilometer 0 Digital',
      langAria: 'Sprache',
      loginEyebrow: 'Kilometer 0 Digital',
      loginSubtitle:
        'Wählen Sie, wie Sie sich bei cloud.km0digital.com anmelden möchten',
      continueGoogle: 'Mit Google fortfahren',
      continueApple: 'Mit Apple fortfahren',
      continueProvider: 'Mit {name} anmelden',
      footerTagline: 'Lokaler Ursprung. Digitale Wirkung.',
      landingDescription:
        'Greifen Sie auf Ihre Dateien in der Cloud zu. Wählen Sie Google/Apple (OIDC) oder lokales Benutzerkonto.',
      landingCta: 'Weiter zur Anmeldung',
      landingCtaOidc: 'Mit Google / Apple fortfahren',
      landingCtaLocal: 'Mit Benutzername und Passwort anmelden',
      landingTagline: 'Lokaler Ursprung · Digitale Wirkung',
      landingDividerOr: 'oder',
      ldapLoginIntro:
        'Melden Sie sich mit Ihrem OpenCloud-Benutzernamen und Passwort an.',
      ldapUsernamePlaceholder: 'Benutzername oder E-Mail',
      ldapPasswordLabel: 'Passwort',
      ldapPasswordPlaceholder: 'Passwort',
      ldapSubmit: 'Anmelden',
      ldapLoginError: 'Benutzername oder Passwort falsch.',
      ldapBackLink: 'Zurück zur Anmeldung',
    },
  };

  function htmlLang(locale) {
    return LOCALES.indexOf(locale) >= 0 ? locale : DEFAULT_LOCALE;
  }

  function normalizeLocale(raw) {
    if (!raw) return null;
    var code = String(raw).toLowerCase().split('-')[0];
    return LOCALES.indexOf(code) >= 0 ? code : null;
  }

  function detectBrowserLocale() {
    if (typeof navigator === 'undefined' || !navigator.language) return DEFAULT_LOCALE;
    var langs = navigator.languages || [navigator.language];
    for (var i = 0; i < langs.length; i++) {
      var loc = normalizeLocale(langs[i]);
      if (loc) return loc;
    }
    return DEFAULT_LOCALE;
  }

  function getLocale() {
    try {
      var params = new URLSearchParams(window.location.search);
      var fromQuery = normalizeLocale(params.get('lang'));
      if (fromQuery) {
        localStorage.setItem(STORAGE_KEY, fromQuery);
        return fromQuery;
      }
      var stored = normalizeLocale(localStorage.getItem(STORAGE_KEY));
      if (stored) return stored;
    } catch (e) {
      /* private mode / blocked storage */
    }
    return detectBrowserLocale();
  }

  function setLocale(locale) {
    try {
      localStorage.setItem(STORAGE_KEY, locale);
    } catch (e) {
      /* ignore */
    }
    applyLocale(locale);
    updateLangSwitcher(locale);
    document.documentElement.lang = htmlLang(locale);
  }

  function t(locale, key, vars) {
    var pack = strings[locale] || strings[DEFAULT_LOCALE];
    var text = pack[key] || strings[DEFAULT_LOCALE][key] || key;
    if (vars) {
      Object.keys(vars).forEach(function (name) {
        text = text.split('{' + name + '}').join(vars[name]);
      });
    }
    return text;
  }

  function applyLocale(locale) {
    var pack = strings[locale] || strings[DEFAULT_LOCALE];

    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      var key = el.getAttribute('data-i18n');
      var name = el.getAttribute('data-i18n-name');
      el.textContent = t(locale, key, name ? { name: name } : null);
    });

    document.querySelectorAll('[data-i18n-placeholder]').forEach(function (el) {
      var key = el.getAttribute('data-i18n-placeholder');
      el.setAttribute('placeholder', t(locale, key));
    });

    document.querySelectorAll('[data-i18n-connector]').forEach(function (el) {
      var id = el.getAttribute('data-i18n-connector');
      if (id === 'google') el.textContent = pack.continueGoogle;
      else if (id === 'apple') el.textContent = pack.continueApple;
      else {
        var name = el.getAttribute('data-i18n-name') || id;
        el.textContent = t(locale, 'continueProvider', { name: name });
      }
    });

    var metaDesc = document.querySelector('meta[name="description"]');
    if (metaDesc) metaDesc.setAttribute('content', pack.metaDescription);
    document.title = pack.pageTitle;

    var logo = document.querySelector('.theme-navbar__logo, .km0-card__logo, .logo');
    if (logo) logo.setAttribute('alt', pack.logoAlt);

    var langNav = document.querySelector('.km0-lang-switch');
    if (langNav) langNav.setAttribute('aria-label', pack.langAria);
  }

  function updateLangSwitcher(locale) {
    document.querySelectorAll('.km0-lang-switch [data-lang]').forEach(function (btn) {
      var active = btn.getAttribute('data-lang') === locale;
      btn.classList.toggle('km0-lang-switch__btn--active', active);
      btn.setAttribute('aria-pressed', active ? 'true' : 'false');
    });
  }

  function bindLangSwitcher() {
    document.querySelectorAll('.km0-lang-switch [data-lang]').forEach(function (btn) {
      btn.addEventListener('click', function (ev) {
        ev.preventDefault();
        var locale = normalizeLocale(btn.getAttribute('data-lang'));
        if (locale) setLocale(locale);
      });
    });
  }

  function init() {
    var locale = getLocale();
    applyLocale(locale);
    updateLangSwitcher(locale);
    bindLangSwitcher();
    document.documentElement.lang = htmlLang(locale);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  window.KM0LoginI18n = { setLocale: setLocale, getLocale: getLocale, locales: LOCALES };
})();
