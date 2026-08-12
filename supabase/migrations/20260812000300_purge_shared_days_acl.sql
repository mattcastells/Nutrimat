-- 37 · La purga que quedó abierta para cualquiera.
--
-- La migración anterior creó `purge_shared_days()` y se olvidó de la mitad que
-- importa. Una función nueva nace con `execute` para `public`, así que quedó
-- **ejecutable por cualquier cuenta con sesión, y hasta por `anon`** — y es
-- `security definer`, o sea que corre con los privilegios de su dueño y no le
-- aplica RLS. Cualquiera podía llamarla y borrarle los días compartidos a todo
-- el mundo.
--
-- Los otros cuatro jobs de mantenimiento están cerrados desde la migración 23
-- exactamente por esto, y ahí se revoca uno por uno: una función agregada
-- después no hereda nada. Comprobado contra la base real —
-- `has_function_privilege('authenticated', ..., 'EXECUTE')` daba `true`— antes
-- de escribir esta línea.
--
-- Los jobs los corre pg_cron, que no pasa por estos roles.

revoke execute on function public.purge_shared_days() from public, anon, authenticated;

-- `purge_soft_deleted` no hace falta revocarla otra vez: `create or replace`
-- conserva los permisos de la función que reemplaza, y se verificó que sigue
-- cerrada. Se deja dicho para que nadie lo asuma al revés la próxima vez.

-- down
-- grant execute on function public.purge_shared_days() to public;
