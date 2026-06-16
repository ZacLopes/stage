-- FASE 3 (T3.1/T3.2/T3.3 seed, PLANO-FASE-3 §5/PR4): flag estrutural da aba
-- Candidaturas + prompt de retorno + adição manual. Nasce OFF/0% (R4) —
-- comportamento ZERO até a release 2.5.0 existir E o fundador decidir o rollout
-- (10→50→100%). Flag OFF = aba Salvas atual (3 buckets) intocada; o prompt de
-- retorno e o FAB de adição manual também ficam OFF. Aceite de ≥30% de resposta
-- ao prompt conta a partir da ATIVAÇÃO desta flag, não da release.
-- Kill switch: UPDATE enabled=false (leitura client failure-safe → false).
insert into public.app_feature_flags (feature_key, enabled, rollout_pct, description)
values ('applications_tracker_v1', false, 0,
        'Aba Candidaturas (4 segmentos sobre applications) + prompt de retorno pós-apply + adição manual. OFF = aba Salvas atual. Rollout decidido pelo fundador pós-2.5.0.')
on conflict (feature_key) do nothing;
