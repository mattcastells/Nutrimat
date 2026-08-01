-- 29 · El sueño también necesita lápida.
--
-- `sleep_logs` era la única tabla de contenido sin `deleted_at`, y del lado de
-- la app `deleteSleep` hacía `removeWhere`: la noche desaparecía del teléfono y
-- seguía viva en la tabla. Como las tablas son la fuente de verdad, la
-- reconciliación siguiente —como mucho 30 segundos después, al volver a la
-- app— la traía de vuelta. Borrar el sueño de una noche no funcionaba, y el
-- síntoma era que "vuelve solo".
--
-- No hace falta tocar el índice único `sleep_logs_one_per_day`: `logSleep`
-- reutiliza el id de la noche que ya existe, así que nunca hay dos filas para
-- el mismo día compitiendo por esa clave. La lápida se pone sobre la misma
-- fila, y volver a cargar esa noche la revive.
alter table public.sleep_logs
  add column if not exists deleted_at timestamptz;

-- La purga de los 30 días ya cubre las demás tablas de contenido; el sueño
-- quedaba afuera porque no tenía de dónde agarrarse.
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
end;
$$;

-- La migración 24 se lo sacó a `authenticated` y a `public`; recrear la función
-- devuelve el EXECUTE por omisión, así que hay que volver a revocarlo. Sin
-- esto, cualquier cuenta puede correr la purga de todo el proyecto.
revoke execute on function public.purge_soft_deleted() from public, anon, authenticated;

-- down
-- alter table public.sleep_logs drop column if exists deleted_at;
