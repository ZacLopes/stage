-- Gate 3.0I — REVERSÃO de um import revisado (snapshot pré-apply + restore).
-- Roda DEPOIS do promote_test (schema mock + 120000/130000) e da migration
-- 20260719120000. Prova: (RV1) ida-e-volta idêntico com pais+filhos; (RV2)
-- trava anti-atropelo (stale); (RV3) idempotência + não-revertível.
-- Chamado como superuser (postgres) com request.jwt.claims setando auth.uid();
-- as funções internas são REVOKEd de PUBLIC mas o owner/superuser as chama.

-- RV1 — IDA E VOLTA: estado rico (experiência+bullets, educação+filhas,
-- projeto+bullets, escalares) → apply (adiciona skill + promove) → revert
-- restaura o perfil IDÊNTICO (comparação estável byte-a-byte).
DO $rv$
DECLARE
  u uuid := '000000dd-0000-0000-0000-0000000000d1';
  att uuid := '000000dd-0000-0000-0000-0000000000a1';
  cand uuid; eid uuid; edid uuid; pid uuid;
  agg jsonb; rev jsonb; pre_stable jsonb; post_stable jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', ('{"sub":"'||u||'"}')::text, false);
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM public._t_reset(u);

  -- Estado PROTEGIDO e rico (cobre todas as tabelas + relação pai/filho).
  INSERT INTO public.profile_personal(user_id, first_name, summary)
    VALUES (u, 'Pré', 'resumo antigo');
  INSERT INTO public.profile_skills(user_id, name) VALUES (u, 'ExistingSkill');
  INSERT INTO public.profile_languages(user_id, name, proficiency) VALUES (u, 'Inglês', 'advanced');
  INSERT INTO public.profile_certifications(user_id, name, issuer) VALUES (u, 'CertPre', 'IssuerPre');
  INSERT INTO public.profile_interests(user_id, name) VALUES (u, 'Xadrez');
  INSERT INTO public.profile_awards(user_id, name) VALUES (u, 'PrêmioPre');
  INSERT INTO public.profile_coursework(user_id, name) VALUES (u, 'CursoPre');
  INSERT INTO public.profile_experiences(user_id, title, company, start_date, end_date)
    VALUES (u, 'ExpPre', 'CoPre', DATE '2020-01-01', DATE '2021-01-01') RETURNING id INTO eid;
  INSERT INTO public.profile_bullets(experience_id, text, order_index) VALUES (eid, 'bulletA', 0);
  INSERT INTO public.profile_bullets(experience_id, text, order_index) VALUES (eid, 'bulletB', 1);
  INSERT INTO public.profile_education(user_id, institution)
    VALUES (u, 'EduPre') RETURNING id INTO edid;
  INSERT INTO public.profile_education_majors(education_id, name) VALUES (edid, 'MajorPre');
  INSERT INTO public.profile_education_minors(education_id, name) VALUES (edid, 'MinorPre');
  INSERT INTO public.profile_education_activities(education_id, text) VALUES (edid, 'AtivPre');
  INSERT INTO public.profile_projects(user_id, name) VALUES (u, 'ProjPre') RETURNING id INTO pid;
  INSERT INTO public.profile_project_bullets(project_id, text, order_index) VALUES (pid, 'pbullet', 0);

  -- Candidata pronta (ainda NÃO current). A foto-base é DEPOIS do seed (o wrapper
  -- também captura aqui), pra a candidata contar igual dos dois lados.
  cand := public._t_seed_ready(u, 'RevRich',
    '{"personal":{"first_name":"CvN"},"skills":[{"name":"NewSkill"}]}'::jsonb, att);
  pre_stable := public._import_snapshot_stable(public._snapshot_profile_content(u));

  -- Aplica via o WRAPPER (tira a foto pré na mesma transação) + promove.
  agg := public.apply_reviewed_with_snapshot(cand, att,
    jsonb_build_array(jsonb_build_object('kind','add','section','skill','source','NewSkill','value','NewSkill')));
  IF (agg->>'promoted') <> 'true' THEN RAISE EXCEPTION 'RV1 setup: não promoveu: %', agg; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='NewSkill') THEN
    RAISE EXCEPTION 'RV1 setup: apply não trouxe NewSkill'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.import_apply_receipts
                  WHERE candidate_id=cand AND attempt_id=att AND pre_snapshot IS NOT NULL) THEN
    RAISE EXCEPTION 'RV1 setup: recibo sem pre_snapshot'; END IF;
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=cand) <> true THEN
    RAISE EXCEPTION 'RV1 setup: candidata não virou current'; END IF;

  -- REVERT.
  rev := public.revert_reviewed_apply(cand, att);
  IF (rev->>'reverted') <> 'true' THEN RAISE EXCEPTION 'RV1: revert falhou: %', rev; END IF;

  -- Perfil IDÊNTICO ao pré-apply (inclui filhos e a flag de fonte atual).
  post_stable := public._import_snapshot_stable(public._snapshot_profile_content(u));
  IF post_stable IS DISTINCT FROM pre_stable THEN
    RAISE EXCEPTION 'RV1: revert NAO restaurou identico. PRE=% POST=%',
      pre_stable, post_stable; END IF;
  -- Sanidade explícita: NewSkill sumiu, filhos voltaram, candidata não é mais current.
  IF EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='NewSkill') THEN
    RAISE EXCEPTION 'RV1: NewSkill sobreviveu ao revert'; END IF;
  IF (SELECT count(*) FROM public.profile_bullets b JOIN public.profile_experiences e ON e.id=b.experience_id
       WHERE e.user_id=u) <> 2 THEN RAISE EXCEPTION 'RV1: bullets não restaurados'; END IF;
  IF (SELECT count(*) FROM public.profile_education_majors m JOIN public.profile_education ed ON ed.id=m.education_id
       WHERE ed.user_id=u) <> 1 THEN RAISE EXCEPTION 'RV1: majors não restaurados'; END IF;
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=cand) <> false THEN
    RAISE EXCEPTION 'RV1: flag de fonte atual não restaurada'; END IF;

  RAISE NOTICE 'RV1 OK: apply muda o perfil e promove; revert restaura idêntico (pais+filhos+flags)';
