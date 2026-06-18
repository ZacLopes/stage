-- Mais 8 tenants InHire (descoberta de tenant — alavanca de crescimento da fonte
-- `inhire`, ver 20260618184100_inhire_source.sql). Validados ao vivo em 18/06/2026
-- via /job-posts/public/pages: todos com volume entry-level BR > 0.
--
-- (V4 Company foi avaliada e DEIXADA DE FORA: ~213 vagas, mas ~55 cargos repetidos
-- em dezenas de franquias — quase-duplicatas que flodariam o feed. Reavaliar depois
-- com limite por cargo se quiser o volume.)
--
-- CHECK de external_job_sources.ats já inclui 'inhire'; aqui só o seed.

BEGIN;

INSERT INTO public.external_job_sources (ats, company_slug, display_name) VALUES
  ('inhire', 'seuestagio',          'Seu Estágio'),
  ('inhire', 'deloitte',            'Deloitte'),
  ('inhire', 'mottu',               'Mottu'),
  ('inhire', 'qitech',              'QI Tech'),
  ('inhire', 'radix',               'Radix'),
  ('inhire', 'venturus',            'Venturus'),
  ('inhire', 'pedraagroindustrial', 'Pedra Agroindustrial'),
  ('inhire', 'appmax',              'Appmax')
ON CONFLICT (ats, company_slug) DO NOTHING;

COMMIT;
