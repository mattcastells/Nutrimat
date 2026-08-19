-- 41 · Que la nutricionista vea el contexto, y desde cuándo hay algo que ver.
--
-- Dos cosas que van juntas porque las dos existen por la misma razón: que un
-- día vacío en la pantalla del profesional signifique lo que de verdad
-- significa.
--
-- ── El contexto va en `wellbeing`, y no en una categoría nueva ───────────
--
-- Los días de enfermedad y el alcohol se abren con `share_wellbeing`, la misma
-- llave que la actividad, el agua y el sueño. No se agrega una quinta
-- categoría a propósito: las cuatro del permiso son las cuatro pestañas del
-- panel, y esa correspondencia —"esta pestaña está apagada" y "esto no me lo
-- compartieron" son la misma frase— es lo que hace legible la pantalla. Una
-- quinta categoría sin pestaña propia rompería la equivalencia para agregar un
-- interruptor más que nadie pidió.
--
-- Lo que sí cambia es cómo se llama la categoría en la app y en el panel:
-- ahora es "actividad, agua, sueño y contexto del día".

drop policy if exists day_markers_care_read on public.day_markers;
create policy day_markers_care_read on public.day_markers
  for select to authenticated
  using (public.has_care_access(user_id, 'wellbeing'));

drop policy if exists alcohol_logs_care_read on public.alcohol_logs;
create policy alcohol_logs_care_read on public.alcohol_logs
  for select to authenticated
  using (public.has_care_access(user_id, 'wellbeing'));

-- ── Desde cuándo lleva registro esta persona ─────────────────────────────
--
-- El problema que resuelve: el panel arma sus períodos con el calendario —"los
-- últimos 30 días"— y contaba como huecos los días **anteriores a que la
-- persona empezara a usar la app**. Alguien que arrancó el 18 aparecía con
-- "13 de 30 días · 17 sin registrar" y un calendario con media pantalla en
-- gris, cuando en realidad no se había salteado ni un día.
--
-- La definición es la misma que ya usaba el informe del teléfono
-- (`LocalRepository.trackingSince`), y eso no es casualidad: si el PDF que
-- genera la app y la pantalla que mira la nutricionista contaran distinto,
-- estarían discutiendo sobre dos números que se llaman igual.
--
--   comidas, actividades y pesos → el primero de los tres
--
-- Agua y sueño quedan afuera **a propósito**: se cargan hacia atrás con
-- facilidad y no marcan cuándo empezó nadie. El peso entra porque el alta
-- guiada lo registra antes que cualquier otra cosa, así que para casi todo el
-- mundo es el primero.
--
-- `security definer` porque quien pregunta —el profesional— no puede leer esas
-- tablas salvo por las policies de care, y la función tiene que poder mirar las
-- tres aunque solo le hayan concedido una. El guard de adentro es lo que
-- reemplaza a esas policies: se contesta sobre uno mismo, o sobre alguien que
-- concedió **alguna** categoría.
create or replace function public.tracking_since(p_user uuid)
returns date
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_first date;
begin
  if p_user <> auth.uid()
     and not (
       public.has_care_access(p_user, 'meals')
       or public.has_care_access(p_user, 'body')
       or public.has_care_access(p_user, 'wellbeing')
       or public.has_care_access(p_user, 'photos')
     ) then
    return null;
  end if;

  select min(d) into v_first from (
    select min(local_date) as d from public.meals
      where user_id = p_user and deleted_at is null
    union all
    select min(local_date) from public.activities
      where user_id = p_user and deleted_at is null
    union all
    select min(local_date) from public.weight_logs
      where user_id = p_user and deleted_at is null
  ) as primeros;

  return v_first;
end $$;

revoke all on function public.tracking_since(uuid) from public;
grant execute on function public.tracking_since(uuid) to authenticated;

-- ── La lista de pacientes, con esa fecha adentro ─────────────────────────
--
-- Va en la vista y no en una consulta aparte del panel porque se necesita en
-- las dos pantallas —la lista y la ficha— y porque son tres index-only scans
-- sobre `(user_id, local_date)`: más barato que un viaje más.
--
-- ⚠️ `create or replace view` **no** deja agregar una columna en el medio ni
-- cambiar el orden. Va al final, después de `expires_at`.
create or replace view public.care_patients
with (security_barrier = true) as
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
    g.expires_at,
    public.tracking_since(g.owner_id) as tracking_since
  from public.care_grants g
  join public.profiles p on p.id = g.owner_id
 where g.professional_id = (select auth.uid())
   and g.status = 'accepted'
   and g.revoked_at is null
   and (g.expires_at is null or g.expires_at > now());

grant select on public.care_patients to authenticated;

-- down
-- drop policy if exists day_markers_care_read on public.day_markers;
-- drop policy if exists alcohol_logs_care_read on public.alcohol_logs;
-- drop function if exists public.tracking_since(uuid);
-- (y volver a la vista de la migración 32)
