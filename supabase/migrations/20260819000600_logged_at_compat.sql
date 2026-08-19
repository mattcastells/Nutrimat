-- 45 · Que el teléfono que todavía no actualizó siga sincronizando.
--
-- La migración 44 renombró `meals.logged_at` a `eaten_at`, y el nombre nuevo es
-- el correcto. Lo que estuvo mal fue **el orden**: la columna la escribe un
-- cliente ya desplegado, y renombrarla sin dejarle un camino deja a cada
-- teléfono con la versión anterior mandando una columna que no existe.
--
-- El daño no es teórico y tampoco es ruidoso, que es lo peor:
--
--   · al subir, el upsert de `meals` falla con 42703 y **solo** esa tabla —el
--     `try` por tabla contiene el resto—, así que peso, actividad, agua y sueño
--     siguen viajando y la app se ve sana;
--   · al bajar, las comidas vuelven sin `logged_at`, el parseo de cada una
--     falla y se saltea sola, así que llega una lista vacía;
--   · la reconciliación conserva lo local (`if (remoteRows.isEmpty) continue`),
--     así que **no se pierde nada** — pero nada nuevo llega al servidor.
--
-- Y el fallo no se ve: `SyncFailed` solo aparece entrando a Ajustes → Respaldo
-- en la nube. Es el mismo modo de falla que ya vació esta base una vez, y está
-- escrito en `auth_providers.dart`: "la app se veía perfecta mientras la base
-- quedaba vacía". La respuesta a eso no puede ser pedirle a la gente que
-- actualice antes de comer.
--
-- ── Lo que hace ─────────────────────────────────────────────────────────
--
-- `logged_at` vuelve como **espejo de solo compatibilidad**, mantenido por un
-- trigger. El nombre bueno sigue siendo `eaten_at` y es el único que usan el
-- panel y la app nueva; nadie tiene que volver a escribir `logged_at`.
--
--   cliente viejo  → manda `logged_at`     → el trigger llena `eaten_at`
--   cliente nuevo  → manda `eaten_at`      → el trigger llena `logged_at`
--   los dos leen su columna y ven lo mismo.
--
-- Sí, es una columna duplicada, que es justo lo que la migración 43 se dedicó a
-- sacar. La diferencia es que esta tiene fecha de vencimiento y está escrita:
-- se borra con la migración que la saque cuando no queden teléfonos por debajo
-- de la versión que estrena `eaten_at`. Eso se comprueba mirando qué
-- `versionCode` reporta la pantalla de Actualizaciones, no de memoria.

-- El default se va de `eaten_at`: es lo que permite distinguir "el cliente no
-- mandó nada" de "el cliente mandó una hora". Con `default now()`, un insert
-- del cliente viejo llegaba al trigger con `eaten_at` ya lleno con la hora de
-- la transacción, y la hora real de la comida —la que venía en `logged_at`— se
-- perdía en silencio.
--
-- El `not null` se queda: los triggers `before` corren **antes** de que se
-- comprueben las restricciones, así que la columna nunca llega vacía a la
-- validación.
alter table public.meals alter column eaten_at drop default;

alter table public.meals add column if not exists logged_at timestamptz;

comment on column public.meals.logged_at is
  'DEPRECADA. Espejo de eaten_at para los clientes anteriores a la v1.21. No '
  'escribir desde código nuevo: la mantiene el trigger meals_logged_at_compat. '
  'Se borra cuando no queden teléfonos con la versión vieja.';

create or replace function public.meals_logged_at_compat()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    -- Cliente viejo: mandó `logged_at` y no sabe que existe `eaten_at`.
    if new.eaten_at is null then
      -- El `coalesce` con `now()` es el piso: una fila sin ninguna de las dos
      -- horas —que no la manda ningún cliente conocido— entra con la de ahora
      -- en vez de romper contra el `not null`.
      new.eaten_at := coalesce(new.logged_at, now());
    end if;

  -- ⚠️ El `update` **no** se puede resolver mirando si `eaten_at` viene null,
  -- y acá es donde el primer intento de esta migración se equivocó.
  --
  -- El push de la app es un upsert que reescribe la fila entera, y PostgREST
  -- arma el `do update set` **solo con las columnas que mandó el cliente**. El
  -- cliente viejo no manda `eaten_at`, así que llega con el valor que ya tenía
  -- —nunca null— y una corrección de hora se descartaba en silencio: la fila
  -- quedaba con el nombre nuevo y la hora vieja.
  --
  -- Lo que distingue quién habla es **cuál de las dos se movió**.
  elsif new.logged_at is distinct from old.logged_at
        and new.eaten_at is not distinct from old.eaten_at then
    new.eaten_at := new.logged_at;
  end if;

  -- Y siempre, en los dos sentidos: el espejo sigue a la columna real. Sin esta
  -- línea el cliente viejo subiría bien y al bajar leería null.
  new.logged_at := new.eaten_at;
  return new;
end $$;

drop trigger if exists meals_logged_at_compat on public.meals;
create trigger meals_logged_at_compat
  before insert or update on public.meals
  for each row execute function public.meals_logged_at_compat();

-- Las filas que ya estaban: el trigger solo corre sobre lo que se escribe de
-- acá en adelante, así que el espejo arranca vacío para todo el historial y el
-- cliente viejo lo leería null.
update public.meals set logged_at = eaten_at where logged_at is null;

-- ── El permiso ──────────────────────────────────────────────────────────
--
-- `authenticated` ya tiene el grant sobre la tabla entera (migración 14), así
-- que una columna nueva queda alcanzada sin tocar nada. La política de care
-- tampoco cambia: se concede por fila, no por columna, y el panel no la pide.

-- down
-- drop trigger if exists meals_logged_at_compat on public.meals;
-- drop function if exists public.meals_logged_at_compat();
-- alter table public.meals drop column if exists logged_at;
-- alter table public.meals alter column eaten_at set default now();
