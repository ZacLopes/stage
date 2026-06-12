-- FASE 2 (T2.2 seed, PLANO-FASE-2 §6/PR1): flag estrutural do feed novo.
-- Nasce OFF/0% (R4) — comportamento ZERO até a release 2.4.0 existir E o
-- fundador decidir o momento do rollout (10→50→100%, degraus de 3-4 dias,
-- gatilho: zero regressão crash/feed_load_failed + save-rate estável).
-- Kill switch global: UPDATE enabled=false (leitura failure-safe → false).
insert into public.app_feature_flags (feature_key, enabled, rollout_pct, description)
values ('feed_list_v1', false, 0,
        'Feed server-side via RPC get_feed_page (lista + swipe por snapshot). OFF = caminho legacy intocado (rollback). Rollout decidido pelo fundador pós-aceitação da 2.4.0.')
on conflict (feature_key) do nothing;
