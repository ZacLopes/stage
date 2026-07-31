-- Interruptor de emergência da porta de import de CV em Perfil → Currículos.
--
-- ⚠️ FLAG NEGATIVA — a única do repo. Leia antes de mexer.
--
--   enabled=true  + rollout_pct=100  ⇒  a porta SOME
--   enabled=false (ou linha ausente) ⇒  a porta APARECE
--
-- A inversão é deliberada. Toda flag do app é failure-CLOSED: quando o cold
-- start não tem rede, `FeatureFlagsService.refresh()` engole a exceção
-- (main.dart:150-152), o cache fica vazio e o recurso some. Isso é seguro para
-- feature nova — e é exatamente o defeito aqui, porque a porta de import não é
-- feature nova: a build publicada (2.4.0+7, commit 37edebc) tinha esse botão na
-- 3ª aba sem flag nenhuma. O estado "escondido" É a regressão que esta fatia
-- conserta; com semântica positiva, qualquer abertura sem rede a recriaria.
--
-- Por que a porta sumiu, para quem for auditar isto depois: o card de import
-- saiu da 3ª aba quando ela virou o Assistente; o clipe 📎 do chat só renderiza
-- em `ChatPhase.gate`, e o gate só acontece com o perfil totalmente vazio; e o
-- substituto em Perfil → Dados está atrás de `trilha_assist_v1`, OFF em prod.
-- Medido em 31/07/2026: 1.550 usuários com perfil preenchido ficaram sem
-- caminho — 681 que já tinham importado e 869 que nunca conseguiram nem a
-- primeira vez.
--
-- O CLIENTE FUNCIONA SEM ESTA LINHA. Ela não liga nada: nasce inerte, só para
-- existir o botão de pânico. Desvio consciente da R4 (rollout 10→50→100),
-- chancelado pelo fundador em 31/07: não é feature nova, é restauração — e um
-- rollout gradual manteria 90% da base sem porta por mais alguns dias.
--
-- ON CONFLICT preserva decisão operacional preexistente e torna a seed
-- idempotente.

BEGIN;

INSERT INTO public.app_feature_flags (
  feature_key,
  enabled,
  rollout_pct,
  description
)
VALUES (
  'cv_import_entry_disabled',
  false,
  0,
  'NEGATIVA: true+100% ESCONDE a porta de importar CV em Perfil -> Curriculos. '
  'Ausente/false = porta visivel (failure-open deliberado). Interruptor de '
  'emergencia; nao e rollout.'
)
ON CONFLICT (feature_key) DO NOTHING;

COMMIT;
