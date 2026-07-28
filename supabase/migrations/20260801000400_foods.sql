-- 04 · foods, foods_cache y recent_foods (07-data-model.md §2.3, §2.4, §2.17).

-- Alimentos propios del usuario: privados (RN-18).
create table if not exists public.foods (
  id           uuid        primary key,
  user_id      uuid        not null
                 references public.profiles (id) on delete cascade,
  name         text        not null,
  brand        text,
  barcode      text,
  serving_size numeric(8,2) not null,
  serving_unit text        not null,
  kcal         integer     not null,
  protein_g    numeric(7,2) not null default 0,
  carbs_g      numeric(7,2) not null default 0,
  fat_g        numeric(7,2) not null default 0,
  fiber_g      numeric(7,2),
  sugar_g      numeric(7,2),
  sodium_mg    numeric(7,2),
  is_favorite  boolean     not null default false,
  source       text        not null default 'user',
  external_id  text,
  nutrient_warning boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,

  constraint foods_name_len check (char_length(name) between 1 and 120),
  constraint foods_source check (source in ('user', 'usda', 'off', 'ai')),
  constraint foods_serving_range check (serving_size > 0 and serving_size <= 10000),
  constraint foods_kcal_range check (kcal between 0 and 2000),
  constraint foods_macro_range check (
    protein_g between 0 and 500
    and carbs_g between 0 and 500
    and fat_g between 0 and 500)
);

-- Cache pública de catálogos externos: lectura para autenticados, escritura
-- solo desde las Edge Functions con service_role.
create table if not exists public.foods_cache (
  id           uuid        primary key default extensions.gen_random_uuid(),
  source       text        not null,
  external_id  text        not null,
  name         text        not null,
  brand        text,
  barcode      text,
  serving_size numeric(8,2) not null default 100,
  serving_unit text        not null default 'g',
  kcal         integer     not null,
  protein_g    numeric(7,2) not null default 0,
  carbs_g      numeric(7,2) not null default 0,
  fat_g        numeric(7,2) not null default 0,
  fiber_g      numeric(7,2),
  sugar_g      numeric(7,2),
  sodium_mg    numeric(7,2),
  nutrients    jsonb,
  fetched_at   timestamptz not null default now(),
  -- TTL de 30 días con refresco perezoso (13-state-management.md §4).
  expires_at   timestamptz not null default now() + interval '30 days',

  constraint foods_cache_source check (source in ('usda', 'off')),
  constraint foods_cache_uniq unique (source, external_id)
);

-- Recientes: alimenta las pestañas de S-16 sin recorrer todo el historial.
create table if not exists public.recent_foods (
  user_id      uuid        not null
                 references public.profiles (id) on delete cascade,
  food_id      text        not null,
  last_used_at timestamptz not null default now(),
  use_count    integer     not null default 1,
  primary key (user_id, food_id)
);

create index if not exists foods_user_active_idx
  on public.foods (user_id) where deleted_at is null;
create index if not exists foods_barcode_idx
  on public.foods (user_id, barcode) where barcode is not null;
create index if not exists foods_search_idx
  on public.foods using gin (
    to_tsvector('spanish', name || ' ' || coalesce(brand, '')));
create index if not exists foods_cache_search_idx
  on public.foods_cache using gin (
    to_tsvector('simple', name || ' ' || coalesce(brand, '')));
create index if not exists foods_cache_lookup_idx
  on public.foods_cache (source, external_id);
create index if not exists recent_foods_recent_idx
  on public.recent_foods (user_id, last_used_at desc);

drop trigger if exists foods_set_updated_at on public.foods;
create trigger foods_set_updated_at
  before update on public.foods
  for each row execute function public.set_updated_at();

-- down
-- drop table if exists public.recent_foods;
-- drop table if exists public.foods_cache;
-- drop table if exists public.foods;
