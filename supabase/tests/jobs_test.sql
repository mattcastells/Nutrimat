-- Los jobs de mantenimiento borran, y por eso se prueban.
--
-- Una purga mal escrita no se nota: no falla, no avisa, y lo que se lleva de
-- más no vuelve. Acá se comprueban las dos mitades de la única regla que
-- tiene: que se vaya lo que ya nadie puede ver, y que **no** se vaya lo que
-- todavía se mira.
--
-- Correr con:  supabase test db

create extension if not exists pgtap with schema extensions;

begin;
select plan(6);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'jobs-a@nutrimat.test', crypt('secreto-a', gen_salt('bf')),
   now(), now(), now());

-- ── shared_days ──────────────────────────────────────────────────────────
-- Cuatro días: hoy, el borde de la ventana que ve un pal, uno viejo y uno
-- muy viejo.
insert into public.shared_days (user_id, local_date, meals, activity_minutes)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date, '[]'::jsonb, 0),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   current_date - 7, '[]'::jsonb, 0),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   current_date - 40, '[]'::jsonb, 0),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   current_date - 400, '[]'::jsonb, 0);

select is(
  (select count(*)::int from public.shared_days
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  4,
  'arrancan las cuatro filas'
);

select lives_ok(
  'select public.purge_shared_days()',
  'la purga corre sin romper nada'
);

select is(
  (select count(*)::int from public.shared_days
    where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  2,
  'se van las dos viejas y quedan las dos de la ventana'
);

-- El día de hoy es el que se está mirando ahora mismo: que sobreviva no es un
-- detalle, es la diferencia entre limpiar y romper.
select isnt_empty(
  $$select 1 from public.shared_days
     where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
       and local_date = current_date$$,
  'el día de hoy sigue estando'
);

-- El borde exacto de lo que la app deja abrir. Si se fuera acá, un pal vería
-- "no cargó nada" en un día que sí tenía cosas.
select isnt_empty(
  $$select 1 from public.shared_days
     where user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
       and local_date = current_date - 7$$,
  'el día más viejo que se puede mirar sigue estando'
);

-- Y que esté colgada del job nocturno, no suelta esperando que alguien la
-- llame: una función de limpieza que no está programada es una función que no
-- limpia.
select is(
  (select count(*)::int
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'purge_soft_deleted'
      and pg_get_functiondef(p.oid) like '%purge_shared_days%'),
  1,
  'la purga nocturna la invoca'
);

select * from finish();
rollback;
