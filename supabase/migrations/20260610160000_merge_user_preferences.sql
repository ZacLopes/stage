-- Fase 1 T1.5 (D2) — merge ONE-SHOT user_preferences → fontes novas.
-- SEM ponte: a escrita legacy está morta desde 2026-05-27 (verificado em
-- plan mode: 0 writes/7d). Regra: a escolha NOVA do usuário vence — o legacy
-- só resgata quem nunca preencheu a fonte nova. IDEMPOTENTE (re-execução = 0).
--
-- Ganhos medidos no dry-run (2026-06-10): 19 users ganham áreas, 33 ganham
-- localização, 27 ganham work_mode, 21 ganham job_types.
-- min_salary (80 users) e min_match_score (34) MORREM conscientemente —
-- decisão do fundador de 27/05 já registrada no código (salário fora da
-- identidade; filtros são temporários/locais).
-- user_preferences fica como fóssil legível; revogação DIFERIDA (critério:
-- builds antigas <5%/2sem E zero bridge_activity na janela).

-- 0. O CHECK de source só permitia user_added/from_resume (descoberto no
--    push — ajuste previsto na decisão (b) da revisão: "a migration adiciona
--    ou o marcador cai"). Estende pra rastrear a origem do merge.
ALTER TABLE public.profile_desired_titles
  DROP CONSTRAINT profile_desired_titles_source_check;
ALTER TABLE public.profile_desired_titles
  ADD CONSTRAINT profile_desired_titles_source_check
  CHECK (source IS NULL OR source IN ('user_added','from_resume','legacy_merge'));

-- 1. areas[] → profile_desired_titles (o app lê desired_titles como áreas —
--    V2 do PLANO-FASE-1). Só users sem NENHUM desired_title.
INSERT INTO public.profile_desired_titles (user_id, title, source)
SELECT up.user_id, t.title, 'legacy_merge'
FROM public.user_preferences up, unnest(up.areas) AS t(title)
WHERE up.areas IS NOT NULL AND array_length(up.areas, 1) > 0
  AND NOT EXISTS (SELECT 1 FROM public.profile_desired_titles dt
                  WHERE dt.user_id = up.user_id);

-- 2. locations[1] → primary_location_city. Só quem não tem NENHUMA
--    localização na fonte nova (nem primary nem other_locations).
INSERT INTO public.profile_job_preferences (user_id, primary_location_city)
SELECT up.user_id, up.locations[1]
FROM public.user_preferences up
WHERE up.locations IS NOT NULL AND array_length(up.locations, 1) > 0
  AND NOT EXISTS (SELECT 1 FROM public.profile_other_locations ol
                  WHERE ol.user_id = up.user_id)
ON CONFLICT (user_id) DO UPDATE
  SET primary_location_city = EXCLUDED.primary_location_city
  WHERE profile_job_preferences.primary_location_city IS NULL;

-- 3. locations[2..] → profile_other_locations (mesmos users do passo 2:
--    primary veio do legacy e ainda não há other_locations).
INSERT INTO public.profile_other_locations (user_id, city)
SELECT up.user_id, t.city
FROM public.user_preferences up, unnest(up.locations[2:]) AS t(city)
WHERE up.locations IS NOT NULL AND array_length(up.locations, 1) > 1
  AND EXISTS (SELECT 1 FROM public.profile_job_preferences p
              WHERE p.user_id = up.user_id
                AND p.primary_location_city = up.locations[1])
  AND NOT EXISTS (SELECT 1 FROM public.profile_other_locations ol
                  WHERE ol.user_id = up.user_id);

-- 4. work_models[] PT → work_mode EN (tradução; vocabulário verificado:
--    remoto/hibrido/presencial → remote/hybrid/in_person). Só quem tem
--    work_mode vazio/null na fonte nova.
INSERT INTO public.profile_job_preferences (user_id, work_mode)
SELECT m.user_id, m.translated
FROM (
  SELECT up.user_id,
         array_agg(DISTINCT CASE v
           WHEN 'remoto' THEN 'remote'
           WHEN 'hibrido' THEN 'hybrid'
           WHEN 'presencial' THEN 'in_person'
           ELSE v END) AS translated
  FROM public.user_preferences up, unnest(up.work_models) AS v
  WHERE up.work_models IS NOT NULL AND array_length(up.work_models, 1) > 0
  GROUP BY up.user_id
) m
ON CONFLICT (user_id) DO UPDATE
  SET work_mode = EXCLUDED.work_mode
  WHERE profile_job_preferences.work_mode IS NULL
     OR array_length(profile_job_preferences.work_mode, 1) IS NULL;

-- 5. job_types[] → job_types (vocabulário idêntico — 0 conflitos no dry-run).
INSERT INTO public.profile_job_preferences (user_id, job_types)
SELECT up.user_id, up.job_types
FROM public.user_preferences up
WHERE up.job_types IS NOT NULL AND array_length(up.job_types, 1) > 0
ON CONFLICT (user_id) DO UPDATE
  SET job_types = EXCLUDED.job_types
  WHERE profile_job_preferences.job_types IS NULL
     OR array_length(profile_job_preferences.job_types, 1) IS NULL;

COMMENT ON TABLE public.user_preferences IS
  'LEGACY/fóssil desde Fase 1 (2026-06-10): escrita morta no app desde 27/05; dados resgatáveis migrados pra profile_job_preferences/profile_desired_titles/profile_other_locations. Revogação diferida.';
