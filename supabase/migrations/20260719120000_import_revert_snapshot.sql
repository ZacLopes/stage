-- Gate 3.0I — REVERSÃO de verdade de um import revisado.
--
-- Não existe primitiva de serializar/restaurar o perfil inteiro no sistema; este
-- arquivo generaliza o molde JÁ EM PRODUÇÃO do "desfazer" de skills
-- (undo_assist_skills_edit_v1, 20260717140000): advisory lock → FOR UPDATE →
-- stale-guard → delete+reinsert PRESERVANDO ids → reafirma o que os gatilhos
-- recomputam → VERIFICA no fim (mismatch ⇒ RAISE ⇒ rollback ⇒ nunca corrompe).
--
-- Fluxo: o cliente aplica via apply_reviewed_with_snapshot (que tira a FOTO
-- pré-apply na MESMA transação e a guarda no recibo). O desfazer chama
-- revert_reviewed_apply, que restaura a foto — com trava anti-atropelo (se o
-- perfil mudou desde o apply, devolve 'stale' e não mexe).
--
-- Co-deploy (3.0J): depende das migrations locais 20260714120000/130000.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Colunas de snapshot no recibo (candidate+attempt-keyed, cascata na candidata)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.import_apply_receipts
  ADD COLUMN IF NOT EXISTS pre_snapshot jsonb,
  ADD COLUMN IF NOT EXISTS after_snapshot jsonb,
  ADD COLUMN IF NOT EXISTS reverted_at timestamptz;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. FOTO do conteúdo do perfil: as 15 tabelas que um apply revisado pode mexer
--    (pais + filhos por FK) + as flags de saved_resumes + o cache legado.
--    NÃO inclui Objetivos (desired_titles/job_preferences/other_locations/
--    application_countries): o import nunca os altera.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._snapshot_profile_content(p_uid uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    -- profile_personal é 1 linha por usuário (PK user_id, sem id) → ordena por user_id.
    'profile_personal',
      (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.user_id), '[]'::jsonb)
         FROM public.profile_personal t WHERE t.user_id = p_uid),
    'profile_skills',
      (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]'::jsonb)
         FROM public.profile_skills t WHERE t.user_id = p_uid),
    'profile_languages',
      (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]'::jsonb)
         FROM public.profile_languages t WHERE t.user_id = p_uid),
    'profile_certifications',
      (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]'::jsonb)
         FROM public.profile_certifications t WHERE t.user_id = p_uid),
    'profile_interests',
      (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]'::jsonb)
         FROM public.profile_interests t WHERE t.user_id = p_uid),
    'profile_awards',
      (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]'::jsonb)
         FROM public.profile_awards t WHERE t.user_id = p_uid),
    'profile_coursework',
      (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]'::jsonb)
         FROM public.profile_coursework t WHERE t.user_id = p_uid),
    'profile_experiences',
      (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]'::jsonb)
         FROM public.profile_experiences t WHERE t.user_id = p_uid),
    'profile_bullets',
      (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]'::jsonb)
         FROM public.profile_bullets t
        WHERE t.experience_id IN (SELECT id FROM public.profile_experiences WHERE user_id = p_uid)),
    'profile_education',
      (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]'::jsonb)
         FROM public.profile_education t WHERE t.user_id = p_uid),
    'profile_education_majors',
      (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]'::jsonb)
         FROM public.profile_education_majors t
        WHERE t.education_id IN (SELECT id FROM public.profile_education WHERE user_id = p_uid)),
    'profile_education_minors',
      (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]'::jsonb)
         FROM public.profile_education_minors t
        WHERE t.education_id IN (SELECT id FROM public.profile_education WHERE user_id = p_uid)),
    'profile_education_activities',
      (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]'::jsonb)
         FROM public.profile_education_activities t
        WHERE t.education_id IN (SELECT id FROM public.profile_education WHERE user_id = p_uid)),
    'profile_projects',
      (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]'::jsonb)
         FROM public.profile_projects t WHERE t.user_id = p_uid),
    'profile_project_bullets',
      (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]'::jsonb)
         FROM public.profile_project_bullets t
        WHERE t.project_id IN (SELECT id FROM public.profile_projects WHERE user_id = p_uid)),
    'saved_resumes_flags',
      (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id', id,
                'is_current_source', is_current_source,
                'is_latest_legacy_source', is_latest_legacy_source) ORDER BY id), '[]'::jsonb)
         FROM public.saved_resumes WHERE user_id = p_uid),
    'imported_resume_cache',
      (SELECT gamification_data->'imported_resume'
         FROM public.user_profiles WHERE id = p_uid)
  )
