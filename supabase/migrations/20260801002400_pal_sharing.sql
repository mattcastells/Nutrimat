-- 25 · Pals: fotos, agua, sueño y detalle de ejercicio, a elección de quien
-- comparte.
--
-- Hasta acá `shared_days` publicaba solo comida (nombre + kcal, sin foto) y un
-- agregado de actividad, sin que nadie pudiera elegir nada — era o todo eso, o
-- nada. Se agrega la posibilidad de sumar cuatro categorías más, cada una
-- apagada por default: quien comparte prende lo que quiere desde su perfil, y
-- mientras no lo haga, nada cambia respecto de hoy.
--
-- Peso y medidas siguen fuera de este archivo por completo, a propósito: eso
-- no se pidió, y la pantalla de Pals promete explícitamente que nunca se
-- comparten.

-- ── Qué prende cada quien ─────────────────────────────────────────────────
alter table public.profiles
  add column if not exists pal_share_photos           boolean not null default false,
  add column if not exists pal_share_water             boolean not null default false,
  add column if not exists pal_share_sleep             boolean not null default false,
  add column if not exists pal_share_activity_detail   boolean not null default false;

-- ── Lo nuevo que se puede publicar ────────────────────────────────────────
-- `activities` solo se llena si `pal_share_activity_detail` está prendido; si
-- no, sigue viajando vacío y el agregado (`activity_minutes`/`activity_count`,
-- que no es opcional y no cambia con esta migración) es todo lo que se ve.
alter table public.shared_days
  add column if not exists activities     jsonb not null default '[]'::jsonb,
  add column if not exists water_glasses  integer,
  add column if not exists sleep_minutes  integer,
  add column if not exists sleep_quality  text;

alter table public.shared_days
  add constraint shared_days_water_range
    check (water_glasses is null or water_glasses between 0 and 40),
  add constraint shared_days_sleep_minutes_range
    check (sleep_minutes is null or sleep_minutes between 0 and 1440),
  add constraint shared_days_sleep_quality_valid
    check (sleep_quality is null
      or sleep_quality in ('bad', 'poor', 'ok', 'good', 'great'));

-- ── Agua y sueño: solo si el dueño lo prendió ─────────────────────────────
-- Esto es la garantía de fondo, no la de la app: aunque un bug de interfaz
-- mandara a publicar de más, la base sigue sin devolver la fila a nadie que
-- no debería verla.
create policy water_logs_pal_read on public.water_logs
  for select to authenticated
  using (
    public.is_pal_of(user_id)
    and exists (
      select 1 from public.profiles p
       where p.id = water_logs.user_id and p.pal_share_water
    )
  );

create policy sleep_logs_pal_read on public.sleep_logs
  for select to authenticated
  using (
    public.is_pal_of(user_id)
    and exists (
      select 1 from public.profiles p
       where p.id = sleep_logs.user_id and p.pal_share_sleep
    )
  );

-- ── Fotos: solo la del día publicado, solo de los últimos 7 días ─────────
-- No es "todas las fotos que subiste alguna vez": el objeto solo se abre si
-- su ruta aparece dentro de un `shared_days.meals` reciente de ese dueño, con
-- el toggle prendido. `(storage.foldername(name))[1]` es la carpeta del
-- dueño, misma convención que la migración 18.
create policy meal_photos_pal_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'meal-photos'
    and public.is_pal_of((storage.foldername(name))[1]::uuid)
    and exists (
      select 1 from public.profiles p
       where p.id = (storage.foldername(name))[1]::uuid
         and p.pal_share_photos
    )
    and exists (
      select 1 from public.shared_days sd
       where sd.user_id = (storage.foldername(name))[1]::uuid
         and sd.local_date >= current_date - 7
         and sd.meals @> jsonb_build_array(jsonb_build_object('photoPath', name))
    )
  );

-- down
-- drop policy if exists meal_photos_pal_read on storage.objects;
-- drop policy if exists sleep_logs_pal_read on public.sleep_logs;
-- drop policy if exists water_logs_pal_read on public.water_logs;
-- alter table public.shared_days
--   drop constraint if exists shared_days_sleep_quality_valid,
--   drop constraint if exists shared_days_sleep_minutes_range,
--   drop constraint if exists shared_days_water_range,
--   drop column if exists sleep_quality,
--   drop column if exists sleep_minutes,
--   drop column if exists water_glasses,
--   drop column if exists activities;
-- alter table public.profiles
--   drop column if exists pal_share_activity_detail,
--   drop column if exists pal_share_sleep,
--   drop column if exists pal_share_water,
--   drop column if exists pal_share_photos;
