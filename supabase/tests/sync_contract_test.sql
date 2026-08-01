-- El contrato entre el push de la app y las tablas (migraciones 29 y 30).
--
-- Dos cosas que no se ven mirando una fila sola y que decidían qué versión de
-- un dato sobrevivía:
--
-- 1. `updated_at` es lo que desempata la reconciliación. El trigger la movía en
--    **todo** UPDATE, y como el push reescribe todas las filas en cada corrida
--    —no es un diff—, el servidor quedaba siempre "más nuevo" que el teléfono y
--    su copia reemplazaba a la local en cada vuelta.
-- 2. El sueño no tenía lápida, así que borrar una noche no llegaba nunca al
--    servidor y la reconciliación la devolvía.
--
-- Correr con:  supabase test db

create extension if not exists pgtap with schema extensions;

begin;
select plan(7);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values ('77777777-7777-7777-7777-777777777777',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'g@nutrimat.test', crypt('secreto-g', gen_salt('bf')), now(), now(), now());

insert into public.meals (id, user_id, slot, local_date, source, name)
values ('eeee0001-0000-4000-8000-000000000001',
        '77777777-7777-7777-7777-777777777777', 'lunch', current_date,
        'manual', 'Milanesa');

-- Se retrasa a mano para que un bump se note: `now()` dentro de una
-- transacción devuelve siempre el mismo valor, así que sin envejecer la fila
-- primero el test pasaría por el motivo equivocado.
--
-- Y hay que apagar el trigger para lograrlo, lo cual dice algo bueno de él: una
-- sentencia que **solo** toca `updated_at` no cambia nada, así que la deja como
-- estaba. Eso es justamente lo que impide que un teléfono con el reloj corrido
-- se declare más nuevo sin haber cambiado un dato.
alter table public.meals disable trigger meals_set_updated_at;
update public.meals set updated_at = now() - interval '1 hour'
 where id = 'eeee0001-0000-4000-8000-000000000001';
alter table public.meals enable trigger meals_set_updated_at;

create temporary table antes on commit drop as
  select updated_at from public.meals
   where id = 'eeee0001-0000-4000-8000-000000000001';

-- ── Reescribir una fila idéntica no la vuelve más nueva ──────────────────
-- Es exactamente lo que hace el push con las cientos de filas que no cambiaron.
update public.meals
   set name = 'Milanesa', slot = 'lunch', updated_at = now()
 where id = 'eeee0001-0000-4000-8000-000000000001';

select is(
  (select updated_at from public.meals
    where id = 'eeee0001-0000-4000-8000-000000000001'),
  (select updated_at from antes),
  'Un push que reescribe la misma fila no la vuelve más nueva'
);

-- ── Un cambio de verdad sí ───────────────────────────────────────────────
update public.meals set name = 'Milanesa con puré'
 where id = 'eeee0001-0000-4000-8000-000000000001';

select ok(
  (select updated_at from public.meals
    where id = 'eeee0001-0000-4000-8000-000000000001')
  > (select updated_at from antes),
  'Un cambio de verdad sí mueve updated_at'
);

-- Y la pone el servidor, no el cliente: mandar una fecha vieja junto con un
-- cambio real no puede hacer que ese cambio parezca viejo.
update public.meals
   set name = 'Milanesa napolitana', updated_at = now() - interval '10 days'
 where id = 'eeee0001-0000-4000-8000-000000000001';

select ok(
  (select updated_at from public.meals
    where id = 'eeee0001-0000-4000-8000-000000000001')
  > now() - interval '1 minute',
  'La hora de un cambio la pone el servidor, no el reloj del teléfono'
);

-- Ni siquiera puede envejecerse sola: sin un cambio de datos que la acompañe,
-- la fecha que mande el cliente se descarta.
update public.meals set updated_at = now() - interval '10 days'
 where id = 'eeee0001-0000-4000-8000-000000000001';

select ok(
  (select updated_at from public.meals
    where id = 'eeee0001-0000-4000-8000-000000000001')
  > now() - interval '1 minute',
  'Un cliente no puede retrodatar una fila sin cambiarle nada'
);

-- ── El sueño tiene lápida ────────────────────────────────────────────────
select has_column(
  'public', 'sleep_logs', 'deleted_at',
  'sleep_logs puede llevar lápida'
);

insert into public.sleep_logs (id, user_id, local_date, minutes, quality, deleted_at)
values
  ('eeee0002-0000-4000-8000-000000000002',
   '77777777-7777-7777-7777-777777777777', current_date - 40, 420, 'good',
   now() - interval '31 days'),
  ('eeee0003-0000-4000-8000-000000000003',
   '77777777-7777-7777-7777-777777777777', current_date - 2, 400, 'ok',
   now() - interval '2 days');

select public.purge_soft_deleted();

select is(
  (select count(*)::int from public.sleep_logs
    where id = 'eeee0002-0000-4000-8000-000000000002'),
  0,
  'La purga se lleva una noche borrada hace más de 30 días'
);

select is(
  (select count(*)::int from public.sleep_logs
    where id = 'eeee0003-0000-4000-8000-000000000003'),
  1,
  'Y deja la que se borró hace dos: la ventana de deshacer es de 30 días'
);

select * from finish();
rollback;
