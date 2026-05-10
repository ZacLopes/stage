-- Migration: adapted_resumes
--
-- Cache server-side da feature "adaptar currículo pra vaga".
-- Cada (user, job) tem no máximo 1 versão adaptada. Cache invalida quando o
-- usuário edita perfil ou currículo (via source_hash).
--
-- Custo: ~$0.001-0.003 por adaptação (gpt-4o-mini). Cache hit = 0.

BEGIN;

CREATE TABLE IF NOT EXISTS public.adapted_resumes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  job_id UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,

  -- Lista de mudanças explicáveis: [{field, label, before, after, reason}]
  changes JSONB NOT NULL,

  -- Currículo adaptado completo (mesmo schema que ResumeData no client).
  -- Nome/email/telefone/empresas/datas batem 100% com o input — validado
  -- server-side antes de salvar.
  resume_data JSONB NOT NULL,

  -- Score de match antes/depois da adaptação (motivacional pro user).
  match_score_before INT,
  match_score_after INT,

  -- SHA-256 dos dados de input do user (perfil + CV + dados imutáveis da
  -- vaga). Se mudar, regera. Mesma estratégia que match_analyses.
  source_hash TEXT NOT NULL,
  prompt_version TEXT NOT NULL,
  model_used TEXT NOT NULL,

  computed_at TIMESTAMPTZ DEFAULT now(),

  UNIQUE (user_id, job_id)
);

CREATE INDEX IF NOT EXISTS adapted_resumes_user_idx
  ON public.adapted_resumes (user_id, computed_at DESC);

ALTER TABLE public.adapted_resumes ENABLE ROW LEVEL SECURITY;

-- Users veem só os próprios.
CREATE POLICY "users_read_own_adapted_resumes"
  ON public.adapted_resumes FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Users podem deletar (caso queiram regenerar manualmente).
CREATE POLICY "users_delete_own_adapted_resumes"
  ON public.adapted_resumes FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- Insert/update: APENAS via service_role (edge function), pra garantir que
-- o validador anti-invenção sempre rode.
CREATE POLICY "service_role_writes_adapted_resumes"
  ON public.adapted_resumes FOR INSERT
  WITH CHECK (false);

CREATE POLICY "service_role_updates_adapted_resumes"
  ON public.adapted_resumes FOR UPDATE
  USING (false);

COMMIT;
