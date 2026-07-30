# Estado de la app

Este documento describe qué está implementado en la aplicación Flutter que vive
en la raíz del proyecto, cómo correrla y qué queda pendiente. La fuente de
verdad funcional sigue siendo [`handoff/`](./handoff/00-index.md).

## 1. Cómo correrla

```bash
flutter pub get
flutter run                        # emulador o teléfono conectado
flutter test                       # cálculos + widgets + sincronía de tokens
flutter analyze                    # sin issues
dart run tool/gen_tokens.dart      # regenera lib/core/theme/tokens.dart
dart run flutter_launcher_icons    # regenera el ícono adaptativo
```

La app arranca en **modo `mock`**: no necesita ninguna variable de entorno ni
conexión. Todo corre contra la base local (`data/local/local_store.dart`). En
una instalación nueva la base arranca vacía y va a la bienvenida; "Probar sin
cuenta" siembra un día cargado y 30 días de historial (modo demo, D-15).

### Entorno de esta máquina

El SDK de Android quedó instalado en `%LOCALAPPDATA%\Android\Sdk` (command-line
tools 19.0, platform-tools, `platforms;android-36`, `build-tools;36.0.0`,
emulador y system image `android-36;google_apis;x86_64`), con las licencias
aceptadas y `flutter config --android-sdk` ya apuntado. Hay un AVD llamado
`nutrimat` (Pixel 7, API 36).

```bash
flutter emulators --launch nutrimat   # levanta el emulador
flutter run                           # instala y corre con hot reload

flutter build apk --release --split-per-abi
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk   ≈ 20 MB
```

Para pasarlo al teléfono: depuración USB activada, `flutter devices` para
verlo, y `flutter run` o `adb install` del APK de arm64. El release ya se firma
con el keystore propio del proyecto (§6).

## 2. Arquitectura

```
presentation  ──►  domain  ◄──  data
```

| Carpeta | Qué contiene |
| --- | --- |
| `lib/core/` | tokens generados, tema claro/oscuro, movimiento, router, formatos, errores |
| `lib/domain/` | enums, modelos, **cálculos puros**, servicios de agregación, interfaces de repositorio |
| `lib/data/` | base local, seed simulado, implementación de todos los repositorios |
| `lib/presentation/` | componentes del sistema de diseño, shell con tabs y FAB, pantallas |
| `tool/gen_tokens.dart` | `design-tokens.json` → `lib/core/theme/tokens.dart` |

`domain/` no importa Flutter. `presentation/` solo conoce las interfaces de
`domain/repositories/repositories.dart`; nunca importa `data/`.

## 3. Qué está implementado

**Cálculo (11-calculation-rules.md).** Las 11 familias de fórmulas como
funciones puras, con los 20 fixtures de §20 en verde más límites y errores:
BMR Mifflin-St Jeor, TDEE, objetivo calórico con clamp de RN-12, macros, MET,
crédito de ejercicio, balance diario, ritmo, duplicados, media móvil y
tendencia, adherencia, IMC.

**Pantallas.** Splash, bienvenida, alta, ingreso, recuperación, onboarding de
6 pasos, Inicio, desglose diario, menú Agregar y menú Ejercicio, nueva comida,
detalle de comida, buscador de alimentos, detalle con porciones, crear
alimento, escanear, cámara, analizando, revisar análisis, registro de
actividad (5 modos), buscar actividad, detalle de actividad, diálogo de
duplicado, peso, medidas, historial con filtros, detalle del día, progreso,
peso y calorías ampliados, progreso de actividad, objetivos, medidas, perfil,
perfil corporal, objetivo y macros, mis cosas, configuración, crédito de
ejercicio, unidades, apariencia, notificaciones, integraciones, privacidad,
eliminar cuenta y acerca de.

**Decisiones que se ven en pantalla.**

