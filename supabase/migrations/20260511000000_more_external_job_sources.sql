-- Migration: expande empresas em external_job_sources
--
-- Adiciona ~25 empresas curadas (Greenhouse + Lever) com presença BR ou
-- contratação global em PT. Foco: tech, fintech, design, marketing.
--
-- Critério de seleção: empresas que SABEMOS existir no ATS público
-- (verificado mentalmente). Cada slug abre uma URL pública:
--   Greenhouse: https://boards.greenhouse.io/<slug>
--   Lever:      https://jobs.lever.co/<slug>
--
-- Se alguma empresa do INSERT abaixo não existir mais no ATS público,
-- o sync-jobs-ats vai logar o erro mas seguir com as outras (try/catch
-- isolado por empresa).

BEGIN;

INSERT INTO public.external_job_sources (ats, company_slug, display_name) VALUES
  -- ── Greenhouse: tech global com hire BR confirmado ──────────────────────
  ('greenhouse', 'canva',         'Canva'),
  ('greenhouse', 'discord',       'Discord'),
  ('greenhouse', 'elastic',       'Elastic'),
  ('greenhouse', 'intercom',      'Intercom'),
  ('greenhouse', 'newrelic',      'New Relic'),
  ('greenhouse', 'plaid',         'Plaid'),
  ('greenhouse', 'ramp',          'Ramp'),
  ('greenhouse', 'revolut',       'Revolut'),
  ('greenhouse', 'shopify',       'Shopify'),
  ('greenhouse', 'snyk',          'Snyk'),
  ('greenhouse', 'vercel',        'Vercel'),
  ('greenhouse', 'wise',          'Wise'),
  ('greenhouse', 'okta',          'Okta'),
  ('greenhouse', 'doordashusa',   'DoorDash'),

  -- ── Greenhouse: BR fintech / tech ──────────────────────────────────────
  ('greenhouse', 'creditas',      'Creditas'),
  ('greenhouse', 'hotmart',       'Hotmart'),

  -- ── Lever: tech global / BR ─────────────────────────────────────────────
  ('lever',      'mercadolibre',  'Mercado Livre'),
  ('lever',      'duolingo',      'Duolingo'),
  ('lever',      'digitalocean',  'DigitalOcean'),
  ('lever',      'segment',       'Segment'),
  ('lever',      'instacart',     'Instacart'),

  -- ── Greenhouse: design / marketing / produto ───────────────────────────
  ('greenhouse', 'figma',         'Figma'),
  ('greenhouse', 'notion',        'Notion'),
  ('greenhouse', 'linear',        'Linear'),
  ('greenhouse', 'retool',        'Retool')
ON CONFLICT (ats, company_slug) DO NOTHING;

COMMIT;
