-- Migration: tabela app_config para force-update gate
--
-- Singleton (id=1). O app lê min_supported_version no startup e bloqueia o
-- usuário se a versão instalada for menor. latest_version é informativo (pode
-- ser usado no futuro pra "soft prompt"). URLs ficam na config pra não precisar
-- rebuildar quando o link da loja mudar.
--
-- Versão segue o formato semver simples "MAJOR.MINOR.PATCH" (mesmo que o
-- pubspec.yaml, sem o build number depois do +). Comparação é numérica por
-- componente, feita no cliente.

BEGIN;

CREATE TABLE IF NOT EXISTS public.app_config (
  id INT PRIMARY KEY DEFAULT 1,
  min_supported_version TEXT NOT NULL DEFAULT '1.0.0',
  latest_version TEXT NOT NULL DEFAULT '1.0.0',
  update_message TEXT,
  ios_store_url TEXT,
  android_store_url TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT app_config_singleton CHECK (id = 1)
);

-- Seed row inicial. Ajustar min_supported_version manualmente no Supabase
-- quando subir build crítica que precisa de força.
INSERT INTO public.app_config (id, min_supported_version, latest_version, ios_store_url, android_store_url)
VALUES (
  1,
  '1.0.0',
  '1.1.0',
  'https://apps.apple.com/app/id0000000000',
  'https://play.google.com/store/apps/details?id=com.example.career_gamification'
)
ON CONFLICT (id) DO NOTHING;

-- RLS: leitura pública (qualquer um pode consultar a config), escrita só via
-- service_role (painel do Supabase).
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app_config read" ON public.app_config;
CREATE POLICY "app_config read"
  ON public.app_config
  FOR SELECT
  USING (true);

COMMIT;
