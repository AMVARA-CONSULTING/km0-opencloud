# Branding del portal Authelia (tema KM0)

Authelia se sirve en `https://id.km0digital.com` con la marca KM0:

| Qué | Dónde |
|-----|--------|
| Logo / favicon | `logo.png`, `favicon.ico` (vía `server.asset_path`) |
| Textos CA/ES/EN/DE | `locales/<lang>/portal.json` |
| Skin visual (card civic-dark) | nginx injecta `/km0-authelia.css` + `/km0-title.js` |

Tras cambiar assets o CSS:

```bash
# assets/locales/logo → reiniciar Authelia
cd /opt/opencloud/authelia && docker compose up -d --force-recreate authelia

# CSS/title → solo reload nginx (vhost ya apunta aquí)
sudo nginx -t && sudo systemctl reload nginx
```

El login local **tiene** que pasar por Authelia (OIDC) para poder ofrecer 2FA;
ya no se muestra el formulario Dex antiguo. El skin KM0 hace que la pantalla
se vea como el hub (fondo navy, card, logo, tipografía).
