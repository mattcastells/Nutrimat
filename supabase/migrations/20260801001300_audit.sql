-- 13 · audit_log (07-data-model.md §6).
--
-- Solo en las tres tablas donde importa saber quién cambió qué: override de
-- calorías, cambio de objetivo y cambio de crédito de ejercicio.

create table if not exists public.audit_log (
  id             uuid        primary key default extensions.gen_random_uuid(),
  user_id        uuid        references public.profiles (id) on delete cascade,
  table_name     text        not null,
  record_id      uuid        not null,
  action         text        not null,
  changed_fields jsonb,
  actor          text        not null default 'user',
  created_at     timestamptz not null default now(),

  constraint audit_log_action check (action in ('insert', 'update', 'delete')),
  constraint audit_log_actor check (actor in ('user', 'sync', 'system'))
);

create index if not exists audit_log_user_idx
  on public.audit_log (user_id, created_at desc);
create index if not exists audit_log_record_idx
  on public.audit_log (table_name, record_id);

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
    row_owner := case when tg_table_name = 'profiles' then new.id else new.user_id end;
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
      row_owner := case when tg_table_name = 'profiles' then new.id else new.user_id end;
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

drop trigger if exists activities_audit on public.activities;
create trigger activities_audit
  after insert or update on public.activities
  for each row execute function public.audit_changes();

drop trigger if exists goals_audit on public.goals;
create trigger goals_audit
  after insert or update on public.goals
  for each row execute function public.audit_changes();

drop trigger if exists profiles_audit on public.profiles;
create trigger profiles_audit
  after update on public.profiles
  for each row execute function public.audit_changes();

-- down
-- drop table if exists public.audit_log;
-- drop function if exists public.audit_changes();
