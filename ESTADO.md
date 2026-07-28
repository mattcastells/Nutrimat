# Estado — 28 de julio de 2026

Dónde quedamos y cómo retomar. **La app está publicada y en uso**: `v1.0.2` en
GitHub, con sesión, respaldo y análisis de foto contra Supabase.

---

## Lo próximo (por acá se arranca)

**Probar el análisis de foto en un teléfono de verdad.** Es lo único del
circuito que nunca se ejecutó: el emulador no tiene cámara, así que la subida al
bucket y la Edge Function de Gemini están escritas y desplegadas pero sin una
corrida real. Sacar una foto de una comida las ejercita a las dos.

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

39 pantallas, el sistema de diseño Nocturne completo, animaciones y
accesibilidad según el handoff. **136 tests en verde**, `flutter analyze`
limpio, APK de release firmado y verificado en el emulador contra el proyecto
real.

Comidas, actividades con cálculo MET, peso, medidas, agua, historial, progreso
y objetivos. El catálogo consulta Open Food Facts (con prioridad a productos
argentinos) y el escaneo por código de barras también.

No hay asistente inicial: entrar lleva directo a Inicio y los datos del perfil
se cargan desde Perfil cuando se quiera.

Detalle completo: [`docs/estado-de-la-app.md`](docs/estado-de-la-app.md)

### El backend (Supabase)

Proyecto `ifincvqdsotorvmwzpos`, región **sa-east-1**, Postgres 17.6.

| | |
| --- | --- |
| Migraciones | 19 de 19 aplicadas |
| Tablas | 24, **todas con RLS** |
| Políticas | 78, más 3 de Storage |
| Buckets | 4 (3 de fotos + `backups`), privados, con política por prefijo |
| Suite pgTAP | **31 de 31** (22 de RLS + 9 de Storage), en local y contra el proyecto real |

Detalle completo: [`supabase/README.md`](supabase/README.md)

### Distribución

Repositorio en [github.com/mattcastells/Nutrimat](https://github.com/mattcastells/Nutrimat),
público. CI en cada push y pull request: `analyze`, tests y la suite de RLS
contra un Postgres limpio. Última publicada: **v1.0.2**.

Publicar una versión es empujar un tag `v1.0.3`: el workflow compila el APK
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
2. **`supabase db push` no funciona desde esta máquina**: el host directo de
   Supabase es IPv6 puro y acá no hay IPv6. Las migraciones se aplican con
   `psql` contra el *session pooler* — el procedimiento exacto está en
   `supabase/README.md`.
3. **RLS sin `GRANT` no hace nada útil**: `authenticated` recibe *permission
   denied* y las políticas ni se evalúan. Los grants están en la migración 14.
4. **El compilador incremental de Kotlin** falla en Windows cuando el proyecto
   está en `D:` y el caché de pub en `C:`. Apagado en `android/gradle.properties`.
5. **Los sheets deben abrirse en el navigator raíz**, si no el FAB y la barra de
   tabs quedan por encima y tapan sus botones.
6. **El endpoint clásico de Open Food Facts devuelve 503 seguido.** Se usa el
   moderno (`search.openfoodfacts.org`).
7. **`flutter build apk` puede devolver un APK viejo.** Si el build tarda 5 s en
   vez de ~140 s, Gradle está reusando un artefacto cacheado y se instala una
   versión anterior. `flutter clean` antes de verificar algo en el emulador.
8. **Los buckets restringen los MIME.** Los de fotos solo aceptan imágenes: el
   respaldo JSON necesitó su propio bucket.

---

## Comandos para retomar

```bash
# La app  (sin --dart-define-from-file arranca en modo local, sin servidor)
flutter emulators --launch nutrimat
flutter run  --dart-define-from-file=env/local.json
flutter test                              # 136 tests
flutter build apk --release --dart-define-from-file=env/local.json

# El backend
supabase start                            # stack local, Studio en :54323
supabase test db                          # suite de RLS
supabase stop
```

---

## Lo que queda

1. **Probar Gemini en un teléfono** — escrito y desplegado, nunca ejecutado.
2. **USDA** para alimentos genéricos vía Edge Function (su clave no puede ir en
   el cliente). Open Food Facts ya está conectado y no necesita clave.
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
