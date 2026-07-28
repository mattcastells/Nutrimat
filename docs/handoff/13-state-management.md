# 13 — State Management

Arquitectura **offline-first**: la fuente de verdad para la UI es siempre la base local.
La red actualiza la base local; la UI nunca lee de la red directamente.

```
UI  ──lee──►  Local store (SQLite / Drift)  ◄──escribe──  Sync engine  ◄──►  Supabase
 │                        ▲                                     ▲
 └──escribe (optimista)───┘                                     │
                                                          Sync queue (persistente)
```

Stack recomendado — **Flutter:** Riverpod 2 + Drift + `connectivity_plus`.
**React Native:** Zustand (estado de UI) + TanStack Query (estado de servidor) +
WatermelonDB o `expo-sqlite` + `@react-native-community/netinfo`.

## 1. Estado global

| Slice | Contenido | Persistencia |
| --- | --- | --- |
| `session` | `userId`, tokens, `isDemo` | Almacenamiento seguro (Keychain / EncryptedSharedPreferences) |
| `profile` | `UserProfile` + objetivo vigente | SQLite + memoria |
| `preferences` | tema, unidades, idioma, filtros recordados | SharedPreferences / MMKV |
| `catalog` | `activity_types` | SQLite, TTL 24 h |
| `connectivity` | `online`, `pendingCount`, `lastSyncAt` | memoria + contador desde SQLite |
| `selectedDate` | día visible en Inicio | memoria (se resetea a hoy al volver a primer plano tras 4 h) |
| `featureFlags` | flags remotos | SQLite, refresco al iniciar |

## 2. Estado local (por pantalla)

Vive en el controlador de la pantalla y muere con ella: borradores de formulario, texto de
búsqueda, acordeones abiertos, selección de chips, scroll.

**Excepción — borradores que sobreviven:** el borrador de `/meal/new`, el de
`/meal/photo/review` y el de `/activity/new` se persisten en SQLite (`drafts`) para no
perderse si la app se cierra. Se recuperan con un banner "Tenés un registro sin terminar ·
Retomar / Descartar" y expiran a las 48 h.

## 3. Estado del servidor

Cada entidad se modela como una consulta con clave estable:

```
['daily-summary', date]
['meals', date]
['activities', date]
['history', from, to, filtersHash]
['progress', from, to]
['food-search', query]          → no se persiste, TTL 5 min en memoria
['activity-types']              → TTL 24 h, persistido
['integrations']
['profile'] ['goal:current']
```

Política por defecto: `staleTime` 30 s, `cacheTime` 24 h, refetch al volver a primer plano
y al recuperar conexión. `food-search` no se refetchea automáticamente.

## 4. Cache

| Dato | Dónde | TTL | Invalidación |
| --- | --- | --- | --- |
| Resumen diario | SQLite + memoria | — | Cualquier mutación de ese día |
| Comidas / actividades | SQLite | — | Por mutación |
| `activity_types` | SQLite | 24 h | Manual desde Configuración |
| Resultados de búsqueda de alimentos | memoria | 5 min | Nueva búsqueda |
| Detalle de alimento externo | SQLite (`foods_cache`) | 30 días | Refresco perezoso |
| Fotos | Sistema de archivos + `cached_network_image` | 7 días | LRU con tope de 200 MB |
| Progreso | memoria | 2 min | Mutación de peso o actividad |

## 5. Persistencia offline

**Todo lo que el usuario puede crear se puede crear sin conexión.** Excepciones explícitas
(porque son imposibles sin red): crear cuenta, iniciar sesión, buscar en catálogos externos,
analizar una foto (se encola), conectar una integración, eliminar la cuenta.

Cada escritura:

1. Genera `id` (uuid v4) en el cliente.
2. Escribe en SQLite con `sync_status = 'pending'`.
3. Actualiza la UI de inmediato (optimista).
4. Encola una operación en `sync_queue`.

Tabla `sync_queue`: `id`, `entity`, `entity_id`, `action` (`create|update|delete`),
`payload jsonb`, `attempts`, `next_attempt_at`, `last_error`, `created_at`.

La cola se procesa **en orden por entidad** (una comida antes que sus ítems; una actividad
antes que su edición). Operaciones sobre entidades distintas van en paralelo, máximo 4.

## 6. Invalidación

