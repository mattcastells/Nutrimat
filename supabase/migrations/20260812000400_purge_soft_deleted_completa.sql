-- 38 · Devolver el purgado del sueño, que la migración 36 se llevó puesto.
--
-- `purge_soft_deleted` se redefinió tres veces: la 16 la creó, la 28 le agregó
-- `sleep_logs` cuando el sueño pasó a tener lápida, y la 36 —la de la purga de
-- `shared_days`— la reescribió **copiando el cuerpo de la 16**. `create or
-- replace` no mezcla: reemplaza. Así que la 36 revirtió en silencio lo que la
-- 28 había agregado y, desde que se aplicó, una noche borrada no se purgaba
-- nunca más.
--
-- Lo atrapó `sync_contract_test.sql`, que lo comprueba desde que existe:
-- "La purga se lleva una noche borrada hace más de 30 días" · have 1, want 0.
--
-- La lección, para la próxima vez que haya que tocar esta función: **el cuerpo
-- se saca de la definición vigente en la base, no del archivo de migración que
-- uno recuerda**. `pg_get_functiondef('public.purge_soft_deleted()'::regprocedure)`
-- lo dice en una línea.

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
  -- La que se había perdido. Va con las otras seis y no aparte, porque la
  -- ventana de deshacer es la misma para todo lo que lleva lápida.
  delete from public.sleep_logs
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.foods
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.exercise_templates
   where deleted_at is not null and deleted_at < now() - interval '30 days';

  -- La proyección de los pals no es un borrado suave: no tiene `deleted_at`
  -- ni lápida, porque no se borra un registro sino que se deja de publicar un
  -- día que ya nadie puede abrir.
  perform public.purge_shared_days();
end;
$$;

-- La migración 28 dejó escrito que recrear la función puede devolver el
-- EXECUTE por omisión, y tenía razón en preocuparse: la 36 creó
-- `purge_shared_days` sin revocar nada y quedó abierta a `anon`. Se revoca de
-- nuevo, que es barato y no depende de recordar cómo trata Postgres los ACL en
-- un `create or replace`.
revoke execute on function public.purge_soft_deleted() from public, anon, authenticated;
revoke execute on function public.purge_shared_days() from public, anon, authenticated;

-- down
-- Volver al cuerpo de la migración 28, sin el `perform`.
