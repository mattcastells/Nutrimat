-- 43 · Sacar lo que no lee nadie.
--
-- Una auditoría de qué toca cada cliente —la app, las Edge Functions y el
-- panel— contra qué hay en el esquema. Lo que sigue no lo nombra ninguno de los
-- tres, y varias de estas cosas además **cuestan en cada sincronización**.
--
-- El criterio para borrar y no para conectar: en todos estos casos el dato o es
-- derivable de lo que ya está guardado, o es del dispositivo y no de la cuenta.
-- Donde el dato sí valía la pena, la migración 44 hace lo contrario —lo conecta
-- en vez de borrarlo—, que es el caso de los recordatorios y las plantillas.
--
-- Cada bloque dice qué se va y por qué. El `down` está al final: son objetos
-- vacíos, así que recrearlos no pierde nada, pero la reconstrucción exacta vive
-- en las migraciones 04, 05, 08, 11 y 16.

-- ── Dos RPC que nunca llamó nadie ────────────────────────────────────────
--
-- Quedaron del plan original (migración 15) y el producto tomó otro camino: la
-- comida se arma con un upsert de `meals` + `meal_items` desde el cliente, y el
-- resumen del día lo calcula el dominio en el teléfono, que es donde está el
-- objetivo vigente y el crédito por ejercicio.
--
-- `get_daily_summary` es la más cara de dejar: duplicaba, en SQL, una regla de
-- negocio que ya vive en Dart. Dos implementaciones de la misma cuenta es la
-- forma más segura de que un día dejen de coincidir, y nadie se entera porque
-- una de las dos no la ejecuta nadie. La migración 40 tuvo que actualizarla
-- solo para que siguiera compilando después de renombrar `rest_days`: eso es
-- exactamente el costo de mantener código muerto.
drop function if exists public.get_daily_summary(date);
drop function if exists public.create_meal_with_items(jsonb, jsonb);


-- ── Los "recientes" del servidor ─────────────────────────────────────────
--
-- `recent_foods` y `recent_activities` los llenan dos triggers en cada insert
-- de `meal_items` y de `activities`. **Nadie los lee nunca**: la app calcula
-- sus recientes con lo que tiene en el dispositivo, y el panel no los muestra.
--
-- No es solo peso muerto, es peso muerto caro: subir un año de historial son
-- miles de inserts, y cada uno dispara un trigger `security definer` con su
-- select y su upsert. Y lo que producen es derivable de `meals` y `activities`
-- con un `group by`, así que ni siquiera hay un dato que se pierda.
--
-- (`track_recent_food` además nunca escribió una fila: se va por
-- `coalesce(food_id, cache_food_id)` y el cliente no manda ninguna de las dos.
-- Ese trigger llevaba desde el día uno haciendo un select por ítem para no
-- guardar nada.)
drop trigger if exists meal_items_track_recent on public.meal_items;
drop trigger if exists activities_track_recent on public.activities;
drop function if exists public.track_recent_food();
drop function if exists public.track_recent_activity();
drop table if exists public.recent_foods;
drop table if exists public.recent_activities;

-- ── El espejo del catálogo externo ───────────────────────────────────────
--
-- `foods_cache` iba a guardar del lado del servidor lo que se trae de USDA y
-- Open Food Facts. El cliente lo cachea en su propio documento —que es donde
-- sirve, porque el punto del cache es buscar sin conexión— y nunca escribió
-- esta tabla. Un espejo de un catálogo público, por cuenta y en el servidor, no
-- le ahorra nada a nadie.
drop table if exists public.foods_cache cascade;
drop function if exists public.expire_food_cache();

-- ── Las dos claves foráneas de `meal_items` que siempre fueron null ──────
--
-- El ítem es un **snapshot** a propósito —lo dice el comentario de la migración
-- 05: "si el alimento de origen cambia después, la comida no muta"— y un
-- snapshot que además guarda un puntero al original es una contradicción: o el
-- número es el de ese día, o sigue al alimento.
--
-- En la práctica nunca hubo que elegir, porque el cliente no manda ninguna de
-- las dos y los ids de su catálogo (`usda:1750340`, `off:7790070410016`) ni
-- siquiera son uuid. Se van las dos columnas y con eso queda un solo modelo:
-- el ítem se explica solo.
alter table public.meal_items
  drop column if exists cache_food_id,
  drop column if exists food_id;

-- ── Las tres tablas de Health Connect ────────────────────────────────────
--
-- La integración existe y funciona, pero **todo lo suyo es del dispositivo**:
-- el permiso lo da un teléfono, el cursor de importación es de ese teléfono, y
-- la app guarda ese estado en su documento local. Una copia en el servidor no
-- estaría sin usar por olvido: estaría equivocada, porque diría que "la cuenta"
-- tiene Health Connect conectado cuando lo tiene un aparato.
--
-- Lo que sí queda del lado de la cuenta es el resultado de la importación —los
-- pesos y las actividades—, que ya viaja por las tablas de siempre.
drop table if exists public.duplicate_resolutions;
drop table if exists public.sync_records;
drop table if exists public.health_integrations;

-- ── Los jobs que quedaron sin función ────────────────────────────────────
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobname)
       from cron.job
      where jobname in ('expire_food_cache', 'trim_recents');
  end if;
end
$$;

drop function if exists public.trim_recents();

-- down
-- Todo lo de arriba está vacío en producción, así que volver atrás es recrear
-- las definiciones de las migraciones 04 (`foods_cache`), 05 (`meal_items`
-- `food_id`/`cache_food_id`, `track_recent_food`), 08 (`recent_activities`,
-- `track_recent_activity`), 11 (las tres de Health Connect), 15 (los dos RPC) y
-- 16 (`trim_recents`, `expire_food_cache` y sus jobs).
