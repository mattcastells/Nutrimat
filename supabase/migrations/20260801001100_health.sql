-- 11 · health_integrations, sync_records y duplicate_resolutions
-- (07-data-model.md §2.12, §2.13, §2.18).

-- Health Connect es la única integración del MVP (D-21). El enum de un solo
-- valor es a propósito: sumar otra es agregar un valor, no rehacer el modelo.
create table if not exists public.health_integrations (
  id              uuid        primary key default extensions.gen_random_uuid(),
  user_id         uuid        not null
                    references public.profiles (id) on delete cascade,
  provider        text        not null,
  status          text        not null default 'not_connected',
  permissions     jsonb       not null default '[]'::jsonb,
  last_sync_at    timestamptz,
  sync_cursor     text,
  last_error      text,
  connected_at    timestamptz,
  disconnected_at timestamptz,
  imported_count  integer     not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint health_integrations_provider check (provider in ('health_connect')),
  constraint health_integrations_status check (status in (
    'not_connected', 'connected', 'permission_denied',
    'provider_unavailable', 'error')),
  constraint health_integrations_uniq unique (user_id, provider)
);

-- Idempotencia del cursor: el mismo registro externo no se importa dos veces.
create table if not exists public.sync_records (
  id                uuid        primary key default extensions.gen_random_uuid(),
  user_id           uuid        not null
                      references public.profiles (id) on delete cascade,
  provider          text        not null,
  entity_type       text        not null,
  external_id       text        not null,
  local_entity_id   uuid,
  source_updated_at timestamptz,
  synced_at         timestamptz not null default now(),
  -- SHA-256 de started_at|duration|calories|distance|type: detecta si el
  -- proveedor cambió el registro sin comparar campo por campo.
  sync_hash         text,
  skipped_reason    text,
  created_at        timestamptz not null default now(),

  constraint sync_records_entity check (entity_type in (
    'activity', 'weight', 'steps', 'heart_rate')),
  constraint sync_records_uniq unique (user_id, provider, entity_type, external_id)
);

-- Auditoría de cada decisión sobre un duplicado: es el insumo para recalibrar
-- los umbrales de RN-07 con datos reales, en vez de a ojo.
create table if not exists public.duplicate_resolutions (
  id            uuid        primary key default extensions.gen_random_uuid(),
  user_id       uuid        not null
                  references public.profiles (id) on delete cascade,
  activity_a_id uuid        not null,
  activity_b_id uuid        not null,
  match_score   numeric(3,2) not null,
  resolution    text        not null,
  resolved_at   timestamptz not null default now(),
  created_at    timestamptz not null default now(),

  constraint duplicate_resolutions_score check (match_score between 0 and 1),
  constraint duplicate_resolutions_resolution check (
    resolution in ('kept_a', 'kept_b', 'kept_both', 'deferred'))
);

create index if not exists sync_records_lookup_idx
  on public.sync_records (user_id, provider, entity_type);
create index if not exists duplicate_resolutions_user_idx
  on public.duplicate_resolutions (user_id, resolved_at desc);

drop trigger if exists health_integrations_set_updated_at on public.health_integrations;
create trigger health_integrations_set_updated_at
  before update on public.health_integrations
  for each row execute function public.set_updated_at();

-- down
-- drop table if exists public.duplicate_resolutions;
-- drop table if exists public.sync_records;
-- drop table if exists public.health_integrations;
