-- 01 · Extensiones y utilidades transversales.
--
-- Todas las migraciones son idempotentes y traen su `-- down` al pie
-- (07-data-model.md §7). Nunca se editan una vez aplicadas en prod.

create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgcrypto with schema extensions;
-- btree_gist habilita la restricción de exclusión de `goals` (uuid + daterange).
create extension if not exists btree_gist with schema extensions;
create extension if not exists pg_trgm with schema extensions;

-- pg_cron puede no estar habilitado en el plan free: los jobs de la migración
-- 16 se saltean solos si falta, y se programan desde el dashboard.
do $$
begin
  execute 'create extension if not exists pg_cron';
exception
  when others then
    raise notice 'pg_cron no disponible (%). Los jobs quedan sin programar.', sqlerrm;
end
$$;

-- `updated_at` lo mantiene un trigger en todas las tablas (§2 convenciones).
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- El borrado físico desde el cliente está prohibido: la app hace soft delete
-- con `deleted_at` (§5). El service_role sí puede purgar.
create or replace function public.guard_hard_delete()
returns trigger
language plpgsql
as $$
begin
  if current_setting('request.jwt.claim.role', true) is distinct from 'service_role'
     and auth.uid() is not null then
    raise exception 'El borrado físico no está permitido: usá deleted_at (soft delete).'
      using errcode = 'check_violation';
  end if;
  return old;
end;
$$;

-- down
-- drop function if exists public.guard_hard_delete();
-- drop function if exists public.set_updated_at();
