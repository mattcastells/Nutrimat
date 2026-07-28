-- 16 · Jobs de mantenimiento (08-supabase-plan.md §7).
--
-- Si pg_cron no está habilitado en el proyecto, las funciones quedan creadas
-- igual y se pueden invocar a mano o programar desde el dashboard.

-- Purga definitiva de lo borrado hace más de 30 días (07-data-model.md §5).
create or replace function public.purge_soft_deleted()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.meals
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.activities
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.weight_logs
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.body_measurements
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.foods
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.exercise_templates
   where deleted_at is not null and deleted_at < now() - interval '30 days';
end;
$$;

-- Cache de catálogos externos vencida.
create or replace function public.expire_food_cache()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.foods_cache where expires_at < now();
end;
$$;

-- Deja las 50 entradas más recientes por usuario.
create or replace function public.trim_recents()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.recent_foods rf
   where rf.ctid not in (
     select ctid from (
       select ctid,
              row_number() over (
                partition by user_id order by last_used_at desc) as rn
         from public.recent_foods
     ) ranked
      where rn <= 50);

  delete from public.recent_activities ra
   where ra.ctid not in (
     select ctid from (
       select ctid,
              row_number() over (
                partition by user_id order by last_used_at desc) as rn
         from public.recent_activities
     ) ranked
      where rn <= 50);
end;
$$;

create or replace function public.purge_audit_log()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.audit_log where created_at < now() - interval '180 days';
end;
$$;

-- Programación. Se saltea sola si pg_cron no está disponible.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobname)
       from cron.job
      where jobname in ('purge_soft_deleted', 'expire_food_cache',
                        'trim_recents', 'purge_audit_log');

    perform cron.schedule('purge_soft_deleted', '0 3 * * *',
                          'select public.purge_soft_deleted()');
    perform cron.schedule('expire_food_cache', '0 4 * * 0',
                          'select public.expire_food_cache()');
    perform cron.schedule('trim_recents', '30 4 * * 0',
                          'select public.trim_recents()');
    perform cron.schedule('purge_audit_log', '0 5 1 * *',
                          'select public.purge_audit_log()');
  else
    raise notice 'pg_cron no está habilitado: programá los jobs desde el dashboard.';
  end if;
end
$$;

-- down
-- select cron.unschedule('purge_soft_deleted');
-- drop function if exists public.purge_audit_log();
-- drop function if exists public.trim_recents();
-- drop function if exists public.expire_food_cache();
-- drop function if exists public.purge_soft_deleted();
