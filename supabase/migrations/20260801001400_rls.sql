-- 14 · Row Level Security (08-supabase-plan.md §2).
--
-- Esto es lo que hace segura a la `anon key` en el cliente. Sin estas
-- políticas, cualquiera con la clave pública lee la base entera.
--
-- Patrón por defecto: se ve y se escribe lo propio; el borrado físico está
-- prohibido porque la app hace soft delete (§5 del modelo de datos).
-- La verificación vive en supabase/tests/rls_test.sql y es obligatoria antes
-- de avanzar (decisions.md §4, paso 4).

-- ── GRANTs ────────────────────────────────────────────────────────────────
-- RLS decide **qué filas** ve un rol, pero antes hace falta permiso sobre la
-- tabla. Sin esto, `authenticated` recibe "permission denied" y las políticas
-- no llegan a evaluarse nunca.
--
-- Dar permisos amplios es seguro **porque** RLS está activo en todas las
-- tablas: donde no hay policy que habilite una operación, la operación se
-- deniega (es el modelo de Supabase). `anon` no recibe permisos de tabla: sin
-- iniciar sesión no se lee nada.
grant usage on schema public to anon, authenticated;

grant select, insert, update, delete
  on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

-- Lo mismo para lo que se cree en migraciones futuras.
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant usage, select on sequences to authenticated;
alter default privileges in schema public
  grant execute on functions to authenticated;

-- ── Helper: aplica el patrón estándar a una tabla con user_id ─────────────
do $$
declare
  t text;
  standard_tables text[] := array[
    'goals', 'foods', 'meals', 'ai_analyses', 'activities', 'activity_goals',
    'exercise_templates', 'rest_days', 'weight_logs', 'body_measurements',
    'health_integrations', 'sync_records', 'duplicate_resolutions',
    'recent_foods', 'recent_activities', 'workout_routines'
  ];
begin
  foreach t in array standard_tables loop
    execute format('alter table public.%I enable row level security', t);

    execute format('drop policy if exists %I on public.%I', t || '_select_own', t);
    execute format(
      'create policy %I on public.%I for select using (auth.uid() = user_id)',
      t || '_select_own', t);

    execute format('drop policy if exists %I on public.%I', t || '_insert_own', t);
    execute format(
      'create policy %I on public.%I for insert with check (auth.uid() = user_id)',
      t || '_insert_own', t);

    execute format('drop policy if exists %I on public.%I', t || '_update_own', t);
    execute format(
      'create policy %I on public.%I for update using (auth.uid() = user_id) '
      'with check (auth.uid() = user_id)',
      t || '_update_own', t);

    -- El borrado físico se prohíbe: la app borra con `deleted_at`.
    execute format('drop policy if exists %I on public.%I', t || '_no_hard_delete', t);
    execute format(
      'create policy %I on public.%I for delete using (false)',
      t || '_no_hard_delete', t);
  end loop;
end
$$;

-- ── profiles: la pertenencia es la propia PK ──────────────────────────────
alter table public.profiles enable row level security;

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select using (auth.uid() = id);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- El alta la hace el trigger `on_auth_user_created`, no el cliente.
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert with check (auth.uid() = id);

drop policy if exists profiles_no_hard_delete on public.profiles;
create policy profiles_no_hard_delete on public.profiles
  for delete using (false);

-- ── meal_items: la pertenencia se resuelve por la comida padre ────────────
alter table public.meal_items enable row level security;

drop policy if exists meal_items_own on public.meal_items;
create policy meal_items_own on public.meal_items
  for all using (exists (
    select 1 from public.meals m
     where m.id = meal_items.meal_id and m.user_id = auth.uid()))
  with check (exists (
    select 1 from public.meals m
     where m.id = meal_items.meal_id and m.user_id = auth.uid()));

-- ── activity_types: los del sistema los lee cualquiera autenticado ────────
alter table public.activity_types enable row level security;

drop policy if exists activity_types_read on public.activity_types;
create policy activity_types_read on public.activity_types
  for select to authenticated using (is_system or user_id = auth.uid());

drop policy if exists activity_types_write_own on public.activity_types;
create policy activity_types_write_own on public.activity_types
  for insert to authenticated
  with check (user_id = auth.uid() and not is_system);

drop policy if exists activity_types_update_own on public.activity_types;
create policy activity_types_update_own on public.activity_types
  for update to authenticated
  using (user_id = auth.uid() and not is_system)
  with check (user_id = auth.uid() and not is_system);

drop policy if exists activity_types_no_hard_delete on public.activity_types;
create policy activity_types_no_hard_delete on public.activity_types
  for delete using (false);

-- ── foods_cache: lectura para autenticados, escritura solo service_role ───
alter table public.foods_cache enable row level security;

drop policy if exists foods_cache_read on public.foods_cache;
create policy foods_cache_read on public.foods_cache
  for select to authenticated using (true);
-- Sin policy de insert/update: solo las Edge Functions con service_role
-- escriben acá (el service_role saltea RLS por diseño).

-- ── audit_log: el usuario lee su log; nadie lo escribe desde el cliente ───
alter table public.audit_log enable row level security;

drop policy if exists audit_read_own on public.audit_log;
create policy audit_read_own on public.audit_log
  for select using (auth.uid() = user_id);

-- ── Fase 2: la pertenencia baja por la actividad y la rutina ──────────────
alter table public.strength_exercises enable row level security;

drop policy if exists strength_exercises_own on public.strength_exercises;
create policy strength_exercises_own on public.strength_exercises
  for all using (exists (
    select 1 from public.activities a
     where a.id = strength_exercises.activity_id and a.user_id = auth.uid()))
  with check (exists (
    select 1 from public.activities a
     where a.id = strength_exercises.activity_id and a.user_id = auth.uid()));

alter table public.strength_sets enable row level security;

drop policy if exists strength_sets_own on public.strength_sets;
create policy strength_sets_own on public.strength_sets
  for all using (exists (
    select 1
      from public.strength_exercises e
      join public.activities a on a.id = e.activity_id
     where e.id = strength_sets.strength_exercise_id and a.user_id = auth.uid()))
  with check (exists (
    select 1
      from public.strength_exercises e
      join public.activities a on a.id = e.activity_id
     where e.id = strength_sets.strength_exercise_id and a.user_id = auth.uid()));

alter table public.routine_exercises enable row level security;

drop policy if exists routine_exercises_own on public.routine_exercises;
create policy routine_exercises_own on public.routine_exercises
  for all using (exists (
    select 1 from public.workout_routines r
     where r.id = routine_exercises.routine_id and r.user_id = auth.uid()))
  with check (exists (
    select 1 from public.workout_routines r
     where r.id = routine_exercises.routine_id and r.user_id = auth.uid()));

-- down
-- (revertir RLS deja la base abierta: no se hace sin un plan explícito)
