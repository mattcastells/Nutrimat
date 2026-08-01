-- 30 · `updated_at` deja de moverse cuando no cambió nada.
--
-- El trigger hacía `new.updated_at = now()` en **todo** UPDATE, sin mirar si la
-- fila había cambiado. Suena inofensivo y no lo es, porque el push no es un
-- diff: sube todas las filas del usuario en cada corrida. Así que cada push
-- reescribía idénticas cientos de filas y les dejaba `updated_at` = "hace un
-- segundo".
--
-- De ahí sale un problema que no se ve hasta que se sigue la cadena entera:
--
--   1. La app guarda una comida a las 13:30 → `updatedAt` local = 13:30.
--   2. Ocho segundos después corre el push y el trigger le pone al servidor
--      `updated_at` = 13:30:08.
--   3. En la próxima reconciliación, `_remoteIsNewer` compara 13:30:08 contra
--      13:30 y da que **el servidor es más nuevo**.
--   4. La copia del servidor reemplaza a la local. En **cada** comida, en
--      **cada** actividad, para siempre.
--
-- El comentario de `document_merge.dart` decía que ante un empate reemplazar
-- "no cambiaría nada salvo el riesgo de traerse una versión con menos campos".
-- Asumía empate; con este trigger el caso normal era que ganara el servidor, y
-- la versión con menos campos era la que volvía siempre.
--
-- Esto no se resuelve confiando en el reloj del cliente —que es justo lo que la
-- migración 23 quiso evitar—: el servidor sigue poniendo la hora en cada cambio
-- de verdad. Lo único que cambia es que una reescritura idéntica ya no cuenta
-- como cambio.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  -- La comparación excluye `updated_at`: el cliente la manda en el payload, así
  -- que sin sacarla toda fila se vería siempre distinta de sí misma y esto no
  -- serviría de nada.
  if tg_op = 'UPDATE'
     and to_jsonb(new) - 'updated_at' = to_jsonb(old) - 'updated_at'
  then
    new.updated_at = old.updated_at;
    return new;
  end if;

  new.updated_at = now();
  return new;
end;
$$;

-- down
-- create or replace function public.set_updated_at()
-- returns trigger language plpgsql as $$
-- begin new.updated_at = now(); return new; end $$;
