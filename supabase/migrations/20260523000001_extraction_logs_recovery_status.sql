-- Migration: extraction logs recovery support
--
-- Semana 3 — Bloco A: reprocessamento de partial failures do backfill.
--
-- Mudanças:
--   1. Expande `status` CHECK pra incluir:
--      - 'recovered'     : log antigo que foi reprocessado com sucesso
--                          (save_profile_from_json ou re-call extract-profile)
--      - 'unrecoverable' : reprocesso tentou e falhou (ex: raw_text faltando,
--                          OpenAI continua 429, JSON inválido persistente)
--      - 'log_only'      : log antigo de tentativa que falhou MAS o user já
--                          tem perfil estruturado completo no banco — não
--                          precisa reprocessar, é só ruído de log
--   2. Adiciona `recovery_attempted_at` pra auditoria — evita re-rodar
--      script de recovery múltiplas vezes em cima do mesmo log.
--
-- Idempotente. Não muda dados existentes.

BEGIN;

ALTER TABLE public.profile_extraction_logs
  DROP CONSTRAINT IF EXISTS profile_extraction_logs_status_check;

ALTER TABLE public.profile_extraction_logs
  ADD CONSTRAINT profile_extraction_logs_status_check
  CHECK (status IN (
    'success',
    'partial',
    'failed',
    'recovered',
    'unrecoverable',
    'log_only'
  ));

ALTER TABLE public.profile_extraction_logs
  ADD COLUMN IF NOT EXISTS recovery_attempted_at TIMESTAMPTZ;

-- Índice parcial pra script de recovery skipar logs já processados.
CREATE INDEX IF NOT EXISTS idx_profile_extraction_logs_recovery
  ON public.profile_extraction_logs (status, recovery_attempted_at)
  WHERE status IN ('failed', 'partial');

COMMIT;