| Mutación | Invalida |
| --- | --- |
| Crear/editar/borrar comida | `daily-summary(date)`, `meals(date)`, `history`, `progress` |
| Crear/editar/borrar actividad | `daily-summary(date)`, `activities(date)`, `history`, `progress` |
| Cambiar crédito de ejercicio | `daily-summary(hoy)`, `progress`, `profile` |
| Cambiar objetivo | `daily-summary(hoy…)`, `progress`, `goal:current` |
| Registrar peso | `daily-summary(date)`, `progress` |
| Sincronizar salud | `daily-summary` de los días tocados, `history`, `progress`, `integrations` |

La invalidación es **por clave, no global**: no se recarga toda la app tras guardar una comida.

## 7. Optimistic updates

Se aplican a: crear/editar/borrar comida y actividad, registrar peso, marcar favorito,
marcar día de descanso, cambiar el crédito de ejercicio.

Patrón:

1. Snapshot del estado previo.
2. Aplicar el cambio en SQLite y notificar a la UI.
3. Encolar.
4. Éxito → `sync_status = 'synced'`, se descarta el snapshot.
5. Fallo **no reintentable** (validación, 403) → revertir con el snapshot + snackbar
   "No pudimos guardar: <motivo>" con acción "Ver detalle".
6. Fallo **reintentable** → **no** se revierte: queda `pending` con su badge y la cola
   reintenta. El usuario no pierde su registro por un problema de red.

El anillo de calorías anima el cambio con `motion.slow`; si la operación se revierte, anima
de vuelta y muestra el snackbar (nunca cambia en silencio).

## 8. Sincronización

**Disparadores:** al iniciar la app; al volver a primer plano (si pasaron > 60 s); al
recuperar conexión; cada 15 min con la app abierta; manual (pull-to-refresh); tras cada
mutación exitosa (flush inmediato de la cola).

**Orden de una pasada:**
1. Flush de `sync_queue` (escrituras locales primero — el usuario tiene prioridad).
2. Pull de cambios remotos por `updated_at > lastPullAt` (paginado, 200 por página).
3. Sincronización de proveedores de salud, si están conectados y pasaron ≥ 30 min.
4. Actualización de `lastPullAt` y de los contadores de la UI.

**Backoff** por operación: 1 s, 4 s, 15 s, 60 s, 5 min, 15 min, 1 h (tope). Tras 24 h de
fallos, la operación se marca `error` y se muestra en Configuración → "Registros sin
sincronizar", con acciones "Reintentar" y "Descartar".

**Health sync incremental:** ancla/cursor persistido por proveedor; nunca se relee toda la
historia salvo que el usuario pulse "Volver a importar todo" (que reinicia el ancla y
protege lo editado por RN-06).

## 9. Manejo de conflictos

| Conflicto | Resolución |
| --- | --- |
| Misma entidad editada en dos dispositivos | **Last-write-wins por `updated_at`**, con una salvedad: si el campo en conflicto es `estimated_calories` y el registro local tiene `user_edited = true`, gana el local (RN-06) |
| Registro borrado en A, editado en B | Gana el borrado; la edición se descarta y se registra en el log de conflictos |
| Importación pisa una edición manual | No se aplica; se guarda `sync_records.skipped_reason = 'user_edited'` |
| Duplicado por importación | No se resuelve solo: `needs_review` + diálogo (RN-07) |
| Objetivo cambiado en dos dispositivos | Gana el de `starts_on` más reciente; si empatan, el de `created_at` mayor |
| Peso del mismo día en dos dispositivos | Upsert por `(user_id, local_date)`: gana el `logged_at` más reciente |

Todos los conflictos resueltos se escriben en una tabla local `conflict_log`
(`entity`, `entity_id`, `field`, `local_value`, `remote_value`, `winner`, `resolved_at`),
visible en Configuración → Avanzado. Nada se pierde en silencio.

## 10. Ciclo de vida y rendimiento

- **Cold start objetivo:** primer frame útil de Inicio en < 1,2 s con datos locales; la
  sincronización ocurre después y actualiza sin bloquear.
- **Background:** al pasar a segundo plano se hace flush de la cola si hay red; no hay
  trabajo periódico en background en el MVP (sin `BGTaskScheduler` / `WorkManager`) — D-14:
  evita el consumo de batería y el pedido de permisos adicionales; la sincronización al
  abrir es suficiente para el caso de uso.
- **Memoria:** las listas largas usan `ListView.builder` / `FlashList`; los gráficos
  submuestrean a un máximo de 180 puntos.
- **Base local:** VACUUM mensual; purga de `sync_queue` completada > 7 días y de
  `conflict_log` > 90 días.
