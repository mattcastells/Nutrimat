-- 31 · Limpieza: índices que duplican a otro y extensiones que nadie usa.
--
-- Nada de esto cambia comportamiento. Son cosas que se acumularon y que cuestan
-- en escritura y en lectura de código, no en correctitud.

-- ── Cinco índices que ya existían con otro nombre ────────────────────────
-- Un `unique` **crea su propio índice**, así que declarar después un índice
-- común sobre las mismas columnas deja dos estructuras idénticas: las dos se
-- actualizan en cada insert y en cada update, y el planificador usa una sola.
--
-- El caso de `weight_logs` merece su línea: el índice extra solo agregaba
-- `desc`, y un b-tree se recorre igual de bien en los dos sentidos. Un índice
-- descendente sobre las mismas columnas no aporta nada.
drop index if exists public.foods_cache_lookup_idx;      -- = foods_cache_uniq
drop index if exists public.rest_days_user_date_idx;     -- = rest_days_uniq
drop index if exists public.body_measurements_series_idx;-- = body_measurements_uniq
drop index if exists public.weight_logs_user_date_idx;   -- = weight_logs_day_uniq
drop index if exists public.water_logs_user_date_idx;    -- = water_logs_one_per_day
drop index if exists public.sleep_logs_user_date_idx;    -- = sleep_logs_one_per_day

-- ── Dos extensiones que no se usan en ningún lado ────────────────────────
-- `uuid-ossp` quedó de la plantilla: los uuid los genera `gen_random_uuid()`
-- de pgcrypto —que sí se usa— y no hay una sola llamada a `uuid_generate_*` en
-- las migraciones, los tests, las Edge Functions ni la app.
--
-- `pg_trgm` se sumó pensando en búsqueda difusa de alimentos, que terminó
-- resolviéndose de otra forma: ARGENFOODS viaja dentro del APK y se busca sin
-- red, y lo demás lo contestan Open Food Facts y USDA. No hay ningún índice
-- GIN/GiST ni ningún operador `%` que dependa de ella.
--
-- `if exists` y no a secas: en un proyecto donde ya se hubieran sacado a mano,
-- esto tiene que seguir corriendo.
drop extension if exists "uuid-ossp";
drop extension if exists pg_trgm;

-- down
-- create extension if not exists pg_trgm;
-- create extension if not exists "uuid-ossp";
-- create index if not exists sleep_logs_user_date_idx on public.sleep_logs (user_id, local_date desc);
-- create index if not exists water_logs_user_date_idx on public.water_logs (user_id, local_date desc);
-- create index if not exists weight_logs_user_date_idx on public.weight_logs (user_id, local_date desc) where deleted_at is null;
-- create index if not exists body_measurements_series_idx on public.body_measurements (user_id, metric, local_date) where deleted_at is null;
-- create index if not exists rest_days_user_date_idx on public.rest_days (user_id, local_date);
-- create index if not exists foods_cache_lookup_idx on public.foods_cache (source, external_id);
