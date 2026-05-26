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

Copia `csp.yaml` y `external-proxy/opencloud.yml`, y aplica `patches/docker-compose.oidc-env.patch` con `patch -p1`.

## Plantilla de entorno

Copiar `.env.debian-core-external-proxy.example` a `opencloud-compose/.env` y rellenar secretos (ver comentarios en el `.env` del servidor).