$$;
REVOKE ALL ON FUNCTION public._snapshot_profile_content(uuid) FROM PUBLIC;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Normalização p/ comparação (stale-guard + verify): tira campos que os
--    gatilhos legitimamente recomputam (updated_at, completeness_score) e o cache
--    derivado. O resto (inclui as flags de fonte atual) é comparado ao pé da letra.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._import_snapshot_stable(p_snap jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT COALESCE(jsonb_object_agg(k, stable_v), '{}'::jsonb)
  FROM jsonb_each(COALESCE(p_snap, '{}'::jsonb) - 'imported_resume_cache') AS e(k, v)
  CROSS JOIN LATERAL (
    SELECT COALESCE(
      jsonb_agg((elem - 'updated_at') - 'completeness_score' ORDER BY elem->>'id'),
      '[]'::jsonb)
    FROM jsonb_array_elements(e.v) AS elem
  ) AS s(stable_v)
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. RESTORE: apaga (pais → cascata nos filhos) e reinsere (pais antes de filhos),
--    preservando ids via jsonb_populate_recordset. Reafirma canonical_skill_id
--    (o trigger de taxonomia recomputa no insert) e restaura as flags + cache.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._restore_profile_snapshot(p_uid uuid, p_snap jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  -- Apaga pais (ON DELETE CASCADE remove bullets/majors/minors/activities/project_bullets).
  DELETE FROM public.profile_experiences WHERE user_id = p_uid;
  DELETE FROM public.profile_education    WHERE user_id = p_uid;
  DELETE FROM public.profile_projects     WHERE user_id = p_uid;
  DELETE FROM public.profile_skills       WHERE user_id = p_uid;
  DELETE FROM public.profile_languages    WHERE user_id = p_uid;
  DELETE FROM public.profile_certifications WHERE user_id = p_uid;
  DELETE FROM public.profile_interests    WHERE user_id = p_uid;
  DELETE FROM public.profile_awards       WHERE user_id = p_uid;
  DELETE FROM public.profile_coursework   WHERE user_id = p_uid;
  DELETE FROM public.profile_personal     WHERE user_id = p_uid;

  -- Reinsere pais antes de filhos (ids preservados ⇒ FKs dos filhos resolvem).
  INSERT INTO public.profile_personal
    SELECT * FROM jsonb_populate_recordset(null::public.profile_personal, p_snap->'profile_personal');
  INSERT INTO public.profile_skills
    SELECT * FROM jsonb_populate_recordset(null::public.profile_skills, p_snap->'profile_skills');
  INSERT INTO public.profile_languages
    SELECT * FROM jsonb_populate_recordset(null::public.profile_languages, p_snap->'profile_languages');
  INSERT INTO public.profile_certifications
    SELECT * FROM jsonb_populate_recordset(null::public.profile_certifications, p_snap->'profile_certifications');
  INSERT INTO public.profile_interests
    SELECT * FROM jsonb_populate_recordset(null::public.profile_interests, p_snap->'profile_interests');
  INSERT INTO public.profile_awards
    SELECT * FROM jsonb_populate_recordset(null::public.profile_awards, p_snap->'profile_awards');
  INSERT INTO public.profile_coursework
    SELECT * FROM jsonb_populate_recordset(null::public.profile_coursework, p_snap->'profile_coursework');
  INSERT INTO public.profile_experiences
    SELECT * FROM jsonb_populate_recordset(null::public.profile_experiences, p_snap->'profile_experiences');
  INSERT INTO public.profile_bullets
    SELECT * FROM jsonb_populate_recordset(null::public.profile_bullets, p_snap->'profile_bullets');
  INSERT INTO public.profile_education
    SELECT * FROM jsonb_populate_recordset(null::public.profile_education, p_snap->'profile_education');
  INSERT INTO public.profile_education_majors
    SELECT * FROM jsonb_populate_recordset(null::public.profile_education_majors, p_snap->'profile_education_majors');
  INSERT INTO public.profile_education_minors
    SELECT * FROM jsonb_populate_recordset(null::public.profile_education_minors, p_snap->'profile_education_minors');
  INSERT INTO public.profile_education_activities
    SELECT * FROM jsonb_populate_recordset(null::public.profile_education_activities, p_snap->'profile_education_activities');
  INSERT INTO public.profile_projects
    SELECT * FROM jsonb_populate_recordset(null::public.profile_projects, p_snap->'profile_projects');
  INSERT INTO public.profile_project_bullets
    SELECT * FROM jsonb_populate_recordset(null::public.profile_project_bullets, p_snap->'profile_project_bullets');

  -- Reafirma canonical_skill_id (o insert dispara o trigger que recomputa/zera).
  UPDATE public.profile_skills s
     SET canonical_skill_id = NULLIF(e.value->>'canonical_skill_id','')::uuid
    FROM jsonb_array_elements(p_snap->'profile_skills') e
   WHERE s.id = (e.value->>'id')::uuid AND s.user_id = p_uid
     AND s.canonical_skill_id IS DISTINCT FROM NULLIF(e.value->>'canonical_skill_id','')::uuid;

  -- Restaura as flags de fonte atual em 2 passos (zera tudo → aplica a foto):
  -- evita violar o índice único parcial "uma fonte atual por usuário".
  UPDATE public.saved_resumes
     SET is_current_source = false, is_latest_legacy_source = false
   WHERE user_id = p_uid;
  UPDATE public.saved_resumes sr
     SET is_current_source = COALESCE((e.value->>'is_current_source')::boolean, false),
         is_latest_legacy_source = COALESCE((e.value->>'is_latest_legacy_source')::boolean, false)
    FROM jsonb_array_elements(p_snap->'saved_resumes_flags') e
   WHERE sr.id = (e.value->>'id')::uuid AND sr.user_id = p_uid;

  -- Cache legado: escreve o valor pré-apply. O guard BEFORE do user_profiles
  -- OVERRIDE quando há fonte atual (reconstrói dela — correto); sem fonte atual,
  -- mantém o escrito (o cache pré-apply — correto).
  UPDATE public.user_profiles up
     SET gamification_data = CASE
           WHEN p_snap->'imported_resume_cache' IS NULL
             OR jsonb_typeof(p_snap->'imported_resume_cache') = 'null'
             THEN COALESCE(up.gamification_data, '{}'::jsonb) - 'imported_resume'
           ELSE jsonb_set(COALESCE(up.gamification_data, '{}'::jsonb),
                          '{imported_resume}', p_snap->'imported_resume_cache', true)
         END
   WHERE up.id = p_uid;
END $$;
REVOKE ALL ON FUNCTION public._restore_profile_snapshot(uuid, jsonb) FROM PUBLIC;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. WRAPPER de apply: tira a foto pré na MESMA transação e a guarda no recibo.
--    Só no PRIMEIRO apply bem-sucedido (replay não regrava a foto).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.apply_reviewed_with_snapshot(
  p_candidate_id uuid, p_attempt_id uuid, p_choices jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_uid uuid := auth.uid(); v_pre jsonb; v_result jsonb; v_existed boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='28000'; END IF;
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(v_uid));
  -- Já há recibo (replay)? Só o PRIMEIRO apply tira a foto pré.
  SELECT EXISTS(SELECT 1 FROM public.import_apply_receipts
                 WHERE candidate_id = p_candidate_id AND attempt_id = p_attempt_id)
    INTO v_existed;
  IF NOT v_existed THEN
    v_pre := public._snapshot_profile_content(v_uid);
  END IF;
  -- Delega o apply atômico + promoção (valida posse/estado; ele acima acquire o
  -- mesmo advisory, re-entrante). Falha dura ⇒ promoted:false (nada persiste).
  v_result := public.apply_reviewed_conflicts_and_promote(p_candidate_id, p_attempt_id, p_choices);
  IF NOT v_existed AND COALESCE((v_result->>'promoted')::boolean, false) THEN
    UPDATE public.import_apply_receipts
       SET pre_snapshot = v_pre,
           after_snapshot = public._snapshot_profile_content(v_uid)
     WHERE candidate_id = p_candidate_id AND attempt_id = p_attempt_id
       AND pre_snapshot IS NULL;
  END IF;
  RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.apply_reviewed_with_snapshot(uuid, uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_reviewed_with_snapshot(uuid, uuid, jsonb) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. REVERT: restaura a foto pré-apply, com trava anti-atropelo + verify.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.revert_reviewed_apply(
  p_candidate_id uuid, p_attempt_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid(); v_owner uuid;
  v_rec public.import_apply_receipts%ROWTYPE;
  v_current jsonb; v_restored jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='28000'; END IF;
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(v_uid));

  SELECT user_id INTO v_owner FROM public.saved_resumes WHERE id = p_candidate_id;
  IF v_owner IS NULL OR v_owner <> v_uid THEN
    RAISE EXCEPTION 'candidate_not_found' USING ERRCODE='P0002';
  END IF;

  SELECT * INTO v_rec FROM public.import_apply_receipts
    WHERE candidate_id = p_candidate_id AND attempt_id = p_attempt_id FOR UPDATE;
  IF NOT FOUND OR v_rec.operation <> 'apply_reviewed' OR v_rec.pre_snapshot IS NULL THEN
    RETURN jsonb_build_object('reverted', false, 'reason', 'not_revertible');
  END IF;
  IF v_rec.reverted_at IS NOT NULL THEN
    RETURN jsonb_build_object('reverted', true, 'reason', 'already_reverted');
  END IF;

  -- Trava anti-atropelo: se o perfil mudou desde o apply, não mexe.
  v_current := public._snapshot_profile_content(v_uid);
  IF public._import_snapshot_stable(v_current)
     IS DISTINCT FROM public._import_snapshot_stable(v_rec.after_snapshot) THEN
    RETURN jsonb_build_object('reverted', false, 'reason', 'stale');
  END IF;

  PERFORM public._restore_profile_snapshot(v_uid, v_rec.pre_snapshot);

  -- VERIFY: o restore tem que reproduzir a foto pré (fora campos voláteis).
  -- Mismatch ⇒ RAISE ⇒ rollback ⇒ perfil segue no estado aplicado (sem corromper).
  v_restored := public._snapshot_profile_content(v_uid);
  IF public._import_snapshot_stable(v_restored)
     IS DISTINCT FROM public._import_snapshot_stable(v_rec.pre_snapshot) THEN
    RAISE EXCEPTION 'revert_verification_failed' USING ERRCODE='23514';
  END IF;

  UPDATE public.import_apply_receipts SET reverted_at = now()
    WHERE candidate_id = p_candidate_id AND attempt_id = p_attempt_id;
  RETURN jsonb_build_object('reverted', true, 'reason', 'ok');
END $$;
REVOKE ALL ON FUNCTION public.revert_reviewed_apply(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.revert_reviewed_apply(uuid, uuid) TO authenticated;
