-- 09 · activity_goals, exercise_templates y rest_days
-- (07-data-model.md §2.10, §2.11, §2.16).

-- Opcionales: nunca alteran el objetivo calórico ni bloquean nada (RN-09).
create table if not exists public.activity_goals (
  id           uuid        primary key,
  user_id      uuid        not null
                 references public.profiles (id) on delete cascade,
  goal_type    text        not null,
  target_value numeric(10,2) not null,
  unit         text        not null,
  period       text        not null default 'week',
  start_date   date        not null default current_date,
  end_date     date,
  enabled      boolean     not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint activity_goals_type check (goal_type in (
    'active_minutes', 'sessions', 'steps', 'distance',
    'strength_sessions', 'active_days')),
  constraint activity_goals_unit check (
    unit in ('minutes', 'count', 'steps', 'meters', 'days')),
  constraint activity_goals_period check (period in ('day', 'week')),
  constraint activity_goals_target check (target_value > 0)
);

create table if not exists public.exercise_templates (
  id                       uuid        primary key,
  user_id                  uuid        not null
                             references public.profiles (id) on delete cascade,
  name                     text        not null,
  activity_type_id         uuid        not null
                             references public.activity_types (id),
  default_duration_minutes integer     not null,
  default_intensity        text        not null default 'moderate',
  default_distance_meters  integer,
  default_notes            text,
  use_count                integer     not null default 0,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  deleted_at               timestamptz,

  constraint exercise_templates_duration check (
    default_duration_minutes between 1 and 1440),
  constraint exercise_templates_intensity check (
    default_intensity in ('light', 'moderate', 'vigorous'))
);

-- Un día de descanso planificado no cuenta como día sin actividad (RN-15).
create table if not exists public.rest_days (
  id         uuid        primary key default extensions.gen_random_uuid(),
  user_id    uuid        not null
               references public.profiles (id) on delete cascade,
  local_date date        not null,
  note       text,
  created_at timestamptz not null default now(),

  constraint rest_days_uniq unique (user_id, local_date)
);

create index if not exists activity_goals_user_idx
  on public.activity_goals (user_id) where enabled;
create index if not exists exercise_templates_user_idx
  on public.exercise_templates (user_id) where deleted_at is null;
create index if not exists rest_days_user_date_idx
  on public.rest_days (user_id, local_date);

drop trigger if exists activity_goals_set_updated_at on public.activity_goals;
create trigger activity_goals_set_updated_at
  before update on public.activity_goals
  for each row execute function public.set_updated_at();

drop trigger if exists exercise_templates_set_updated_at on public.exercise_templates;
create trigger exercise_templates_set_updated_at
  before update on public.exercise_templates
  for each row execute function public.set_updated_at();

-- down
-- drop table if exists public.rest_days;
-- drop table if exists public.exercise_templates;
-- drop table if exists public.activity_goals;
