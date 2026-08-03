-- 32 · Acceso profesional: que una nutricionista pueda seguir a alguien.
--
-- El problema es distinto del de Pals y por eso no reusa esa maquinaria. Un
-- pal ve una **proyección** (`shared_days`): comida y si te moviste, nada más,
-- y lo que no está publicado ahí no existe del lado del servidor. Un
-- seguimiento nutricional necesita justo lo que esa proyección deja afuera —el
-- detalle de cada ítem, los macros, el peso, las medidas— y eso ya vive en las
-- tablas reales, legible solo por su dueño.
--
-- Entonces la pregunta no es qué publicar sino **a quién abrirle lo que ya
-- está**, y la respuesta no puede ser un rol admin. Una cuenta que lee a todos
-- convierte una credencial filtrada en una filtración total y no deja rastro
-- de quién autorizó qué. Acá el permiso lo da el dueño, es por categoría, es
-- revocable y puede vencer.
--
-- Todo lo que sigue es **solo lectura**. No hay una sola política de insert,
-- update o delete para el profesional: si mañana el backoffice tuviera un bug
-- que intenta escribir, la base lo rechaza.

-- ── El vínculo ───────────────────────────────────────────────────────────
-- Un profesional puede seguir a varias personas y una persona puede tener más
-- de un profesional, pero el par es único: dos filas para el mismo par serían
-- dos permisos que hay que revocar por separado, y uno se olvida.
create table if not exists public.care_grants (
  id              uuid        primary key default gen_random_uuid(),
  owner_id        uuid        not null
                    references public.profiles (id) on delete cascade,
  professional_id uuid        not null
                    references public.profiles (id) on delete cascade,

  -- Nace `accepted` porque quien lo crea es el dueño: conceder y elegir qué
  -- conceder son el mismo acto. `pending` queda previsto para el día que el
  -- profesional pueda pedirlo él —ahí sí hay un consentimiento que esperar—,
  -- y hoy no lo escribe nadie.
  status          text        not null default 'accepted',

  -- Qué se abre. Todas apagadas: un permiso recién aceptado sin categorías
  -- prendidas no muestra nada, que es el default correcto.
  share_meals     boolean     not null default false,
  share_photos    boolean     not null default false,
  share_body      boolean     not null default false,
  share_wellbeing boolean     not null default false,

  -- Vencimiento opcional. Un permiso que caduca solo es mejor que uno que
  -- depende de que alguien se acuerde de apagarlo.
  expires_at      timestamptz,

  created_at      timestamptz not null default now(),
  accepted_at     timestamptz,
  revoked_at      timestamptz,
  updated_at      timestamptz not null default now(),

  constraint care_grants_status check (
    status in ('pending', 'accepted', 'revoked')),

  -- Seguirse a uno mismo no es un permiso, es ruido que después hay que
  -- filtrar en cada consulta.
  constraint care_grants_no_self check (owner_id <> professional_id),

  constraint care_grants_unique_pair unique (owner_id, professional_id)
);

create index if not exists care_grants_owner_idx
  on public.care_grants (owner_id);
create index if not exists care_grants_professional_idx
  on public.care_grants (professional_id, status);

drop trigger if exists care_grants_updated_at on public.care_grants;
create trigger care_grants_updated_at
  before update on public.care_grants
  for each row execute function public.set_updated_at();

-- ── El código con el que se pide ─────────────────────────────────────────
-- Mismo razonamiento que `pal_code`: pedir por correo obligaría a saber el
-- correo del otro y permitiría probar direcciones para ver quién tiene cuenta.
-- El profesional muestra su código, el dueño lo carga en la app.
--
-- Va en columna propia y no reusa `pal_code` porque son dos permisos muy
-- distintos: quien te dicta su código para ser pal no debería estar dictando,
-- sin saberlo, el que abre el detalle de tus comidas y tu peso.
alter table public.profiles
  add column if not exists care_code text unique;

create or replace function public.generate_care_code()
returns text
language plpgsql
as $$
declare
  -- Sin 0/O ni 1/I/L: se dicta por teléfono.
  alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  code text;
begin
  loop
    code := 'NT-';
    for _ in 1..6 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.profiles where care_code = code);
  end loop;
  return code;
end $$;

-- A diferencia de `pal_code`, **no** se le pone a todo el mundo al crearse la
-- cuenta: solo tiene código quien va a ejercer de profesional, y lo pide desde
-- el backoffice. Un código que existe es una superficie que alguien puede
-- adivinar; no hay razón para que lo tengan las cuentas que nunca lo usan.
create or replace function public.ensure_care_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  existing text;
begin
  select care_code into existing from public.profiles where id = auth.uid();
  if existing is not null then
    return existing;
  end if;

  existing := public.generate_care_code();
  update public.profiles set care_code = existing where id = auth.uid();
  return existing;
end $$;

