-- 07 · activity_types (07-data-model.md §2.9).
--
-- Los valores MET viven acá, no en el código (D-06): se pueden corregir sin
-- publicar una versión de la app. Un lint prohíbe literales MET en la UI.

create table if not exists public.activity_types (
  id                  uuid        primary key default extensions.gen_random_uuid(),
  slug                text        not null unique,
  display_name        text        not null,
  category            text        not null,
  default_met         numeric(4,2) not null,
  light_met           numeric(4,2),
  moderate_met        numeric(4,2),
  vigorous_met        numeric(4,2),
  supports_distance   boolean     not null default false,
  supports_steps      boolean     not null default false,
  supports_heart_rate boolean     not null default false,
  icon_name           text        not null default 'DotsThreeCircle',
  is_system           boolean     not null default false,
  user_id             uuid        references public.profiles (id) on delete cascade,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint activity_types_category check (
    category in ('cardio', 'strength', 'mobility', 'sports', 'other')),
  -- Mismo rango que la fórmula MET (11-calculation-rules.md §8).
  constraint activity_types_met_range check (default_met between 0.9 and 23.0),
  constraint activity_types_light_range check (
    light_met is null or light_met between 0.9 and 23.0),
  constraint activity_types_moderate_range check (
    moderate_met is null or moderate_met between 0.9 and 23.0),
  constraint activity_types_vigorous_range check (
    vigorous_met is null or vigorous_met between 0.9 and 23.0),
  -- Los del sistema no tienen dueño; los personalizados sí.
  constraint activity_types_ownership check (
    (is_system and user_id is null) or (not is_system and user_id is not null))
);

create index if not exists activity_types_user_idx
  on public.activity_types (user_id) where user_id is not null;

drop trigger if exists activity_types_set_updated_at on public.activity_types;
create trigger activity_types_set_updated_at
  before update on public.activity_types
  for each row execute function public.set_updated_at();

-- down
-- drop table if exists public.activity_types;
