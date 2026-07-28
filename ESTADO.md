# Estado — 28 de julio de 2026

Dónde quedamos y cómo retomar. La app funciona y se puede instalar; el backend
está creado y verificado. Falta unir las dos cosas.

---

## Lo próximo (por acá se arranca)

**Pegar la `anon key` en `supabase/.env.local`.** Es el único dato que falta
para conectar la app con Supabase.

> Dashboard → proyecto `ifincvqdsotorvmwzpos` → Project Settings → API →
> Project API keys → **`anon` / `public`**

```bash
# supabase/.env.local  (ya existe, con la contraseña de la base cargada)
SUPABASE_ANON_KEY=eyJ...
```

Con eso sigue: `supabase_flutter`, Auth real y un repositorio remoto detrás de
las mismas interfaces de `domain/repositories/`. **Las pantallas no se tocan**:
esa es toda la ventaja de haber separado las capas.

⚠️ La `service_role key` no va nunca en la app, ni en el repo, ni en un chat:
saltea RLS por completo. Solo vive en los secretos de las Edge Functions.

---

## Qué está hecho

### La app (Flutter, Android)

40 pantallas, el sistema de diseño Nocturne completo, animaciones y
accesibilidad según el handoff. **82 tests en verde**, `flutter analyze`
limpio, APK de release firmado con keystore propio y probado en el emulador.

Funciona hoy sin backend: comidas, actividades con cálculo MET real, peso,
medidas, historial, progreso y objetivos, todo local. El catálogo de alimentos
consulta Open Food Facts de verdad (con prioridad a productos argentinos) y el
escaneo por código de barras también.

Detalle completo: [`docs/estado-de-la-app.md`](docs/estado-de-la-app.md)

### El backend (Supabase)

Proyecto `ifincvqdsotorvmwzpos`, región **sa-east-1**, Postgres 17.6.

| | |
| --- | --- |
| Migraciones | 17 de 17 aplicadas |
| Tablas | 24, **todas con RLS** |
| Políticas | 78 |
| Suite pgTAP de RLS | **22 de 22**, en local y contra el proyecto real |

Detalle completo: [`supabase/README.md`](supabase/README.md)

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

---

## Comandos para retomar

```bash
# La app
flutter emulators --launch nutrimat
flutter run
flutter test                              # 82 tests
flutter build apk --release --split-per-abi

# El backend
supabase start                            # stack local, Studio en :54323
supabase test db                          # suite de RLS
supabase stop
```

---

## Después de conectar la app

En orden de lo que más desbloquea:

1. **Auth y sincronización**: reemplazar `LocalRepository` por local-first con
   Drift + `sync_queue` contra Supabase (13-state-management.md §5 y §8).
2. **Buckets de Storage** y sus políticas por prefijo (08-supabase-plan.md §3).
3. **Gemini**: Edge Function `analyze-meal-photo` con la key del lado del
   servidor; después prender el flag `NM_AI_PHOTO`.
4. **USDA** para alimentos genéricos vía Edge Function (su clave no puede ir en
   el cliente). Open Food Facts ya está conectado y no necesita clave.
5. **Health Connect** de verdad: adaptador nativo, permisos, `minSdk 29`;
   después prender `NM_HEALTH_SYNC`.
6. **GitHub y CI**: `flutter analyze`, tests y la suite de RLS en cada push.

---

## Resuelto: la tabla MET de carrera

`11-calculation-rules.md` §11 chocaba con el fixture T-15 de §20 para una
carrera de 10 km/h (11,0 contra 9,8). **Ganó el fixture.** Los cortes de la
tabla (6,5 / 8,0 / 9,7 / 11,3 km/h) son 4/5/6/7 mph convertidos — los anclajes
del Compendium of Physical Activities — y la columna de caminata ya asignaba a
cada tramo el MET de su borde *inferior*. La de carrera usaba el *superior*:
estaba corrida un renglón. Se corrigió la tabla, no la función.
