# Branding del portal Authelia (tema KM0)

Authelia carga automáticamente estos ficheros si existen en este directorio
(montado como `/config/assets`):

- `logo.png` — logo mostrado en el portal de login/2FA.
- `favicon.ico` — favicon del portal.

`scripts/setup-authelia-secrets.sh` copia `logo.png` desde el tema de Dex
(`/opt/opencloud/dex/web/themes/km0/logo.png`) si está disponible. El favicon
`.ico` debe generarse a partir de `favicon.svg` del mismo tema, p. ej.:

```bash
convert -background none /opt/opencloud/dex/web/themes/km0/favicon.svg \
  -define icon:auto-resize=64,32,16 /opt/opencloud/authelia/assets/favicon.ico
```

Ambos ficheros están en `.gitignore` (son binarios derivados del tema).
