# Auditoría técnica — 1 de agosto de 2026

> **Estado: aplicada.** Este documento es el informe original, que se conserva
> como está para que quede el diagnóstico. Lo que se hizo con cada hallazgo está
> en [`auditoria-handoff.md`](auditoria-handoff.md), que se fue tachando a
> medida que se arreglaba. Resumen: las etapas 1 a 6 están implementadas y
> verificadas —**399 tests** de Flutter, **85 pgTAP**, `analyze --fatal-infos`
> limpio, 32 migraciones aplicando desde cero— y no se publicó ninguna versión
> todavía.

Alcance: la app entera (Flutter/Android), el backend Supabase (27 migraciones,
4 Edge Functions, 5 suites pgTAP), CI/CD, dependencias, documentación y tests.
Sin modificar código: esto es el informe y el plan.

**Punto de partida sano**: `flutter analyze` limpio, **376 tests en verde**, sin
secretos en la historia de git (verificado con `git log -S`), Gitleaks corriendo
en CI, `android:allowBackup=false`, RLS habilitado en las 26 tablas, ninguna
clave de proveedor dentro del APK. Lo que sigue no contradice eso: son los
huecos que quedan debajo.

## Cómo leer las certezas

| Etiqueta | Qué significa |
| --- | --- |
| **CONFIRMADO** | Verificado leyendo el código y el esquema. No requiere más prueba para actuar. |
| **PROBABLE** | El mecanismo está en el código; falta una corrida real para verlo. Se indica cuál. |
| **SUGERENCIA** | Mejora, no defecto. |

**Brecha conocida de esta auditoría**: la revisión dedicada de
`lib/domain/calculations/` (13 archivos: BMR, TDEE, MET, macros, adherencia) y
de la suite de 38 tests quedó incompleta por corte de sesión. Los cálculos **no
están auditados a fondo**; ver la etapa 5 del plan.

---

# 1 · Seguridad y privacidad

## C-1 · Quien envía una solicitud de Pal puede aceptársela solo, y ver el día del otro sin consentimiento

**CRÍTICO · CONFIRMADO**

