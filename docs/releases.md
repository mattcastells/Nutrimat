# Publicar una versión

Nutrimat no está en Play Store. Cada versión es un **release de GitHub** con el
APK firmado adjunto, y la app se actualiza sola desde Configuración →
Actualizaciones.

---

## Configuración por única vez

Antes del primer release hay que cargar cuatro secretos en el repositorio:
`Settings → Secrets and variables → Actions → New repository secret`.

| Secreto | Qué va |
| --- | --- |
| `KEYSTORE_BASE64` | El `android/nutrimat-upload.jks` codificado en base64 |
| `KEYSTORE_PASSWORD` | `storePassword` de `android/key.properties` |
| `KEY_PASSWORD` | `keyPassword` de `android/key.properties` |
| `KEY_ALIAS` | `nutrimat` |
| `SUPABASE_URL` | `https://ifincvqdsotorvmwzpos.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | La `sb_publishable_…` de `env/local.json` |

Los dos últimos no son secretos de verdad — la publishable key está pensada para
viajar en el cliente — pero van como secretos igual para que no queden escritos
en los registros de cada compilación.

Para generar el base64 del keystore, desde la raíz del proyecto:

```powershell
# PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android\nutrimat-upload.jks")) | Set-Clipboard
```

```bash
# bash
base64 -w0 android/nutrimat-upload.jks
```

> 🔑 **El keystore es irreemplazable.** Android exige que todas las versiones de
> una app estén firmadas con la misma clave. Si se pierde, no se puede publicar
> nunca más una actualización de Nutrimat: habría que sacar una app nueva, con
> otro `applicationId`, y nadie podría actualizar desde la vieja. Guardá una
> copia de `android/nutrimat-upload.jks` y `android/key.properties` fuera de
> esta máquina — gestor de contraseñas o un Drive privado.

Subirlo como secreto de GitHub **no cuenta como respaldo**: los secretos se
escriben pero no se pueden volver a leer.

---

## Compilar en tu máquina

La conexión a Supabase entra por `--dart-define`. Copiá
[`env/local.json.example`](../env/local.json.example) a `env/local.json`,
completá los dos valores y usalo en todos los comandos:

```bash
flutter run   --dart-define-from-file=env/local.json
flutter build apk --release --dart-define-from-file=env/local.json
```

`env/local.json` está en `.gitignore`. **Sin ese archivo la app compila y
arranca igual**, pero en modo local: no se puede iniciar sesión y los datos
viven solo en el teléfono. Es a propósito — así `flutter test` y un clon recién
bajado funcionan sin credenciales.

---

## Publicar

1. **Subir la versión** en `pubspec.yaml`. El formato es `semver+build`:

   ```yaml
   version: 1.1.0+2
   ```

   El número antes del `+` es lo que compara el updater; el de después es el
   `versionCode` de Android, que **tiene que crecer en cada release** o el
   teléfono se niega a instalar encima.

2. **Commitear y pushear** ese cambio a `main`.

3. **Tagear y pushear el tag**:

   ```bash
   git tag v1.1.0
   git push origin v1.1.0
   ```

El workflow [`release.yml`](../.github/workflows/release.yml) hace el resto:
verifica que el tag coincida con `pubspec.yaml`, corre `analyze` y los tests,
restaura el keystore, compila, verifica la firma y publica el release.

Si el tag y `pubspec.yaml` no coinciden, falla antes de compilar. Es a
propósito: un APK que dice `1.0.0` publicado bajo el tag `v1.1.0` rompe la
comparación de versiones del updater.

### Qué se publica

| Archivo | Para qué |
| --- | --- |
| `nutrimat-<v>-universal.apk` | **El que usa el updater.** Anda en cualquier teléfono |
| `nutrimat-<v>-arm64-v8a.apk` | Casi todos los teléfonos actuales, más chico |
| `nutrimat-<v>-armeabi-v7a.apk` | Equipos viejos de 32 bits |
| `nutrimat-<v>-x86_64.apk` | Emuladores |

⚠️ El nombre del universal es un contrato con la app: `GithubReleasesClient`
busca el asset que termina en `-universal.apk`. Si se cambia, el updater deja
de encontrar la actualización.

---

## Cómo actualiza la app

`Configuración → Actualizaciones` consulta
`api.github.com/repos/mattcastells/Nutrimat/releases/latest`, compara con la
versión instalada y, si hay una posterior, ofrece bajar el APK universal y
abrirlo con el instalador de Android.

Tres decisiones detrás de eso:

- **El chequeo es manual.** No hay consulta al abrir la app ni descarga
  automática: bajar 26 MB con datos móviles no es algo que decida el software.
- **No hay token en el APK.** El repositorio es público y la API se consulta sin
  credenciales. Un token embebido en un APK es un token filtrado.
- **La app no instala nada.** Escribe el archivo y se lo pasa al instalador de
  paquetes; el diálogo de confirmación lo muestra Android.

La primera vez, Android pide habilitar a Nutrimat como origen de instalación
(`Ajustes → Apps → Nutrimat → Instalar apps desconocidas`). Eso lo concede la
persona, una sola vez, y no se puede evitar.

### Si el repositorio pasara a privado

El updater deja de funcionar y **no alcanza con ponerle un token al cliente**.
Habría que mover la consulta a una Edge Function de Supabase que guarde el token
del lado del servidor y le devuelva a la app la URL de descarga.

### Si algún día va a Play Store

Hay que sacar el permiso `REQUEST_INSTALL_PACKAGES` del manifest y la descarga:
Google lo rechaza salvo para gestores de paquetes. El updater tendría que
limitarse a avisar que hay versión nueva y abrir la ficha de Play.

---

## Verificación continua

[`ci.yml`](../.github/workflows/ci.yml) corre en cada push a `main` y en cada
pull request: `flutter analyze --fatal-infos`, `flutter test`, y las suites
pgTAP de RLS y Storage contra un Postgres limpio con las 18 migraciones
aplicadas desde cero.
