-- F7 da reformulação da adaptação de CV: adiciona quality_score (0-100)
-- em adapted_resumes pra ranquear adaptações por qualidade objetiva.
-- Cálculo no edge function adapt-resume-to-job; populado no upsert.
--
-- Fórmula (0-100, soma de 5 fatores):
--   30 pts: campos preservados (name/email/phone/linkedin/location/#exp/#edu)
--   20 pts: zero retries do validador (1 retry = 10 pts, 2 = 0)
--   20 pts: Jaccard de bigrams entre summary adaptado e CV original
--   15 pts: % requisitos da vaga presentes no CV adaptado
--   15 pts: inverso histórico de cv_adaptation_user_edited (default 15)
--
-- NULL = ainda não foi calculado (linhas legadas). Próximo retry/refresh
-- recalcula. Não retroage automaticamente.

ALTER TABLE adapted_resumes
  ADD COLUMN IF NOT EXISTS quality_score smallint;

COMMENT ON COLUMN adapted_resumes.quality_score IS
  '0-100 score de qualidade da adaptação. Calculado no edge function adapt-resume-to-job (F7). NULL = linhas pré-F7.';

-- Índice parcial pra dashboard de adaptações de baixa qualidade (alert).
CREATE INDEX IF NOT EXISTS idx_adapted_resumes_low_quality
  ON adapted_resumes (computed_at DESC)
  WHERE quality_score IS NOT NULL AND quality_score < 70;
