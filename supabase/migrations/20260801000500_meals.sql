-- 05 · meals, meal_items y el trigger de totales (07-data-model.md §2.5, §2.6).
--
-- Los totales de la comida están desnormalizados y los mantiene el trigger:
-- es la **única** vía de escritura de esos campos (D-11).

create table if not exists public.meals (
  id              uuid        primary key,
  user_id         uuid        not null
                    references public.profiles (id) on delete cascade,
  slot            text        not null,
  logged_at       timestamptz not null default now(),
  local_date      date        not null,
  name            text,
  total_kcal      integer     not null default 0,
  total_protein_g numeric(7,2) not null default 0,
  total_carbs_g   numeric(7,2) not null default 0,
  total_fat_g     numeric(7,2) not null default 0,
  source          text        not null default 'manual',
  ai_analysis_id  uuid,
  photo_path      text,
  notes           text,
  is_favorite     boolean     not null default false,
  sync_status     text        not null default 'synced',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,

  constraint meals_slot check (slot in ('breakfast', 'lunch', 'dinner', 'snack')),
  constraint meals_source check (
    source in ('manual', 'ai_photo', 'barcode', 'duplicate')),
  constraint meals_sync_status check (
    sync_status in ('synced', 'pending', 'syncing', 'error', 'needs_review'))
);

create table if not exists public.meal_items (
  id               uuid        primary key,
  meal_id          uuid        not null
                     references public.meals (id) on delete cascade,
  food_id          uuid        references public.foods (id) on delete set null,
  cache_food_id    uuid        references public.foods_cache (id) on delete set null,
  -- Snapshot: si el alimento de origen cambia después, la comida no muta.
  name             text        not null,
  quantity         numeric(8,2) not null,
  unit             text        not null,
  kcal             integer     not null,
  protein_g        numeric(7,2) not null default 0,
  carbs_g          numeric(7,2) not null default 0,
  fat_g            numeric(7,2) not null default 0,
  ai_confidence    numeric(3,2),
  was_ai_corrected boolean     not null default false,
  position         smallint    not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint meal_items_quantity check (quantity > 0 and quantity <= 10000),
  constraint meal_items_confidence check (
    ai_confidence is null or ai_confidence between 0 and 1)
);

-- Se redondea por ítem y se suman los redondeados, para que la suma visible
-- coincida con el total visible (11-calculation-rules.md §6).
create or replace function public.recalc_meal_totals()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_meal uuid := coalesce(new.meal_id, old.meal_id);
begin
  update public.meals m
     set total_kcal      = coalesce(t.kcal, 0),
         total_protein_g = coalesce(t.protein_g, 0),
         total_carbs_g   = coalesce(t.carbs_g, 0),
         total_fat_g     = coalesce(t.fat_g, 0),
         updated_at      = now()
    from (
      select sum(kcal)::integer as kcal,
             sum(protein_g)     as protein_g,
             sum(carbs_g)       as carbs_g,
             sum(fat_g)         as fat_g
        from public.meal_items
       where meal_id = target_meal
    ) t
   where m.id = target_meal;

  return coalesce(new, old);
end;
$$;

drop trigger if exists meal_items_recalc_totals on public.meal_items;
create trigger meal_items_recalc_totals
  after insert or update or delete on public.meal_items
  for each row execute function public.recalc_meal_totals();

-- Recientes de alimentos: se alimenta solo al registrar una comida.
create or replace function public.track_recent_food()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid;
  key   text := coalesce(new.food_id::text, new.cache_food_id::text);
begin
  if key is null then
    return new;
  end if;

  select user_id into owner from public.meals where id = new.meal_id;
  if owner is null then
    return new;
  end if;

  insert into public.recent_foods (user_id, food_id, last_used_at, use_count)
  values (owner, key, now(), 1)
  on conflict (user_id, food_id) do update
    set last_used_at = now(),
        use_count    = public.recent_foods.use_count + 1;

  return new;
end;
$$;

drop trigger if exists meal_items_track_recent on public.meal_items;
create trigger meal_items_track_recent
  after insert on public.meal_items
  for each row execute function public.track_recent_food();

create index if not exists meals_user_date_idx
  on public.meals (user_id, local_date) where deleted_at is null;
create index if not exists meals_user_slot_date_idx
  on public.meals (user_id, slot, local_date) where deleted_at is null;
create index if not exists meals_deleted_idx
  on public.meals (deleted_at) where deleted_at is not null;
create index if not exists meal_items_meal_idx on public.meal_items (meal_id);

drop trigger if exists meals_set_updated_at on public.meals;
create trigger meals_set_updated_at
  before update on public.meals
  for each row execute function public.set_updated_at();

drop trigger if exists meal_items_set_updated_at on public.meal_items;
create trigger meal_items_set_updated_at
  before update on public.meal_items
  for each row execute function public.set_updated_at();

drop trigger if exists meals_guard_hard_delete on public.meals;
create trigger meals_guard_hard_delete
  before delete on public.meals
  for each row execute function public.guard_hard_delete();

-- down
-- drop table if exists public.meal_items;
-- drop table if exists public.meals;
