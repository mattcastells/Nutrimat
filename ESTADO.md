# Estado — 29 de julio de 2026

Dónde quedamos y cómo retomar. **La app está publicada y en uso**: `v1.3.0` en
GitHub, con sesión, respaldo y análisis de foto contra Supabase.

---

## Lo próximo (por acá se arranca)

**La versión con el arreglo del updater hay que instalarla a mano una vez.**
El que está instalado en el teléfono no puede pedir el permiso de instalación
(ver "Cosas que ya nos mordieron" §9), así que no puede traerse el arreglo solo:
hay que bajar el `-universal.apk` del release desde el navegador. De ahí en más
Configuración → Actualizaciones funciona sin salir de la app.

**Probar el análisis de foto en un teléfono de verdad.** Es lo único del
circuito que nunca se ejecutó: el emulador no tiene cámara, así que la subida al
bucket y la Edge Function de Gemini están escritas y verificadas contra el
servidor, pero sin una foto real de por medio.

**Cambiar el nombre de la cuenta de prueba.** La migración
`20260801002100_display_name_no_email` ya está aplicada, así que ninguna cuenta
nueva vuelve a quedar con la parte del correo anterior a la arroba como nombre
visible. Las que ya existen conservan el que tengan —reescribirlas a ciegas le
borraría el nombre a quien sí lo puso—, y se cambian desde Perfil → tocar el
nombre.

Después, si hiciera falta: los datos se respaldan como un documento JSON en
Storage, no como filas. Eso cubre no perder nada y cambiar de teléfono. Recién
si se necesita consultar del lado del servidor —estadísticas, varios
dispositivos a la vez— habría que pasar a sincronización relacional contra las
24 tablas (13-state-management.md §5 y §8).

Para compilar con servidor hay que pasarle la config:

```bash
flutter run --dart-define-from-file=env/local.json
```

Sin ese archivo la app arranca en **modo local** y lo dice: no autentica contra
nadie y los datos no salen del teléfono. Es a propósito, para que un clon recién
bajado y `flutter test` funcionen sin credenciales.

⚠️ La `secret key` (`sb_secret_…`) no va nunca en la app, ni en el repo, ni en
un chat: saltea RLS por completo. Solo vive en los secretos de las Edge
Functions.

---

## Qué está hecho

### La app (Flutter, Android)

40 pantallas, el sistema de diseño Nocturne completo, animaciones y
accesibilidad según el handoff. **189 tests en verde**, `flutter analyze`
limpio, APK de release firmado y verificado en el emulador contra el proyecto
real.

Comidas, actividades con cálculo MET, peso, medidas, agua, historial, progreso
y objetivos. El catálogo consulta Open Food Facts (con prioridad a productos
argentinos) y el escáner lee el código de barras con la cámara. Recordatorios
locales de agua y de registro con horario configurable, sueño por noche y
planificación de comidas hasta tres días adelante.

**Objetivos.** Cuatro: bajar de peso, mantener, subir de peso y ganar músculo.
Elegir uno deja configurado el ritmo, las calorías, los macros y la actividad
semanal de una sola vez (`domain/calculations/goal_presets.dart` explica de
dónde sale cada número). Se elige al crear la cuenta y se cambia desde Perfil.
Las calorías del día se editan desde la propia tarjeta de Inicio, de a 50 kcal
o escribiendo el valor.

**Medidas corporales.** Tres grupos, como los entrega una nutricionista:
perímetros en cm, pliegues cutáneos en mm y bioimpedancia. Se cargan todos
juntos por fecha, no de a uno. El peso y la altura quedan afuera a propósito:
tienen su propio registro y alimentan el cálculo de BMR.

No hay asistente inicial: al crear la cuenta se pide el nombre y el objetivo, y
de ahí se entra directo a Inicio. El resto de los datos del perfil se cargan
desde Perfil cuando se quiera.

Detalle completo: [`docs/estado-de-la-app.md`](docs/estado-de-la-app.md)

### El backend (Supabase)

Proyecto `ifincvqdsotorvmwzpos`, región **sa-east-1**, Postgres 17.6.

| | |
| --- | --- |
| Migraciones | 22 de 22 aplicadas |
| Tablas | 24, **todas con RLS** |
| Políticas | 78, más 3 de Storage |
| Buckets | 4 (3 de fotos + `backups`), privados, con política por prefijo |
| Pals | vínculo por código; `shared_days` es la **única** superficie compartida |
| Suite pgTAP | **50 de 50** (22 RLS + 9 Storage + 19 Pals), en local y contra el proyecto real |

Detalle completo: [`supabase/README.md`](supabase/README.md)

### Distribución

