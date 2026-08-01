-- 28 · El consentimiento de Pals, que la política no estaba haciendo cumplir.
--
-- Tres agujeros, los tres en la misma superficie y encontrados en la auditoría
-- del 1 de agosto (`docs/auditoria-2026-08-01.md`, C-1 y C-3).
--
-- El de fondo: `pals_update` decía en su comentario "aceptar o bloquear lo hace
-- quien recibe" y **no lo restringía**. Su `using` incluía al que manda la
-- solicitud, sin acotar columnas ni transiciones, así que quien pedía el
-- vínculo podía escribir `status = 'accepted'` sobre su propia fila. Y como
-- `is_pal_of` solo mira que diga `accepted` —no le importa quién lo puso—,
-- desde ahí veía el día del otro. Sin que el otro hiciera nada.
--
-- No hacía falta ni que la víctima tuviera prendida ninguna categoría:
-- `PalPublisher` publica comida y actividad de toda cuenta activa. Alcanzaba
-- con conocer un código de ocho caracteres.

-- ── 1 · Responder una solicitud es del que la recibe ─────────────────────
-- Ahora la política dice lo que decía el comentario: solo el destinatario,
-- solo desde `pending`, y solo hacia `accepted` o `blocked`.
--
-- El que manda la solicitud pierde el UPDATE y no lo necesita: cancelar es
-- borrar, y `pals_delete` ya lo permite de los dos lados. Deshacer un bloqueo
-- también es borrar la fila — una transición `blocked → accepted` no existe
-- como gesto en la app y no vale la pena habilitarla.
drop policy if exists pals_update on public.pals;
create policy pals_update on public.pals
  for update to authenticated
  using (
    addressee_id = (select auth.uid())
    and status = 'pending'
  )
  with check (
    addressee_id = (select auth.uid())
    and status in ('accepted', 'blocked')
  );

-- ── 2 · Un vínculo no cambia de personas ─────────────────────────────────
-- RLS no puede comparar OLD contra NEW: el `with check` de arriba mira la fila
-- resultante, así que quien pasa el filtro podría reescribir `addressee_id` y
-- apuntar un vínculo ya aceptado a un tercero que nunca lo pidió. Los uuid
-- ajenos no son secretos (aparecen en `shared_days.user_id` y en las rutas de
-- las fotos), así que esto se cierra con un trigger o no se cierra.
create or replace function public.guard_pal_identity()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is not null
     and (new.requester_id is distinct from old.requester_id
       or new.addressee_id is distinct from old.addressee_id)
  then
    raise exception 'Un vínculo de pals no puede cambiar de personas.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists pals_guard_identity on public.pals;
create trigger pals_guard_identity
  before update on public.pals
  for each row execute function public.guard_pal_identity();

-- ── 3 · El perfil deja de abrirse entero ─────────────────────────────────
-- `profiles_pal_read` existía para que la lista de pals pudiera mostrar el
-- nombre del otro, y su comentario decía que el nombre era "lo único del perfil
-- que se abre". No era cierto: RLS es por fila, no por columna, y el grant de
-- la migración 14 es sobre todas. Un pal —y también alguien con la solicitud
-- apenas mandada, sin aceptar— podía leer `pal_code`, `birth_date`,
-- `height_cm`, `biological_sex`, `activity_level` y los toggles de qué comparte.
--
-- La fecha de nacimiento y la altura son datos de salud, y el `pal_code` ajeno
-- es la llave para pedir el vínculo del punto 1.
--
-- Se reemplaza por una vista con las dos columnas que la lista necesita. La
-- vista corre con los privilegios de su dueño (`security_invoker` queda en
-- false, que es el default) y por eso puede leer `profiles` con la policy ya
-- borrada; lo que la acota es su propio `where`, no RLS. `security_barrier`
-- impide que el planificador cuele una función del que consulta por delante de
-- ese `where`.
drop policy if exists profiles_pal_read on public.profiles;

create or replace view public.pal_profiles
with (security_barrier = true) as
  select p.id, p.display_name
    from public.profiles p
   where public.is_pal_of(p.id)
      or exists (
        select 1 from public.pals
         where status = 'pending'
           and ((requester_id = (select auth.uid()) and addressee_id = p.id)
             or (addressee_id = (select auth.uid()) and requester_id = p.id))
      );

grant select on public.pal_profiles to authenticated;

-- El nombre se sigue viendo con la solicitud pendiente, a propósito: "Ana
-- quiere ser tu pal" es la pantalla, y sin el nombre no se puede decidir. Lo
-- que cambia es que ahora es **solo** el nombre.

