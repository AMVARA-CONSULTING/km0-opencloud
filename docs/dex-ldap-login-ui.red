h1. Dex LDAP login UI — KM0 card layout

h2. Summary

The Dex LDAP form at @/dex/auth/ldap/login@ now matches the landing page @/login.html@: centered card, logo inside the panel, language switcher (CA | ES | EN | DE), and KM0-styled username/password fields plus gradient submit button. The top navbar was removed from this screen only.

---

h2. User-facing URLs

|_.Page|_.URL|
| Login landing | "https://cloud.km0digital.com/login.html":https://cloud.km0digital.com/login.html |
| Local (LDAP) sign-in | @https://cloud.km0digital.com/dex/auth/ldap/login@ |

Flow: landing → *Sign in with username and password* → LDAP form → OpenCloud OIDC callback.

---

h2. Repo changes

|_.Path|_.Role|
| @dex/web/templates/password.html@ | LDAP form markup + i18n hooks |
| @dex/web/templates/header-card.html@ | Card shell (no navbar) |
| @dex/web/templates/footer-card.html@ | Card footer + @i18n.js@ |
| @dex/web/themes/km0/styles.css@ | Card layout, inputs, primary button, error box |
| @dex/web/themes/km0/i18n.js@ | CA / ES / EN / DE strings for LDAP screen |

Logo on the LDAP card uses the same asset as the landing page: @https://km0digital.com/brand/logo.png@.

---

h2. Deploy

After editing @dex/web/@, restart Dex so templates reload:

<pre><code class="shell">
cd /opt/opencloud/dex && docker compose restart dex
</code></pre>

Verify: open the LDAP URL (with valid @state@ / @back@ from a real login) — page must show @km0-card@, not @theme-navbar@.

---

*2026-05-27 — km0-opencloud*
