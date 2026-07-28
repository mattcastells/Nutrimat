-- 12 · Tablas de fase 2 (07-data-model.md §2.19).
--
-- Se crean **vacías** y sin UI. Su existencia es lo que permite agregar el
-- seguimiento de gimnasio después sin migrar datos existentes (PRD §5).

create table if not exists public.strength_exercises (
  id          uuid        primary key default extensions.gen_random_uuid(),
  activity_id uuid        not null
                references public.activities (id) on delete cascade,
  name        text        not null,
  position    smallint    not null default 0,
  notes       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.strength_sets (
  id                   uuid        primary key default extensions.gen_random_uuid(),
  strength_exercise_id uuid        not null
                         references public.strength_exercises (id) on delete cascade,
  set_number           smallint    not null,
  reps                 smallint,
  weight_kg            numeric(6,2),
  rest_seconds         smallint,
  is_warmup            boolean     not null default false,
  rpe                  numeric(3,1),
  created_at           timestamptz not null default now(),

  constraint strength_sets_rpe check (rpe is null or rpe between 1 and 10)
);

create table if not exists public.workout_routines (
  id         uuid        primary key default extensions.gen_random_uuid(),
  user_id    uuid        not null
               references public.profiles (id) on delete cascade,
  name       text        not null,
  notes      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.routine_exercises (
  id               uuid     primary key default extensions.gen_random_uuid(),
  routine_id       uuid     not null
                     references public.workout_routines (id) on delete cascade,
  name             text     not null,
  position         smallint not null default 0,
  target_sets      smallint,
  target_reps      smallint,
  created_at       timestamptz not null default now()
);

create index if not exists strength_exercises_activity_idx
  on public.strength_exercises (activity_id);
create index if not exists strength_sets_exercise_idx
  on public.strength_sets (strength_exercise_id);

-- down
-- drop table if exists public.routine_exercises;
-- drop table if exists public.workout_routines;
-- drop table if exists public.strength_sets;
-- drop table if exists public.strength_exercises;
