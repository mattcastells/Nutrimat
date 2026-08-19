-- 44 · Un campo que no decía lo que guarda, y dos tablas que nadie llenaba.
--
-- Lo contrario de la migración 43: acá el dato sí vale la pena, así que en vez
-- de sacar la tabla se arregla lo que faltaba para que sirva.

-- ── `meals.logged_at` guarda la hora de la comida, no la de la carga ─────
--
-- La app tiene un botón "Cambiar hora" en el formulario y arma este valor con
-- **la fecha elegida más la hora elegida**, no con `now()`. Editar una comida
-- lo conserva. O sea que hace tiempo que esta columna es la hora a la que se
-- comió, y el nombre quedó del primer día, cuando sí era la de la carga.
--
-- Un nombre que miente sobre lo que guarda es la misma clase de problema que
-- este esquema ya se comió dos veces: son los "dos números que se llaman
-- igual". Acá el daño concreto es que la hora de la comida —el insumo de la
-- ventana de alimentación y de los horarios, que es media consulta— parece un
-- dato de auditoría y por eso no la usó nunca ninguna pantalla de análisis.
--
-- El resto de las tablas se quedan con `logged_at` **y hacen bien**: en
-- `sleep_logs`, `weight_logs` y `alcohol_logs` ese campo sí es cuándo se
-- registró, y en el sueño además es lo que desempata la reconciliación. Después
-- de esto, cada nombre quiere decir lo que guarda.
alter table public.meals rename column logged_at to eaten_at;

comment on column public.meals.eaten_at is
  'Cuándo se comió, en hora local del dispositivo. Lo elige la persona en el '
  'formulario (por omisión, el momento de cargarla). No es cuándo se registró: '
  'para eso está created_at.';

-- ── Los recordatorios ────────────────────────────────────────────────────
--
-- La tabla existe desde la migración 22 y **el cliente nunca la escribió**. Su
-- propio comentario decía por qué tenía que existir: "se guardan igual para que
-- cambiar de dispositivo no pierda la configuración, que es lo único molesto de
-- volver a armar". Eso es exactamente lo que no pasaba.
--
-- Pero acá, a diferencia de `rest_days`, no alcanzaba con que el cliente la
-- nombrara: **la tabla no podía guardar lo que el modelo tiene**. Nació con un
-- solo `hour`/`minute` por tipo, y el recordatorio de agua son tres horarios
-- —10, 14 y 18—, porque un solo aviso al día no sirve para algo que se hace de
-- a poco. Así que el esquema se pone al día con el modelo antes de conectarlo.
--
-- `times` son **minutos desde medianoche**, no dos columnas ni un jsonb: es un
-- entero por horario, ordenable y con un check que lo acota al día. El `weekdays`
-- se va porque nunca hubo pantalla que lo eligiera; el día que la haya, vuelve.
alter table public.reminders
  add column if not exists times smallint[] not null default '{}';

-- Los horarios que hubiera cargados pasan al arreglo antes de sacar las
-- columnas viejas. En producción esta tabla está vacía —nadie la escribió
-- nunca— así que esto no mueve nada; está para que la migración sea correcta y
-- no solo suficiente.
update public.reminders
   set times = array[(hour * 60 + minute)::smallint]
 where cardinality(times) = 0;

alter table public.reminders
  drop column if exists hour,
  drop column if exists minute,
  drop column if exists weekdays;

alter table public.reminders
  drop constraint if exists reminders_hour_range,
  drop constraint if exists reminders_minute_range;

alter table public.reminders
  drop constraint if exists reminders_times_range;
alter table public.reminders
  add constraint reminders_times_range check (
    -- Ocho es el tope del modelo (`Reminder.maxTimes`): más que eso es ruido,
    -- no un recordatorio.
    cardinality(times) <= 8
    -- `<= all (…)` y no una subconsulta con `generate_series`: un `check` no
    -- puede contener subconsultas, y Postgres lo rechaza al crearlo con
    -- "cannot use subquery in check constraint". Con un arreglo vacío las dos
    -- comparaciones dan verdadero, que es lo que corresponde.
    and 0 <= all (times)
    and 1439 >= all (times)
  );

-- El id lo pone la base y no el cliente. El modelo `Reminder` **no tiene id**:
-- se identifica por (usuario, tipo), que es el único que ya tenía la tabla. Sin
-- un default acá, el cliente tendría que inventar un uuid en cada subida, y en
-- el upsert por (user_id, kind) eso reescribiría la primary key de la fila en
-- cada sincronización.
alter table public.reminders
  alter column id set default extensions.gen_random_uuid();

create index if not exists reminders_user_idx
  on public.reminders (user_id);

-- ── Las plantillas de ejercicio ──────────────────────────────────────────
--
-- Igual: `exercise_templates` existe desde la migración 09, la app las guarda
-- en su documento local y nunca subían. Una plantilla que alguien se armó a
-- mano y pierde al cambiar de teléfono es de las cosas más molestas de rehacer,
-- que es justo el argumento por el que la tabla se creó.
--
-- Lleva lápida, así que entra en la purga de 30 días como el resto. El cuerpo
-- de `purge_soft_deleted` sale de la definición vigente (migración 42), no de
-- memoria: `create or replace` reemplaza, no mezcla.
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
-- alter table public.meals rename column eaten_at to logged_at;
-- drop index if exists public.reminders_user_idx;
