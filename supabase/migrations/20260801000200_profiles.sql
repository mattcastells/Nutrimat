-- 02 · profiles + alta automática desde auth.users (07-data-model.md §2.1).

create table if not exists public.profiles (
  id                          uuid primary key
                                references auth.users (id) on delete cascade,
  display_name                text,
  avatar_path                 text,
  biological_sex              text        not null default 'unspecified',
  birth_date                  date,
  height_cm                   numeric(5,1),
  activity_level              text        not null default 'sedentary',
  timezone                    text        not null default 'America/Argentina/Buenos_Aires',
  unit_system                 text        not null default 'metric',
  theme_mode                  text        not null default 'system',
  locale                      text        not null default 'es',
  -- 0 % por defecto: el ejercicio no suma al presupuesto (D-02).
  exercise_credit_percentage  smallint    not null default 0,
  exercise_credit_enabled     boolean     not null default false,
  show_net_calories           boolean     not null default false,
  profile_completed           boolean     not null default false,
  deletion_requested_at       timestamptz,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),

  constraint profiles_display_name_len check (
    display_name is null or char_length(display_name) <= 80),
  constraint profiles_biological_sex check (
    biological_sex in ('male', 'female', 'unspecified')),
  constraint profiles_activity_level check (
    activity_level in ('sedentary', 'light', 'moderate', 'high', 'very_high')),
  constraint profiles_unit_system check (unit_system in ('metric', 'imperial')),
  constraint profiles_theme_mode check (theme_mode in ('light', 'dark', 'system')),
  constraint profiles_credit_range check (
    exercise_credit_percentage between 0 and 100),
  constraint profiles_height_range check (
    height_cm is null or height_cm between 90 and 250),
  -- Edad 13–100 (RN-12 y F-02).
  constraint profiles_birth_date_range check (
    birth_date is null
    or birth_date between current_date - interval '100 years'
                      and current_date - interval '13 years')
);

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Cada usuario de auth tiene su fila de perfil desde el minuto cero (F-01).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- down
-- drop trigger if exists on_auth_user_created on auth.users;
-- drop function if exists public.handle_new_user();
-- drop table if exists public.profiles;
