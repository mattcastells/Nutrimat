# 07 — Data Model

Base: **PostgreSQL 15 (Supabase)**. Réplica local en **SQLite** con el mismo esquema
lógico (tipos adaptados) para operación offline.

Convenciones:

- PK `uuid` generada **en el cliente** (`uuid v4`) → escritura offline idempotente.
- `created_at` / `updated_at`: `timestamptz not null default now()`; `updated_at` lo
  mantiene el trigger `set_updated_at()`.
- `deleted_at timestamptz null` → soft delete en todas las tablas de contenido de usuario.
  Toda vista y consulta filtra `deleted_at is null` salvo la papelera.
- Timestamps en UTC. `local_date date` se calcula en el cliente con `profiles.timezone` y
  se guarda explícitamente (D-09).
- Energía en `kcal` entera; peso `numeric(6,2)` kg; distancia `integer` metros;
  duración `integer` minutos.
- `sync_status text` ∈ `synced | pending | syncing | error | needs_review` (solo local; en
  Postgres existe para poder marcar `needs_review`).

---

## 1. Diagrama entidad-relación

```
                         ┌───────────────┐
                         │  auth.users   │
                         └───────┬───────┘
                                 │ 1:1
                         ┌───────▼───────┐
                    ┌────┤   profiles    ├────┐
                    │    └───────┬───────┘    │
                    │            │            │
        ┌───────────▼──┐  ┌──────▼──────┐  ┌──▼───────────────┐
        │    goals     │  │ weight_logs │  │ body_measurements│
        └──────────────┘  └─────────────┘  └──────────────────┘
                    │
   ┌────────────────┼─────────────────────┬───────────────────┐
   │                │                     │                   │
┌──▼─────┐   ┌──────▼───────┐    ┌────────▼────────┐  ┌───────▼────────┐
│ meals  │   │  activities  │    │ activity_goals  │  │ rest_days      │
└──┬─────┘   └──┬────────┬──┘    └─────────────────┘  └────────────────┘
   │ 1:N        │        │ N:1
┌──▼─────────┐  │   ┌────▼───────────┐
│ meal_items │  │   │ activity_types │◄──── seed: met-catalog.json
└──┬─────────┘  │   └────┬───────────┘
   │ N:1        │        │ 1:N
┌──▼─────┐      │   ┌────▼──────────────┐
│ foods  │      │   │ exercise_templates│
└────────┘      │   └───────────────────┘
   ▲            │
   │        ┌───▼───────────────┐   ┌─────────────────────┐
┌──┴──────┐ │ strength_exercises│   │ duplicate_resolutions│
│ai_analy-│ │  (fase 2)         │   └─────────────────────┘
│ ses     │ └───┬───────────────┘
└─────────┘     │ 1:N
            ┌───▼───────────┐
            │ strength_sets │  (fase 2)
            └───────────────┘

      ┌──────────────────────┐        ┌───────────────┐
      │ health_integrations  │──1:N──►│ sync_records  │
      └──────────────────────┘        └───────────────┘

      ┌──────────────┐   ┌───────────────┐   ┌────────────────┐
      │ foods_cache  │   │ recent_foods  │   │recent_activities│
      │  (público RO)│   └───────────────┘   └────────────────┘
      └──────────────┘
```

---

## 2. Tablas

### 2.1 `profiles`

