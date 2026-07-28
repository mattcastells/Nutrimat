-- 03 · goals (07-data-model.md §2.2).
--
-- El objetivo vigente nunca se actualiza: se cierra (`ends_on = ayer`) y se
-- inserta otro desde hoy (F-13). El historial no se reescribe.

create table if not exists public.goals (
  id                  uuid        primary key,
  user_id             uuid        not null
                        references public.profiles (id) on delete cascade,
  goal_type           text        not null,
  rate_kg_per_week    numeric(3,2) not null default 0,
  target_weight_kg    numeric(6,2),
  base_calorie_target integer     not null,
  target_method       text        not null default 'calculated',
  bmr_kcal            integer,
  tdee_kcal           integer,
  protein_g           integer     not null default 0,
  carbs_g             integer     not null default 0,
  fat_g               integer     not null default 0,
  macro_method        text        not null default 'default',
  starts_on           date        not null,
  ends_on             date,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint goals_type check (goal_type in ('lose', 'maintain', 'gain')),
  -- Tope de 1 kg por semana: no existe una opción más agresiva (RN-13).
  constraint goals_rate_range check (rate_kg_per_week between 0 and 1),
  constraint goals_target_range check (base_calorie_target between 800 and 6000),
  constraint goals_method check (target_method in ('calculated', 'manual')),
  constraint goals_macro_method check (macro_method in ('default', 'custom')),
  constraint goals_dates check (ends_on is null or ends_on >= starts_on)
);

-- Un solo objetivo vigente por día: la base lo garantiza, no la app.
alter table public.goals drop constraint if exists goals_no_overlap;
alter table public.goals add constraint goals_no_overlap
  exclude using gist (
    user_id with =,
    daterange(starts_on, coalesce(ends_on, 'infinity'::date), '[]') with &&
  );

create index if not exists goals_user_current_idx
  on public.goals (user_id, starts_on desc);

drop trigger if exists goals_set_updated_at on public.goals;
create trigger goals_set_updated_at
  before update on public.goals
  for each row execute function public.set_updated_at();

-- down
-- drop table if exists public.goals;
