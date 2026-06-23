-- Migration: legacy_completion_screen_flag
--
-- BUGFIX (perfis ocos / thin profiles): o AuthGate (splash_screen.dart) caía,
-- como fallback pós-login, na CompletionScreen legacy. A opção "Começar do
-- zero" dela chamava markOnboardingCompleted() SEM coletar nada — e o fallback
-- era atingido por quem tinha user_profiles legacy completo
-- (needsProfileSetup=false) mas profile_personal vazio (isInProfileFirstFlow=
-- false). Medição: 473/800 perfis ocos (59%) batiam exatamente essa condição.
--
-- O fix roteia o fallback pro onboarding que COLETA (TwoDoorsScreen). Este flag
-- é só um KILL-SWITCH pra restaurar a CompletionScreen em caso de regressão de
-- roteamento. Default OFF ⇒ fix ligado (failure-safe: flag ausente/off ⇒
-- TwoDoorsScreen, nunca a tela data-less). Ligar = enabled + rollout_pct=100.
--
-- R2: migration via CLI (`supabase db push`) + manifest. NÃO aplicar pelo
-- dashboard. R4: comportamento atrás de flag estrutural (app_feature_flags).

BEGIN;

INSERT INTO public.app_feature_flags (feature_key, enabled, rollout_pct, description)
VALUES (
  'legacy_completion_screen_enabled',
  false,
  0,
  'KILL-SWITCH: restaura a CompletionScreen legacy como fallback pós-login. Default OFF = fallback vai pro onboarding que coleta (TwoDoorsScreen). Ligar (true,100) só pra rollback de emergencia do fix dos perfis ocos.'
)
ON CONFLICT (feature_key) DO NOTHING;

COMMIT;
