-- Alinha valores aceitos em profile_job_preferences.job_types com a
-- taxonomia já usada pela feature de Vagas (job.jobTypeRaw + filtros
-- em job_preferences_screen).
--
-- Antes: 'full_time', 'internship', 'contract', 'part_time' (LinkedIn-like,
--        genérico, descolado da audiência entry-level do Stage).
-- Depois: 'estagio', 'trainee', 'clt_junior', 'temporario' (entry-level BR,
--         match natural com vagas sincronizadas).
--
-- Migração segura: 0 linhas hoje têm job_types preenchido (checked via SQL
-- antes), então não precisa migrar dados.

BEGIN;

ALTER TABLE public.profile_job_preferences
  DROP CONSTRAINT IF EXISTS profile_job_preferences_job_types_check;

ALTER TABLE public.profile_job_preferences
  ADD CONSTRAINT profile_job_preferences_job_types_check
  CHECK (
    job_types IS NULL
    OR job_types <@ ARRAY['estagio','trainee','clt_junior','temporario']::TEXT[]
  );

COMMIT;
