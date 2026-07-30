-- 26 · Una estimación por texto no tiene foto, y eso era un NOT NULL.
--
-- `ai_analyses.photo_path` nació `not null` porque el único análisis era el de
-- una foto. Cuando se sumó `analyze-meal-text` la función quedó insertando sin
-- esa columna, y como supabase-js **no lanza** en el error de un insert —lo
-- devuelve en `{ error }` y ahí nadie lo miraba—, el insert fallaba en silencio
-- en cada estimación por texto.
--
-- Dos consecuencias, las dos invisibles hasta que alguien las buscara:
--
-- 1. Ninguna estimación por texto quedó registrada. Es la tabla contra la que
--    se miden las latencias y los fallos del prompt, así que la única forma de
--    saber si el circuito de texto anda era que alguien lo reportara — que es
--    exactamente cómo nos enteramos.
-- 2. La función devolvía un `id` de una fila que no existía, y la app lo guarda
--    en `meals.ai_analysis_id`. Al subir esa comida, la FK contra `ai_analyses`
--    la rechazaba: cualquier comida cargada por descripción **nunca llegaba a
--    las tablas**, con el push relacional entero fallando en ese registro.
--
-- Acá se arregla la causa (la columna) y se le pone un cinturón a la
-- consecuencia (la FK), porque una comida es el dato que importa y no puede
-- perderse por el registro de cómo se estimó.

alter table public.ai_analyses alter column photo_path drop not null;

-- Qué originó el análisis. Sirve para dos cosas: medir cada circuito por
-- separado y que "no tiene foto" sea un hecho declarado en vez de deducido de
-- un null. Las filas que ya existen son todas de foto.
alter table public.ai_analyses
  add column if not exists source text not null default 'photo';

alter table public.ai_analyses
  drop constraint if exists ai_analyses_source;
alter table public.ai_analyses
  add constraint ai_analyses_source check (source in ('photo', 'text'));

-- La mitad que sí tiene sentido exigir: un análisis de foto sin la ruta de la
-- foto no se puede reproducir ni auditar. Al de texto no se le pide nada.
alter table public.ai_analyses
  drop constraint if exists ai_analyses_photo_path_present;
alter table public.ai_analyses
  add constraint ai_analyses_photo_path_present
  check (source <> 'photo' or photo_path is not null);

-- ── create_meal_with_items ───────────────────────────────────────────────
-- Igual que la migración 15, con un solo cambio: el vínculo con el análisis se
-- guarda **solo si la fila existe**.
--
-- El registro de cómo se estimó una comida es un insumo para mejorar el
-- prompt; la comida es el dato de la persona. Que el primero falte no puede
-- ser el motivo de que el segundo no se guarde, y hasta ahora lo era.
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
  v_analysis uuid;
begin
  v_analysis := (p_meal ->> 'ai_analysis_id')::uuid;
  if v_analysis is not null
     and not exists (select 1 from public.ai_analyses where id = v_analysis)
  then
    v_analysis := null;
  end if;

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
    v_analysis,
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

-- down
-- alter table public.ai_analyses drop constraint if exists ai_analyses_photo_path_present;
-- alter table public.ai_analyses drop constraint if exists ai_analyses_source;
-- alter table public.ai_analyses drop column if exists source;
-- alter table public.ai_analyses alter column photo_path set not null;
