-- Taxonomia de skills (P5, Fase C): flag estrutural do typeahead canônico no
-- editor de skills. Nasce OFF/0% (R4) — comportamento ZERO até a próxima release
-- existir E o fundador decidir o rollout (10→50→100%). OFF = input texto-livre
-- atual do EditListModal. O trigger no banco já normaliza canonical_skill_id em
-- todo write (qualquer client), então o dado fica canônico mesmo com a flag OFF;
-- o typeahead só guia o usuário a escolher a canônica (reduz nova fragmentação).
-- Kill switch: UPDATE enabled=false (leitura client failure-safe → false).
insert into public.app_feature_flags (feature_key, enabled, rollout_pct, description)
values ('skills_typeahead_v1', false, 0,
        'Typeahead canônico (skills_catalog) no editor de skills. OFF = input texto-livre. Rollout pós-release decidido pelo fundador.')
on conflict (feature_key) do nothing;
