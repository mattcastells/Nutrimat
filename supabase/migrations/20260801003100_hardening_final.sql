-- 32 · Los tres que quedaron de la auditoría del lado del servidor.
--
-- Ninguno es una brecha abierta: son bordes que se pueden empujar. Van juntos
-- porque los tres son la misma idea —no dejar que el cliente decida cuánto
-- espacio ocupa ni qué se ejecuta— y porque los tres son baratos.

-- ── 1 · `rate_limits` no puede crecer para siempre ───────────────────────
-- La tabla lleva una fila por usuario, bucket y día, y **nada la limpiaba**:
-- los cuatro jobs de mantenimiento no la mencionan. Con uso normal eso ya crece
-- sin techo; y como `check_rate_limit` acepta cualquier texto como bucket, una
-- cuenta cualquiera podía llamar `check_rate_limit('x' || n, 1)` en bucle y
-- crear filas ilimitadas en el día. En plan Free, con 2 GB, es de los pocos
-- "para siempre" que quedaban en el esquema.
--
-- La allowlist acopla esta migración a los nombres que usan las funciones, y
-- eso está bien: agregar una cuota nueva **debería** pasar por una migración,
-- que es donde se ve. Los tres de acá salen de `supabase/functions/*/index.ts`
-- (`ai_analysis`, `food_search`) y de `request_pal` (`pal_request`).
create or replace function public.check_rate_limit(p_bucket text, p_max integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_count integer;
begin
  if p_bucket not in ('ai_analysis', 'food_search', 'pal_request') then
    raise exception 'Bucket de cuota desconocido: %', p_bucket
      using errcode = 'check_violation';
  end if;

  insert into public.rate_limits (user_id, bucket, day, count)
  values (auth.uid(), p_bucket, current_date, 1)
  on conflict (user_id, bucket, day)
    do update set count = rate_limits.count + 1
  returning count into current_count;

  return current_count <= p_max;
end;
$$;

grant execute on function public.check_rate_limit(text, integer) to authenticated;

-- Y se barren las de más de una semana. La cuota es diaria: una fila de hace
-- ocho días no responde ninguna pregunta.
create or replace function public.purge_rate_limits()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.rate_limits where day < current_date - 7;
end;
$$;

revoke execute on function public.purge_rate_limits() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobname)
       from cron.job where jobname = 'purge_rate_limits';
    perform cron.schedule('purge_rate_limits', '15 3 * * *',
                          'select public.purge_rate_limits()');
  else
    raise notice 'pg_cron no está habilitado: programá purge_rate_limits desde el dashboard.';
  end if;
end
$$;

-- ── 2 · Un nombre largo no puede tumbar el alta ──────────────────────────
-- `handle_new_user` insertaba el `display_name` de la metadata sin truncar,
-- contra un `check` de 80 caracteres. La excepción sale del trigger y aborta el
-- insert en `auth.users`: el registro falla entero con "Database error saving
-- new user", que no dice nada y no se puede arreglar del lado de quien se
-- registra. La API de signup acepta metadata arbitraria, así que no alcanza con
-- que la pantalla valide.
--
-- Se trunca en vez de rechazar: perder unas letras de un nombre visible es
-- infinitamente mejor que no poder crear la cuenta.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    left(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), 80)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- ── 3 · `anon` deja de poder ejecutar funciones ──────────────────────────
-- Postgres le da EXECUTE a PUBLIC por omisión en cada función nueva, y PUBLIC
-- incluye a `anon`. Hoy todas fallan seguro —`auth.uid()` es NULL sin sesión, y
-- de ahí no pasan ni el NOT NULL ni las políticas—, así que esto no cierra un
-- agujero: cierra la **posibilidad** de que la próxima función que se escriba
-- lo tenga sin que nadie se dé cuenta. Es lo mismo que la migración 24 ya hizo
-- con los jobs de mantenimiento, ahora como regla general.
revoke execute on all functions in schema public from public, anon;

-- Y lo que `authenticated` sí necesita, explícito. Si una función no está acá,
-- la app no la puede llamar — que es exactamente la señal que se quiere.
grant execute on function public.request_pal(text) to authenticated;
grant execute on function public.check_rate_limit(text, integer) to authenticated;
grant execute on function public.is_pal_of(uuid) to authenticated;
grant execute on function public.pal_shares(uuid, text) to authenticated;
grant execute on function public.create_meal_with_items(jsonb, jsonb) to authenticated;
grant execute on function public.get_daily_summary(date) to authenticated;

-- El default para lo que se cree de acá en adelante también se cierra.
alter default privileges in schema public revoke execute on functions from public;

-- down
-- grant execute on all functions in schema public to authenticated;
-- (los revokes no se deshacen solos: hay que volver a otorgar lo que haga falta)
