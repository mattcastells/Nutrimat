-- El nombre visible deja de salir del correo.
--
-- `handle_new_user` caía en `split_part(email, '@', 1)` cuando el alta no traía
-- nombre. Eso convertía la parte del correo anterior a la arroba en el nombre
-- que ven los pals: alguien que se registró como `nombre.apellido@…` quedaba
-- expuesto ante cualquiera que le aceptara una solicitud, sin haberlo elegido
-- ni poder verlo desde la app.
--
-- Desde acá el nombre es lo que la persona escribió al crear la cuenta. Si no
-- hay ninguno, la fila queda en `null` y la app muestra "Sin nombre" hasta que
-- se cargue desde Perfil. Un placeholder honesto es mejor que un dato personal
-- filtrado por omisión.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Las cuentas ya creadas conservan lo que tengan: reescribirlas a ciegas le
-- borraría el nombre a quien sí lo puso. Para limpiar el que quedó del correo,
-- cada quien lo cambia desde Perfil → tu nombre.

-- down
-- create or replace function public.handle_new_user()
-- returns trigger language plpgsql security definer set search_path = public as $$
-- begin
--   insert into public.profiles (id, display_name)
--   values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name',
--                            split_part(new.email, '@', 1)))
--   on conflict (id) do nothing;
--   return new;
-- end;
-- $$;
