-- 08 · activities ★ (07-data-model.md §2.8).
--
-- La tabla donde más fácil se implementa mal el producto: el porcentaje de
-- crédito va **congelado** en la fila (D-05), el valor calculado nunca se
-- pierde ante un override (RN-04) y el índice único externo impide que dos
-- sincronizaciones dupliquen la misma sesión (RN-07).

create table if not exists public.activities (
  id                         uuid        primary key,
  user_id                    uuid        not null
                               references public.profiles (id) on delete cascade,
  activity_type_id           uuid        not null
                               references public.activity_types (id),
  custom_name                text,
  started_at                 timestamptz not null,
  ended_at                   timestamptz,
  local_date                 date        not null,
  duration_minutes           integer     not null,
  intensity                  text        not null default 'moderate',
  distance_meters            integer,
  steps                      integer,
  average_heart_rate         smallint,
  maximum_heart_rate         smallint,
  estimated_calories         integer     not null,
  original_calories          integer,
  applied_calories           integer     not null default 0,
  exercise_credit_percentage smallint    not null default 0,
  estimation_method          text        not null default 'met',
  met_value                  numeric(4,2),
  weight_kg_used             numeric(6,2),
  override_reason            text,
  source_type                text        not null default 'manual',
  external_source            text,
  external_id                text,
  source_updated_at          timestamptz,
  user_edited                boolean     not null default false,
  notes                      text,
  photo_path                 text,
  device_name                text,
  is_favorite                boolean     not null default false,
  sync_status                text        not null default 'synced',
  deletion_reason            text,
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now(),
  deleted_at                 timestamptz,

  -- Sin tope práctico en la UI: el límite es el del modelo, un día (D-22).
  constraint activities_duration check (duration_minutes between 1 and 1440),
  constraint activities_intensity check (
    intensity in ('light', 'moderate', 'vigorous')),
  constraint activities_calories check (estimated_calories between 1 and 10000),
  constraint activities_credit check (
    exercise_credit_percentage between 0 and 100),
  constraint activities_distance check (
    distance_meters is null or distance_meters between 0 and 500000),
  constraint activities_steps check (
    steps is null or steps between 0 and 200000),
  constraint activities_avg_hr check (
    average_heart_rate is null or average_heart_rate between 30 and 230),
  constraint activities_max_hr check (
    maximum_heart_rate is null or maximum_heart_rate between 30 and 230),
  constraint activities_hr_order check (
    maximum_heart_rate is null or average_heart_rate is null
    or average_heart_rate <= maximum_heart_rate),
  constraint activities_interval check (ended_at is null or ended_at > started_at),
  constraint activities_notes_len check (
    notes is null or char_length(notes) <= 1000),
  constraint activities_method check (estimation_method in (
    'met', 'provider', 'user_override', 'met_recalculated', 'pace')),
  constraint activities_source_type check (
    source_type in ('manual', 'imported', 'template', 'duplicated')),
  constraint activities_sync_status check (
    sync_status in ('synced', 'pending', 'syncing', 'error', 'needs_review')),
  constraint activities_deletion_reason check (
    deletion_reason is null or deletion_reason in ('user', 'duplicate_merge'))
);

-- Impide que dos sincronizaciones del mismo proveedor dupliquen una actividad.
create unique index if not exists activities_external_uniq
  on public.activities (user_id, external_source, external_id)
  where external_source is not null
    and external_id is not null
    and deleted_at is null;

create index if not exists activities_user_date_idx
  on public.activities (user_id, local_date) where deleted_at is null;
create index if not exists activities_user_started_idx
  on public.activities (user_id, started_at desc) where deleted_at is null;
create index if not exists activities_type_idx
  on public.activities (activity_type_id);
create index if not exists activities_favorite_idx
  on public.activities (user_id, is_favorite)
  where is_favorite and deleted_at is null;
create index if not exists activities_external_idx
  on public.activities (external_source, external_id)
  where external_source is not null;
create index if not exists activities_pending_idx
  on public.activities (user_id, sync_status) where sync_status <> 'synced';
create index if not exists activities_deleted_idx
  on public.activities (deleted_at) where deleted_at is not null;

-- `applied_calories = round(estimated × porcentaje / 100)` (RN-02). La base es
-- la última palabra: si el cliente manda otra cosa, se corrige acá.
create or replace function public.recalc_applied_calories()
returns trigger
language plpgsql
as $$
begin
  new.applied_calories := round(
    new.estimated_calories * new.exercise_credit_percentage / 100.0);
  return new;
end;
$$;

drop trigger if exists activities_recalc_applied on public.activities;
create trigger activities_recalc_applied
  before insert or update of estimated_calories, exercise_credit_percentage
  on public.activities
  for each row execute function public.recalc_applied_calories();

-- Recientes de actividad: alimenta los chips de S-09 y S-10.
create table if not exists public.recent_activities (
  user_id          uuid        not null
                     references public.profiles (id) on delete cascade,
  activity_type_id uuid        not null
                     references public.activity_types (id) on delete cascade,
  last_used_at     timestamptz not null default now(),
  use_count        integer     not null default 1,
  primary key (user_id, activity_type_id)
);

create or replace function public.track_recent_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.recent_activities (
    user_id, activity_type_id, last_used_at, use_count)
  values (new.user_id, new.activity_type_id, now(), 1)
  on conflict (user_id, activity_type_id) do update
    set last_used_at = now(),
        use_count    = public.recent_activities.use_count + 1;
  return new;
end;
$$;

drop trigger if exists activities_track_recent on public.activities;
create trigger activities_track_recent
  after insert on public.activities
  for each row execute function public.track_recent_activity();

drop trigger if exists activities_set_updated_at on public.activities;
create trigger activities_set_updated_at
  before update on public.activities
  for each row execute function public.set_updated_at();

drop trigger if exists activities_guard_hard_delete on public.activities;
create trigger activities_guard_hard_delete
  before delete on public.activities
  for each row execute function public.guard_hard_delete();

-- down
-- drop table if exists public.recent_activities;
-- drop table if exists public.activities;
