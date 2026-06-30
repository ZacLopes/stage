-- Remoção reversível da trilha gamificada (estilo Duolingo) da aba Currículo.
-- Nasce OFF/0% → o card "Construir pela trilha" some da aba Currículo (fica só
-- "Importar CV") e o passo equivalente do tutorial é pulado. O código da trilha
-- continua no app (congelado, R6); só o entry point da aba Currículo é gateado.
-- A trilha no ONBOARDING (TwoDoorsScreen) NÃO é afetada — continua disponível
-- pra quem não tem CV.
--
-- Leitura client é binária (isGloballyEnabled): só conta como ON com
-- enabled=true E rollout_pct=100. Failure-safe → false (trilha escondida).
--
-- Voltar a trilha (sem rebuild, na hora, pra todos):
--   UPDATE public.app_feature_flags
--      SET enabled = true, rollout_pct = 100
--    WHERE feature_key = 'resume_trail_enabled';
insert into public.app_feature_flags (feature_key, enabled, rollout_pct, description)
values ('resume_trail_enabled', false, 0,
        'Card "Construir pela trilha" na aba Currículo. OFF = escondido (só Importar CV). Onboarding não afetado. Ligar (enabled=true, 100%) traz a trilha de volta sem rebuild.')
on conflict (feature_key) do nothing;
