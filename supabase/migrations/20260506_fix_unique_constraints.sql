-- Fix: partial unique indexes não funcionam com ON CONFLICT.
-- Substitui pelos UNIQUE CONSTRAINT regulares.
-- (Em PostgreSQL, UNIQUE permite múltiplas linhas com NULL nas colunas envolvidas
--  por default — semântica NULLS DISTINCT — então não conflita com linhas legacy
--  sem source/slug.)

BEGIN;

-- ============================================================================
-- jobs: UNIQUE (source, external_id)
-- ============================================================================
DROP INDEX IF EXISTS public.jobs_source_external_id_uniq;

ALTER TABLE public.jobs
  DROP CONSTRAINT IF EXISTS jobs_source_external_id_key;

ALTER TABLE public.jobs
  ADD CONSTRAINT jobs_source_external_id_key UNIQUE (source, external_id);

-- ============================================================================
-- companies: UNIQUE (slug)
-- ============================================================================
DROP INDEX IF EXISTS public.companies_slug_uniq;

ALTER TABLE public.companies
  DROP CONSTRAINT IF EXISTS companies_slug_key;

ALTER TABLE public.companies
  ADD CONSTRAINT companies_slug_key UNIQUE (slug);

COMMIT;
