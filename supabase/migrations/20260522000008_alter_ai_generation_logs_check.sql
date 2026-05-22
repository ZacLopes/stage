-- Migration: alter ai_generation_logs CHECK pra aceitar 'profile_extraction'
--
-- Migration isolada (separada da criação de profile_extraction_logs) pra
-- facilitar revisão e rollback. Segue o padrão de 20260516000000_jobs_skill_extraction.sql:
-- DROP CONSTRAINT IF EXISTS + ADD CONSTRAINT com lista expandida.
--
-- Lista expandida com 'profile_extraction' (extract-profile edge function).
-- Mantemos todos os tipos existentes pra não quebrar nada que já loga.

BEGIN;

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
    'skill_extraction',
    'profile_extraction'
  ));

COMMIT;
