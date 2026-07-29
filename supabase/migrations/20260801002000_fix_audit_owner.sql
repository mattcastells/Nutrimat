-- 21 · Arreglo de `audit_changes`: cualquier update a `profiles` fallaba.
--
-- La migración 13 resuelve el dueño de la fila así:
--
--     case when tg_table_name = 'profiles' then new.id else new.user_id end
--
-- PL/pgSQL arma la expresión entera como una consulta y resuelve **todos** los
-- campos al planificarla, no solo los de la rama que se toma. Como `profiles`
-- no tiene `user_id`, el trigger revienta con "record new has no field
-- user_id" en cada update de esa tabla.
--
-- Nunca se notó porque la app guarda el perfil en el teléfono y no escribe esa
-- tabla; apareció al agregarle la columna `pal_code` a los perfiles que ya
-- existían.
--
-- La solución es sacar el campo por JSON, que se resuelve en tiempo de
-- ejecución y no exige que la columna exista en el tipo.

create or replace function public.audit_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  diff       jsonb := '{}'::jsonb;
  new_json   jsonb;
  old_json   jsonb;
  field      text;
  row_owner  uuid;
begin
  if tg_op = 'INSERT' then
    new_json := to_jsonb(new);
    row_owner := coalesce(new_json ->> 'user_id', new_json ->> 'id')::uuid;
    insert into public.audit_log (user_id, table_name, record_id, action, actor)
    values (row_owner, tg_table_name, new.id, 'insert',
            case when auth.uid() is null then 'system' else 'user' end);
    return new;
  end if;

  if tg_op = 'UPDATE' then
    new_json := to_jsonb(new);
    old_json := to_jsonb(old);

    for field in select jsonb_object_keys(new_json) loop
      -- `updated_at` cambia siempre: registrarlo sería ruido.
      if field <> 'updated_at'
         and new_json -> field is distinct from old_json -> field then
        diff := diff || jsonb_build_object(
          field,
          jsonb_build_object('from', old_json -> field, 'to', new_json -> field));
      end if;
    end loop;

    if diff <> '{}'::jsonb then
      row_owner := coalesce(new_json ->> 'user_id', new_json ->> 'id')::uuid;
      insert into public.audit_log (
        user_id, table_name, record_id, action, changed_fields, actor)
      values (row_owner, tg_table_name, new.id, 'update', diff,
              case when auth.uid() is null then 'system' else 'user' end);
    end if;
    return new;
  end if;

  return coalesce(new, old);
end;
$$;
