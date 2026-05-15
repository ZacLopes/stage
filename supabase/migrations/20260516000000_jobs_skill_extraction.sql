-- Migration: jobs_skill_extraction
--
-- Cache server-side da feature "confirmação de skills antes da adaptação".
-- Extração de skills atômicas é POR VAGA (não por user) — as skills que a vaga
-- pede são as mesmas pra qualquer candidato. Cruzamento contra CV (in_cv) e
-- contra confirmed_skills (pre_confirmed) é feito em runtime na Edge Function.
--
-- Custo extração: ~$0.0003/call (gpt-4o-mini). Cache hit = 0.

BEGIN;

CREATE TABLE IF NOT EXISTS public.jobs_skill_extraction (
  job_id          UUID PRIMARY KEY REFERENCES public.jobs(id) ON DELETE CASCADE,

  -- Skills extraídas: [{name: string, source: 'requirements'|'description'}]
  skills          JSONB NOT NULL,

  prompt_version  TEXT NOT NULL DEFAULT 'v1',
  model_used      TEXT NOT NULL,
  computed_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS jobs_skill_extraction_computed_idx
  ON public.jobs_skill_extraction (computed_at DESC);

ALTER TABLE public.jobs_skill_extraction ENABLE ROW LEVEL SECURITY;

-- Sem policy de SELECT pro user direto: acesso só via Edge Function
-- (service_role). User recebe o resultado já cruzado com o CV dele.

-- Estender CHECK de generation_type pra aceitar 'skill_extraction'
ALTER TABLE public.ai_generation_logs
  DROP CONSTRAINT IF EXISTS ai_generation_logs_generation_type_check;

ALTER TABLE public.ai_generation_logs
  ADD CONSTRAINT ai_generation_logs_generation_type_check
  CHECK (generation_type IN (
    'profile',
    'resume',
    'interview',
    'bullets',
    'resume_evaluation',
    'resume_refine',
    'match_analysis',
    'resume_adaptation',
    'skill_extraction'
  ));

COMMIT;
