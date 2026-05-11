-- Migration: desativa external_job_sources que falharam no sync (slug inválido
-- ou empresa usa outro ATS). Mantidas na tabela com is_active=false pra:
--   (a) tentar redescobrir no futuro com slug corrigido;
--   (b) servir de "log" do que já testamos.
--
-- Identificadas via run manual do sync-jobs-ats em 2026-05-11: as 17 abaixo
-- retornaram erro (HTTP 404 ou inválido) no board público.

BEGIN;

UPDATE public.external_job_sources
SET is_active = false,
    last_sync_error = 'slug inválido ou board público inexistente (run manual 2026-05-11)'
WHERE (ats, company_slug) IN (
  ('greenhouse', 'canva'),
  ('greenhouse', 'plaid'),
  ('greenhouse', 'ramp'),
  ('greenhouse', 'revolut'),
  ('greenhouse', 'shopify'),
  ('greenhouse', 'snyk'),
  ('greenhouse', 'wise'),
  ('greenhouse', 'creditas'),
  ('greenhouse', 'hotmart'),
  ('greenhouse', 'notion'),
  ('greenhouse', 'linear'),
  ('greenhouse', 'retool'),
  ('lever', 'mercadolibre'),
  ('lever', 'duolingo'),
  ('lever', 'digitalocean'),
  ('lever', 'segment'),
  ('lever', 'instacart')
);

COMMIT;
