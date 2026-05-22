-- Migration: profile_extraction_logs
--
-- Logs específicos da edge function extract-profile, complementando
-- ai_generation_logs (que tem o panorama de LLM observability — tokens,
-- modelo, custo). Aqui ficam só os campos próprios do extrator:
--   - raw_json_output: o JSON estruturado pra debug de regressão
--   - raw_text_input_hash: SHA-256 do raw_text pra detectar reprocessamento
--   - confidence_global + low_confidence_fields: qualidade da extração
--   - status: success / partial / failed (matriz de observabilidade no
--     docs/profile_architecture.md)
--
-- FK ai_generation_log_id liga ao log de LLM correspondente; ON DELETE
-- SET NULL pra preservar o histórico de extração mesmo se o log de LLM
-- for purgado (retenção pode divergir).
--
-- RLS habilitada SEM POLICIES DE SELECT — debug de extração contém PII
-- (raw_json_output). Acesso só via service_role (edge functions admin).

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_extraction_logs (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  ai_generation_log_id  UUID REFERENCES public.ai_generation_logs(id) ON DELETE SET NULL,
  confidence_global     NUMERIC(3,2) CHECK (confidence_global IS NULL OR confidence_global BETWEEN 0 AND 1),
  low_confidence_fields JSONB,
  raw_json_output       JSONB,
  raw_text_input_hash   TEXT,
  status                TEXT NOT NULL CHECK (status IN ('success','partial','failed')),
  error_message         TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profile_extraction_logs_user
  ON public.profile_extraction_logs (user_id, created_at DESC);

-- Índice parcial: queries operacionais filtram pra status != 'success'
-- ao monitorar saúde do extrator (raro = pequeno = rápido).
CREATE INDEX IF NOT EXISTS idx_profile_extraction_logs_status
  ON public.profile_extraction_logs (status)
  WHERE status != 'success';

-- Índice parcial: monitora extrações com baixa confiança pra ajustar
-- prompt (também raro = pequeno = rápido).
CREATE INDEX IF NOT EXISTS idx_profile_extraction_logs_low_confidence
  ON public.profile_extraction_logs (confidence_global)
  WHERE confidence_global IS NOT NULL AND confidence_global < 0.7;

ALTER TABLE public.profile_extraction_logs ENABLE ROW LEVEL SECURITY;

-- DELIBERADAMENTE SEM POLICIES — só service_role acessa.

COMMIT;