-- ── 3b · Las tres policies que leían `profiles` para saber qué se comparte ──
-- Cerrar `profiles` rompe algo que no se ve a simple vista. Las políticas de
-- agua, sueño y fotos de la migración 25 preguntan por el toggle así:
--
--   and exists (select 1 from public.profiles p
--                where p.id = water_logs.user_id and p.pal_share_water)
--
-- Ese `exists` se evalúa **como quien consulta**, o sea con RLS de `profiles`
-- aplicada. Funcionaba solo porque `profiles_pal_read` dejaba ver la fila del
-- otro; sin esa policy el `exists` da falso siempre y un pal deja de ver el
-- agua, el sueño y las fotos que el dueño sí prendió. Lo atrapó
-- `pals_sharing_test.sql`, que es exactamente para lo que estaba escrito.
--
-- La respuesta no es volver a abrir el perfil, sino preguntar por el toggle
-- con una función que no dependa de verlo: `security definer`, con las dos
-- condiciones —ser pal y que esté prendido— en un solo lugar en vez de
-- repetidas en cada policy.
create or replace function public.pal_shares(p_owner uuid, p_category text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_pal_of(p_owner)
     and exists (
       select 1 from public.profiles p
        where p.id = p_owner
          and case p_category
                when 'photos'          then p.pal_share_photos
                when 'water'           then p.pal_share_water
                when 'sleep'           then p.pal_share_sleep
                when 'activity_detail' then p.pal_share_activity_detail
                -- Una categoría que no existe no comparte nada. Sin este
                -- `else` un typo en una policy futura devolvería NULL, que en
                -- un `using` no es "sí" pero tampoco es un error que se vea.
                else false
              end
     );
$$;

grant execute on function public.pal_shares(uuid, text) to authenticated;

-- Y de paso las dos de agua y sueño se acotan a la misma ventana de 7 días que
-- la de fotos ya tenía. La pantalla de un pal muestra hasta 7 días atrás; que
-- la base entregara el historial completo era más superficie que la que el
-- producto promete, sin que nadie la usara.
drop policy if exists water_logs_pal_read on public.water_logs;
create policy water_logs_pal_read on public.water_logs
  for select to authenticated
  using (
    public.pal_shares(user_id, 'water')
    and local_date >= current_date - 7
  );

drop policy if exists sleep_logs_pal_read on public.sleep_logs;
create policy sleep_logs_pal_read on public.sleep_logs
  for select to authenticated
  using (
    public.pal_shares(user_id, 'sleep')
    and local_date >= current_date - 7
  );

drop policy if exists meal_photos_pal_read on storage.objects;
create policy meal_photos_pal_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'meal-photos'
    -- El cast a uuid va detrás de una comprobación de forma: un objeto cuya
    -- primera carpeta no sea un uuid —lo sube un job, o un bucket nuevo—
    -- hacía fallar la consulta entera con "invalid input syntax for type
    -- uuid", y el `and bucket_id = ...` de arriba no garantiza cortocircuito.
    and name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/'
    and public.pal_shares((storage.foldername(name))[1]::uuid, 'photos')
    and exists (
      select 1 from public.shared_days sd
       where sd.user_id = (storage.foldername(name))[1]::uuid
         and sd.local_date >= current_date - 7
         and sd.meals @> jsonb_build_array(jsonb_build_object('photoPath', name))
    )
  );

-- ── 4 · El código de pal no se escribe desde el cliente ──────────────────
-- `profiles_update_own` no acota columnas, así que el dueño podía escribir su
-- propio `pal_code`. Dos problemas: elegirse uno trivial, y sobre todo usar el
-- índice único como oráculo —`update ... set pal_code = '<candidato>'`, y un
-- 23505 significa "ese código existe"— probando de a miles y esquivando el
-- límite de 20 por día de `request_pal`, que es la única defensa contra la
-- enumeración que se había construido.
--
-- Lanzar y no ignorar en silencio: así el intento tampoco sirve de oráculo,
-- porque el error es el mismo exista o no el código.
create or replace function public.guard_pal_code()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is not null and new.pal_code is distinct from old.pal_code then
    raise exception 'El código de pal no se cambia desde el cliente.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard_pal_code on public.profiles;
create trigger profiles_guard_pal_code
  before update on public.profiles
  for each row execute function public.guard_pal_code();

-- down
-- drop trigger if exists profiles_guard_pal_code on public.profiles;
-- drop function if exists public.guard_pal_code();
-- drop view if exists public.pal_profiles;
-- drop trigger if exists pals_guard_identity on public.pals;
-- drop function if exists public.guard_pal_identity();