| Columna | Tipo | Null | Default | Notas |
| --- | --- | --- | --- | --- |
| `id` | `uuid` | no | — | PK, FK → `auth.users.id` ON DELETE CASCADE |
| `display_name` | `text` | sí | — | ≤ 80 |
| `avatar_path` | `text` | sí | — | Ruta en bucket `avatars` |
| `biological_sex` | `text` | no | `'unspecified'` | `male \| female \| unspecified` — usado en Mifflin-St Jeor |
| `birth_date` | `date` | sí | — | Edad 13–100 |
| `height_cm` | `numeric(5,1)` | sí | — | 90–250 |
| `activity_level` | `text` | no | `'sedentary'` | `sedentary \| light \| moderate \| high \| very_high` |
| `timezone` | `text` | no | `'America/Argentina/Buenos_Aires'` | IANA |
| `unit_system` | `text` | no | `'metric'` | `metric \| imperial` |
| `theme_mode` | `text` | no | `'system'` | `light \| dark \| system` |
| `locale` | `text` | no | `'es'` | — |
| `exercise_credit_percentage` | `smallint` | no | `0` | 0–100 (D-02) |
| `exercise_credit_enabled` | `boolean` | no | `false` | Toggle maestro |
| `show_net_calories` | `boolean` | no | `false` | RN-11 |
| `profile_completed` | `boolean` | no | `false` | — |
| `deletion_requested_at` | `timestamptz` | sí | — | F-14 |
| `created_at` / `updated_at` | `timestamptz` | no | `now()` | — |

Constraints: `check (exercise_credit_percentage between 0 and 100)`,
`check (height_cm is null or height_cm between 90 and 250)`.

### 2.2 `goals`

Historial de objetivos: nunca se actualiza el objetivo vigente, se cierra y se crea otro.

| Columna | Tipo | Notas |
| --- | --- | --- |
| `id` | `uuid` PK | |
| `user_id` | `uuid` FK → profiles | |
| `goal_type` | `text` | `lose \| maintain \| gain` |
| `rate_kg_per_week` | `numeric(3,2)` | 0–1 (RN-13); 0 si mantiene |
| `target_weight_kg` | `numeric(6,2)` null | opcional |
| `base_calorie_target` | `integer` | 800–6000 |
| `target_method` | `text` | `calculated \| manual` |
| `bmr_kcal` / `tdee_kcal` | `integer` null | snapshot del cálculo |
| `protein_g` / `carbs_g` / `fat_g` | `integer` | objetivos de macro |
| `macro_method` | `text` | `default \| custom` |
| `starts_on` | `date` | |
| `ends_on` | `date` null | null = vigente |
| `created_at` / `updated_at` | | |

Constraints: `exclude using gist (user_id with =, daterange(starts_on, coalesce(ends_on,'infinity'::date)) with &&)`
→ garantiza un solo objetivo vigente por día.

### 2.3 `foods`

Alimentos **propios** del usuario.

`id`, `user_id`, `name text not null`, `brand text`, `barcode text`,
`serving_size numeric(8,2) not null`, `serving_unit text not null`,
`kcal integer not null`, `protein_g/carbs_g/fat_g numeric(7,2) not null default 0`,
`fiber_g/sugar_g/sodium_mg numeric(7,2)`, `is_favorite boolean default false`,
`source text default 'user'` (`user | usda | off | ai`), `external_id text`,
`created_at`, `updated_at`, `deleted_at`.

### 2.4 `foods_cache`

Cache pública de catálogos externos, solo lectura para los clientes.

`id uuid PK`, `source text` (`usda | off`), `external_id text`, `name`, `brand`,
`serving_size`, `serving_unit`, `kcal`, macros, `nutrients jsonb`,
`fetched_at timestamptz`, `expires_at timestamptz`.
Unique `(source, external_id)`. TTL 30 días, refresco perezoso.

### 2.5 `meals`

`id`, `user_id`, `slot text` (`breakfast|lunch|dinner|snack`), `logged_at timestamptz`,
`local_date date`, `name text` null, `total_kcal integer`, `total_protein_g/carbs_g/fat_g numeric(7,2)`,
`source text` (`manual | ai_photo | barcode | duplicate`), `ai_analysis_id uuid` null,
`photo_path text` null, `notes text` null, `is_favorite boolean`, `sync_status text`,
`created_at`, `updated_at`, `deleted_at`.

Los totales están **desnormalizados** y los mantiene el trigger `recalc_meal_totals()`
sobre `meal_items` (D-11: lectura de Inicio en una sola consulta).

### 2.6 `meal_items`

