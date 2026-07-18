-- Fase 2 original (Assistente assume a terceira aba): gate estrutural da
-- conversa assistida, do header compacto e da casa única do currículo geral.
--
-- Nasce OFF/0% e depende também de `trilha_coleta_v1`. O rollout só pode
-- avançar 10 -> 50 -> 100 depois da fundação transacional/CAS da Fase 3 e da
-- validação adversarial de concorrência; a coorte efetiva sempre é a
-- interseção com o gate pai. O kill-switch é
-- `enabled=false` e passa a valer quando o app atualizar o cache de flags
-- (normalmente no próximo cold start).
--
-- ON CONFLICT preserva uma decisão operacional preexistente e torna a seed
-- idempotente. Esta migration não ativa nem altera rollout remoto.

BEGIN;

INSERT INTO public.app_feature_flags (
  feature_key,
  enabled,
  rollout_pct,
  description
)
VALUES (
  'trilha_assist_v1',
  false,
  0,
  'Assistente na terceira aba, aninhado em trilha_coleta_v1. OFF = conversa/preview legado. Rollout somente após writers transacionais/CAS da Fase 3.'
)
ON CONFLICT (feature_key) DO NOTHING;

COMMIT;
