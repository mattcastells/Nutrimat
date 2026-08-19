-- 40 · El contexto del día: enfermedad, descanso y alcohol.
--
-- Dos features nuevas que el modelo tenía que absorber sin convertirse en un
-- fichero de tablas de una columna. La decisión larga está en
-- `docs/contexto-diario.md`; acá va lo que hace falta para leer el
-- SQL.
--
-- ── Por qué `day_markers` y no `sick_days` ───────────────────────────────
--
-- Un día enfermo y un día de descanso son **la misma forma**: una fecha que
-- queda calificada, sin magnitud que medir. Ya había una tabla para el segundo
-- caso —`rest_days`, de la migración 09— con exactamente estas columnas:
-- `(user_id, local_date, note)` y un único por día. Crear `sick_days` al lado
-- habría sido copiarla entera para cambiarle el nombre, y la siguiente
-- etiqueta —vacaciones, viaje, menstruación— habría pedido una tercera.
--
-- Así que `rest_days` **se generaliza**: se le agrega un discriminador y pasa a
-- ser `day_markers`. Sumar una etiqueta es agregar un valor al check, no una
-- tabla.
--
-- Y de paso se cierra algo que estaba roto sin que se notara: `rest_days`
-- **nunca se sincronizó**. La app guarda los días de descanso en un `Set` del
-- documento local (`LocalStore.restDays`) y el cliente relacional no la nombra,
-- así que la tabla está vacía en producción y un día de descanso marcado en un
-- teléfono no existía en el siguiente. Lo que de verdad lo cierra es que ahora
-- la app la escribe.
--
-- ── Por qué el alcohol **no** entra en `day_markers` ─────────────────────
--
-- Porque no es una etiqueta: tiene magnitud. Un consumo se parece a una
-- actividad —puede haber varios en el mismo día, cada uno con su cantidad y sus
-- calorías— y lo que se le pregunta es "cuánto", no "sí o no". Meterlo en la
-- tabla de marcas obligaría a un `jsonb` con la cantidad adentro, y con eso se
-- pierden los `check` que en este esquema tienen todas las escalas
-- (`sleep_logs_quality_valid`, `body_measurements_range`) y "cuántos tragos por
-- semana" pasa a ser un cast.

-- ── Las marcas del día ───────────────────────────────────────────────────
alter table public.rest_days rename to day_markers;

alter table public.day_markers
  add column if not exists kind       text not null default 'rest',
  add column if not exists severity   smallint,
  add column if not exists tags       text[] not null default '{}',
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

-- Lo que había eran días de descanso: es el default de la columna, así que las
-- filas viejas ya quedaron bien. El default se saca ahora para que de acá en
-- adelante haya que decir de cuál se trata.
alter table public.day_markers alter column kind drop default;

alter table public.day_markers
  drop constraint if exists day_markers_kind;
alter table public.day_markers
  add constraint day_markers_kind check (kind in ('rest', 'sick'));

-- 1 a 3, y solo para 'sick'. Tres niveles y no diez por lo mismo que el sueño
-- tiene cinco: nadie distingue un 6 de un 7 de su propio malestar, y una escala
-- falsamente precisa invita a leer tendencias que no existen.
alter table public.day_markers
  drop constraint if exists day_markers_severity;
alter table public.day_markers
  add constraint day_markers_severity check (
    severity is null or (kind = 'sick' and severity between 1 and 3));

-- Los síntomas del futuro entran acá sin tocar el esquema. Con techo, como
-- `profiles.dietary_flags`: una columna sin límite es una invitación.
alter table public.day_markers
  drop constraint if exists day_markers_tags_len;
alter table public.day_markers
  add constraint day_markers_tags_len check (
    array_length(tags, 1) is null or array_length(tags, 1) <= 16);

alter table public.day_markers
  drop constraint if exists day_markers_note_len;
alter table public.day_markers
  add constraint day_markers_note_len check (
    note is null or char_length(note) <= 500);