revoke all on function public.ensure_care_code() from public;
grant execute on function public.ensure_care_code() to authenticated;

-- ── La pregunta que hace cada política ───────────────────────────────────
-- `security definer` por lo mismo que `is_pal_of`: la función mira
-- `care_grants`, y quien consulta no tiene por qué poder leer esa tabla entera
-- para que la política funcione.
--
-- Las tres condiciones van juntas a propósito: aceptado, no revocado y no
-- vencido. Separarlas en distintas políticas dejaría la puerta a que una se
-- olvide en la próxima tabla.
create or replace function public.has_care_access(
  p_owner uuid,
  p_category text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.care_grants g
     where g.professional_id = auth.uid()
       and g.owner_id = p_owner
       and g.status = 'accepted'
       and g.revoked_at is null
       and (g.expires_at is null or g.expires_at > now())
       and case p_category
             when 'meals'     then g.share_meals
             when 'photos'    then g.share_photos
             when 'body'      then g.share_body
             when 'wellbeing' then g.share_wellbeing
             -- Una categoría que no existe no abre nada. Sin este `else`, un
             -- typo en una política futura devolvería null y la política
             -- fallaría cerrada por casualidad y no por diseño.
             else false
           end
  );
$$;

revoke all on function public.has_care_access(uuid, text) from public;
grant execute on function public.has_care_access(uuid, text) to authenticated;

-- ── Quién ve y quién toca el vínculo ─────────────────────────────────────
alter table public.care_grants enable row level security;

-- Los dos lados ven el vínculo: el dueño para revocarlo, el profesional para
-- saber a quién puede seguir.
drop policy if exists care_grants_select on public.care_grants;
create policy care_grants_select on public.care_grants
  for select to authenticated
  using (
    owner_id = (select auth.uid())
    or professional_id = (select auth.uid())
  );

-- El permiso lo crea el dueño, a nombre propio. El profesional **no puede
-- insertar**: si pudiera, se estaría concediendo lo que solo el otro tiene
-- para conceder, y da igual con qué valores lo intente.
drop policy if exists care_grants_grant on public.care_grants;
create policy care_grants_grant on public.care_grants
  for insert to authenticated
  with check (owner_id = (select auth.uid()));

-- Elegir categorías, poner vencimiento y revocar: todo del dueño. El
-- profesional no actualiza nada.
drop policy if exists care_grants_owner_manages on public.care_grants;
create policy care_grants_owner_manages on public.care_grants
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- Revocar es `status = 'revoked'`, no borrar la fila: queda el registro de que
-- ese acceso existió y hasta cuándo. Un permiso sobre datos de salud que
-- desaparece sin dejar rastro no se puede auditar después.
drop policy if exists care_grants_no_hard_delete on public.care_grants;
create policy care_grants_no_hard_delete on public.care_grants
  for delete to authenticated
  using (false);

-- ── Lo que se abre ───────────────────────────────────────────────────────
-- Un `select` por tabla, cada uno nombrando su categoría. Nada de `for all`.

drop policy if exists meals_care_read on public.meals;
create policy meals_care_read on public.meals
  for select to authenticated
  using (public.has_care_access(user_id, 'meals'));

-- `meal_items` no tiene `user_id`: cuelga de la comida, igual que su política
-- de dueño.
drop policy if exists meal_items_care_read on public.meal_items;
create policy meal_items_care_read on public.meal_items
  for select to authenticated
  using (exists (
    select 1 from public.meals m
     where m.id = meal_items.meal_id
       and public.has_care_access(m.user_id, 'meals')
  ));

drop policy if exists weight_logs_care_read on public.weight_logs;
create policy weight_logs_care_read on public.weight_logs
  for select to authenticated
  using (public.has_care_access(user_id, 'body'));

drop policy if exists body_measurements_care_read on public.body_measurements;
create policy body_measurements_care_read on public.body_measurements
  for select to authenticated
  using (public.has_care_access(user_id, 'body'));

drop policy if exists activities_care_read on public.activities;
create policy activities_care_read on public.activities
  for select to authenticated
  using (public.has_care_access(user_id, 'wellbeing'));

drop policy if exists water_logs_care_read on public.water_logs;
create policy water_logs_care_read on public.water_logs
  for select to authenticated
  using (public.has_care_access(user_id, 'wellbeing'));

drop policy if exists sleep_logs_care_read on public.sleep_logs;
create policy sleep_logs_care_read on public.sleep_logs
  for select to authenticated
  using (public.has_care_access(user_id, 'wellbeing'));

-- El objetivo del día es el número contra el que se lee todo lo demás: sin él
-- "1.800 kcal" no dice si estuvo bien o mal. Va con `meals` porque es la misma
-- pregunta.
drop policy if exists goals_care_read on public.goals;
create policy goals_care_read on public.goals
  for select to authenticated
  using (public.has_care_access(user_id, 'meals'));

