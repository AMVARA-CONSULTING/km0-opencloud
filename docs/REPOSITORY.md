# Repositorio km0-opencloud

**Remote:** `git@github.com:AMVARA-CONSULTING/km0-opencloud.git`

Este repositorio versiona la **configuración operativa KM0** para OpenCloud en Debian (Nginx externo, Dex OIDC, plantillas web). No incluye el producto OpenCloud ni un fork de [opencloud-compose](https://github.com/opencloud-eu/opencloud-compose).

## Qué se versiona

| Ruta | Contenido |
|------|-----------|
| `overrides/opencloud-compose/` | Parches mínimos (CSP, external-proxy, patch OIDC en `docker-compose.yml`, plantilla `.env`) |
| `dex/` | Stack Dex, tema KM0, plantillas (sin `.env`) |
| `nginx/` | Plantillas para `/etc/nginx/` |
| `host-www/opencloud-auth/` | Login híbrido y `config-*.json` para `/var/www/opencloud-auth/` |
| `scripts/` | Backups y `apply-opencloud-compose-overrides.sh` |
| `docs/` | Runbook, este archivo, export Redmine `.red` |

## Qué no se versiona (pero puede existir en el servidor)

| Ruta / dato | Motivo |
|-------------|--------|
| `opencloud-compose/` | Clon de upstream; actualizar con `git pull` + script de overrides |
| `opencloud-compose/.env`, `dex/.env` | Secretos (`chmod 600`) |
| `/opt/google-client-secret.json`, Apple `.p8` | OAuth fuera del árbol Git |
| Volúmenes Docker `opencloud_*`, `dex_dex-data` | Datos y `opencloud.yaml` autogenerado |
| `/etc/letsencrypt/`, `/var/www/certbot/` | Certificados y ACME |
| `README.red` | Borrador local (gitignored) |

## Despliegue en servidor nuevo

```bash
git clone git@github.com:AMVARA-CONSULTING/km0-opencloud.git /opt/opencloud
cd /opt/opencloud

./scripts/apply-opencloud-compose-overrides.sh

cp overrides/opencloud-compose/.env.debian-core-external-proxy.example opencloud-compose/.env
chmod 600 opencloud-compose/.env
# Editar .env (contraseñas, dominios, comentarios operativos)

cp dex/.env.example dex/.env && chmod 600 dex/.env
# Rellenar Google/Apple según dex/README.md

# Plantillas host
sudo cp nginx/sites-available/opencloud /etc/nginx/sites-available/opencloud
sudo cp nginx/conf.d/opencloud-map.conf /etc/nginx/conf.d/
sudo cp -r host-www/opencloud-auth /var/www/opencloud-auth

cd opencloud-compose && docker compose up -d
cd ../dex && docker compose up -d
```

## Actualizar upstream OpenCloud Compose

```bash
git -C /opt/opencloud pull
git -C /opt/opencloud/opencloud-compose pull
/opt/opencloud/scripts/apply-opencloud-compose-overrides.sh
cd /opt/opencloud/opencloud-compose && docker compose pull && docker compose up -d
```

## Documentación Redmine / blog

Export Textile para wiki: [`docs/km0-opencloud-resumen.red`](km0-opencloud-resumen.red)
