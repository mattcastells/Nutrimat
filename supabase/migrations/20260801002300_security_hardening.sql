-- 24 · Hardening de seguridad: privilegios mínimos + límite de uso.
--
-- Dos cosas encontradas en una auditoría, ninguna explotada, las dos baratas
-- de cerrar:
--
-- 1. El GRANT genérico de la migración 14 (`grant execute on all functions
--    in schema public to authenticated`, más su `alter default privileges`
--    para funciones futuras) también le dio a `authenticated` permiso de
--    ejecutar los jobs de mantenimiento de la migración 16
--    (`purge_soft_deleted`, `expire_food_cache`, `trim_recents`,
--    `purge_audit_log`), pensados solo para `pg_cron`. Revocarlo no rompe los
--    jobs: `cron.schedule` corre como el dueño de la base, no como
--    `authenticated`.
--
-- 2. No había ninguna primitiva atómica de límite de uso. El chequeo de cuota
--    de IA (`analyze-meal-text`/`analyze-meal-photo`) contaba filas y recién
--    después insertaba, sin atomicidad: dos pedidos en paralelo podían pasar
--    el chequeo juntos. Y `food-search` no tenía cuota alguna.

-- ── Privilegios mínimos en los jobs de mantenimiento ──────────────────────
revoke execute on function public.purge_soft_deleted() from public, authenticated;
revoke execute on function public.expire_food_cache() from public, authenticated;
revoke execute on function public.trim_recents() from public, authenticated;
revoke execute on function public.purge_audit_log() from public, authenticated;

-- ── Límite de uso, atómico y reutilizable ─────────────────────────────────
-- Un contador por usuario/bucket/día. Nadie lo lee ni lo escribe directo —RLS
-- sin políticas lo cierra del todo—; solo `check_rate_limit`, que es
-- `security definer`, lo toca.
create table public.rate_limits (
  user_id uuid not null references public.profiles(id) on delete cascade,
  bucket  text not null,
  day     date not null default current_date,
  count   integer not null default 0,
  primary key (user_id, bucket, day)
);

alter table public.rate_limits enable row level security;

-- Sube el contador del día y devuelve si sigue dentro del límite. El
-- `insert ... on conflict ... do update ... returning` es una sola sentencia:
-- dos llamadas en paralelo no pueden leer el mismo conteo viejo, que es
-- justamente lo que fallaba en el chequeo manual de la cuota de IA.
create or replace function public.check_rate_limit(p_bucket text, p_max integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_count integer;
begin
  insert into public.rate_limits (user_id, bucket, day, count)
  values (auth.uid(), p_bucket, current_date, 1)
  on conflict (user_id, bucket, day)
    do update set count = rate_limits.count + 1
  returning count into current_count;

  return current_count <= p_max;
end;
$$;

grant execute on function public.check_rate_limit(text, integer) to authenticated;

-- Defensa en profundidad: 20 solicitudes de pal por día alcanzan de sobra
-- para uso real y frenan un script que martille el RPC. El código en sí ya
-- tiene un espacio enorme (31⁸) y no dice nada de su dueño; esto es aparte.
create or replace function public.request_pal(p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  target uuid;
begin
  if not public.check_rate_limit('pal_request', 20) then
    return 'rate_limited';
  end if;

  select id into target from public.profiles
   where pal_code = upper(trim(p_code));

  if target is null then return 'not_found'; end if;
  if target = auth.uid() then return 'self'; end if;

  if exists (
    select 1 from public.pals
     where (requester_id = auth.uid() and addressee_id = target)
        or (addressee_id = auth.uid() and requester_id = target)
  ) then
    return 'already';
  end if;

  insert into public.pals (requester_id, addressee_id)
  values (auth.uid(), target);

  return 'sent';
end $$;

-- down
-- drop function if exists public.request_pal(text);
-- drop function if exists public.check_rate_limit(text, integer);
-- drop table if exists public.rate_limits;
-- grant execute on function public.purge_soft_deleted() to authenticated;
-- grant execute on function public.expire_food_cache() to authenticated;
-- grant execute on function public.trim_recents() to authenticated;
-- grant execute on function public.purge_audit_log() to authenticated;
