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
        'Inicia sesión con Google o tu usuario.',
      landingCta: 'Continuar al inicio de sesión',
      landingCtaOidc: 'Continuar con Google',
      landingCtaLocal: 'Iniciar sesión con usuario y contraseña',
      landingTagline: 'Origen local · Impacto digital',
      landingDividerOr: 'o',
      hubTitle: 'KM0 Account',
      ldapLoginIntro: 'Inicia sesión una vez para todos los servicios KM0.',
      ldapUsernamePlaceholder: 'Usuario',
      ldapPasswordLabel: 'Contraseña',
      ldapPasswordPlaceholder: 'Contraseña',
      ldapSubmit: 'Iniciar sesión',
      ldapLoginError: 'Usuario o contraseña incorrectos.',
      ldapErrorTitle: 'Problema al iniciar sesión',
      ldapOidcAccountTitle: 'Usa Google para esta cuenta',
      ldapOidcAccountError:
        'Esta cuenta se creó con Google. Inicia sesión con Google en lugar de usuario y contraseña.',
      ldapErrorGeneric:
        'No hemos podido iniciar sesión. Inténtalo de nuevo o usa otro método de acceso.',
      ldapBackLink: 'Volver al inicio de sesión',
      registerPageTitle: 'Crear cuenta — Kilómetro 0 Digital',
      registerMetaDescription: 'Registro en OpenCloud — Kilómetro 0 Digital',
      registerIntro: 'Crea tu cuenta con correo y contraseña para acceder a OpenCloud.',
      registerEmailLabel: 'Correo electrónico',
      registerEmailPlaceholder: 'tu@correo.com',
      registerPasswordLabel: 'Contraseña',
      registerPasswordPlaceholder: 'Contraseña',
      registerConfirmPasswordLabel: 'Confirmar contraseña',
      registerConfirmPasswordPlaceholder: 'Repite la contraseña',
      registerSubmit: 'Crear cuenta',
      registerSignInLink: '¿Ya tienes cuenta? Inicia sesión',
      registerCreateAccountLink: '¿Aún no tienes cuenta?',
      registerPricingNotice:
        'Este servicio está en fase de pruebas y es gratuito por ahora. Tras el periodo de pruebas, el almacenamiento en la nube costará <strong>1,99 €/mes</strong>. <a href="https://km0digital.com/pricing/" target="_blank" rel="noopener">Ver precios</a>',
      registerSuccessBanner: 'Cuenta creada. Inicia sesión con tu correo y contraseña.',
      registerErrorEmailInvalid: 'Introduce un correo electrónico válido.',
      registerErrorPasswordMismatch: 'Las contraseñas no coinciden.',
      registerErrorPasswordWeak: 'La contraseña debe tener al menos 8 caracteres e incluir un carácter especial.',
      registerErrorDuplicate: 'Este correo ya está registrado. Si la creaste con Google, usa «Continuar con Google» en la página de inicio de sesión.',
      registerErrorValidation: 'No se pudo validar los datos. Comprueba el correo y la contraseña.',
      registerErrorServiceUnavailable: 'El registro no está disponible temporalmente. Inténtalo más tarde o inicia sesión con Google.',
      registerErrorRateLimit: 'Demasiados intentos. Espera un minuto e inténtalo de nuevo.',
      registerErrorGeneric: 'No se pudo crear la cuenta. Inténtalo de nuevo más tarde.',
      registerSubmitting: 'Creando cuenta…',
      registerSigningIn: 'Iniciando sesión…',
      registerCreateMailLabel: 'Crear también una cuenta de KM0 Mail (@km0digital.com o dominio propio)',
      registerErrorFreemailMailbox: 'KM0 Mail no admite Gmail, Outlook u otros correos gratuitos como buzón. Usa @km0digital.com o tu dominio propio.',
      logoutPageTitle: 'Sesión cerrada — Kilómetro 0 Digital',
      logoutMetaDescription: 'Sesión cerrada en OpenCloud — Kilómetro 0 Digital',
      logoutTitle: 'Sesión cerrada',
      logoutMessage: 'Has cerrado sesión en OpenCloud correctamente.',
      logoutReturnLogin: 'Volver a iniciar sesión',
      logoutGoHome: 'Ir a km0digital.com',
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
        "Inicia sessió amb Google o el teu usuari.",
      landingCta: "Continuar a l'inici de sessió",
      landingCtaOidc: 'Continuar amb Google',
      landingCtaLocal: "Iniciar sessió amb usuari i contrasenya",
      landingTagline: 'Origen local · Impacte digital',
      landingDividerOr: 'o',
      hubTitle: 'KM0 Account',
      ldapLoginIntro: 'Inicia sessió una vegada per a tots els serveis KM0.',
      ldapUsernamePlaceholder: 'Usuari',
      ldapPasswordLabel: 'Contrasenya',
      ldapPasswordPlaceholder: 'Contrasenya',
      ldapSubmit: 'Iniciar sessió',
      ldapLoginError: 'Usuari o contrasenya incorrectes.',
      ldapErrorTitle: "Problema en iniciar sessió",
      ldapOidcAccountTitle: 'Fes servir Google per a aquest compte',
      ldapOidcAccountError:
        "Aquest compte es va crear amb Google. Inicia sessió amb Google en lloc d'usuari i contrasenya.",
      ldapErrorGeneric:
        "No hem pogut iniciar sessió. Torna-ho a provar o fes servir un altre mètode d'accés.",
      ldapBackLink: "Tornar a l'inici de sessió",
      registerPageTitle: 'Crear compte — Kilòmetre 0 Digital',
      registerMetaDescription: "Registre a OpenCloud — Kilòmetre 0 Digital",
      registerIntro: "Crea el teu compte amb correu i contrasenya per accedir a OpenCloud.",
      registerEmailLabel: 'Correu electrònic',
      registerEmailPlaceholder: 'tu@correu.com',
      registerPasswordLabel: 'Contrasenya',
      registerPasswordPlaceholder: 'Contrasenya',
      registerConfirmPasswordLabel: 'Confirmar contrasenya',
      registerConfirmPasswordPlaceholder: 'Repeteix la contrasenya',
      registerSubmit: 'Crear compte',
      registerSignInLink: 'Ja tens compte? Inicia sessió',
      registerCreateAccountLink: 'Encara no tens compte?',
      registerPricingNotice:
        'Aquest servei està en fase de proves i és gratuït per ara. Després del període de proves, l\'emmagatzematge al núvol costarà <strong>1,99 €/mes</strong>. <a href="https://km0digital.com/ca/pricing/" target="_blank" rel="noopener">Veure preus</a>',
      registerSuccessBanner: 'Compte creat. Inicia sessió amb el teu correu i contrasenya.',
      registerErrorEmailInvalid: 'Introdueix un correu electrònic vàlid.',
      registerErrorPasswordMismatch: 'Les contrasenyes no coincideixen.',
      registerErrorPasswordWeak: 'La contrasenya ha de tenir almenys 8 caràcters i incloure un caràcter especial.',
      registerErrorDuplicate: 'Aquest correu ja està registrat. Si el vas crear amb Google, fes servir «Continuar amb Google» a la pàgina d\'inici de sessió.',
      registerErrorValidation: 'No s\'han pogut validar les dades. Comprova el correu i la contrasenya.',
      registerErrorServiceUnavailable: 'El registre no està disponible temporalment. Torna-ho a provar més tard o inicia sessió amb Google.',
      registerErrorRateLimit: 'Massa intents. Espera un minut i torna-ho a provar.',
      registerErrorGeneric: 'No s\'ha pogut crear el compte. Torna-ho a provar més tard.',
      registerSubmitting: 'Creant compte…',
      registerSigningIn: 'Iniciant sessió…',
      registerCreateMailLabel: 'Crear també un compte de KM0 Mail (@km0digital.com o domini propi)',
      registerErrorFreemailMailbox: 'KM0 Mail no admet Gmail, Outlook ni altres correus gratuïts com a bústia. Fes servir @km0digital.com o el teu domini propi.',
      logoutPageTitle: 'Sessió tancada — Kilòmetre 0 Digital',
      logoutMetaDescription: "Sessió tancada a OpenCloud — Kilòmetre 0 Digital",
      logoutTitle: 'Sessió tancada',
      logoutMessage: "Has tancat sessió a OpenCloud correctament.",
      logoutReturnLogin: "Tornar a iniciar sessió",
      logoutGoHome: 'Anar a km0digital.com',
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
        'Sign in with Google or your account.',
      landingCta: 'Continue to sign in',
      landingCtaOidc: 'Continue with Google',
      landingCtaLocal: 'Sign in with username and password',
      landingTagline: 'Local origin · Digital impact',
      landingDividerOr: 'or',
      hubTitle: 'KM0 Account',
      ldapLoginIntro: 'Sign in once for all KM0 services.',
      ldapUsernamePlaceholder: 'Username',
      ldapPasswordLabel: 'Password',
      ldapPasswordPlaceholder: 'Password',
      ldapSubmit: 'Sign in',
      ldapLoginError: 'Incorrect username or password.',
      ldapErrorTitle: 'Sign-in problem',
      ldapOidcAccountTitle: 'Use Google for this account',
      ldapOidcAccountError:
        'This account was created with Google. Sign in with Google instead of username and password.',
      ldapErrorGeneric:
        'We could not sign you in. Please try again or use another sign-in method.',
      ldapBackLink: 'Back to sign-in',
      registerPageTitle: 'Create account — Kilometer 0 Digital',
      registerMetaDescription: 'OpenCloud registration — Kilometer 0 Digital',
      registerIntro: 'Create your account with email and password to access OpenCloud.',
      registerEmailLabel: 'Email',
      registerEmailPlaceholder: 'you@example.com',
      registerPasswordLabel: 'Password',
      registerPasswordPlaceholder: 'Password',
      registerConfirmPasswordLabel: 'Confirm password',
      registerConfirmPasswordPlaceholder: 'Repeat password',
      registerSubmit: 'Create account',
      registerSignInLink: 'Already have an account? Sign in',
      registerCreateAccountLink: "Don't have an account yet?",
      registerPricingNotice:
        'This service is currently in testing and free to try. After the testing period, cloud storage will be <strong>€1.99/month</strong>. <a href="https://km0digital.com/en/pricing/" target="_blank" rel="noopener">See pricing</a>',
      registerSuccessBanner: 'Account created. Sign in with your email and password.',
      registerErrorEmailInvalid: 'Enter a valid email address.',
      registerErrorPasswordMismatch: 'Passwords do not match.',
      registerErrorPasswordWeak: 'Password must be at least 8 characters and include a special character.',
      registerErrorDuplicate: 'This email is already registered. If you created it with Google, use "Continue with Google" on the sign-in page.',
      registerErrorValidation: 'Could not validate your details. Check your email and password.',
      registerErrorServiceUnavailable: 'Registration is temporarily unavailable. Try again later or sign in with Google.',
      registerErrorRateLimit: 'Too many attempts. Wait a minute and try again.',
      registerErrorGeneric: 'Could not create account. Please try again later.',
      registerSubmitting: 'Creating account…',
      registerSigningIn: 'Signing in…',
      registerCreateMailLabel: 'Also create a KM0 Mail account (@km0digital.com or your own domain)',
      registerErrorFreemailMailbox: 'KM0 Mail cannot use Gmail, Outlook, or other freemail domains as a mailbox. Use @km0digital.com or your own domain.',
      logoutPageTitle: 'Signed out — Kilometer 0 Digital',
      logoutMetaDescription: 'Signed out of OpenCloud — Kilometer 0 Digital',
      logoutTitle: 'Signed out',
      logoutMessage: 'You have been signed out of OpenCloud.',
      logoutReturnLogin: 'Return to sign in',
      logoutGoHome: 'Go to km0digital.com',
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
        'Melden Sie sich mit Google oder Ihrem Benutzerkonto an.',
      landingCta: 'Weiter zur Anmeldung',
      landingCtaOidc: 'Mit Google fortfahren',
      landingCtaLocal: 'Mit Benutzername und Passwort anmelden',
      landingTagline: 'Lokaler Ursprung · Digitale Wirkung',
      landingDividerOr: 'oder',
      hubTitle: 'KM0 Account',
      ldapLoginIntro: 'Melden Sie sich einmal für alle KM0-Dienste an.',
      ldapUsernamePlaceholder: 'Benutzername',
      ldapPasswordLabel: 'Passwort',
      ldapPasswordPlaceholder: 'Passwort',
      ldapSubmit: 'Anmelden',
      ldapLoginError: 'Benutzername oder Passwort falsch.',
      ldapErrorTitle: 'Anmeldeproblem',
      ldapOidcAccountTitle: 'Google für dieses Konto verwenden',
      ldapOidcAccountError:
        'Dieses Konto wurde mit Google erstellt. Melden Sie sich mit Google statt Benutzername und Passwort an.',
      ldapErrorGeneric:
        'Anmeldung fehlgeschlagen. Bitte erneut versuchen oder eine andere Anmeldemethode wählen.',
      ldapBackLink: 'Zurück zur Anmeldung',
      registerPageTitle: 'Konto erstellen — Kilometer 0 Digital',
      registerMetaDescription: 'OpenCloud-Registrierung — Kilometer 0 Digital',
      registerIntro: 'Erstellen Sie Ihr Konto mit E-Mail und Passwort für OpenCloud.',
      registerEmailLabel: 'E-Mail',
      registerEmailPlaceholder: 'sie@beispiel.de',
      registerPasswordLabel: 'Passwort',
      registerPasswordPlaceholder: 'Passwort',
      registerConfirmPasswordLabel: 'Passwort bestätigen',
      registerConfirmPasswordPlaceholder: 'Passwort wiederholen',
      registerSubmit: 'Konto erstellen',
      registerSignInLink: 'Bereits ein Konto? Anmelden',
      registerCreateAccountLink: 'Noch kein Konto?',
      registerPricingNotice:
        'Dieser Dienst befindet sich in der Testphase und ist derzeit kostenlos. Nach der Testphase kostet Cloud-Speicher <strong>1,99 €/Monat</strong>. <a href="https://km0digital.com/de/pricing/" target="_blank" rel="noopener">Preise ansehen</a>',
      registerSuccessBanner: 'Konto erstellt. Melden Sie sich mit E-Mail und Passwort an.',
      registerErrorEmailInvalid: 'Geben Sie eine gültige E-Mail-Adresse ein.',
      registerErrorPasswordMismatch: 'Passwörter stimmen nicht überein.',
      registerErrorPasswordWeak: 'Passwort muss mindestens 8 Zeichen und ein Sonderzeichen enthalten.',
      registerErrorDuplicate: 'Diese E-Mail ist bereits registriert. Wenn Sie das Konto mit Google erstellt haben, nutzen Sie auf der Anmeldeseite „Mit Google fortfahren“.',
      registerErrorValidation: 'Daten konnten nicht validiert werden. Prüfen Sie E-Mail und Passwort.',
      registerErrorServiceUnavailable: 'Registrierung vorübergehend nicht verfügbar. Später erneut versuchen oder mit Google anmelden.',
      registerErrorRateLimit: 'Zu viele Versuche. Eine Minute warten und erneut versuchen.',
      registerErrorGeneric: 'Konto konnte nicht erstellt werden. Bitte später erneut versuchen.',
      registerSubmitting: 'Konto wird erstellt…',
      registerSigningIn: 'Anmeldung läuft…',
      registerCreateMailLabel: 'Auch ein KM0-Mail-Konto erstellen (@km0digital.com oder eigene Domain)',
      registerErrorFreemailMailbox: 'KM0 Mail unterstützt Gmail, Outlook und andere Freemail-Domains nicht als Postfach. Nutze @km0digital.com oder deine eigene Domain.',
      logoutPageTitle: 'Abgemeldet — Kilometer 0 Digital',
      logoutMetaDescription: 'Abgemeldet von OpenCloud — Kilometer 0 Digital',
      logoutTitle: 'Abgemeldet',
      logoutMessage: 'Sie wurden von OpenCloud abgemeldet.',
      logoutReturnLogin: 'Zur Anmeldung zurück',
      logoutGoHome: 'Zu km0digital.com',
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

    document.querySelectorAll('[data-i18n-html]').forEach(function (el) {
      var key = el.getAttribute('data-i18n-html');
      el.innerHTML = t(locale, key);
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
    if (metaDesc) {
      var metaKey = metaDesc.getAttribute('data-i18n-meta') || 'metaDescription';
      metaDesc.setAttribute('content', t(locale, metaKey));
    }

    var titleEl = document.querySelector('title[data-i18n]');
    if (titleEl) {
      document.title = t(locale, titleEl.getAttribute('data-i18n'));
    } else {
      document.title = pack.pageTitle;
    }

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

  window.KM0LoginI18n = {
    setLocale: setLocale,
    getLocale: getLocale,
    locales: LOCALES,
    t: function (key) { return t(getLocale(), key); },
  };
})();
