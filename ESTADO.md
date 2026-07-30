# Estado — 30 de julio de 2026

Dónde quedamos y cómo retomar. **La app está publicada y en uso**: `v1.7.0` en
GitHub, con sesión, respaldo y análisis de foto contra Supabase.

---

## Lo próximo (por acá se arranca)

**La versión con el arreglo del updater hay que instalarla a mano una vez, en
todos los teléfonos.** El updater que está instalado —cualquiera de la 1.0.4 a
la 1.5.0— junta el APK entero en memoria y el sistema lo mata cerca del 80 % de
la barra (§13). No puede traerse su propio arreglo: hay que bajar el
`-universal.apk` del release desde el navegador. De ahí en más Configuración →
Actualizaciones funciona sin salir de la app.

Al que además nunca habilitó la instalación le va a faltar el permiso de §12,
que es otro problema y tiene su propio botón en la pantalla.

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
accesibilidad según el handoff. **262 tests en verde**, `flutter analyze`
limpio, APK de release firmado y verificado en el emulador contra el proyecto
real.

Comidas, actividades con cálculo MET, peso, medidas, agua, historial, progreso
y objetivos. Hay un **widget de calorías restantes** para la pantalla de inicio
del teléfono. El catálogo consulta Open Food Facts (con prioridad a productos
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
| Migraciones | 26 de 26 aplicadas |
| Tablas | 26, **todas con RLS** — se sumó `rate_limits` (migración 24) |
| Políticas | 83, más 5 de Storage |
| Buckets | 4 (3 de fotos + `backups`), privados, con política por prefijo |
| Pals | vínculo por código; `shared_days` sigue siendo la superficie compartida, ahora con fotos/agua/sueño/detalle de ejercicio opcionales, apagados por default y elegidos desde Perfil |
| Suite pgTAP | **66 de 66** (22 RLS + 9 Storage + 19 Pals + 8 hardening + 8 privacidad de Pals), en local y contra el proyecto real |

Detalle completo: [`supabase/README.md`](supabase/README.md)

### Distribución

Repositorio en [github.com/mattcastells/Nutrimat](https://github.com/mattcastells/Nutrimat),
público. CI en cada push y pull request: `analyze`, tests y la suite de RLS
contra un Postgres limpio. Última publicada: **v1.7.0**.

Publicar una versión es empujar un tag `v1.7.1`: el workflow compila el APK
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
13. **La descarga de la actualización se clavaba en el 78 %: era memoria, no
    red ni permiso.** El updater juntaba el APK entero en un `List<int>` antes
    de escribirlo. Un `List<int>` de Dart no guarda un byte por elemento sino
    una palabra de 64 bits: **ocho veces el tamaño del archivo**, más la copia
    que hace cada vez que la lista crece al doble. Para el APK de 75 MB eso son
    ~600 MB de lista y un pedido de 1 GB en la última duplicación. Android
    mataba el proceso ahí, y en el teléfono se veía como una barra que dejaba de
    moverse cerca del 80 % sin ningún error.

    Los números dicen cuándo se rompió: la lista duplica en potencias de dos,
    así que un APK de hasta 64 MiB terminaba pidiendo 512 MB y pasaba. La 1.0.3
    pesaba 57,5 MB y andaba; **la 1.0.4 pasó a 73 MB y no volvió a andar**.
    Todas las versiones desde entonces comparten ese código de descarga, así que
    **nadie pudo actualizarse desde la app entre la 1.0.4 y la 1.5.0** — y se
    atribuyó al permiso de §12, que es un problema real pero distinto.

    Desde ahora la descarga se escribe a disco a medida que llega
    (`downloadApkTo`, con `addStream` para que el archivo le ponga freno a la
    red) y el trozo que no llega tiene plazo propio. Corolario incómodo: **el
    arreglo no puede llegar por el updater**, porque el updater instalado es el
    roto. La versión que lo trae hay que bajarla del navegador una vez.
14. **Una lista de pals cacheada para toda la sesión se vivía como "las
    invitaciones no llegan".** `palsProvider` era un `FutureProvider` sin
    `autoDispose`: se resolvía una vez por sesión de app y no se volvía a pedir,
    ni saliendo de la pantalla y volviendo. Quien abría Pals antes de que le
    llegara una solicitud no la veía aparecer nunca, hasta cerrar y reabrir la
    app. Peor: al escribir el código de alguien que ya le había mandado una
    solicitud, el RPC devolvía `already` y la pantalla decía "ya tenés un
    vínculo con esa persona" **arriba de una lista vacía**, porque esa rama
    tampoco invalidaba el provider.

    Verificado contra la base antes de tocar nada: la fila `pending` estaba ahí,
    las policies la dejaban leer de los dos lados y `request_pal` en vivo es
    igual a la migración. Lo único que no se rehacía era la consulta. Ahora se
    relee al entrar, hay botón de actualizar, y Perfil muestra cuántas
    solicitudes quedaron sin responder.
15. **`ref.invalidate()` en `initState()` revienta si el widget se monta como
    raíz de una tab.** `PalsScreen` releía su lista al entrar así desde que se
    resolvió el punto 14, y anduvo bien mientras Pals era una pantalla que se
    empujaba desde Perfil. Al pasar a ser la raíz de la tab "Pals" (§ más abajo)
    empezó a tirar *"dependOnInheritedWidgetOfExactType() ... called before
    initState() completed"*: `ref.invalidate` pide el `ProviderContainer` por
    el árbol de widgets, y eso está prohibido mientras el propio `initState`
    del widget todavía no terminó — cosa que antes nunca pasaba porque un
    push crea su subárbol aparte, y que con una tab de `StatefulShellRoute` sí
    pasa. Se corrige con `WidgetsBinding.instance.addPostFrameCallback`
    alrededor del `invalidate`, no tocando la lógica. Corolario: cualquier
    pantalla que haga esto en `initState` y alguna vez pase a ser la raíz de
    una tab hay que revisarla por lo mismo.

---

## Hecho el 30 de julio de 2026

Pals ahora es una tab de la barra inferior (antes vivía escondida como una
fila de Perfil) y ahí mismo se ve organizado por categorías, igual que
Inicio: comida (con foto, si el otro la comparte), actividad (agregado
siempre, detalle si lo prende), agua y sueño — cada categoría apagada por
default y prendida desde Perfil → "Qué ven mis pals". Se puede mirar hasta
7 días atrás con el mismo selector de fecha que Inicio, acotado en las dos
puntas. Historial se mudó adentro de Progreso (ya no es una tab) para
hacerle lugar.

De paso: el peso de un día anterior ya se puede editar y borrar (con
deshacer) desde "Registros" en Progreso → Peso — antes ninguna fila ahí
tenía `onEdit` ni borrado, ni siquiera la de hoy. Se sacaron los mensajes de
"sin conexión" que nunca podían dispararse (no hay detección real desde que
se quitó el interruptor de desarrollo) y se corrigió la copia de Privacidad,
que seguía prometiendo que "todo vive en tu teléfono" con la nube ya
andando. Y una pasada de seguridad: los jobs de mantenimiento dejaron de ser
ejecutables por cualquier cuenta, `check_rate_limit` (atómico) reemplaza el
conteo manual de la cuota de IA y le puso cuota por primera vez a
`food-search` (que además nunca validaba el JWT, solo que el header
existiera), `android:allowBackup` pasó a `false`, y Gitleaks corre en cada
push.

### Una ronda de bugs reportados, el mismo día

Ocho, y tres eran el mismo error de fondo: **algo que no pasaba y no lo
decía**.

1. **"Registrar peso no funciona."** No era el sheet ni la navegación: un
   cambio de más de 3 kg contra el último registro mostraba un cartel y
   volvía sin escribir nada, esperando un segundo toque a "Guardar". Si en el
   medio se tocaba el campo —lo primero que hace cualquiera cuando algo no
   pasó— el aviso se reseteaba y el botón volvía a no hacer nada. Ahora es un
   diálogo con el botón que confirma al lado: un toque guarda, o pregunta.
   Nunca no hace nada.
2. **La estimación por texto.** `ai_analyses.photo_path` era `not null` y una
   estimación por texto no tiene foto, así que el insert fallaba **en
   silencio** (supabase-js devuelve el error, no lo lanza) en cada estimación.
   Ninguna quedó registrada nunca, y la función devolvía un `id` de una fila
   inexistente que la app guarda en `meals.ai_analysis_id`: la FK rechazaba
   esa comida y **ninguna comida cargada por descripción llegó a las tablas**.
   Migración 26, más un cinturón en `create_meal_with_items` (el registro de
   cómo se estimó no puede ser el motivo de que se pierda la comida). Del lado
   de la app, `_estimate()` solo capturaba `AppError` y un `TypeError` **no es
   una `Exception`**: cualquier respuesta con forma inesperada dejaba el botón
   girando para siempre. Y la entrada estaba escondida en el "+" de cada
   sección, así que quien entraba por el FAB no la encontraba nunca.
3. **"Agregar un ítem que falta"** en la revisión de la IA no hacía nada: los
   ítems vivían en una lista de la pantalla y el borrador se armaba recién al
   guardar, así que el buscador agregaba a `null` — y `addItem` sobre `null`
   no hace nada y no avisa. Ahora el borrador es la única lista y se abre al
   entrar. Un alimento del catálogo se distingue del estimado: lleva "Del
   catálogo" en vez de un badge de confianza, porque tiene una tabla
   nutricional detrás y no una estimación.
4. **Escanear.** El escáner no estaba donde se arma la comida, y desde el menú
   Agregar iba derecho a la cámara **sin comida abierta** (mismo `addItem`
   sobre `null`). Además el detalle de alimento cerraba **dos pantallas a
   ciegas**, asumiendo que entre el borrador y él hay exactamente una: con el
   escáner abierto desde el borrador, los dos pop se llevaban puesto el
   borrador. Ahora el detalle avisa "agregué" y cada pantalla intermedia se
   cierra sola.
5. Medidas corporales pasó de una fila de píldoras —donde había que elegir una
   métrica para ver su número y abrir un sheet para cargarla— a **campos con
   la última medida abajo**, que se guardan todos juntos. Las series salen por
   sheet. La regla de "campo en blanco = borrar el registro" quedó en un solo
   lugar (`MeasurementDraft`), porque ahora hay dos pantallas que cargan lo
   mismo.
6. El estado vacío se centraba dentro de **su propio** ancho, así que en "Mis
   cosas" —donde no hay botón que estire la columna— el bloque quedaba 60 px a
   la izquierda del eje. Arreglado en `EmptyState`, que es donde estaba.
7. Se sacó el "Buscar actualizaciones" de Acerca de: iba a la misma pantalla
   que la fila de arriba en Configuración.
8. El día de un pal quedó por categorías en orden fijo —comida, agua, deporte,
   sueño— con las comidas adentro por momento del día.

### Widget de calorías restantes

En la pantalla de inicio del teléfono, sin abrir la app. Detalle en
[`docs/estado-de-la-app.md`](docs/estado-de-la-app.md) §3; lo que importa acá
es que **el dato lleva su fecha y el widget la mira**: si lo guardado no es de
hoy no muestra el número, dice "Abrí Nutrimat para hoy". Un widget con el
número de ayer no se distingue de uno al día, y eso es la misma clase de
mentira que la app no se permite en ningún otro lado.

Verificado en el emulador: el sistema registra el provider
(`dumpsys appwidget`), la app escribe el dato del día
(`shared_prefs/nm_widget.xml`) y un `APPWIDGET_UPDATE` forzado dibuja sin
excepciones. **Falta verlo puesto en una pantalla de inicio de verdad**: eso
pide un toque largo en el launcher.

---

## Comandos para retomar

```bash
# La app  (sin --dart-define-from-file arranca en modo local, sin servidor)
flutter emulators --launch nutrimat
flutter run  --dart-define-from-file=env/local.json
flutter test                              # 262 tests
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
