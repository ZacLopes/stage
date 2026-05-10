-- Migration: Setup pra ingestão de vagas externas (Apify Gupy + Greenhouse + Lever)
--
-- Adiciona campos de sourcing em jobs/companies, cria tabela de mapeamento
-- de boards públicos (Greenhouse/Lever), e seed inicial das empresas.

BEGIN;

-- ============================================================================
-- 1. Campos de sourcing externo em jobs
-- ============================================================================

ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS source TEXT,
  ADD COLUMN IF NOT EXISTS external_id TEXT,
  ADD COLUMN IF NOT EXISTS external_url TEXT,
  ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS raw_payload JSONB;

-- Dedup: dois jobs com mesmo (source, external_id) é o mesmo job. Permite
-- mesmo external_id em fontes diferentes (ex: Gupy + Greenhouse).
CREATE UNIQUE INDEX IF NOT EXISTS jobs_source_external_id_uniq
  ON public.jobs (source, external_id)
  WHERE source IS NOT NULL;

-- Index pra otimizar query do "mark stale"
CREATE INDEX IF NOT EXISTS jobs_source_last_seen_idx
  ON public.jobs (source, last_seen_at)
  WHERE source IS NOT NULL;

-- ============================================================================
-- 2. Slug + source em companies (pra dedup entre múltiplos sources)
-- ============================================================================

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS slug TEXT,
  ADD COLUMN IF NOT EXISTS source TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS companies_slug_uniq
  ON public.companies (slug)
  WHERE slug IS NOT NULL;

-- ============================================================================
-- 3. Tabela de mapeamento de boards públicos (Greenhouse + Lever)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.external_job_sources (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ats          TEXT NOT NULL CHECK (ats IN ('greenhouse', 'lever')),
  company_slug TEXT NOT NULL,         -- slug que vai na URL (ex: 'inter', 'mercadolivre')
  display_name TEXT NOT NULL,         -- nome amigável pra UI ('Inter')
  is_active    BOOLEAN NOT NULL DEFAULT TRUE,
  last_synced_at TIMESTAMPTZ,
  last_sync_error TEXT,               -- nullable; preenche se sync falhou
  created_at   TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT external_job_sources_unique UNIQUE (ats, company_slug)
);

ALTER TABLE public.external_job_sources ENABLE ROW LEVEL SECURITY;

-- Service role only — tabela de configuração interna, usuários não precisam ler
CREATE POLICY "Service role only on external_job_sources"
  ON public.external_job_sources FOR ALL
  USING (false);

-- ============================================================================
-- 4. Seed das empresas Greenhouse com presença BR confirmada (testadas ao vivo)
-- ============================================================================

INSERT INTO public.external_job_sources (ats, company_slug, display_name) VALUES
  ('greenhouse', 'inter',       'Inter'),
  ('greenhouse', 'c6bank',      'C6 Bank'),
  ('greenhouse', 'stone',       'Stone'),
  ('greenhouse', 'nubank',      'Nubank'),
  ('greenhouse', 'quintoandar', 'QuintoAndar'),
  ('greenhouse', 'gympass',     'Wellhub (Gympass)'),
  ('greenhouse', 'vtex',        'VTEX'),
  ('greenhouse', 'ebanx',       'EBANX'),
  ('greenhouse', 'airbnb',      'Airbnb'),
  ('greenhouse', 'datadog',     'Datadog'),
  ('greenhouse', 'mongodb',     'MongoDB'),
  ('greenhouse', 'twilio',      'Twilio'),
  ('greenhouse', 'pinterest',   'Pinterest'),
  ('greenhouse', 'picpay',      'PicPay'),
  ('greenhouse', 'cloudflare',  'Cloudflare'),
  ('greenhouse', 'gitlab',      'GitLab'),
  ('greenhouse', 'asana',       'Asana'),
  ('greenhouse', 'dropbox',     'Dropbox'),
  ('greenhouse', 'anthropic',   'Anthropic'),
  ('greenhouse', 'stripe',      'Stripe')
ON CONFLICT (ats, company_slug) DO NOTHING;

COMMIT;
