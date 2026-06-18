-- Adiciona o ATS `inhire` (API pública api.inhire.app) como fonte de vagas.
--
-- InHire é um ATS brasileiro com endpoint público documentado que entrega vaga
-- net-new (baixo overlap com Gupy/Greenhouse/Lever). Adapter em
-- supabase/functions/sync-jobs-ats/sources/inhire.ts; pega carona no MESMO
-- orquestrador/cron que os outros ATS.
--
-- `company_slug` = o tenant (subdomínio). A vaga pública vive em
-- https://{tenant}.inhire.app/vagas/{jobId}. Postgres não permite ALTER em
-- CHECK, então DROP + ADD (mesmo padrão da 20260520000000_external_jobs_more_ats).
--
-- Tenants do seed: validados ao vivo em 18/06/2026 (volume entry-level BR > 0
-- medido via /job-posts/public/pages). Descoberta de novos tenants é a alavanca
-- de crescimento — cada tenant novo é só mais uma linha aqui.

BEGIN;

ALTER TABLE public.external_job_sources
  DROP CONSTRAINT IF EXISTS external_job_sources_ats_check;

ALTER TABLE public.external_job_sources
  ADD CONSTRAINT external_job_sources_ats_check
  CHECK (ats IN (
    'greenhouse',
    'lever',
    'ashby',
    'workable',
    'recruitee',
    'smartrecruiters',
    'teamtailor',
    'inhire'
  ));

INSERT INTO public.external_job_sources (ats, company_slug, display_name) VALUES
  ('inhire', 'db1',       'DB1 Group'),
  ('inhire', 'alice',     'Alice'),
  ('inhire', 'tera',      'Tera'),
  ('inhire', 'v360',      'V360'),
  ('inhire', 'priner',    'Priner'),
  ('inhire', 'hand',      'Hand'),
  ('inhire', 'solutis',   'Solutis'),
  ('inhire', 'mazzatech', 'MazzaTech')
ON CONFLICT (ats, company_slug) DO NOTHING;

COMMIT;
