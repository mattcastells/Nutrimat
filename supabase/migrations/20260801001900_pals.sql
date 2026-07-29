-- 20 · Pals: amigos que ven el día del otro.
--
-- La idea del producto es acotada a propósito: un pal ve **qué comiste y si te
-- moviste**, nada más. Ni peso, ni medidas, ni fotos, ni los ítems de cada
-- comida.
--
-- Eso no se resuelve mostrando menos en la app. Se resuelve **publicando
-- menos**: los datos siguen viviendo en el teléfono y a Postgres viaja una
-- proyección diaria con lo justo. Lo que no está en `shared_days` no existe
-- del lado del servidor, así que ningún bug de interfaz ni consulta directa
-- puede filtrarlo.

-- ── Código para agregarse ────────────────────────────────────────────────
-- Agregar por correo obligaría a saber el correo del otro y permitiría probar
-- direcciones para ver quién tiene cuenta. Un código corto y rotable no dice
-- nada de quién es su dueño.
alter table public.profiles
  add column if not exists pal_code text unique;

-- Sin ambigüedad al dictarlo: sin 0/O ni 1/I/L.
create or replace function public.generate_pal_code()
returns text
language plpgsql
as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  code text;
begin
  loop
    code := '';
    for _ in 1..8 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.profiles where pal_code = code);
  end loop;
  return code;
end $$;

update public.profiles set pal_code = public.generate_pal_code()
  where pal_code is null;

create or replace function public.set_pal_code()
returns trigger language plpgsql as $$
begin
  if new.pal_code is null then
    new.pal_code := public.generate_pal_code();
  end if;
  return new;
end $$;

drop trigger if exists profiles_pal_code on public.profiles;
create trigger profiles_pal_code
  before insert on public.profiles
  for each row execute function public.set_pal_code();

-- ── Vínculo ──────────────────────────────────────────────────────────────
create table if not exists public.pals (
  id           uuid        primary key default gen_random_uuid(),
  requester_id uuid        not null references public.profiles (id) on delete cascade,
  addressee_id uuid        not null references public.profiles (id) on delete cascade,
  status       text        not null default 'pending',
  created_at   timestamptz not null default now(),
  responded_at timestamptz,

  constraint pals_status check (status in ('pending', 'accepted', 'blocked')),
  -- Nadie es su propio pal, y no se puede pedir dos veces a la misma persona.
  constraint pals_not_self check (requester_id <> addressee_id),
  constraint pals_unique unique (requester_id, addressee_id)
);

create index if not exists pals_addressee_idx
  on public.pals (addressee_id, status);
create index if not exists pals_requester_idx
  on public.pals (requester_id, status);

-- Marca si dos personas son pals aceptados, en cualquier dirección.
create or replace function public.is_pal_of(p_owner uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.pals
     where status = 'accepted'
       and ((requester_id = auth.uid() and addressee_id = p_owner)
         or (addressee_id = auth.uid() and requester_id = p_owner))
  );
$$;

-- ── La proyección compartida ─────────────────────────────────────────────
-- Una fila por persona y día. `meals` guarda solo momento, nombre y calorías:
-- alcanza para "cargó el almuerzo" sin exponer el detalle de cada ítem.
create table if not exists public.shared_days (
  user_id          uuid        not null references public.profiles (id) on delete cascade,
  local_date       date        not null,
  meals            jsonb       not null default '[]'::jsonb,
  activity_minutes integer     not null default 0,
  activity_count   integer     not null default 0,
  updated_at       timestamptz not null default now(),

  primary key (user_id, local_date),
  constraint shared_days_minutes check (activity_minutes between 0 and 1440),
  constraint shared_days_count check (activity_count between 0 and 50)
);

create index if not exists shared_days_date_idx
  on public.shared_days (local_date desc);

-- ── RLS ──────────────────────────────────────────────────────────────────
alter table public.pals enable row level security;
alter table public.shared_days enable row level security;

grant select, insert, update, delete on public.pals to authenticated;
grant select, insert, update, delete on public.shared_days to authenticated;
grant execute on function public.is_pal_of(uuid) to authenticated;

-- Pals: se ve y se maneja lo propio, de los dos lados del vínculo.
drop policy if exists pals_select on public.pals;
create policy pals_select on public.pals
  for select to authenticated
  using (requester_id = (select auth.uid()) or addressee_id = (select auth.uid()));

-- Solo se piden vínculos a nombre propio.
drop policy if exists pals_insert on public.pals;
create policy pals_insert on public.pals
  for insert to authenticated
  with check (requester_id = (select auth.uid()));

-- Aceptar o bloquear lo hace quien recibe; cancelar, cualquiera de los dos.
drop policy if exists pals_update on public.pals;
create policy pals_update on public.pals
  for update to authenticated
  using (requester_id = (select auth.uid()) or addressee_id = (select auth.uid()))
  with check (requester_id = (select auth.uid()) or addressee_id = (select auth.uid()));

drop policy if exists pals_delete on public.pals;
create policy pals_delete on public.pals
  for delete to authenticated
  using (requester_id = (select auth.uid()) or addressee_id = (select auth.uid()));

-- El día compartido: lo escribe su dueño y lo leen sus pals aceptados.
drop policy if exists shared_days_own on public.shared_days;
create policy shared_days_own on public.shared_days
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Solo lectura para el pal: no hay policy de escritura para terceros.
drop policy if exists shared_days_pal_read on public.shared_days;
create policy shared_days_pal_read on public.shared_days
  for select to authenticated
  using (public.is_pal_of(user_id));

-- El nombre del pal hace falta para mostrarlo en la lista. Es lo único del
-- perfil que se abre, y solo entre pals aceptados o con solicitud en curso.
drop policy if exists profiles_pal_read on public.profiles;
create policy profiles_pal_read on public.profiles
  for select to authenticated
  using (
    public.is_pal_of(id)
    or exists (
      select 1 from public.pals
       where status = 'pending'
         and ((requester_id = (select auth.uid()) and addressee_id = profiles.id)
           or (addressee_id = (select auth.uid()) and requester_id = profiles.id))
    )
  );

-- ── Pedir un pal por código ──────────────────────────────────────────────
-- `security definer` porque hay que buscar por código en una tabla que RLS
-- mantiene cerrada. Devuelve solo el resultado de la operación: nunca el
-- perfil, ni siquiera si el código existe cuando ya hay vínculo.
create or replace function public.request_pal(p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  target uuid;
begin
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

grant execute on function public.request_pal(text) to authenticated;