| Decisión | Dónde se comprueba |
| --- | --- |
| D-02 · crédito 0 % por defecto | Inicio oculta "Ajuste aplicado" y ofrece "El ejercicio no suma a tu presupuesto · Cambiar" |
| D-05 · porcentaje congelado | cambiar el crédito recalcula solo hoy y días futuros |
| D-06 · MET fuera del código | `assets/mock/met_catalog.json`, espejo del seed de `activity_types` |
| D-07 · nunca borra sola | el diálogo de duplicado es la única vía de resolución |
| D-12 · calorías activas | la importación descarta valores > 1500 kcal/h y recalcula por MET |
| D-16 · un peso por día | registrar de nuevo actualiza y avisa |
| D-17 / RN-14 · sin castigo | el exceso se dibuja en `accent-700`, nunca en rojo |
| D-22 · duración sin tope | presets + deslizador 5–240 + campo libre `hh:mm` hasta 24:00 |
| RN-03 · estimaciones | todo gasto lleva "≈" y su método visible |

**Widget de la pantalla de inicio del teléfono.** Las calorías restantes de hoy,
sin abrir la app. Vive en `android/app/src/main/kotlin/.../CaloriesWidget.kt` y
lo dibuja el launcher, en su proceso, así que no puede preguntarle nada a Dart:
la app le deja el dato escrito (`HomeWidgetPublisher`, canal
`io.nutrimat.app/widget`) cada vez que se registra algo y cada vez que se abre
o se vuelve a ella.

Dos decisiones que no son de comodidad:

- **El texto viaja ya formateado.** El separador de miles y las palabras
  ("kcal restantes", "kcal de más") salen de `Fmt` y del mismo criterio que
  Inicio. El widget no reimplementa nada porque dos formateadores terminan
  diciendo cosas distintas del mismo número.
- **El dato lleva su fecha y el widget la mira.** Si lo guardado no es de hoy no
  muestra el número: dice "Abrí Nutrimat para hoy". Un widget que no se
  actualizó desde ayer mostrando "te quedan 1.234 kcal" es peor que uno vacío,
  porque no se distingue de uno al día — la misma regla por la que la app nunca
  presenta una estimación como si fuera una medición.

**Movimiento (21-motion-and-loading.md).** Anillo con crecimiento y count-up,
barras de macros con stagger, gráficos con trazado progresivo y barras que
crecen desde abajo, transición de pantalla de 12 px, sheets, diálogos con
escala, skeletons con shimmer de 1200 ms, spinner que conserva el ancho del
botón, FAB que rota a ×, y el modo de movimiento reducido completo.

**Accesibilidad.** Etiquetas semánticas compuestas, acciones de swipe expuestas
también en el menú contextual, tabla de datos desplegable en cada gráfico,
área táctil de 48×48, texto escalable hasta 200 %, y el color nunca como único
portador de información.

## 4. Qué es real y qué está simulado

| Área | Cómo está resuelto |
| --- | --- |
| **Catálogo de alimentos** | **Real**: Open Food Facts, con prioridad a productos de Argentina. Lo consultado queda cacheado y sirve sin conexión. Los 24 alimentos de `assets/mock/foods.json` quedan como base offline |
| **Código de barras** | **Real**: consulta por EAN contra la API de producto de OFF |
| **Respaldo** | **Real**: exportar/importar JSON desde Configuración → Privacidad |
| Autenticación | Local: crea la sesión y el perfil sin servidor |
| Persistencia | Documento JSON en preferencias, con la forma del esquema de Drift |
| Análisis de foto | **Apagado** tras `FeatureFlags.aiPhotoAnalysis`: devolvía un resultado fijo |
| Sincronización de salud | **Apagada** tras `FeatureFlags.healthConnectSync`: insertaba 3 actividades inventadas |
| Sin conexión | No hay detección real. Existió un interruptor de desarrollo en Configuración → Avanzado para simularlo; se sacó de la interfaz por peligroso en manos de quien usa la app |

La regla de los flags: **mientras una integración devuelva datos inventados, su
flag va en `false`**. Es preferible una pantalla que diga "todavía no" a un
registro falso en el historial. Se encienden al compilar:

```bash
flutter run --dart-define=NM_AI_PHOTO=true
```

### Datos de ejemplo

"Crear cuenta" arranca la app **vacía**. Los 3 comidas, 2 actividades y 30 días
de historial solo entran por "Probar sin cuenta" (modo demo, D-15).

## 5. Verificación

