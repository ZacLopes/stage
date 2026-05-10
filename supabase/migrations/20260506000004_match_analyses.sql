-- Match Score com IA: cache de análises por (user, vaga) + ampliação do
-- generation_type permitido em ai_generation_logs.

BEGIN;

-- ============================================================================
-- 1. Estender CHECK constraint de ai_generation_logs pra incluir 'match_analysis'
-- ============================================================================

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
    'match_analysis'
  ));

-- ============================================================================
-- 2. Tabela de cache: uma entrada por (user, job)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.match_analyses (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  job_id          UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
  score           INT  NOT NULL CHECK (score BETWEEN 0 AND 100),
  reasons         JSONB NOT NULL DEFAULT '[]'::jsonb,
  model_used      TEXT NOT NULL,
  prompt_version  TEXT NOT NULL DEFAULT 'v1',
  -- SHA-256 hex das prefs+gamification_data relevantes. Quando muda, cache stale.
  profile_hash    TEXT NOT NULL,
  computed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT match_analyses_user_job_uniq UNIQUE (user_id, job_id)
);

CREATE INDEX IF NOT EXISTS idx_match_analyses_user
  ON public.match_analyses(user_id);

CREATE INDEX IF NOT EXISTS idx_match_analyses_user_hash
  ON public.match_analyses(user_id, profile_hash);

-- ============================================================================
-- 3. RLS: usuário só lê/escreve as próprias análises
-- ============================================================================

ALTER TABLE public.match_analyses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user reads own matches"
  ON public.match_analyses FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "user inserts own matches"
  ON public.match_analyses FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user updates own matches"
  ON public.match_analyses FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "user deletes own matches"
  ON public.match_analyses FOR DELETE
  USING (auth.uid() = user_id);

COMMIT;
