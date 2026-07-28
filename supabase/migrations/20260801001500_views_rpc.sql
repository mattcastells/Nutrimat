-- 15 · Vistas activas y RPC (08-supabase-plan.md §1).
--
-- Las vistas encapsulan el filtro de soft delete para no repetirlo en cada
-- consulta (07-data-model.md §5). `security_invoker` hace que la RLS del
-- usuario siga aplicando al leer la vista.

create or replace view public.v_active_meals
with (security_invoker = true) as
  select * from public.meals where deleted_at is null;

create or replace view public.v_active_activities
with (security_invoker = true) as
  select * from public.activities where deleted_at is null;

-- ── create_meal_with_items ───────────────────────────────────────────────
-- Una comida y sus ítems en una sola transacción, idempotente por el `id`
-- que genera el cliente: reintentar una escritura encolada no duplica (F-07).
create or replace function public.create_meal_with_items(
  p_meal  jsonb,
  p_items jsonb
)
returns public.meals
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_meal   public.meals;
  v_item   jsonb;
  v_position smallint := 0;
begin
  insert into public.meals (
    id, user_id, slot, logged_at, local_date, name, source,
    ai_analysis_id, photo_path, notes, sync_status
  )
  values (
    (p_meal ->> 'id')::uuid,
    auth.uid(),
    p_meal ->> 'slot',
    coalesce((p_meal ->> 'logged_at')::timestamptz, now()),
    (p_meal ->> 'local_date')::date,
    p_meal ->> 'name',
    coalesce(p_meal ->> 'source', 'manual'),
    (p_meal ->> 'ai_analysis_id')::uuid,
    p_meal ->> 'photo_path',
    p_meal ->> 'notes',
    'synced'
  )
  -- 409 por id duplicado se considera éxito: la escritura ya había llegado.
  on conflict (id) do update set updated_at = now()
  returning * into v_meal;

  -- Al reenviar la misma comida, sus ítems se reemplazan por los del payload.
  delete from public.meal_items where meal_id = v_meal.id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    insert into public.meal_items (
      id, meal_id, food_id, cache_food_id, name, quantity, unit, kcal,
      protein_g, carbs_g, fat_g, ai_confidence, was_ai_corrected, position
    )
    values (
      coalesce((v_item ->> 'id')::uuid, extensions.gen_random_uuid()),
      v_meal.id,
      (v_item ->> 'food_id')::uuid,
      (v_item ->> 'cache_food_id')::uuid,
      v_item ->> 'name',
      (v_item ->> 'quantity')::numeric,
      coalesce(v_item ->> 'unit', 'g'),
      (v_item ->> 'kcal')::integer,
      coalesce((v_item ->> 'protein_g')::numeric, 0),
      coalesce((v_item ->> 'carbs_g')::numeric, 0),
      coalesce((v_item ->> 'fat_g')::numeric, 0),
      (v_item ->> 'ai_confidence')::numeric,
      coalesce((v_item ->> 'was_ai_corrected')::boolean, false),
      v_position
    );
    v_position := v_position + 1;
  end loop;

  select * into v_meal from public.meals where id = v_meal.id;
  return v_meal;
end;
$$;

-- ── get_daily_summary ────────────────────────────────────────────────────
-- El agregado de Inicio en una sola consulta (S-06). Devuelve las seis filas
-- del cálculo por separado: el objetivo base nunca se modifica por el
-- ejercicio (RN-01).
create or replace function public.get_daily_summary(p_date date)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user            uuid := auth.uid();
  v_goal            public.goals;
  v_consumed        integer := 0;
  v_protein         numeric := 0;
  v_carbs           numeric := 0;
  v_fat             numeric := 0;
  v_estimated       integer := 0;
  v_applied         integer := 0;
  v_minutes         integer := 0;
  v_sessions        integer := 0;
  v_steps           integer;
  v_credit          smallint := 0;
  v_credit_enabled  boolean := false;
  v_is_rest         boolean := false;
  v_weight          numeric;
begin
  if v_user is null then
    raise exception 'ERR_UNAUTHENTICATED' using errcode = '28000';
  end if;

  select exercise_credit_percentage, exercise_credit_enabled
    into v_credit, v_credit_enabled
    from public.profiles where id = v_user;

  select * into v_goal
    from public.goals
   where user_id = v_user
     and starts_on <= p_date
     and (ends_on is null or ends_on >= p_date)
   order by starts_on desc
   limit 1;

  select coalesce(sum(total_kcal), 0),
         coalesce(sum(total_protein_g), 0),
         coalesce(sum(total_carbs_g), 0),
         coalesce(sum(total_fat_g), 0)
    into v_consumed, v_protein, v_carbs, v_fat
    from public.meals
   where user_id = v_user and local_date = p_date and deleted_at is null;

  select coalesce(sum(estimated_calories), 0),
         coalesce(sum(applied_calories), 0),
         coalesce(sum(duration_minutes), 0),
         count(*),
         nullif(coalesce(sum(steps), 0), 0)
    into v_estimated, v_applied, v_minutes, v_sessions, v_steps
    from public.activities
   where user_id = v_user and local_date = p_date and deleted_at is null;

  select exists (
    select 1 from public.rest_days
     where user_id = v_user and local_date = p_date) into v_is_rest;

  select weight_kg into v_weight
    from public.weight_logs
   where user_id = v_user and local_date <= p_date and deleted_at is null
   order by local_date desc
   limit 1;

  if not v_credit_enabled then
    v_applied := 0;
  end if;

  return jsonb_build_object(
    'date',                  p_date,
    'base_target',           coalesce(v_goal.base_calorie_target, 0),
    'consumed_kcal',         v_consumed,
    'exercise_estimated_kcal', v_estimated,
    'exercise_applied_kcal', v_applied,
    'credit_percentage',     v_credit,
    'credit_enabled',        v_credit_enabled,
    'adjusted_target',       coalesce(v_goal.base_calorie_target, 0) + v_applied,
    'remaining_kcal',        coalesce(v_goal.base_calorie_target, 0) + v_applied - v_consumed,
    'net_kcal',              v_consumed - v_applied,
    'macros', jsonb_build_object(
      'protein', jsonb_build_object('current', v_protein, 'target', coalesce(v_goal.protein_g, 0)),
      'carbs',   jsonb_build_object('current', v_carbs,   'target', coalesce(v_goal.carbs_g, 0)),
      'fat',     jsonb_build_object('current', v_fat,     'target', coalesce(v_goal.fat_g, 0))),
    'activity_totals', jsonb_build_object(
      'minutes', v_minutes, 'sessions', v_sessions, 'steps', v_steps),
    'weight_kg', v_weight,
    'is_rest_day', v_is_rest
  );
end;
$$;

-- down
-- drop function if exists public.get_daily_summary(date);
-- drop function if exists public.create_meal_with_items(jsonb, jsonb);
-- drop view if exists public.v_active_activities;
-- drop view if exists public.v_active_meals;
