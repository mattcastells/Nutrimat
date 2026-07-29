-- Las tres tablas que le faltaban al esquema, y la limpieza de las que sobran.
--
-- El esquema original quedó atrás respecto de la app: agua, sueño y
-- recordatorios se agregaron al producto y nunca tuvieron dónde vivir del lado
-- del servidor. Mientras el respaldo fue un JSON opaco eso no se notaba —
-- viajaba todo junto adentro—, pero para persistir en tablas hay que tenerlas.
--
-- Se aprovecha para sacar cuatro tablas de una función de fuerza (rutinas,
-- ejercicios y series) que nunca se construyó en la app. Están vacías y sin
-- código que las toque: dejarlas es sugerir que hay algo detrás.

-- ── Agua ──────────────────────────────────────────────────────────────────
--
-- Se guarda el **conteo de vasos** y no mililitros, igual que en el teléfono:
-- el tamaño del vaso es una preferencia del perfil, así que cambiarla no puede
-- reescribir el historial. Los 8 vasos de ayer siguen siendo 8.
create table if not exists public.water_logs (
  id            uuid primary key,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  local_date    date not null,
  glasses       smallint not null default 0,
  sync_status   text not null default 'synced',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- 40 vasos son 10 litros: más que eso es un error de tipeo, no una persona
  -- tomando agua. Mismo tope que `WaterLog.maxGlasses`.
  constraint water_logs_glasses_range check (glasses between 0 and 40),
  -- Uno por día y por persona, como el peso (D-16).
  constraint water_logs_one_per_day unique (user_id, local_date)
);

-- ── Sueño ─────────────────────────────────────────────────────────────────
--
-- Se registra sobre el día en que se **despertó**, que es como la gente lo
-- cuenta: "anoche dormí seis horas" va en el día de hoy.
create table if not exists public.sleep_logs (
  id            uuid primary key,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  local_date    date not null,
  minutes       smallint not null,
  quality       text not null default 'ok',
  logged_at     timestamptz not null default now(),
  notes         text,
  sync_status   text not null default 'synced',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- De 0 a 24 h. El tope existe para atajar un cero de más.
  constraint sleep_logs_minutes_range check (minutes between 0 and 1440),
  constraint sleep_logs_quality_valid
    check (quality in ('bad', 'poor', 'ok', 'good', 'great')),
  constraint sleep_logs_one_per_day unique (user_id, local_date)
);

-- ── Recordatorios ─────────────────────────────────────────────────────────
--
-- Son locales al teléfono: los programa Android, no el servidor. Se guardan
-- igual para que cambiar de dispositivo no pierda la configuración, que es lo
-- único molesto de volver a armar.
create table if not exists public.reminders (
  id            uuid primary key,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  kind          text not null,
  enabled       boolean not null default false,
  hour          smallint not null default 9,
  minute        smallint not null default 0,
  -- Días de la semana en que aplica, 1 = lunes.
  weekdays      smallint[] not null default '{1,2,3,4,5,6,7}',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint reminders_hour_range check (hour between 0 and 23),
  constraint reminders_minute_range check (minute between 0 and 59),
  constraint reminders_one_per_kind unique (user_id, kind)
);

-- ── RLS ───────────────────────────────────────────────────────────────────
--
-- ⚠️ RLS sin GRANT no hace nada útil: `authenticated` recibe *permission
-- denied* y las políticas ni se evalúan. Van juntos, como en la migración 14.
alter table public.water_logs  enable row level security;
alter table public.sleep_logs  enable row level security;
alter table public.reminders   enable row level security;

grant select, insert, update, delete
  on public.water_logs, public.sleep_logs, public.reminders
  to authenticated;

create policy water_logs_own on public.water_logs
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy sleep_logs_own on public.sleep_logs
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy reminders_own on public.reminders
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- `updated_at` lo mantiene la base, no el cliente: si lo mandara el teléfono,
-- un reloj mal puesto rompería la resolución de conflictos por fecha.
create trigger water_logs_set_updated_at
  before update on public.water_logs
  for each row execute function public.set_updated_at();

create trigger sleep_logs_set_updated_at
  before update on public.sleep_logs
  for each row execute function public.set_updated_at();

create trigger reminders_set_updated_at
  before update on public.reminders
  for each row execute function public.set_updated_at();

create index if not exists water_logs_user_date_idx
  on public.water_logs (user_id, local_date desc);
create index if not exists sleep_logs_user_date_idx
  on public.sleep_logs (user_id, local_date desc);

-- ── Lo que sobra ──────────────────────────────────────────────────────────
--
-- Cuatro tablas de una función de fuerza que la app nunca tuvo: ni pantalla,
-- ni modelo, ni una línea de código que las nombre. Están vacías. Se sacan en
-- orden de dependencia.
drop table if exists public.strength_sets;
drop table if exists public.strength_exercises;
drop table if exists public.routine_exercises;
drop table if exists public.workout_routines;

-- down
-- drop table if exists public.reminders;
-- drop table if exists public.sleep_logs;
-- drop table if exists public.water_logs;
-- (las de fuerza se recuperan de la migración 20260801000900 si hicieran falta)