`id`, `meal_id` FK ON DELETE CASCADE, `food_id` null, `cache_food_id` null,
`name text not null` (snapshot: si el alimento cambia después, la comida no muta),
`quantity numeric(8,2)`, `unit text`, `kcal integer`, `protein_g/carbs_g/fat_g numeric(7,2)`,
`ai_confidence numeric(3,2)` null, `was_ai_corrected boolean default false`,
`position smallint`, `created_at`, `updated_at`.

### 2.7 `ai_analyses`

`id`, `user_id`, `photo_path text`, `status text` (`pending|completed|failed|accepted|discarded`),
`model text`, `prompt_version text`, `items jsonb`, `raw_response jsonb`,
`confidence_avg numeric(3,2)`, `latency_ms integer`, `error_code text` null,
`corrections jsonb` null, `created_at`, `updated_at`.

### 2.8 `activities`  ★

| Columna | Tipo | Null | Notas |
| --- | --- | --- | --- |
| `id` | `uuid` | no | PK |
| `user_id` | `uuid` | no | FK |
| `activity_type_id` | `uuid` | no | FK → `activity_types` |
| `custom_name` | `text` | sí | Nombre del entrenamiento / actividad personalizada |
| `started_at` | `timestamptz` | no | — |
| `ended_at` | `timestamptz` | sí | `started_at + duration` si falta |
| `local_date` | `date` | no | Día del usuario |
| `duration_minutes` | `integer` | no | 1–1440 |
| `intensity` | `text` | no | `light \| moderate \| vigorous` |
| `distance_meters` | `integer` | sí | 0–500000 |
| `steps` | `integer` | sí | 0–200000 |
| `average_heart_rate` | `smallint` | sí | 30–230 |
| `maximum_heart_rate` | `smallint` | sí | 30–230, ≥ average |
| `estimated_calories` | `integer` | no | Valor vigente (puede ser el corregido) |
| `original_calories` | `integer` | sí | Valor calculado antes del override (RN-04) |
| `applied_calories` | `integer` | no | Lo que suma al objetivo (RN-02) |
| `exercise_credit_percentage` | `smallint` | no | Porcentaje congelado al guardar |
| `estimation_method` | `text` | no | `met \| provider \| user_override \| met_recalculated \| pace` |
| `met_value` | `numeric(4,2)` | sí | MET usado |
| `weight_kg_used` | `numeric(6,2)` | sí | Peso usado en el cálculo (trazabilidad) |
| `override_reason` | `text` | sí | — |
| `source_type` | `text` | no | `manual \| imported \| template \| duplicated` |
| `external_source` | `text` | sí | `health_connect \| health_connect \| garmin \| …` |
| `external_id` | `text` | sí | Id del proveedor |
| `source_updated_at` | `timestamptz` | sí | Para sync incremental |
| `user_edited` | `boolean` | no | RN-06 |
| `notes` | `text` | sí | ≤ 1000 |
| `photo_path` | `text` | sí | — |
| `device_name` | `text` | sí | Dispositivo de origen |
| `is_favorite` | `boolean` | no | — |
| `sync_status` | `text` | no | — |
| `deletion_reason` | `text` | sí | `user \| duplicate_merge` |
| `created_at` / `updated_at` / `deleted_at` | | | |

Constraints:
```sql
check (duration_minutes between 1 and 1440)
check (intensity in ('light','moderate','vigorous'))
check (estimated_calories between 1 and 10000)
check (exercise_credit_percentage between 0 and 100)
check (maximum_heart_rate is null or average_heart_rate is null
       or average_heart_rate <= maximum_heart_rate)
check (ended_at is null or ended_at > started_at)
-- impide duplicados de registros externos
create unique index activities_external_uniq
  on activities (user_id, external_source, external_id)
  where external_source is not null and external_id is not null and deleted_at is null;
```

### 2.9 `activity_types`

`id`, `slug text unique`, `display_name text`, `category text`
(`cardio | strength | mobility | sports | other`), `default_met numeric(4,2)`,
`light_met`, `moderate_met`, `vigorous_met` (`numeric(4,2)` null),
`supports_distance boolean`, `supports_steps boolean`, `supports_heart_rate boolean`,
`icon_name text` (Phosphor), `is_system boolean`, `user_id uuid null` (null = del sistema),
`created_at`, `updated_at`.

