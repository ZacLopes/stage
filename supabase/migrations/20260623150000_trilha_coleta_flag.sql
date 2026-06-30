-- Migration: trilha_coleta_flag
--
-- PLANO-FASE-6 T6.3 (Increment 5a): flag estrutural que liga o card
-- "Completar com a IA" no hub do Perfil (abre a trilha de coleta conversacional).
--
-- Default OFF (rollout_pct 0) → card escondido pra todo mundo; failure-safe
-- (flag ausente/não-carregada ⇒ escondido). Rollout gradual 10→50→100 decidido
-- pelo fundador. Hash determinístico de user_id (isEnabledForUser) dá rollout
-- percentual estável entre sessões.
--
-- R2: migration via CLI (`supabase db push`) + manifest; nunca pelo dashboard.
-- R4: comportamento atrás de flag estrutural (app_feature_flags).

BEGIN;

INSERT INTO public.app_feature_flags (feature_key, enabled, rollout_pct, description)
VALUES (
  'trilha_coleta_v1',
  false,
  0,
  'Card "Completar com a IA" no hub do Perfil -> trilha de coleta conversacional (skills, experiencia, prefs, idiomas). Default OFF; rollout 10->50->100.'
)
ON CONFLICT (feature_key) DO NOTHING;

COMMIT;