| Qué | Resultado |
| --- | --- |
| `flutter analyze` | sin issues, con reglas extra sobre `flutter_lints` |
| `flutter test` | **110 en verde**: 55 de cálculo (los 20 fixtures + límites y errores), 13 del catálogo externo, 4 de respaldo, 5 de Inicio, 4 de arranque y navegación, 1 de sincronía de tokens |
| Desbordes de layout a 393 × 852 dp | ninguno |
| `flutter build apk --debug` | ✓ `app-debug.apk` (144 MB) |
| `flutter build apk --release --split-per-abi` | ✓ arm64 19,6 MB · armeabi-v7a 17,4 MB · x86_64 20,7 MB |
| Corrida en emulador (Pixel 7, API 36) | ✓ bienvenida → demo → Inicio → desglose → Progreso → registro de actividad |

Los tests de widget corren a tamaño de teléfono real (1179 × 2556 px, 3×) para
que un desborde aparezca como falla y no como un detalle que se ve recién en
el dispositivo.

**Lo que solo apareció al correrla de verdad**, ya corregido:

1. El APK de release **no declaraba `android.permission.INTERNET`**. En debug
   Flutter la agrega sola, así que el catálogo online andaba al desarrollar y
   no en el APK instalado. Es la clase de error que no se ve hasta probar el
   artefacto que se va a distribuir.
2. El `cgi/search.pl` de Open Food Facts devuelve **503** con frecuencia. Se
   migró al servicio moderno (`search.openfoodfacts.org`), que además permite
   filtrar por país.
3. La barra de tabs quedaba 1 px corta: el borde superior comía altura del
   contenido.
4. La fila-día del Historial no truncaba la fecha y desbordaba 30 px.
5. La barra de Grasas usaba `caution`, que el sistema reserva para lo estimado
   o incierto (§1.3). Los tres macros pasaron a la paleta de datos (§1.4).
6. Los sheets se abrían en el navigator del shell, así que el FAB y la barra de
   tabs quedaban **encima** del sheet y tapaban su último botón. Ahora usan el
   navigator raíz y respetan el orden de elevación (sheet 30 · fab 20).
7. El compilador incremental de Kotlin falla en Windows cuando el proyecto y el
   caché de pub están en discos distintos. Se apagó en `gradle.properties`.

## 6. Firma y distribución

El release se firma con `android/nutrimat-upload.jks` y las credenciales de
`android/key.properties`, **los dos fuera del control de versiones**. Si se
pierde el keystore no se puede volver a publicar una actualización de la misma
app: hay que respaldarlo junto con su contraseña.

Si `key.properties` no está, el build de release cae a la firma de debug para
que `flutter run --release` siga funcionando en otra máquina.

```bash
flutter build apk --release --split-per-abi
# app-arm64-v8a-release.apk ≈ 20 MB
```

R8 está activo (`isMinifyEnabled`), con las reglas de `proguard-rules.pro`.

## 7. Qué falta

1. **Supabase**: proyecto, migraciones de `08-supabase-plan.md`, RLS con pgTAP,
   y reemplazar `LocalRepository` por la implementación remota + Drift.
2. **Gemini**: Edge Function `analyze-meal-photo` y la cuota real de 20/día;
   después, prender `NM_AI_PHOTO`.
3. **USDA**: Edge Function `food-search` para los genéricos — su clave no puede
   vivir en el cliente. Open Food Facts ya está conectado sin clave.
4. **Health Connect de verdad**: adaptador en `data/native/`, permisos y
   `minSdk 29`; después, prender `NM_HEALTH_SYNC`.
5. **Publicación en GitHub** y CI (análisis, tests, goldens).
6. **Goldens** de las 48 pantallas y tests de integración con Patrol.
7. **Lint de capas** (`import_lint`) para que el build falle si se viola la
   dirección de dependencias.
8. **Mover a Drift/SQLite**: hoy todo el usuario vive en un documento JSON en
   preferencias. Anda, pero no es donde debería estar un año de registros.

## 8. Una inconsistencia del handoff

`11-calculation-rules.md` §11 ubica una carrera de 10 km/h en el tramo
9,7–11,3 km/h, que da **MET 11,0**; el fixture T-15 de §20 espera **9,8** para
esa misma entrada. Se implementó la tabla de §11, que es la regla normativa, y
el test lo deja documentado. Si el valor correcto es 9,8, hay que corregir los
límites de la tabla, no la función.
