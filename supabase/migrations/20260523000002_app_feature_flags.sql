-- Migration: app_feature_flags
--
-- Semana 3 — Bloco F.1: feature flags granulares pra rollout das versões v2
-- (templates v2, adapt v2, match v2).
--
-- Por que tabela própria e NÃO PostHog:
--   PostHog mostrou comportamento async-frágil na Semana 2 — flag
--   `new_onboarding_enabled` não retornava true confiavelmente por causa
--   do cache async, forçando bypass hardcoded. Pra controlar rollout de
--   features CRÍTICAS (PDF/adapt/match), o failure mode "flag não carregou
--   ainda → fica em v1" silenciosamente atrasa rollout e contamina
--   métricas de comparação v1 vs v2.
--
-- Resolução: tabela direta no Supabase + leitura síncrona pelo client
-- com cache cold-start. Hash determinístico de user_id pra rollout
-- percentual (consistente entre sessões).
--
-- RLS: leitura pública (qualquer authenticated). Escrita apenas via
-- service_role (admin/console).

BEGIN;

CREATE TABLE IF NOT EXISTS public.app_feature_flags (
  feature_key  TEXT PRIMARY KEY,
  enabled      BOOLEAN NOT NULL DEFAULT false,
  rollout_pct  INTEGER NOT NULL DEFAULT 0 CHECK (rollout_pct BETWEEN 0 AND 100),
  description  TEXT,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.app_feature_flags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app_feature_flags read all" ON public.app_feature_flags;
CREATE POLICY "app_feature_flags read all"
  ON public.app_feature_flags
  FOR SELECT
  TO authenticated
  USING (true);

-- Seed dos 3 flags da Semana 3, todos OFF.
-- Founder ajusta via Supabase Studio quando decidir avançar rollout.
INSERT INTO public.app_feature_flags (feature_key, enabled, rollout_pct, description)
VALUES
  ('templates_v2_enabled', false, 0, 'PDF templates lêem schema profile_* relacional via JOIN. Fallback automático pro v1 se perfil vazio.'),
  ('adapt_v2_enabled',     false, 0, 'adapt-resume-to-job v2 recebe user_id + lê schema relacional. Output inclui _source_bullet_id + _action por bullet.'),
  ('match_v2_enabled',     false, 0, 'analyze-match v2 usa profile_skills/profile_personal.summary. Fallback raw_text só se skills+summary+experiences todos vazios.')
ON CONFLICT (feature_key) DO NOTHING;

-- Trigger pra manter updated_at em sync (manual UPDATE no Studio bate aqui).
CREATE OR REPLACE FUNCTION public.touch_app_feature_flags_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_app_feature_flags_updated_at ON public.app_feature_flags;
CREATE TRIGGER trg_app_feature_flags_updated_at
  BEFORE UPDATE ON public.app_feature_flags
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_app_feature_flags_updated_at();

COMMIT;