Seed: `met-catalog.json` (15 tipos del MVP). Los valores MET **no se hardcodean en la UI**;
se leen de esta tabla y se pueden actualizar sin publicar una versión (D-06).

### 2.10 `activity_goals`

`id`, `user_id`, `goal_type text`
(`active_minutes | sessions | steps | distance | strength_sessions | active_days`),
`target_value numeric(10,2)`, `unit text` (`minutes|count|steps|meters|days`),
`period text` (`day|week`), `start_date date`, `end_date date null`,
`enabled boolean default true`, `created_at`, `updated_at`.

### 2.11 `exercise_templates`

`id`, `user_id`, `name text`, `activity_type_id uuid`, `default_duration_minutes integer`,
`default_intensity text`, `default_distance_meters integer null`, `default_notes text null`,
`use_count integer default 0`, `created_at`, `updated_at`, `deleted_at`.

### 2.12 `health_integrations`

`id`, `user_id`, `provider text` (`health_connect`),
`status text` (`not_connected | connected | permission_denied | provider_unavailable | error`),
`permissions jsonb` (array de scopes concedidos), `last_sync_at timestamptz null`,
`sync_cursor text null`, `last_error text null`, `connected_at`, `disconnected_at`,
`created_at`, `updated_at`. Unique `(user_id, provider)`.

### 2.13 `sync_records`

`id`, `user_id`, `provider text`, `entity_type text` (`activity|weight|steps|heart_rate`),
`external_id text`, `local_entity_id uuid null`, `source_updated_at timestamptz`,
`synced_at timestamptz`, `sync_hash text`, `skipped_reason text null`, `created_at`.
Unique `(user_id, provider, entity_type, external_id)`.

`sync_hash` = SHA-256 de `started_at|duration|calories|distance|type` — permite detectar si
el proveedor cambió el registro sin comparar campo por campo.

### 2.14 `weight_logs`

`id`, `user_id`, `weight_kg numeric(6,2)`, `local_date date`, `logged_at timestamptz`,
`source text` (`manual | imported`), `external_source`, `external_id`, `notes text`,
`photo_path text`, `sync_status`, `created_at`, `updated_at`, `deleted_at`.
Unique `(user_id, local_date) where deleted_at is null` (F-11: upsert por día).

### 2.15 `body_measurements`

`id`, `user_id`, `metric text` (`waist|hip|chest|arm|thigh|neck|body_fat_pct`),
`value numeric(6,2)`, `unit text` (`cm|pct`), `local_date date`, `notes`,
`created_at`, `updated_at`, `deleted_at`. Unique `(user_id, metric, local_date)` parcial.

### 2.16 `rest_days`

`id`, `user_id`, `local_date date`, `note text`, `created_at`.
Unique `(user_id, local_date)`. RN-15.

### 2.17 `recent_foods` / `recent_activities`

`user_id` + (`food_id` | `activity_type_id`) + `last_used_at` + `use_count`.
PK compuesta. Se actualizan por trigger al crear una comida / actividad. Se limitan a las
50 entradas más recientes por usuario mediante un job semanal.

### 2.18 `duplicate_resolutions`

`id`, `user_id`, `activity_a_id`, `activity_b_id`, `match_score numeric(3,2)`,
`resolution text` (`kept_a | kept_b | kept_both | deferred`), `resolved_at`, `created_at`.
Sirve de auditoría y de insumo para afinar el umbral de RN-07.

### 2.19 Fase 2 (crear la migración, no la UI)

**`strength_exercises`**: `id`, `activity_id` FK, `name`, `position`, `notes`,
`created_at`, `updated_at`.
**`strength_sets`**: `id`, `strength_exercise_id` FK, `set_number smallint`,
`reps smallint`, `weight_kg numeric(6,2)`, `rest_seconds smallint`,
`is_warmup boolean`, `rpe numeric(3,1)`, `created_at`.
**`workout_routines`** / **`routine_exercises`**: rutinas reutilizables.