-- El único pasa a ser por tipo: el mismo día puede ser de descanso **y** de
-- enfermedad, que es justamente el caso que la nutricionista quiere ver.
alter table public.day_markers
  drop constraint if exists rest_days_uniq;
drop index if exists public.day_markers_uniq;
create unique index day_markers_uniq
  on public.day_markers (user_id, local_date, kind)
  where deleted_at is null;

create index if not exists day_markers_user_date_idx
  on public.day_markers (user_id, local_date desc)
  where deleted_at is null;

-- ── El alcohol ───────────────────────────────────────────────────────────
--
-- Una fila por consumo y no una por día: "dos copas de vino y una cerveza" es
-- un sábado normal, y un solo renglón por día obliga a elegir cuál de los dos
-- tipos se guarda. Agrupar por día después es una línea; separar lo que se
-- guardó junto no se puede.
--
-- `std_drinks` es la unidad de bebida estándar de 10 g de etanol —la que usa el
-- Ministerio de Salud, no los 14 g de EE.UU.— y es lo único con lo que se
-- pueden sumar una cerveza y un whisky. La calcula la app a partir del volumen
-- y la graduación, igual que `activities.estimated_calories` calcula el gasto:
-- la fórmula vive en el dominio, donde se puede probar, y la base guarda el
-- resultado.
create table if not exists public.alcohol_logs (
  id          uuid        primary key default extensions.gen_random_uuid(),
  user_id     uuid        not null
                references public.profiles (id) on delete cascade,
  local_date  date        not null,
  drink_type  text        not null,

  -- Cuántas unidades de esa bebida: 2 copas, 1 lata. Con decimal porque media
  -- copa existe.
  quantity    numeric(5,2) not null default 1,

  -- Lo que define una unidad. Vienen del preset elegido y quedan guardados en
  -- la fila: si mañana se corrige el preset de "chopp", el sábado pasado sigue
  -- siendo lo que se tomó.
  volume_ml   integer     not null,
  abv_pct     numeric(4,1) not null,

  std_drinks  numeric(5,2) not null,

  -- Las calorías del alcohol. Separadas de `meals` a propósito: no se cargan
  -- como comida, y sumarlas ahí escondería de dónde salieron.
  kcal        integer     not null default 0,

  note        text,
  logged_at   timestamptz not null default now(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,

  constraint alcohol_logs_type check (drink_type in (
    'beer', 'wine', 'spirits', 'cocktail', 'cider', 'other')),
  -- 30 unidades de una bebida en un día es un error de tipeo, no una noche.
  constraint alcohol_logs_quantity check (quantity > 0 and quantity <= 30),
  constraint alcohol_logs_volume check (volume_ml between 10 and 2000),
  constraint alcohol_logs_abv check (abv_pct >= 0 and abv_pct <= 96),
  constraint alcohol_logs_std check (std_drinks >= 0 and std_drinks <= 100),
  constraint alcohol_logs_kcal check (kcal >= 0 and kcal <= 5000),
  constraint alcohol_logs_note_len check (
    note is null or char_length(note) <= 500)
);

create index if not exists alcohol_logs_user_date_idx
  on public.alcohol_logs (user_id, local_date desc)
  where deleted_at is null;

-- ── RLS ──────────────────────────────────────────────────────────────────
--
-- RLS sin GRANT no hace nada útil: `authenticated` recibe *permission denied* y
-- las políticas ni se evalúan. Van juntos, como en las migraciones 14 y 23.
alter table public.day_markers  enable row level security;
alter table public.alcohol_logs enable row level security;

grant select, insert, update, delete
  on public.day_markers, public.alcohol_logs
  to authenticated;

-- Las cuatro políticas que le puso el helper de la migración 14 cuando la tabla
-- se llamaba `rest_days`. **Renombrar la tabla no renombra sus políticas**, así
-- que siguen ahí con el nombre viejo: dicen lo mismo que la de abajo, pero
-- dejarlas es dejar cuatro reglas con el nombre de una tabla que ya no existe,
-- y la próxima persona que audite esto va a buscar `rest_days` y no la va a
-- encontrar.
drop policy if exists rest_days_select_own on public.day_markers;
drop policy if exists rest_days_insert_own on public.day_markers;
drop policy if exists rest_days_update_own on public.day_markers;
drop policy if exists rest_days_delete_own on public.day_markers;
drop policy if exists rest_days_own on public.day_markers;
drop policy if exists day_markers_own on public.day_markers;
create policy day_markers_own on public.day_markers
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists alcohol_logs_own on public.alcohol_logs;
create policy alcohol_logs_own on public.alcohol_logs
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- `updated_at` lo mantiene la base y no el cliente: un reloj mal puesto en el
-- teléfono rompería la resolución de conflictos por fecha.
drop trigger if exists day_markers_set_updated_at on public.day_markers;
create trigger day_markers_set_updated_at
  before update on public.day_markers
  for each row execute function public.set_updated_at();

drop trigger if exists alcohol_logs_set_updated_at on public.alcohol_logs;
create trigger alcohol_logs_set_updated_at
  before update on public.alcohol_logs
  for each row execute function public.set_updated_at();

-- ── La purga ─────────────────────────────────────────────────────────────
--
-- Las dos tablas nuevas llevan lápida, así que entran en la ventana de 30 días
-- como todo el resto.
--
-- El cuerpo sale de la definición vigente (migración 38), no de memoria:
-- `create or replace` reemplaza, no mezcla, y así fue como la 36 revirtió en
-- silencio lo que la 28 había agregado.
create or replace function public.purge_soft_deleted()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.meals
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.activities
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.weight_logs
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.body_measurements
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.sleep_logs
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.foods
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.exercise_templates
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.day_markers
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.alcohol_logs
   where deleted_at is not null and deleted_at < now() - interval '30 days';

  perform public.purge_shared_days();
end;
$$;

revoke execute on function public.purge_soft_deleted() from public, anon, authenticated;

-- ── El RPC que nombraba la tabla vieja ───────────────────────────────────
--
-- `get_daily_summary` no lo llama la app —el resumen del día lo arma el dominio
-- en el teléfono— pero quedó del plan original y referencia `rest_days` por
-- nombre. Se actualiza para que siga compilando en vez de dejar una función que
-- revienta al primer llamado, y de paso devuelve también el día de enfermedad.
create or replace function public.get_daily_summary(p_date date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_goal record;
  v_consumed integer; v_protein numeric; v_carbs numeric; v_fat numeric;
  v_estimated integer; v_applied integer; v_minutes integer;
  v_sessions integer; v_steps integer;
  v_is_rest boolean; v_is_sick boolean; v_weight numeric;
  v_credit integer; v_credit_enabled boolean;
begin
  select exercise_credit_percentage, exercise_credit_enabled
    into v_credit, v_credit_enabled
    from public.profiles where id = v_user;

  select * into v_goal
    from public.goals
   where user_id = v_user and starts_on <= p_date
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
    select 1 from public.day_markers
     where user_id = v_user and local_date = p_date
       and kind = 'rest' and deleted_at is null) into v_is_rest;

  select exists (
    select 1 from public.day_markers
     where user_id = v_user and local_date = p_date
       and kind = 'sick' and deleted_at is null) into v_is_sick;

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
    'is_rest_day',           v_is_rest,
    'is_sick_day',           v_is_sick,
    'weight_kg',             v_weight);
end;
$$;

-- down
-- drop table if exists public.alcohol_logs;
-- alter table public.day_markers rename to rest_days;
-- alter table public.rest_days
--   drop column if exists kind, drop column if exists severity,
--   drop column if exists tags, drop column if exists updated_at,
--   drop column if exists deleted_at;
