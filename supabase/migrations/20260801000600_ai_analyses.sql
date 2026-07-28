-- 06 · ai_analyses (07-data-model.md §2.7).
--
-- Guarda lo que propuso el modelo y el diff contra lo que la persona guardó:
-- es el insumo para mejorar el prompt (F-06) y para medir `ai_result_corrected`.

create table if not exists public.ai_analyses (
  id             uuid        primary key,
  user_id        uuid        not null
                   references public.profiles (id) on delete cascade,
  photo_path     text        not null,
  status         text        not null default 'pending',
  model          text        not null,
  prompt_version text        not null,
  items          jsonb       not null default '[]'::jsonb,
  raw_response   jsonb,
  confidence_avg numeric(3,2),
  latency_ms     integer,
  error_code     text,
  corrections    jsonb,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint ai_analyses_status check (
    status in ('pending', 'completed', 'failed', 'accepted', 'discarded')),
  constraint ai_analyses_confidence check (
    confidence_avg is null or confidence_avg between 0 and 1)
);

alter table public.meals
  drop constraint if exists meals_ai_analysis_fk;
alter table public.meals
  add constraint meals_ai_analysis_fk
  foreign key (ai_analysis_id) references public.ai_analyses (id) on delete set null;

-- La cuota de 20 análisis por día se cuenta sobre este índice (D-18).
create index if not exists ai_analyses_user_day_idx
  on public.ai_analyses (user_id, created_at desc);

drop trigger if exists ai_analyses_set_updated_at on public.ai_analyses;
create trigger ai_analyses_set_updated_at
  before update on public.ai_analyses
  for each row execute function public.set_updated_at();

-- down
-- alter table public.meals drop constraint if exists meals_ai_analysis_fk;
-- drop table if exists public.ai_analyses;
