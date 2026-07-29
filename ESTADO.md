# Estado — 29 de julio de 2026

Dónde quedamos y cómo retomar. **La app está publicada y en uso**: `v1.5.0` en
GitHub, con sesión, respaldo y análisis de foto contra Supabase.

---

## Lo próximo (por acá se arranca)

**La versión con el arreglo del updater hay que instalarla a mano una vez.**
El que está instalado en el teléfono no puede pedir el permiso de instalación
(ver "Cosas que ya nos mordieron" §12), así que no puede traerse el arreglo
solo: hay que bajar el `-universal.apk` del release desde el navegador. De ahí
en más Configuración → Actualizaciones funciona sin salir de la app.

**Si un teléfono quedó sin datos, restaurar antes de cargar nada.**
Configuración → Respaldo en la nube → "Restaurar desde la nube". Desde la 1.3.1
un documento vacío ya no puede pisar la copia buena (§9), así que la copia
está a salvo mientras tanto; en versiones anteriores no lo estaba.

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

**Verificar las filas contra uso real.** Desde la 1.5.0 los datos se guardan
por **dos caminos a la vez**: el documento JSON en Storage (con historial de
diez copias fechadas desde la 1.4.3) y **filas en las tablas**. El documento
sigue siendo la fuente de verdad de la app; las filas se llenan en paralelo
para poder compararlas sin arriesgar nada.

Lo que falta es mirar unos días de uso y confirmar que las filas coinciden con
el documento. Recién ahí se invierte la prioridad —que es cambiar el orden en
`splash_screen.dart`, no una reescritura— y las tablas pasan a mandar
(13-state-management.md §5 y §8).

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
accesibilidad según el handoff. **235 tests en verde**, `flutter analyze`
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

**Catálogo de alimentos.** Tres fuentes que no se pisan:

| Fuente | Qué cubre | Dónde vive |
| --- | --- | --- |
| **ARGENFOODS** (UNLu) | 252 alimentos argentinos verificados | dentro del APK, anda sin conexión |
| **Open Food Facts** | productos envasados, por código de barras | consulta directa, Argentina primero |
| **USDA** | alimentos genéricos y crudos | Edge Function `food-search` |

La tabla argentina se extrajo de los PDF de ARGENFOODS y **cada fila se valida
contra Atwater** (4/4/9) y contra la suma de componentes, en el parser y otra
vez en `test/data/argenfoods_catalog_test.dart`. No es paranoia: el primer
intento dio "aceite de oliva, 100 g de proteína" —las columnas corridas— y ese
número en el historial de alguien es peor que no tener el alimento.

**Comidas frecuentes y descripción por texto.** Lo que se repite aparece arriba
del "+" de cada slot para cargarlo de una. Y se puede escribir "dos empanadas
de carne y una coca": lo estima la Edge Function `analyze-meal-text`, que
comparte validación y cuota con la de foto.

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
| Migraciones | 23 de 23 aplicadas |
| Tablas | 25, **todas con RLS** — agua, sueño y recordatorios entraron en la 23; salieron cuatro de fuerza que nunca se usaron |
| Políticas | 78, más 3 de Storage |
| Buckets | 4 (3 de fotos + `backups`), privados, con política por prefijo |
| Pals | vínculo por código; `shared_days` es la **única** superficie compartida |
| Suite pgTAP | **50 de 50** (22 RLS + 9 Storage + 19 Pals), en local y contra el proyecto real |

Detalle completo: [`supabase/README.md`](supabase/README.md)

### Distribución

Repositorio en [github.com/mattcastells/Nutrimat](https://github.com/mattcastells/Nutrimat),
público. CI en cada push y pull request: `analyze`, tests y la suite de RLS
contra un Postgres limpio. Última publicada: **v1.5.0**.

Publicar una versión es empujar un tag `v1.5.1`: el workflow compila el APK
firmado y crea el release. La app se actualiza sola desde **Configuración →
Actualizaciones**, sin pasar por Play Store.

Procedimiento completo: [`docs/releases.md`](docs/releases.md), condensado con
sus trampas en la skill [`.claude/skills/publicar`](.claude/skills/publicar/SKILL.md).

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
9. **Una lectura fallida borraba todos los datos del teléfono.** `LocalStore`
   hacía `remove()` sobre el documento que no había podido interpretar: un
   solo registro con un campo raro y se perdía **todo** —comidas, peso,
   medidas, historial— sin copia y sin aviso. Encima la app quedaba
   indistinguible de un teléfono nuevo, así que el respaldo vacío que salía de
   ahí podía pisar la copia buena de la nube.

   Cuatro reglas que quedaron y no se negocian:

   - Lo que no se puede leer **se aparta, no se borra** (`quarantine`).
   - Cada registro se lee por separado: uno malo no se lleva puesto el resto.
   - **Un documento sin un solo registro no se sube nunca.** Es la última
     línea de defensa y no depende de que la puerta de `openAfterRestore`
     esté bien: esa puerta se abre igual cuando la descarga falla.
   - Una lectura fallida y un teléfono vacío **no se pueden ver igual**:
     `RestoreOutcome` los distingue y la app lo dice en Inicio.

   Corolario: cualquier acción que llame a `store.reset()` —el modo demo— tiene
   que preguntar antes si hay datos cargados.
10. **Todo `await` contra la red necesita timeout propio.** La subida de la
    foto al bucket no tenía, así que con señal mala el `Future` no terminaba
    nunca y el análisis por IA se quedaba girando para siempre en "Está
    tardando más de lo normal" — sin error, sin salida. Peor: `analyze()` se
    llamaba sin `try`, así que aunque hubiera fallado nadie lo habría
    mostrado. Una espera eterna es la peor forma de contar un fallo, porque no
    se distingue de estar por terminar. Ídem `openAfterRestore`, que se comía
    el error de descarga en silencio.
11. **Publicar APK por arquitectura rompió la actualización.**
    `--split-per-abi` le suma un corrimiento por ABI al `versionCode`
    (`abi × 1000 + code`): en la 1.3.1 el universal quedó en 11 y el de arm64
    en 2011. Como el updater baja **siempre el universal**, quien instaló el
    de su arquitectura recibía la actualización, la descargaba, y Android la
    rechazaba por downgrade. El diálogo dice "No se instaló la app" y nada
    más. Desde la 1.3.2 se publica un solo APK y el `versionCode` arranca en
    **5000**, por encima del 4011 que llegó a publicarse. Igualar los códigos
    desde `build.gradle.kts` **no funciona**: el plugin de Flutter los pisa
    después. Si vuelven los APK chicos, primero el updater tiene que elegir
    por arquitectura.
12. **`REQUEST_INSTALL_PACKAGES` en el manifest no alcanza para instalar.**
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
flutter test                              # 235 tests
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
2. **Dar vuelta la fuente de verdad.** Desde la 1.5.0 cada cambio se escribe
   en las tablas *además* del documento JSON, y al entrar con el teléfono
   vacío los datos se traen de las tablas. Pero el documento **sigue siendo la
   fuente de verdad de la app**: las filas se llenan en paralelo para poder
   verificarlas contra uso real sin arriesgar nada. Cuando estén verificadas,
   invertir la prioridad es cambiar el orden en `splash_screen.dart`, no una
   reescritura.

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