- **Archivo**: [`supabase/migrations/20260801001900_pals.sql:131-136`](../supabase/migrations/20260801001900_pals.sql#L131-L136)
- **Evidencia**:

  ```sql
  -- Aceptar o bloquear lo hace quien recibe; cancelar, cualquiera de los dos.
  create policy pals_update on public.pals
    for update to authenticated
    using (requester_id = (select auth.uid()) or addressee_id = (select auth.uid()))
    with check (requester_id = (select auth.uid()) or addressee_id = (select auth.uid()));
  ```

  El comentario dice que aceptar lo hace quien recibe. La política **no lo dice**:
  no restringe columnas ni transiciones, y el `using` incluye al *requester*. No
  hay trigger sobre `pals` que lo compense (inventario de `create trigger` en las
  27 migraciones).

  `is_pal_of` ([`:84-89`](../supabase/migrations/20260801001900_pals.sql#L84-L89))
  solo mira `status = 'accepted'` — no le importa quién lo puso.

- **Cómo reproducirlo**: con el JWT de A, tras `request_pal(<código de B>)`:

  ```sql
  update pals set status = 'accepted', responded_at = now()
   where requester_id = auth.uid();   -- 1 fila
  select * from shared_days where user_id = '<B>';  -- el día de B
  ```

- **Impacto**: anula el consentimiento de Pals. `PalPublisher.publish` publica
  comida y actividad de **toda** cuenta activa, así que la víctima no necesita
  haber prendido ninguna categoría: con auto-aceptarse ya se le ve el día.
  Dos vectores más por la misma política: un usuario **bloqueado puede
  desbloquearse** (`blocked → accepted`), y se puede **re-apuntar
  `addressee_id`** de un vínculo aceptado a un tercero cuyo uuid se conozca
  (los uuid se filtran en `shared_days.user_id` y en las rutas de fotos).
- **Solución**: partir la política — el addressee actualiza solo desde
  `pending`, y solo hacia `accepted`/`blocked`; el requester no necesita UPDATE
  (cancelar ya es DELETE). Como RLS no compara OLD vs NEW, sumar un trigger
  `before update` que rechace cambios de `requester_id`/`addressee_id`.
  Alternativa más limpia: revocar el UPDATE directo y mover la respuesta a un
  RPC `respond_pal(pal_id, action)` `security definer`.
- **Riesgos del arreglo**: la app acepta con `update ... eq('id', palId)` como
  addressee ([`pals_client.dart:129-141`](../lib/data/remote/pals_client.dart#L129-L141)) —
  ese camino sobrevive a la política partida, pero hay que probar también el
  rechazo. Si se opta por el RPC, el cliente cambia en la misma versión.
- **Tests pgTAP**: (1) A no puede pasar su propia solicitud a `accepted`;
  (2) A no puede revertir un `blocked`; (3) A no puede cambiar `addressee_id`;
  (4) B sí puede aceptar la pendiente.

## C-2 · "Eliminar mi cuenta" no elimina nada: solo cierra sesión

**CRÍTICO · CONFIRMADO**

- **Archivos**: [`settings_screens.dart:858-869`](../lib/presentation/screens/settings/settings_screens.dart#L858-L869)
  (la acción), [`:655-663`](../lib/presentation/screens/settings/settings_screens.dart#L655-L663)
  (la promesa), [`PRIVACY_POLICY.md:76-79`](../PRIVACY_POLICY.md)
- **Evidencia**: tras escribir "ELIMINAR" y tocar *Eliminar definitivamente*, el
  handler completo es:

  ```dart
  await ref.read(authGatewayProvider).signOut();
  await repo.signOut();          // store.reset(...) local, nada más
  context.go(Routes.welcome);
  ```

  La pantalla dice *"Se borran el perfil, las comidas, las actividades, los
  pesos, las medidas, las fotos y las integraciones. Es irreversible tras 7 días
  de gracia."* La política publicada en un repo público promete lo mismo en
  inglés. No existe Edge Function ni RPC de borrado (las funciones son cuatro:
  analyze-meal-photo, analyze-meal-text, food-search, suggest-meals). La columna
  `profiles.deletion_requested_at` existe desde la migración 2 y **nada la
  escribe** (`grep` en `lib/`, `supabase/functions/`, migraciones).
- **Impacto**: quedan intactos el usuario de Auth, las 26 tablas, los 3 buckets
  de fotos y el bucket `backups` con hasta 10 copias del documento completo. Y
  como las tablas son la fuente de verdad, **si la persona vuelve a entrar todo
  reaparece**. Son datos de salud con una promesa de borrado incumplida.
- **Solución**: Edge Function `delete-account` con la secret key: borra los
  objetos de Storage por prefijo, elimina el usuario de Auth y deja que la
  cascada desde `profiles` limpie las filas. La gracia de 7 días se implementa
  de verdad con `deletion_requested_at` + job, o se saca de la copia.
  **Mientras no exista, corregir el texto de la pantalla y de la política.**
- **Riesgos del arreglo**: irreversible; exigir reautenticación reciente.
  Verificar la cascada contra `pals` y `shared_days`.
- **Tests**: pgTAP de que tras borrar un perfil no queda fila en ninguna tabla
  ni objeto con ese prefijo; widget test de que la pantalla no promete borrado
  mientras el gateway no exponga `deleteAccount`.

## C-3 · El perfil entero se abre a pals **y a solicitudes pendientes**: `pal_code`, fecha de nacimiento, altura, sexo

**CRÍTICO · CONFIRMADO**

- **Archivos**: [`20260801001900_pals.sql:156-169`](../supabase/migrations/20260801001900_pals.sql#L156-L169)
  (política), [`20260801001400_rls.sql:22-24`](../supabase/migrations/20260801001400_rls.sql#L22-L24) (el GRANT)
- **Evidencia**: el comentario dice *"El nombre del pal hace falta para
  mostrarlo en la lista. **Es lo único del perfil que se abre**"*. Pero RLS es
  por fila, no por columna, y el grant es `select` sobre todas: se abre
  `pal_code`, `birth_date`, `height_cm`, `biological_sex`, `activity_level`,
  `deletion_requested_at` y los toggles. Y la rama `pending` lo concede **antes
  de que la persona acepte**: alcanza con mandar una solicitud.
- **Cómo verificarlo**: con solicitud enviada y sin aceptar,
  `select pal_code, birth_date, height_cm from profiles where id = '<B>'`.
- **Impacto**: datos personales de salud visibles para cualquiera que conozca tu
  código y mande una solicitud; y fuga del `pal_code` ajeno, que es la llave del
  vector C-1.
- **Solución**: vista `pal_profiles (id, display_name, avatar_path)` con
  `security_invoker` para la lista, y sacar `profiles_pal_read` de `profiles`.
  Mínimo urgente: eliminar la rama `pending` y excluir `pal_code`.
- **Riesgos**: revocar de más rompe el `select()` completo del propio perfil que
  hace el cliente relacional — por eso la vista aparte y no `grant select
  (columnas)`.

## A-1 · Actions de CI sin pin a SHA, en el workflow que maneja el keystore irreemplazable

**ALTO · CONFIRMADO**

- **Archivos**: [`release.yml:28,30`](../.github/workflows/release.yml),
  [`ci.yml:26,33,43,99`](../.github/workflows/ci.yml)
- **Evidencia**: las nueve referencias son tags mutables (`actions/checkout@v4`,
  `subosito/flutter-action@v2`, `gitleaks/gitleaks-action@v2`,
  `supabase/setup-cli@v1`). En `release.yml` los pasos siguientes manejan
  `KEYSTORE_BASE64`, las contraseñas del keystore y un `GITHUB_TOKEN` con
  `contents: write`.
- **Impacto**: si se compromete una action de terceros (caso `tj-actions`,
  2025), un tag re-apuntado exfiltra el keystore — y **si se pierde el keystore
  no se puede volver a publicar una actualización nunca más**.
- **Solución**: pin a SHA completo con comentario de versión, al menos en
  `release.yml`; Dependabot para `github-actions` mantiene los pins al día.
- **Check de CI**: `zizmor` o `actionlint` exigiendo pin por SHA.

## M-1 · `ci.yml` sin bloque `permissions`

**MEDIO · CONFIRMADO la ausencia; PROBABLE que el default sea write**

`release.yml` declara `permissions`; `ci.yml` no, así que el token queda con el
default del repo (en repos personales suele ser read/write). Combinado con A-1,
un paso comprometido podría escribir en el repo. Arreglo: `permissions:
contents: read` a nivel workflow.

## M-2 · La política de privacidad omite dos salidas de datos reales

**MEDIO · CONFIRMADO**

La tabla de terceros de [`PRIVACY_POLICY.md:67-72`](../PRIVACY_POLICY.md) declara
Supabase, Gemini ("a meal photo or a text description"), USDA y Open Food Facts.
Faltan:

1. **GitHub**: desde que el chequeo de versión es automático al abrir la app,
   GitHub ve IP y user-agent de cada usuario en cada apertura.
2. **Gemini, con más que una foto o una descripción**: `suggest-meals` manda
   `Calorías disponibles: N kcal. Momento del día: X. Le faltan N g de
   proteína.` — datos derivados del registro de salud.

El documento se presenta como *"drafted directly from the app's source code to
describe actual behavior"*. Arreglo: dos filas más en la tabla.

## M-3 · `rate_limits` crece sin límite y acepta buckets arbitrarios

**MEDIO · CONFIRMADO**

[`20260801002300_security_hardening.sql:30-63`](../supabase/migrations/20260801002300_security_hardening.sql#L30-L63):
ningún job la purga (`purge_soft_deleted`, `expire_food_cache`, `trim_recents`,
`purge_audit_log` — ninguno la toca) y `check_rate_limit(p_bucket text, ...)` no
valida el bucket: un cliente autenticado puede llamar `check_rate_limit('x'||n,
1)` en bucle y crear filas ilimitadas. Arreglo: job
`delete from rate_limits where day < current_date - 7` + allowlist de buckets.

## B-1 · `pal_code` es escribible por su dueño, y el unique sirve de oráculo

**BAJO · CONFIRMADO**

`profiles_update_own` no restringe columnas: se puede probar códigos ajenos con
`update profiles set pal_code='<candidato>'` (23505 = existe), esquivando el
rate limit de 20/día de `request_pal`, que es la única defensa de enumeración
construida. El espacio 31⁸ mantiene el riesgo bajo. Arreglo: trigger que
rechace cambios de `pal_code` salvo `service_role`.

## B-2 · Un `display_name` de más de 80 caracteres rompe el alta entera

**BAJO · CONFIRMADO el camino SQL**

`handle_new_user` inserta sin truncar contra un `check (<= 80)`; la excepción en
el trigger aborta el insert en `auth.users` → "Database error saving new user".
Alcanzable por la API de signup con metadata arbitraria. Arreglo: `left(trim(...), 80)`.

## Informativo de seguridad

- **`config.toml`**: contraseñas de 6 sin requisitos y `enable_confirmations =
  false`. Solo gobierna el stack local, pero es la referencia que se copia —
  **verificar el estado real en el dashboard** (Auth → Providers → Email).
- **Funciones ejecutables por `anon`** vía el EXECUTE default de PUBLIC. Todas
  fallan seguro hoy (verificadas una por una), pero conviene el
  `revoke execute ... from public, anon` que la migración 23 ya aplicó a los jobs.
- **`guard_hard_delete` depende de un GUC legacy** (`request.jwt.claim.role`):
  hoy es correcto por accidente (`auth.uid()` es NULL para service_role), no por
  diseño. `auth.role()` lo haría correcto por diseño.
- **La cuota diaria de IA resetea a medianoche UTC**, o sea 21:00 en Argentina.
- **El updater no verifica digest**: solo compara tamaño contra el `size` del
  asset, teniendo `digest` (sha256) disponible en la API de GitHub. La defensa
  fuerte (firma de Android) está intacta, así que es robustez adicional.

---

# 2 · Integridad de datos y sincronización

Es el bloque con más masa. La causa común: **el push y el pull no comparten un
contrato de identidad ni de borrado**, y el trigger `set_updated_at` convierte
cada push en "el servidor es más nuevo".

## C-4 · Editar una medida corporal rompe la sincronización de `body_measurements` para siempre

**CRÍTICO · CONFIRMADO por código + esquema**

- **Archivos**: [`local_repository.dart:1243-1261`](../lib/data/repositories/local_repository.dart#L1243-L1261),
  [`20260801001000_body.sql:54-56`](../supabase/migrations/20260801001000_body.sql#L54-L56),
  [`relational_sync_client.dart:182-193`](../lib/data/remote/relational_sync_client.dart#L182-L193)
- **Evidencia**: `logMeasurement` descarta la fila del día y crea otra con
  **id nuevo siempre**:

  ```dart
  store.measurements = <BodyMeasurement>[
    ...store.measurements.where((m) => !(m.metric == metric && isSameDay(m.localDate, date))),
    BodyMeasurement(id: _uuid.v4(), ...),
  ];
  ```

  La base tiene `create unique index body_measurements_uniq on (user_id, metric,
  local_date) where deleted_at is null`. El push es un `upsert` por PK y **nunca
  borra filas remotas**.

- **Cadena completa**: editar la medida de hoy → id nuevo local, la fila vieja
  sigue viva en la tabla → el push intenta INSERT del id nuevo → viola el índice
  único → `PostgrestException` → como el upsert es un solo statement, **ninguna
  medida entra** → y como nada borra la fila vieja, **cada push posterior falla
  igual, para siempre**. Mientras tanto el refresh trae la fila vieja, el merge
  la agrega al final y `measurementsOn` (map literal) deja que **la última pise a
  la anterior**: la pantalla vuelve a mostrar el valor que la persona ya corrigió.
- **Cómo verificarlo**: registrar cintura hoy, esperar el push, corregir el
  valor, esperar → Configuración → Respaldo en la nube muestra `SyncFailed` con
  `body_measurements`; salir y volver a la app (>30 s) → vuelve el valor viejo.
- **Impacto**: es el mismo modo de falla que dejó `public.meals` en cero, pero
  vigente y disparado por un gesto normal (corregir un número mal tipeado).
- **Solución**: reutilizar el id existente del mismo día/métrica, como ya hacen
  `logWeight` y `logSleep`; y borrado suave con `deleted_at` empujado en vez de
  `removeWhere`. Para cuentas ya afectadas: dedup server-side por
  `(user_id, metric, local_date)` quedándose con el más reciente, **antes** de
  que el cliente empiece a reusar ids.
- **Tests**: "editar una medida no cambia el id"; push con fake que rechaza el
  segundo insert del mismo (metric, date) y verifica que el resto entra igual.

## A-2 · Tras cada push el remoto le gana a todo en el merge: horas en UTC y campos que se pierden

**ALTO · mecanismo CONFIRMADO; el corrimiento visual PROBABLE**

- **Archivos**: [`20260801000100_extensions.sql:23-32`](../supabase/migrations/20260801000100_extensions.sql#L23-L32)
  (`new.updated_at = now()` incondicional), [`relational_sync_client.dart:253-296`](../lib/data/remote/relational_sync_client.dart#L253-L296)
  (el push no manda `updated_at` ni `ai_analysis_id`; los ítems no mandan
  `food_id`), [`:496-505`](../lib/data/remote/relational_sync_client.dart#L496-L505) (el pull adopta el `updated_at` del servidor),
  [`document_merge.dart:191-206`](../lib/domain/services/document_merge.dart#L191-L206)
- **Cadena**: cada push re-upserta **todas** las filas (es un upsert completo, no
  un diff). El UPDATE dispara `set_updated_at` aunque la fila no haya cambiado →
  `updated_at` remoto = hora del último push, siempre más nuevo que el
  `updatedAt` local (hora del guardado). En el siguiente pull, `_remoteIsNewer`
  da verdadero para **cada** registro no editado después del push, y la copia
  del servidor reemplaza a la local.

  Lo que vuelve en esa copia: sin `aiAnalysisId` (el pull no lo mapea), los
  ítems sin `foodId` (no viaja a propósito), y `loggedAt` como
  `2026-07-31T16:30:00+00:00` → `DateTime.parse` lo deja en UTC → `timeOfDay`
  (`DateFormat` sin `toLocal()`) muestra **16:30 donde se registró 13:30**.

  El comentario del merge — *"ante un empate reemplazarlo no cambiaría nada
  salvo el riesgo de traerse una versión con menos campos"* — asumía empate. Con
  el trigger, el caso normal es que el remoto gane.
- **Por qué recién ahora**: hasta la migración 26, `public.meals` tenía cero
  filas. Este circuito recién se volvió alcanzable; nadie lo vivió todavía.
- **Cómo verificarlo**: registrar un almuerzo a las 13:30, esperar el push (8 s),
  mandar la app a fondo >30 s, volver: el detalle muestra 16:30.
- **Solución** (cualquiera de las dos primeras corta lo grueso): (1) mandar
  `updated_at` del cliente en el insert y hacer el trigger condicional
  (`if new is distinct from old`); (2) `toLocal()` al armar el documento en el
  pull; (3) mapear `ai_analysis_id`/`food_id` en ambas direcciones.
- **Riesgos**: confiar en el reloj del cliente es justo lo que la migración 22
  quiso evitar — por eso el trigger se conserva para updates reales.
- **Tests**: round-trip push→pull→merge con fake que simula el bump y verifica
  que una comida no editada queda **idéntica**; test de `timeOfDay` con UTC.

## A-3 · Los borrados no llegan al servidor: resucitan solos

**ALTO · CONFIRMADO**

- **Archivos**: [`relational_sync_client.dart:253-255`](../lib/data/remote/relational_sync_client.dart#L253-L255)
  (`if (!m.isDeleted)`), [`:302-303`](../lib/data/remote/relational_sync_client.dart#L302-L303),
  [`local_repository.dart:1143-1147`](../lib/data/repositories/local_repository.dart#L1143-L1147) (`deleteSleep` con `removeWhere`),
  [`:1262-1266`](../lib/data/repositories/local_repository.dart#L1262-L1266)
- **Evidencia**: el propio cliente lo admite — *"A diferencia de
  comidas/actividades (que simplemente dejan de subirse al borrarse), el peso sí
  escribe `deleted_at`"*. En todo el cliente relacional hay **una sola** tabla
  que tumba: `weight_logs`. Sueño y medidas ni siquiera tienen lápida local.
- **Dos niveles de daño**:
  1. **Mismo teléfono, hoy**: borrar el sueño de una noche → la fila sigue en la
     tabla → el refresh la trae como "solo en el servidor" → **reaparece en
     ≤30 s**.
  2. **Reinstalación, segundo dispositivo o la web anunciada**: las comidas y
     actividades borradas reviven **todas** (la lápida vive solo en el documento
     local). Y como `purgeDeletedPhotos` ya sacó la foto del bucket a las 24 h,
     reviven con `photo_path` roto.
- **Efecto lateral en el servidor**: `purge_soft_deleted` sobre `meals` y
  `activities` es un **no-op perpetuo** (nunca hay `deleted_at is not null`), o
  sea que el servidor retiene lo borrado indefinidamente — en tensión con la
  política de privacidad.
- **Solución**: un solo contrato de borrado — `deleted_at` en todas las tablas
  de contenido, empujado como ya se hace con el peso, y traído por el pull.
- **Tests**: "borrar y refrescar no revive", por colección; y un test estructural
  (al estilo `enum_constraints_test`) que falle si una colección tiene borrado
  duro local y push sin `deleted_at` — es el invariante que se rompió dos veces.

## A-4 · Iniciar sesión sobre un teléfono con datos de otra cuenta los adopta y los sube

**ALTO · flujo CONFIRMADO; frecuencia PROBABLE**

- **Archivo**: [`local_repository.dart:217-236`](../lib/data/repositories/local_repository.dart#L217-L236)
- **Evidencia**: `signIn` resetea **solo si `base.isDemo`**. Con un perfil real
  previo hace `_ensureUsableProfile((store.profile ?? base).copyWith(email: ...))`,
  conservando comidas, pesos y medidas del usuario anterior.
- **Cómo se llega**: si la sesión de A se revoca o vence (cambio de contraseña
  en otro lado, refresh token inválido), el splash manda a `welcome` **sin tocar
  el documento local**. Si ahí entra B, `openAfterPull` mezcla lo de A con las
  tablas de B, y el push escribe los registros de A con el `user_id` de B.
  El alta (`SignUpScreen`) sí está protegida; el iniciar sesión no.
- **Impacto**: mezcla permanente de datos entre cuentas — la misma clase de
  contaminación que el reset del modo demo ya corrigió para el otro camino.
- **Solución**: resetear también cuando la identidad guardada no coincida con la
  cuenta que entra. Guardar el `auth uid` en el documento (el email puede
  cambiar).

## M-4 · Únicos "uno por día" contra ids aleatorios por dispositivo

**MEDIO · PROBABLE (requiere dos dispositivos)**

`weight_logs`, `body_measurements`, `water_logs`, `sleep_logs` y `reminders`
tienen unique por `(user_id, local_date)`; el push upserta por PK con ids `v4`.
Dos dispositivos que creen su fila para el mismo día producen un 23505 que
**no se auto-repara** (el merge conserva las dos filas locales). Arreglo: id
determinístico (uuid v5 de `user_id|tabla|fecha`) para las tablas 1-por-día.

## M-5 · `pull` sin paginación contra `max_rows = 1000`

**MEDIO · falta de paginación CONFIRMADA; el truncado PROBABLE**

[`relational_sync_client.dart:396-403`](../lib/data/remote/relational_sync_client.dart#L396-L403):
`select()` plano sin `range()`. A ~4 comidas × 3 ítems por día, `meal_items`
cruza 1000 filas en ~3 meses. Desde ahí cada pull reconstruye comidas con ítems
faltantes — y con A-2, esa versión mutilada gana el merge. **Verificación
pendiente**: el valor de "Max rows" del proyecto real en el dashboard.
Arreglo: paginar con `.range()` ordenando por `id`.

## M-6 · `meal_items` se pide con un `inFilter` de todos los ids

**MEDIO · PROBABLE**

[`:428-434`](../lib/data/remote/relational_sync_client.dart#L428-L434): PostgREST
codifica `in.(...)` en el query string; 4 comidas/día × 1 año ≈ 1.400 uuids ≈
>50 kB de URL, por encima del límite usual del proxy → el pull entero falla y
`refresh` devuelve false en silencio. Arreglo: `select('*, meal_items(*)')`
embebido, que es un solo request sin lista de ids.

## M-7 · "Restaurar una copia" ya no restaura

**MEDIO · CONFIRMADO por diseño**

El diálogo promete *"Lo que hayas registrado acá después de esa fecha se
pierde"*. Pero desde que las tablas son la fuente de verdad, el refresh siguiente
une el documento restaurado contra las tablas —que tienen todo lo posterior— y
lo re-agrega. Dos features correctas por separado que juntas rompen el caso de
uso declarado. Hay que **decidir la semántica** y escribirla: o restaurar
también escribe a tablas (necesita el DELETE remoto de A-3), o el diálogo pasa a
decir "se combina con lo que hay en la cuenta".

## M-8 · Cerrar sesión no drena lo pendiente

**MEDIO · CONFIRMADO**

Los comentarios de `flush()` y `push()` dicen *"Se usa al cerrar sesión"* —
**nadie los llama ahí** (`grep`: solo `app.dart` en `paused` y el botón manual).
La secuencia real cierra el gateway (con lo que cualquier flush posterior sale
por `account == null`) y después resetea el documento. Un registro hecho <8 s
antes de cerrar sesión no queda **en ningún lado**.

## M-9 · La purga de fotos limpia la ruta sin haber borrado, si no hay conexión

**MEDIO · CONFIRMADO**

`purgeDeletedPhotos` confía en que `delete` lance para no limpiar la ruta
(*"Nunca se limpia la ruta sin haber borrado"*). Pero
[`photo_storage_client.dart:104-116`](../lib/data/remote/photo_storage_client.dart#L104-L116)
traga cualquier `Exception`: un `SocketException` retorna éxito → la ruta se
limpia → **foto huérfana permanente** en el recurso que ESTADO identifica como
el único que va a doler.

## M-10 · Cancelar el análisis deja la foto huérfana en el bucket

**MEDIO · CONFIRMADO**

`analyze` sube con un uuid al azar antes de analizar, pero `remotePath` muere
como variable local del repositorio: cuando la pantalla cancela o el análisis
falla, la UI **no puede** borrarla aunque quiera. La limpieza al descartar
existe solo en `PhotoReviewScreen._discardIfUnsaved`.

## Bajos e informativos de datos

- **`logWeight` no acepta `source`**: el peso importado de Health Connect queda
  como `'manual'` (el check de la base contempla `'imported'`), y "Borrar lo
  importado" solo mira actividades.
- **Goals sin marca de tiempo en el merge**: con dos dispositivos, el objetivo
  viejo puede quedar vigente y des-cerrarse en el servidor.
- **`PalPublisher` pierde el cambio que llega durante una publicación** (no
  marca dirty ni reprograma).
- **Los APK descargados se acumulan**: `stagingPath` borra solo el archivo del
  mismo nombre; quedan 75 MB por versión en el directorio de soporte.
- **El documento entero se re-serializa en el hilo principal en cada commit**
  (un vaso de agua = documento entero; el sync de Health Connect hace ~90
  commits seguidos). Hoy aguanta; crece linealmente con el historial.
- **La cuarentena de un usuario anterior sobrevive al cambio de cuenta**: el
  siguiente usuario puede verla y exportarla desde la pantalla de recuperación.

---

# 3 · Manejo de errores y esperas

## A-5 · Cuatro clientes sin un solo timeout, contra la regla explícita de la casa

**ALTO · CONFIRMADO (conteo verificado archivo por archivo)**

| Cliente | `.timeout(` |
| --- | --- |
| `cloud_backup_client.dart` | **0** |
| `pals_client.dart` | **0** |
| `supabase_auth_gateway.dart` | **0** |
| `photo_storage_client.dart` | 1 (falta en `signedUrl` y `remove`) |
| relational, gemini, github, usda, off, suggestions | ✅ |

ESTADO §10: *"Todo `await` contra la red necesita timeout propio"*, y los
clientes de Supabase no traen uno por defecto. Consecuencias concretas:

- `CloudBackupService.flush` colgado deja `_uploading = true` **para siempre**:
  el respaldo muere en silencio hasta reiniciar la app.
- `PalPublisher.publish` colgado deja `_publishing = true`: Pals deja de publicar.
- El **splash** espera `openAfterRestore` → `download` sin plazo, mientras
  [`splash_screen.dart:13-15`](../lib/presentation/screens/auth/splash_screen.dart#L13-L15)
  promete *"`checking` dura como máximo 1500 ms; si excede, se navega igual"* —
  **ese tope no existe en el código**. La app puede quedarse en el logo.
- "Entrar" tras credenciales correctas puede girar indefinidamente.

## A-6 · La pantalla de Respaldo dice "Al día" después de un fallo

**ALTO · CONFIRMADO**

[`auth_providers.dart:48-63`](../lib/presentation/providers/auth_providers.dart#L48-L63):
`backupStateProvider` se suscribe a `service.states` (broadcast **sin replay**) y
no siembra `service.state`, que existe. `_statusLabel(null)` → `'Al día'`.

El provider de al lado hace lo correcto y explica por qué: *"quien abre la
pantalla después de un fallo no vería nada hasta el próximo cambio — justo el
caso en el que uno la abre"*. Es la misma clase de mentira que costó meses de
`meals` vacíos, en la pantalla que existe para verla. (De paso: el
`StreamTransformer` que envuelve el stream es un no-op literal.)

## A-7 · "Tu código" de Pals puede quedar en "…" toda la sesión

**ALTO · CONFIRMADO**

`myPalCodeProvider` es un `FutureProvider` **global** a cinco líneas de
`palsProvider`, cuyo docstring explica por qué el suyo lleva `autoDispose`. Si
la primera consulta falla (sin conexión), **cachea el error**: el botón
"Actualizar" invalida solo `palsProvider`, y nadie invalida este. El código
queda en "…" hasta matar la app — y es lo único que una persona necesita para
que la agreguen.

## M-11 · El agujero de "solo `on AppError`" sigue abierto en Sugerencias

**MEDIO · patrón CONFIRMADO**

[`suggestions_screen.dart:87-109`](../lib/presentation/screens/meal/suggestions_screen.dart#L87-L109)
captura solo `on AppError`, mientras el precedente ya arreglado documenta la
lección: *"un `TypeError` no es una `Exception`… dejaba `_busy` en true para
siempre"*. Los casts del parse lanzan `Error`, que atraviesa todo → "Buscando
opciones que entren…" para siempre, sin botón de refresco. Mismo patrón, con
ventana menor, en `updates_screen`, `pals_screen._request`, `cloud_backup_screen`
y `food_screens._lookup`.

## M-12 · Aceptar/Quitar un pal sin try/catch

**MEDIO · CONFIRMADO**

[`pals_screen.dart:101-128`](../lib/presentation/screens/pals/pals_screen.dart#L101-L128):
`await ref.read(palsClientProvider)?.accept(pal.id);` sin captura. El fallo de
red es un unhandled async error: "toco Aceptar y no pasa nada" — la
fenomenología exacta del bug reportado nº 1 de la ronda de julio.

## M-13 · `openAfterPull` no abre la puerta en `finally`

**MEDIO · gap estructural CONFIRMADO**

La doc dice *"Pase lo que pase se abre la puerta de escritura"*, pero
`_canPush = true` está después del await, sin `try/finally` (el servicio hermano
sí lo usa). Y los catch del cliente son `on ... Exception`: un `TypeError` de los
casts del mapeo es un `Error` y se escapa. Resultado: `_canPush` queda en false y
`markDirty` sale temprano **en silencio** el resto de la sesión.

---

# 4 · Funcionalidad y UX

## A-8 · "Cargar la comida a mano" tras un fallo pisa el borrador y deja un spinner sin salida

**ALTO · CONFIRMADO por lectura del flujo**

[`photo_screens.dart:384-399`](../lib/presentation/screens/photo/photo_screens.dart#L384-L399):
`_manual()` llama `start(...)` **incondicionalmente**, a diferencia de la
revisión, que hace `appendAnalysis` cuando ya hay borrador. Con 2 ítems cargados
→ foto → falla el análisis → "Cargar a mano": (1) los 2 ítems se pierden en
silencio; (2) al guardar, el `pop()` vuelve a una `MealFormScreen` cuyo draft es
`null` → `Scaffold` con spinner y **sin AppBar**: solo sale con el back del
sistema.

## A-9 · El día seleccionado nunca vuelve a "hoy", y el comentario dice que sí

**ALTO · CONFIRMADO el comentario vs. código; el aterrizaje PROBABLE**

[`app_providers.dart:36-48`](../lib/presentation/providers/app_providers.dart#L36-L48):
*"Se resetea a hoy al volver a primer plano tras 4 h"* — pero `goToToday()` tiene
**un solo caller**: el botón "Hoy" del date picker. El lifecycle `resumed`
publica el widget y sincroniza, y jamás toca `selectedDateProvider`.

Dejar la app en background a la noche y abrirla a la mañana deja Inicio en
"Ayer", y el FAB arma la URL con esa fecha: **el desayuno cae en el día de
ayer**. El widget del teléfono, mientras tanto, publica "hoy": widget y app
dicen cosas distintas.

## M-14 · La tabla nutricional rotula "por 100 g" pero divide por la porción

**MEDIO · lógica CONFIRMADA**

[`food_widgets.dart:454,494-500`](../lib/presentation/components/food/food_widgets.dart#L494-L500):
`factor100 = 100 / food.servingSize` con encabezado fijo `'por 100 g'`. Un
alimento propio "Huevo, 1 unidad, 70 kcal" muestra **"por 100 g: 7.000 kcal"**.
Correcto para ARGENFOODS/OFF/USDA (porción = 100 g); disparate con apariencia de
dato para alimentos por unidad, que el formulario permite crear.

## M-15 · La media móvil del peso es invisible en tema claro

**MEDIO · CONFIRMADO numéricamente**

`NmChartColors.trend = 0xFFE9E9ED` es un color de **texto del tema oscuro** usado
como línea fija: sobre el `surface` blanco del tema claro da ≈ **1,06:1** de
contraste. La línea de objetivo (`0xFFCFD3E5`) da ≈ 1,35:1. `CalorieRing` ya
hace lo correcto (`nm.isDark ? c800 : c200`).

## M-16 · El calendario no deja elegir los días de planificación que las flechas sí permiten

**MEDIO · CONFIRMADO**

`date_picker_sheet.dart` deshabilita **todo** futuro (`isFutureDay` → `onTap:
null`) y el mes siguiente, mientras el header permite avanzar hasta
`maxPlanningDays` (+3) y el producto promociona "planificación hasta tres días
adelante".

## Bajos de UX

- **Doble-tap sin guard** en "Guardar alimento" (`food_screens.dart:671-715`) y
  "Y otra" (`activity_form_screen.dart:735-738`): dos registros con taps rápidos.
- **Deep link con `templateId` inexistente crashea**: `firstWhere(..., orElse: ()
  => repo.templates.first)` lanza `StateError` con 0 plantillas.
- **Tipear "0" en el objetivo manual** lanza (`Infinity.round()`).
- **La búsqueda online traga los errores**: `.catchError((_) => const <Food>[])`
  por fuente hace que "No encontramos ese alimento" también signifique "estás sin
  conexión", y vuelve inalcanzable el botón "Reintentar" que existe para eso.
- **Cancelar la cámara siempre reporta "No pudimos abrir la cámara"**: el
  `on Object` marca `_permissionDenied` para cualquier fallo.

---

# 5 · Código muerto, comentarios engañosos y deuda

## Código muerto verificado (con el grep que lo prueba)

| Elemento | Prueba |
| --- | --- |
| `Result<T>`, `Ok`, `Err`, `Page<T>` (`core/result.dart`) | `grep` en `lib/` y `test/`: **cero** usos |
| `create_meal_with_items` (RPC) | Solo migraciones y docs; la app llama **un** RPC: `request_pal`. El "cinturón" de la migración 26 protege un camino que nadie transita |
| `get_daily_summary`, `v_active_meals` | Cero referencias en la app |
| `PendingReviewBanner` | Solo su definición; su doc dice "visible sobre cualquier tab (RN-07)" |
| `offlineProvider`, `pendingCountProvider`, `ChartSession.reset()`, `isPlannable()` | Cero consumidores |
| Rutas `/profile/templates` y `/profile/favorites` | Declaradas y registradas, nunca navegadas |
| Query params `?target=meal` / `?target=ai_item` | El router no los lee: sugieren un mecanismo que no existe |
| `store.historyFilters` | Plomería de persistencia completa que la UI jamás escribe |
| Extensiones `uuid-ossp` y `pg_trgm` | Ningún uso en todo el repo |
| 5 índices duplicados | El unique ya provee el índice (`foods_cache`, `rest_days`, `body_measurements`, `weight_logs`, water/sleep) |
| `uploads/*.pdf` | El mismo PDF dos veces, byte a byte (MD5 idéntico), sin referencias |

**Tablas creadas y nunca cableadas**: `reminders` (creada explícitamente *"para
que cambiar de dispositivo no pierda la configuración"* — y el push/pull no la
incluye), `rest_days`, `exercise_templates`, `health_integrations`,
`sync_records`, `duplicate_resolutions`. Y **`recent_foods` queda vacía para
siempre**: `track_recent_food` sale temprano si ambos ids son NULL, y el push los
manda NULL a propósito — `trim_recents` corre cada semana para mantener una
tabla vacía y otra que nadie lee.

## Comentarios que contradicen el código

Los ocho verificados uno por uno:

1. `app_providers.dart:36` — "se resetea a hoy tras 4 h": no existe (A-9).
2. `splash_screen.dart:14` — "máximo 1500 ms": no hay ningún tope (A-5).
3. `cloud_backup_service.dart:163` y `relational_sync_service.dart:200` — "se usa
   al cerrar sesión": nadie los llama ahí (M-8).
4. `history_screen.dart:21` — "los filtros se persisten": son `StateProvider` en
   memoria; se pierden al matar la app.
5. `pals.sql:157` — "es lo único del perfil que se abre": se abre la fila entera (C-3).
6. `pals.sql:131` — "aceptar lo hace quien recibe": cualquiera de los dos (C-1).
7. `relational_sync_client.dart:23-29` — "el documento sigue siendo la fuente de
   verdad… cuando las filas estén verificadas se da vuelta": ya se dio vuelta.
8. `local_store.dart:21-26` — "la red todavía no participa": participa por tres lados.

Más los contadores desactualizados: `ci.yml` dice "las 18 migraciones",
`docs/releases.md` "las 22", `supabase/README.md` "26 de 26" — son **27**.
`docs/releases.md:154` afirma que "el chequeo es manual" cuando el updater
consulta solo al abrir.

## Dependencias

`flutter pub outdated`: **46 paquetes con versiones más nuevas**, ninguno con
vulnerabilidad conocida identificada (no invento CVEs; verificar con osv.dev
sobre el lockfile). Los majors atrasados que importan:

| Paquete | Actual | Último |
| --- | --- | --- |
| `flutter_riverpod` | 2.6.1 | 3.4.2 |
| `go_router` | 14.8.1 | 17.3.0 |
| `flutter_local_notifications` | 20.1.0 | 22.2.0 |
| `package_info_plus` | 9.0.1 | 10.2.1 |
| `share_plus` | 12.0.2 | 13.3.0 |
| `flutter_lints` | 5.0.0 | 6.0.0 |

Y en Android, `androidx.health.connect:connect-client:1.1.0-alpha07` — **una
alpha en el build de release**. Las 21 dependencias directas tienen imports
reales (verificado paquete por paquete): no hay deps muertas.

## Tests

**376 en verde**, y la suite tiene piezas realmente buenas: los tres cerrojos del
seed demo, el `enum_constraints_test` que compara enums Dart contra checks SQL,
los 15 tests del merge, la validación Atwater del catálogo. Lo que falta:

- **Sin cobertura pgTAP**: los abusos de `pals_update` (C-1, el más importante),
  la exposición de columnas de `profiles` (C-3), el bucket `backups`,
  `reminders`, `create_meal_with_items`, el rollover de día de `check_rate_limit`.
- **Falsa seguridad puntual**: el `'already'` de `pals_test.sql:128` es
  secuencial y no puede detectar la carrera de `request_pal`.
- **Ningún test de round-trip push→pull→merge** con el bump del trigger: es
  exactamente el hueco por donde entra A-2.
- **Cálculos sin auditar** (brecha de esta auditoría): `bmr`, `tdee`,
  `calorie_target`, `macros`, `met_calories`, `exercise_credit`, `adherence`,
  `moving_average`, `pace_met`, `rounding`, `duplicate_score`, `goal_presets`,
  `daily_balance`.

---

# 6 · Verificaciones que salieron limpias

Vale nombrarlas: son las que **no** hay que volver a revisar.

- **Sin secretos en la historia de git** (`git log -S 'sb_secret'`,
  `--diff-filter=A` sobre `*.env*`, `*.jks`, `*key*`): solo plantillas.
  `key.properties` y `*.jks` correctamente ignorados; `.idea/`, `.vscode/` y
  `*.iml` no trackeados.
- **Sin claves de proveedor en el cliente**: solo la publishable key por
  `--dart-define`, segura por RLS; Gemini y USDA detrás de Edge Functions.
- **Inyección SQL: nada.** Ninguna función concatena input en SQL dinámico; todas
  las `security definer` fijan `search_path`.
- **Storage**: los 4 buckets privados, con límite de tamaño y MIME acotado, y las
  4 políticas por prefijo llevan `using` **y** `with check`.
- **`anon` sin grants de tabla**; los jobs de mantenimiento efectivamente
  revocados; `check_rate_limit` es atómico de verdad.
- **La carrera pull-vs-escritura local no existe**: el bloque
  `toDocument()` → `merge` → `restoreDocument` es síncrono sin awaits
  intermedios, y los vasos del widget viajan como **deltas**, no como total.
- **"Un documento sin registros no se sube nunca"** está doblemente cubierto, y
  el pull devuelve `null` en vez de un documento vacío que pise.
- **La cuarentena funciona como se documenta**, y la siembra demo tiene los tres
  cerrojos descritos.
- **Ciclo de vida de la UI**: los ~35 `TextEditingController`, todos los
  `AnimationController`, `Timer` y el `MobileScannerController` tienen su
  `dispose()`. `if (!mounted)` presente en todos los usos de context tras await
  que se revisaron.
- **El patrón de `ref.invalidate` en `initState`** (ESTADO §15) no se repite: las
  cuatro raíces de tab están limpias.
- **Redirect del router sin ciclos** (tabla de verdad completa), y el
  doble-pop a ciegas está resuelto en sus tres cadenas.
- **Manifest y Kotlin sólidos**: permisos mínimos, `exported="false"` donde
  corresponde, todos los `PendingIntent` con `FLAG_IMMUTABLE`, release con
  `minify + shrinkResources`, y el fallback de firma debug es imposible en el
  workflow de release.
- **El release gate verifica** que el tag coincida con la versión de pubspec,
  corre analyze + tests, chequea el versionCode con aapt2 y borra las
  credenciales del runner con `if: always()`.
- **Diferencias dev/prod limpias**: sin `usesCleartextTraffic`, sin
  `network_security_config`, cero `print`/`debugPrint` en `lib/`, y los códigos
  técnicos solo se muestran fuera de `dart.vm.product`.