-- Del perfil, solo lo que hace falta para leer los números: nombre para saber
-- a quién está mirando, y sexo/nacimiento/altura porque son las entradas del
-- cálculo que ella va a querer revisar. La política no puede filtrar columnas,
-- así que la restricción de columnas la hace la vista de abajo y esta política
-- se limita a quien tenga cualquier categoría abierta.
drop policy if exists profiles_care_read on public.profiles;
create policy profiles_care_read on public.profiles
  for select to authenticated
  using (
    public.has_care_access(id, 'meals')
    or public.has_care_access(id, 'body')
    or public.has_care_access(id, 'wellbeing')
  );

-- ── Fotos ────────────────────────────────────────────────────────────────
-- Como la de pals, pero sin la ventana de siete días: un seguimiento mira
-- hacia atrás, y recortarlo a una semana volvería la categoría inútil. El
-- límite acá es el permiso, no el calendario.
drop policy if exists meal_photos_care_read on storage.objects;
create policy meal_photos_care_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'meal-photos'
    and public.has_care_access((storage.foldername(name))[1]::uuid, 'photos')
  );

-- ── A quién sigue cada profesional ───────────────────────────────────────
-- El backoffice necesita listar pacientes sin poder leer `profiles` entero.
-- `security_invoker` para que la vista no sea un agujero: sigue corriendo con
-- los permisos de quien consulta, así que devuelve exactamente lo que las
-- políticas de arriba ya permiten.
create or replace view public.care_patients
with (security_invoker = true)
as
  select
    g.id            as grant_id,
    g.owner_id      as patient_id,
    p.display_name  as patient_name,
    p.biological_sex,
    p.birth_date,
    p.height_cm,
    p.unit_system,
    g.share_meals,
    g.share_photos,
    g.share_body,
    g.share_wellbeing,
    g.accepted_at,
    g.expires_at
  from public.care_grants g
  join public.profiles p on p.id = g.owner_id
 where g.professional_id = auth.uid()
   and g.status = 'accepted'
   and g.revoked_at is null
   and (g.expires_at is null or g.expires_at > now());

grant select on public.care_patients to authenticated;

-- ── Conceder acceso por código ───────────────────────────────────────────
-- El dueño no puede leer `profiles` ajenos para traducir un código a un id
-- —ni debería—, así que la traducción la hace la función.
--
-- El acto de conceder y el de elegir qué conceder son el mismo: nace
-- `accepted` con las categorías que se pasaron, porque quien llama es el
-- dueño y no hay un segundo consentimiento que esperar. Un `pending` acá
-- sería un permiso a medio dar que alguien tiene que ir a confirmar.
create or replace function public.grant_care_access(
  p_code            text,
  p_share_meals     boolean default false,
  p_share_photos    boolean default false,
  p_share_body      boolean default false,
  p_share_wellbeing boolean default false,
  p_expires_at      timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  professional uuid;
  grant_id     uuid;
begin
  select id into professional
    from public.profiles
   where care_code = upper(trim(p_code));

  if professional is null then
    raise exception 'ERR_NOT_FOUND' using hint = 'Ese código no existe.';
  end if;

  if professional = auth.uid() then
    raise exception 'ERR_VALIDATION' using hint = 'Ese código es el tuyo.';
  end if;

  -- Volver a conceder sobre un par que ya existe **reemplaza** las categorías
  -- en vez de fallar: es lo que uno espera de "cambiar qué ve", y obliga a
  -- pasar por acá para reabrir uno revocado, que es donde está el control.
  insert into public.care_grants as g (
    owner_id, professional_id, status,
    share_meals, share_photos, share_body, share_wellbeing,
    expires_at, accepted_at
  )
  values (
    auth.uid(), professional, 'accepted',
    p_share_meals, p_share_photos, p_share_body, p_share_wellbeing,
    p_expires_at, now()
  )
  on conflict (owner_id, professional_id) do update
     set status          = 'accepted',
         share_meals     = excluded.share_meals,
         share_photos    = excluded.share_photos,
         share_body      = excluded.share_body,
         share_wellbeing = excluded.share_wellbeing,
         expires_at      = excluded.expires_at,
         accepted_at     = coalesce(g.accepted_at, now()),
         revoked_at      = null
  returning g.id into grant_id;

  return grant_id;
end $$;

revoke all on function public.grant_care_access(
  text, boolean, boolean, boolean, boolean, timestamptz) from public;
grant execute on function public.grant_care_access(
  text, boolean, boolean, boolean, boolean, timestamptz) to authenticated;

-- Revocar sin tener que armar el update a mano desde la app.
create or replace function public.revoke_care_access(p_grant_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.care_grants
     set status = 'revoked', revoked_at = now()
   where id = p_grant_id
     and owner_id = auth.uid();
$$;

revoke all on function public.revoke_care_access(uuid) from public;
grant execute on function public.revoke_care_access(uuid) to authenticated;
