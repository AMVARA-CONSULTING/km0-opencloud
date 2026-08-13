# KM0 Authelia — 2FA opcional para Cloud

Authelia como **proveedor OIDC detrás de Dex**, dando 2FA opcional (opt-in por
grupo LDAP `2fa-enabled`) a **cloud.km0digital.com**. Valida la contraseña
contra el mismo LDAP de OpenCloud IDM y añade el 2º factor (TOTP / WebAuthn).

Portal: **https://id.km0digital.com**. Mail (webmail nativo, IMAP/SMTP) **no se
toca** en esta fase.

## Flujo

```
OpenCloud SPA/apps → Dex (cloud.km0digital.com/dex)
    ├─ connector google  (2FA propio de Google, sin cambios)
    └─ connector authelia (OIDC) → Authelia (id.km0digital.com)
                                       ├─ LDAP OpenCloud IDM (ldaps opencloud:9235)
                                       └─ 2º factor si el usuario ∈ grupo 2fa-enabled
```

El login local dejó de usar el conector `ldap` directo de Dex (se retiró para
que no exista una vía que salte Authelia). Google sigue igual.

## Requisitos previos

- OpenCloud desplegado (aporta la red `opencloud_opencloud-net`, el volumen
  `opencloud_opencloud-data` con `idm/ldap.crt`, y el LDAPS en `opencloud:9235`).
- El certificado LDAPS de IDM debe incluir `DNS:opencloud` en el SAN. Si no,
  ejecutar `/opt/opencloud/scripts/regenerate-opencloud-idm-ldap-cert.sh --restart`.
- Buzón `noreply@km0digital.com` en km0-mail para las notificaciones (recuperación).
- DNS `id.km0digital.com` → IP del host.
- Grupo `2fa-enabled` creado en OpenCloud IDM (ver `register-api`).

## Despliegue

```bash
# 1. Secretos + render de configuración (idempotente)
SMTP_PASSWORD='<password de noreply@km0digital.com>' \
  /opt/opencloud/authelia/scripts/setup-authelia-secrets.sh
#    → imprime AUTHELIA_OIDC_CLIENT_SECRET para dex/.env

# 2. Añadir el secreto en /opt/opencloud/dex/.env y aplicar Dex
#    AUTHELIA_OIDC_CLIENT_SECRET=...
cd /opt/opencloud/dex && docker compose up -d

# 3. Certificado + vhost del portal
sudo /opt/opencloud/authelia/scripts/issue-id-km0digital-cert.sh

# 4. Levantar Authelia+Redis
/opt/opencloud/authelia/scripts/deploy-authelia.sh
```

## Verificación

```bash
curl -fsS http://127.0.0.1:9091/api/health          # Authelia OK
curl -fsS https://id.km0digital.com/api/health       # a través de nginx
docker exec opencloud-dex grep -A3 'id: authelia' /etc/dex/config.yaml
```

- Login en Cloud de un usuario **sin** grupo → solo contraseña.
- Añadir el usuario al grupo `2fa-enabled` (botón "Activar 2FA" en Cloud) →
  el siguiente login fuerza el enrolamiento de TOTP/WebAuthn.
- Google y apps nativas (Desktop/Android/iOS) siguen funcionando.

## Notas de seguridad / operación

- Secretos en `secrets/authelia.secrets.env` y `secrets/oidc.jwks.key.pem`
  (gitignored). Rotación: `setup-authelia-secrets.sh --rotate` (invalida
  sesiones/tokens existentes).
- El secreto de cliente OIDC va en texto plano con prefijo `$plaintext$`. Para
  endurecer, sustituir por hash `authelia crypto hash generate pbkdf2`.
- **Break-glass admin**: si Authelia cae, se puede reactivar temporalmente el
  conector `ldap` en `dex/config.yaml` para que el admin entre solo con
  contraseña; volver a retirarlo tras la incidencia.
