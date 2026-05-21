-- Distingue a origem de cada currículo salvo na biblioteca:
--   'manual'   → criado/editado no app pelo usuário (default).
--   'imported' → veio do PDF que o user fez upload (cv_import_service).
--   'adapted'  → gerado pela adaptação por IA pra uma vaga específica.
--
-- Usado pela UI da biblioteca pra colorir/agrupar/filtrar entradas e
-- pra evitar dependência de heurística sobre o título (frágil).
-- NULL não é permitido — default 'manual' cobre linhas legadas.

ALTER TABLE saved_resumes
  ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'manual';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'saved_resumes_source_check'
      AND table_name = 'saved_resumes'
  ) THEN
    ALTER TABLE saved_resumes
      ADD CONSTRAINT saved_resumes_source_check
      CHECK (source IN ('manual', 'imported', 'adapted'));
  END IF;
END $$;

COMMENT ON COLUMN saved_resumes.source IS
  'Origem do currículo: manual (criado no app), imported (PDF upload), adapted (gerado por IA).';

-- Backfill: títulos que começam com "Meu Currículo" historicamente são
-- imports (kImportedResumeBaseTitle em cv_import_service.dart).
UPDATE saved_resumes
SET source = 'imported'
WHERE source = 'manual'
  AND title LIKE 'Meu Currículo%';
