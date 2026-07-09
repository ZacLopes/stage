-- Migration: profile_job_preferences — fit cultural
--
-- 3 preferências culturais coletadas na trilha (seção fit): tipo de empresa que
-- a pessoa busca, jeito do dia a dia (metas definidas ↔ dinâmico) e estilo de
-- trabalho (autonomia ↔ colaboração). Valor único = id da opção escolhida.
-- Aditivas e NULLABLE — perfis legados/import ficam com NULL; o client só grava
-- pela trilha (atrás da flag trilha_coleta_v1). Espelha desired_position.

BEGIN;

ALTER TABLE public.profile_job_preferences
  ADD COLUMN IF NOT EXISTS company_stage     TEXT,
  ADD COLUMN IF NOT EXISTS work_environment  TEXT,
  ADD COLUMN IF NOT EXISTS work_style        TEXT;

COMMENT ON COLUMN public.profile_job_preferences.company_stage IS
  'Fit cultural (trilha): tipo de empresa buscada — startup/scaleup/established/open. NULL p/ legado.';
COMMENT ON COLUMN public.profile_job_preferences.work_environment IS
  'Fit cultural (trilha): jeito do dia a dia — structured/dynamic/balanced. NULL p/ legado.';
COMMENT ON COLUMN public.profile_job_preferences.work_style IS
  'Fit cultural (trilha): estilo de trabalho — autonomy/collaboration/flexible. NULL p/ legado.';

COMMIT;
