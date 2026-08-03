-- 34 · Una comida no puede depender de una fila de auditoría para existir.
--
-- `meals.ai_analysis_id` tenía clave foránea a `ai_analyses`, y eso bloqueaba
-- la sincronización entera de una cuenta: quien carga sus comidas con IA tenía
-- **todas** sus comidas apuntando a análisis que del otro lado podían no estar,
-- así que el lote de `meals` se rechazaba completo, todas las veces, para
-- siempre. Y `meal_items` caía atrás, porque su policy pide que exista la
-- comida padre.
--
-- El error es de diseño y no de datos. `meals` es una tabla offline-first: la
-- escribe el teléfono, puede vivir semanas sin conexión y después sube.
-- `ai_analyses` es un registro de auditoría que escribe la Edge Function del
-- lado del servidor. Una FK entre las dos obliga a que el registro de auditoría
-- exista **antes** que el dato de la persona, y ese orden no está garantizado
-- por nada: la función puede haber fallado al insertar —ignora el error de
-- inserción a propósito para no tumbar el análisis—, el análisis puede haberse
-- hecho en una compilación sin servidor, o la comida puede venir de un
-- respaldo restaurado.
--
-- El vínculo es informativo: sirve para saber de qué análisis salió una comida.
-- Perderlo es barato. Perder las comidas de alguien no.
--
-- Se conserva la columna y se le saca la restricción. Los ids que quedan
-- apuntando a nada siguen sirviendo para rastrear, y los que apuntan a un
-- análisis real se pueden seguir cruzando con un join.

alter table public.meals
  drop constraint if exists meals_ai_analysis_fk;

-- Por si en algún proyecto quedó con el nombre que le pone Postgres por
-- omisión en vez del explícito.
alter table public.meals
  drop constraint if exists meals_ai_analysis_id_fkey;

-- El índice sí se conserva: sin la FK, el join por análisis sigue existiendo y
-- es lo único que hace que ese cruce no sea un scan.
create index if not exists meals_ai_analysis_idx
  on public.meals (ai_analysis_id)
  where ai_analysis_id is not null;

-- down
-- No se restaura la FK: volver a ponerla vuelve a romper la sincronización de
-- cualquier cuenta que cargue con IA, que es exactamente lo que esta migración
-- arregla.
