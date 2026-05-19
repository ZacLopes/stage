-- Expande o CHECK constraint de `external_job_sources.ats` para suportar os
-- 5 novos ATS além de greenhouse/lever: ashby, workable, recruitee,
-- smartrecruiters, teamtailor. Cada um será seedado em migration própria
-- (20260520000001_seed_ashby_companies.sql, etc) após validação manual via curl.
--
-- Postgres não permite ALTER CONSTRAINT em CHECK, então faz DROP + ADD.

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
    'teamtailor'
  ));

COMMIT;
