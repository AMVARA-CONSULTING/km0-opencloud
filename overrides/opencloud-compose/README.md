# Parches KM0 sobre opencloud-compose (upstream)

Este directorio **no** es un fork de [opencloud-eu/opencloud-compose](https://github.com/opencloud-eu/opencloud-compose). Solo contiene los archivos que KM0 modifica respecto al clon local en `opencloud-compose/`.

## Clon upstream (en el servidor)

```bash
git clone https://github.com/opencloud-eu/opencloud-compose.git /opt/opencloud/opencloud-compose
cd /opt/opencloud/opencloud-compose
```

## Aplicar parches

Desde la raíz del repo `km0-opencloud`:

```bash
./scripts/apply-opencloud-compose-overrides.sh
```

Copia `csp.yaml`, `external-proxy/opencloud.yml`, and `external-proxy/collabora.yml`, and applies `patches/docker-compose.oidc-env.patch` with `patch -p1`.

`external-proxy/collabora.yml` also sets collaboration `EVENTS_ENDPOINT` / `STORE_NODES` to `opencloud:9233` (required from OpenCloud 7.3.0 so WOPI reaches OpenCloud NATS instead of loopback).

## Plantilla de entorno

| Plantilla | Uso |
|-----------|-----|
| `.env.debian-core-external-proxy.example` | OpenCloud solo (sin Collabora/WOPI) |
| `.env.debian-collabora-external-proxy.example` | OpenCloud + Collabora Online CODE + WOPI |

Copiar la plantilla adecuada a `opencloud-compose/.env` y rellenar secretos (ver comentarios en el `.env` del servidor).

Con Collabora, además:

```bash
/opt/opencloud/scripts/issue-collabora-wopi-certs.sh   # DNS + Let's Encrypt + nginx
/opt/opencloud/scripts/enable-collabora-compose.sh     # overrides + docker compose up -d
```
