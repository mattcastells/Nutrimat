-- 10 · weight_logs y body_measurements (07-data-model.md §2.14, §2.15).

-- Un peso por día: registrar de nuevo actualiza el existente (D-16, F-11).
create table if not exists public.weight_logs (
  id              uuid        primary key,
  user_id         uuid        not null
                    references public.profiles (id) on delete cascade,
  weight_kg       numeric(6,2) not null,
  local_date      date        not null,
  logged_at       timestamptz not null default now(),
  source          text        not null default 'manual',
  external_source text,
  external_id     text,
  notes           text,
  photo_path      text,
  sync_status     text        not null default 'synced',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,

  constraint weight_logs_range check (weight_kg between 25 and 400),
  constraint weight_logs_source check (source in ('manual', 'imported')),
  constraint weight_logs_sync_status check (
    sync_status in ('synced', 'pending', 'syncing', 'error', 'needs_review'))
);

create unique index if not exists weight_logs_day_uniq
  on public.weight_logs (user_id, local_date) where deleted_at is null;
create index if not exists weight_logs_user_date_idx
  on public.weight_logs (user_id, local_date desc) where deleted_at is null;

create table if not exists public.body_measurements (
  id         uuid        primary key,
  user_id    uuid        not null
               references public.profiles (id) on delete cascade,
  metric     text        not null,
  value      numeric(6,2) not null,
  unit       text        not null default 'cm',
  local_date date        not null,
  notes      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint body_measurements_metric check (metric in (
    'waist', 'hip', 'chest', 'arm', 'thigh', 'neck', 'body_fat_pct')),
  constraint body_measurements_unit check (unit in ('cm', 'pct')),
  -- 10–300 cm por medida; grasa corporal 3–70 % (S-26).
  constraint body_measurements_range check (
    (unit = 'cm'  and value between 10 and 300) or
    (unit = 'pct' and value between 3 and 70))
);

create unique index if not exists body_measurements_uniq
  on public.body_measurements (user_id, metric, local_date)
  where deleted_at is null;
create index if not exists body_measurements_series_idx
  on public.body_measurements (user_id, metric, local_date)
  where deleted_at is null;

drop trigger if exists weight_logs_set_updated_at on public.weight_logs;
create trigger weight_logs_set_updated_at
  before update on public.weight_logs
  for each row execute function public.set_updated_at();

drop trigger if exists body_measurements_set_updated_at on public.body_measurements;
create trigger body_measurements_set_updated_at
  before update on public.body_measurements
  for each row execute function public.set_updated_at();

-- down
-- drop table if exists public.body_measurements;
-- drop table if exists public.weight_logs;
