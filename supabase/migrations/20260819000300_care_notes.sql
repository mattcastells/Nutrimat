-- 42 · Las notas de la profesional: la primera escritura del panel.
--
-- Hasta acá el acceso profesional era **solo lectura**, y la migración 32 lo
-- dice con todas las letras: "no hay una sola política de insert, update o
-- delete para el profesional". Esa frase sigue valiendo y hay que leerla con
-- precisión: lo que no se puede escribir son **los datos del paciente**. Si el
-- panel tuviera un bug que intenta corregir un peso o borrar una comida, la
-- base lo sigue rechazando, y ninguna de las políticas de abajo lo cambia.
--
-- Lo que se abre es una tabla nueva donde el profesional escribe **lo suyo**:
-- lo que observó, lo que acordaron, qué mirar la próxima vez. Sin esto, la
-- consulta se prepara en un cuaderno aparte y la pantalla que tiene los datos
-- no tiene la lectura de esos datos.
--
-- ── Quién las lee ────────────────────────────────────────────────────────
--
-- **Solo quien las escribió.** El paciente no las ve, ni siquiera las suyas.
--
-- Es la decisión que mantiene la nota útil: una observación clínica que el
-- paciente va a leer se escribe distinto —o no se escribe— y termina siendo un
-- mensaje en vez de una nota de trabajo. Para lo que sí es para el paciente
-- está la consulta.
--
-- Es reversible en una línea (agregar `owner_id = auth.uid()` al `using` del
-- select) y queda anotado acá para que la próxima persona sepa que fue una
-- elección y no un olvido.
--
-- ── Y qué pasa si le revocan el acceso ───────────────────────────────────
--
-- Las notas siguen siendo legibles por quien las escribió, pero **no se pueden
-- escribir nuevas**. Son dos cosas distintas: el texto es del profesional y
-- borrárselo al revocar sería borrarle su propio historial de trabajo; seguir
-- anotando sobre alguien que cortó el acceso, en cambio, es justamente lo que
-- el corte tiene que impedir.

create table if not exists public.care_notes (
  id              uuid        primary key default extensions.gen_random_uuid(),

  -- Quien escribe. No es `professional_id` a secas porque la tabla no depende
  -- de que el vínculo siga vivo: si el permiso se revoca, la fila queda y su
  -- dueño sigue siendo esta persona.
  author_id       uuid        not null
                    references public.profiles (id) on delete cascade,

  -- Sobre quién. Sin FK a `care_grants`: un vínculo revocado y vuelto a
  -- conceder es otra fila de `care_grants`, y la nota de marzo no tiene por qué
  -- morirse con él.
  patient_id      uuid        not null
                    references public.profiles (id) on delete cascade,

  -- `null` = una nota sobre el seguimiento en general. Con fecha = anclada a
  -- ese día, que es lo que permite abrir el 12 de julio y encontrar por qué
  -- ese día no hay nada cargado.
  local_date      date,

  body            text        not null,

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,

  constraint care_notes_body_len check (
    char_length(body) between 1 and 4000),
  constraint care_notes_no_self check (author_id <> patient_id)
);

create index if not exists care_notes_lookup_idx
  on public.care_notes (author_id, patient_id, local_date)
  where deleted_at is null;

drop trigger if exists care_notes_set_updated_at on public.care_notes;
create trigger care_notes_set_updated_at
  before update on public.care_notes
  for each row execute function public.set_updated_at();

alter table public.care_notes enable row level security;

grant select, insert, update, delete on public.care_notes to authenticated;

-- Leer: las propias, siempre. No depende del permiso vigente, por lo de arriba.
drop policy if exists care_notes_read_own on public.care_notes;
create policy care_notes_read_own on public.care_notes
  for select to authenticated
  using (author_id = (select auth.uid()));

-- Escribir: a nombre propio y **solo sobre un paciente con acceso vigente**.
-- `has_care_access` con cualquiera de las categorías alcanza: quien concedió
-- algo aceptó el seguimiento, y las notas no leen datos, los comentan.
drop policy if exists care_notes_write on public.care_notes;
create policy care_notes_write on public.care_notes
  for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and (
      public.has_care_access(patient_id, 'meals')
      or public.has_care_access(patient_id, 'body')
      or public.has_care_access(patient_id, 'wellbeing')
      or public.has_care_access(patient_id, 'photos')
    )
  );

-- Corregir y borrar: las propias, sin pedirle permiso vigente a nadie. Alguien
-- que perdió el acceso tiene que poder borrar lo que escribió.
drop policy if exists care_notes_update_own on public.care_notes;
create policy care_notes_update_own on public.care_notes
  for update to authenticated
  using (author_id = (select auth.uid()))
  with check (author_id = (select auth.uid()));

drop policy if exists care_notes_delete_own on public.care_notes;
create policy care_notes_delete_own on public.care_notes
  for delete to authenticated
  using (author_id = (select auth.uid()));

-- La lápida entra en la misma ventana de 30 días que todo lo demás.
--
-- El cuerpo sale de la definición vigente (migración 40), no de memoria.
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
  delete from public.sleep_logs
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.foods
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.exercise_templates
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.day_markers
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.alcohol_logs
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.care_notes
   where deleted_at is not null and deleted_at < now() - interval '30 days';

  perform public.purge_shared_days();
end;
$$;

revoke execute on function public.purge_soft_deleted() from public, anon, authenticated;

-- down
-- drop table if exists public.care_notes;
-- (y volver al cuerpo de `purge_soft_deleted` de la migración 40)