Repositorio en [github.com/mattcastells/Nutrimat](https://github.com/mattcastells/Nutrimat),
público. CI en cada push y pull request: `analyze`, tests y la suite de RLS
contra un Postgres limpio. Última publicada: **v1.3.0**.

Publicar una versión es empujar un tag `v1.3.1`: el workflow compila el APK
firmado y crea el release. La app se actualiza sola desde **Configuración →
Actualizaciones**, sin pasar por Play Store.

Procedimiento completo: [`docs/releases.md`](docs/releases.md)

---

## Estado de la máquina

Todo esto quedó instalado y configurado; no hay que rehacerlo.

| Herramienta | Dónde |
| --- | --- |
| Android SDK | `%LOCALAPPDATA%\Android\Sdk` (platform-tools, android-36, build-tools 36) |
| Emulador | AVD `nutrimat` (Pixel 7, API 36) — `flutter emulators --launch nutrimat` |
| Keystore de release | `android/nutrimat-upload.jks` + `android/key.properties` |
| Supabase CLI | 2.110.0 (scoop) |
| Stack local | quedó **corriendo** en Docker — se apaga con `supabase stop` |

### 🔑 Respaldar antes que nada

`android/nutrimat-upload.jks` y `android/key.properties` están fuera de git a
propósito. **Si se pierde el keystore no se puede volver a publicar una
actualización de la app nunca más.** Copialos a un lugar seguro (gestor de
contraseñas, Drive privado) antes de seguir.

---

## Cosas que ya nos mordieron

Para no volver a perder tiempo con lo mismo:

1. **El APK de release no llevaba `android.permission.INTERNET`.** Flutter la
   inyecta sola en debug, así que el catálogo online andaba al desarrollar y
   habría estado muerto en el teléfono. Ya está en el manifest.
2. **`supabase db push --linked` no funciona desde esta máquina**: resuelve el
   host directo de Supabase, que es IPv6 puro, y acá no hay IPv6. Pero
   pasándole el *session pooler* con `--db-url` anda, sin Docker y sin
   `supabase login` — el comando exacto está en `supabase/README.md`. Sin
   Docker tira warnings de `failed to connect to the docker API`: son del
   caché opcional del catálogo, no de la migración. Confirmar siempre con
   `supabase migration list`.
3. **RLS sin `GRANT` no hace nada útil**: `authenticated` recibe *permission
   denied* y las políticas ni se evalúan. Los grants están en la migración 14.
4. **El compilador incremental de Kotlin** falla en Windows cuando el proyecto
   está en `D:` y el caché de pub en `C:`. Apagado en `android/gradle.properties`.
5. **Los sheets deben abrirse en el navigator raíz**, si no el FAB y la barra de
   tabs quedan por encima y tapan sus botones.
6. **El endpoint clásico de Open Food Facts devuelve 503 seguido.** Se usa el
   moderno (`search.openfoodfacts.org`).
7. **`flutter build apk` puede devolver un APK viejo**, y ni la duración del
   build ni `flutter clean` alcanzan para detectarlo o evitarlo: pasó con
   builds de 5 s, de 171 s, y con `flutter clean` de por medio. Gradle guarda
   estado en `android/.gradle` y en su daemon. Antes de verificar algo en el
   emulador:

   ```bash
   (cd android && ./gradlew --stop)
   rm -rf build .dart_tool android/.gradle android/app/build
   flutter pub get && flutter build apk --release ...
   ```

   Para confirmar que el APK es el del código, buscar un texto nuevo dentro de
   `libapp.so` (se extrae del APK, que es un zip). Es la única prueba que no
   miente.
8. **Los buckets restringen los MIME.** Los de fotos solo aceptan imágenes: el
   respaldo JSON necesitó su propio bucket.
9. **`REQUEST_INSTALL_PACKAGES` en el manifest no alcanza para instalar.**
   Desde Android 8 el permiso solo habilita a *pedir*; quien autoriza es la
   persona, **por app instaladora**, en Ajustes → Apps → Nutrimat → Instalar
   apps desconocidas. Sin eso `startActivity` con el APK devuelve éxito y el
   sistema descarta la instalación sin decir nada: la app mostraba "Android
   está instalando" y el teléfono no instalaba nada. Ahora se consulta
   `canRequestPackageInstalls()` antes de bajar los 25 MB y hay un botón que
   lleva a la pantalla exacta. El instalador dejó de depender de `open_filex`
   (que no contempla ese chequeo) y vive en `MainActivity.kt` con su propio
   `FileProvider` (`${applicationId}.updates`).

---

## Comandos para retomar

```bash
# La app  (sin --dart-define-from-file arranca en modo local, sin servidor)
flutter emulators --launch nutrimat
flutter run  --dart-define-from-file=env/local.json
flutter test                              # 189 tests
flutter build apk --release --dart-define-from-file=env/local.json

# El backend
supabase start                            # stack local, Studio en :54323
supabase test db                          # suite de RLS
supabase stop
```

---

## Lo que queda

1. **Notificación de pal** ("X cargó su desayuno"): necesita push (FCM) y un
   disparador del lado del servidor. Los recordatorios locales ya están.
2. **USDA** para alimentos genéricos vía Edge Function (su clave no puede ir
   en el cliente). Open Food Facts ya está conectado y no necesita clave.
3. **Sincronización relacional** contra las 24 tablas, si algún día hace falta
   consultar del lado del servidor. Hoy el respaldo en Storage alcanza.

**Health Connect queda descartado**: con la app usada por una sola persona que
carga sus actividades a mano, importar desde Samsung Health aporta poco y trae
riesgo de doble conteo. El flag y las pantallas quedan por si cambia.

---

## Resuelto: la tabla MET de carrera

`11-calculation-rules.md` §11 chocaba con el fixture T-15 de §20 para una
carrera de 10 km/h (11,0 contra 9,8). **Ganó el fixture.** Los cortes de la
tabla (6,5 / 8,0 / 9,7 / 11,3 km/h) son 4/5/6/7 mph convertidos — los anclajes
del Compendium of Physical Activities — y la columna de caminata ya asignaba a
cada tramo el MET de su borde *inferior*. La de carrera usaba el *superior*:
estaba corrida un renglón. Se corrigió la tabla, no la función.