Estas tablas se crean vacías en el MVP. Su existencia es lo que permite agregar el
seguimiento de gimnasio después sin migrar datos existentes.

---

## 3. Índices

```sql
-- acceso por usuario y día (el patrón dominante)
create index on meals            (user_id, local_date) where deleted_at is null;
create index on activities       (user_id, local_date) where deleted_at is null;
create index on weight_logs      (user_id, local_date) where deleted_at is null;
create index on body_measurements(user_id, metric, local_date) where deleted_at is null;

-- listados y detalle
create index on activities  (user_id, started_at desc) where deleted_at is null;
create index on activities  (activity_type_id);
create index on activities  (user_id, is_favorite) where is_favorite and deleted_at is null;
create index on meal_items  (meal_id);
create index on meals       (user_id, slot, local_date) where deleted_at is null;

-- sincronización y deduplicación
create index on activities   (external_source, external_id) where external_source is not null;
create index on sync_records (user_id, provider, entity_type);
create index on activities   (user_id, sync_status) where sync_status <> 'synced';

-- soft delete / papelera
create index on activities (deleted_at) where deleted_at is not null;
create index on meals      (deleted_at) where deleted_at is not null;

-- búsqueda de alimentos
create index on foods       using gin (to_tsvector('spanish', name || ' ' || coalesce(brand,'')));
create index on foods_cache using gin (to_tsvector('simple',  name || ' ' || coalesce(brand,'')));
create index on foods_cache (source, external_id);
create index on foods       (user_id, barcode) where barcode is not null;
```

## 4. Restricciones clave

| Restricción | Propósito |
| --- | --- |
| `activities_external_uniq` (parcial única) | Impide que dos sincronizaciones del mismo proveedor dupliquen una actividad |
| `sync_records` unique `(user_id, provider, entity_type, external_id)` | Idempotencia del cursor de sincronización |
| `weight_logs` unique `(user_id, local_date)` parcial | Un peso por día |
| `goals` exclusión por rango de fechas | Un objetivo vigente por día |
| `rest_days` unique `(user_id, local_date)` | Un descanso por día |
| CHECKs de rango en `activities` y `profiles` | Las validaciones de UI también viven en la base |

## 5. Soft deletes y papelera

- Borrar = `update … set deleted_at = now(), deletion_reason = 'user'`.
- La UI ofrece "Deshacer" durante 8 s (borra `deleted_at`).
- Un job diario purga definitivamente lo que lleve > 30 días borrado.
- Las vistas `v_active_meals`, `v_active_activities` encapsulan el filtro para no repetirlo.

## 6. Auditoría

- `updated_at` por trigger en todas las tablas.
- Tabla `audit_log` (`id`, `user_id`, `table_name`, `record_id`, `action`, `changed_fields jsonb`,
  `actor` (`user|sync|system`), `created_at`) alimentada por trigger **solo** en
  `activities`, `goals` y `profiles` — las tres donde importa saber quién cambió qué
  (override de calorías, cambio de objetivo, cambio de crédito).
- Retención de `audit_log`: 180 días.

## 7. Migraciones

- Numeradas y versionadas: `supabase/migrations/YYYYMMDDHHMMSS_descripcion.sql`.
- Cada migración es **idempotente** (`create table if not exists`, `drop … if exists`) y
  trae su `-- down` comentado al pie.
- Nunca se edita una migración ya aplicada en producción: se crea una nueva.
- Cambios de columna en dos pasos (agregar nullable → backfill → hacer not null) para no
  bloquear escrituras.
- El seed de `activity_types` es una migración de datos (`0007_seed_activity_types.sql`)
  con `on conflict (slug) do update` para poder ajustar los MET sin publicar la app.
- El esquema SQLite se genera desde las mismas migraciones con un script
  (`tool/gen_sqlite_schema.dart`) y se versiona junto a la app; el cliente aplica
  migraciones locales por número de versión al abrir la base.