END $rv$;

-- RV2 — TRAVA anti-atropelo: se o perfil mudou desde o apply, revert devolve
-- 'stale' e NÃO mexe (a edição manual sobrevive).
DO $rv$
DECLARE
  u uuid := '000000dd-0000-0000-0000-0000000000d2';
  att uuid := '000000dd-0000-0000-0000-0000000000a2';
  cand uuid; agg jsonb; rev jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', ('{"sub":"'||u||'"}')::text, false);
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, first_name) VALUES (u, 'Pré');
  INSERT INTO public.profile_skills(user_id, name) VALUES (u, 'ExistingSkill');
  cand := public._t_seed_ready(u, 'RevStale',
    '{"personal":{"first_name":"CvN"},"skills":[{"name":"NewSkill"}]}'::jsonb, att);
  agg := public.apply_reviewed_with_snapshot(cand, att,
    jsonb_build_array(jsonb_build_object('kind','add','section','skill','source','NewSkill','value','NewSkill')));
  IF (agg->>'promoted') <> 'true' THEN RAISE EXCEPTION 'RV2 setup: não promoveu'; END IF;

  -- EDIÇÃO MANUAL depois do apply (o usuário mexeu no perfil).
  INSERT INTO public.profile_skills(user_id, name) VALUES (u, 'ManualDepois');

  rev := public.revert_reviewed_apply(cand, att);
  IF (rev->>'reverted') <> 'false' OR (rev->>'reason') <> 'stale' THEN
    RAISE EXCEPTION 'RV2: esperava stale, veio %', rev; END IF;
  -- A edição manual E o import continuam (nada foi atropelado).
  IF NOT EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='ManualDepois')
     OR NOT EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='NewSkill') THEN
    RAISE EXCEPTION 'RV2: stale mexeu no perfil (não devia)'; END IF;
  RAISE NOTICE 'RV2 OK: mudou desde o apply → revert stale, perfil intacto';
END $rv$;

-- RV3 — idempotência + não-revertível.
DO $rv$
DECLARE
  u uuid := '000000dd-0000-0000-0000-0000000000d3';
  att uuid := '000000dd-0000-0000-0000-0000000000a3';
  att2 uuid := '000000dd-0000-0000-0000-0000000000b3';
  cand uuid; cand2 uuid; agg jsonb; rev1 jsonb; rev2 jsonb; revx jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', ('{"sub":"'||u||'"}')::text, false);
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, first_name) VALUES (u, 'Pré');
  INSERT INTO public.profile_skills(user_id, name) VALUES (u, 'ExistingSkill');
  cand := public._t_seed_ready(u, 'RevIdem',
    '{"personal":{"first_name":"CvN"},"skills":[{"name":"NewSkill"}]}'::jsonb, att);
  agg := public.apply_reviewed_with_snapshot(cand, att,
    jsonb_build_array(jsonb_build_object('kind','add','section','skill','source','NewSkill','value','NewSkill')));
  IF (agg->>'promoted') <> 'true' THEN RAISE EXCEPTION 'RV3 setup: não promoveu'; END IF;

  rev1 := public.revert_reviewed_apply(cand, att);
  IF (rev1->>'reverted') <> 'true' THEN RAISE EXCEPTION 'RV3: 1º revert falhou: %', rev1; END IF;
  rev2 := public.revert_reviewed_apply(cand, att);
  IF (rev2->>'reverted') <> 'true' OR (rev2->>'reason') <> 'already_reverted' THEN
    RAISE EXCEPTION 'RV3: 2º revert não foi idempotente: %', rev2; END IF;

  -- Candidata REAL porém nunca aplicada (sem recibo/snapshot) → não-revertível.
  cand2 := public._t_seed_ready(u, 'RevNoReceipt',
    '{"personal":{"first_name":"CvN"},"skills":[{"name":"X"}]}'::jsonb, att2);
  revx := public.revert_reviewed_apply(cand2, att2);
  IF (revx->>'reverted') <> 'false' OR (revx->>'reason') <> 'not_revertible' THEN
    RAISE EXCEPTION 'RV3: candidata sem recibo devia ser não-revertível: %', revx; END IF;
  RAISE NOTICE 'RV3 OK: revert idempotente (2º=already_reverted); candidata sem foto = não-revertível';
END $rv$;

SELECT 'REVERT_SQL_TESTS_OK' AS result;
