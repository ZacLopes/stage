-- Migration: save_profile_from_json
--
-- Função PL/pgSQL que persiste o JSON estruturado (saída do extract-profile)
-- nas 18 tabelas relacionais numa única transaction. Modo replace: deleta
-- entradas existentes do user e re-insere o novo conjunto.
--
-- Modo replace é aceitável na Semana 1 (ninguém edita manualmente ainda).
-- Quando a Semana 2 trouxer edição manual, evoluirá pra merge inteligente
-- (preservar campos editados, fazer upsert por chave natural).
--
-- SECURITY DEFINER + REVOKE FROM PUBLIC + GRANT TO service_role: só edge
-- functions admin podem chamar. Cliente Flutter passa pelo edge function
-- save-profile (que valida auth e chama esta RPC).
--
-- Estrutura esperada de p_data: ver _shared/profile_schema.ts
-- (PROFILE_JSON_SCHEMA).

BEGIN;

CREATE OR REPLACE FUNCTION public.save_profile_from_json(
  p_user_id UUID,
  p_data    JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exp     JSONB;
  v_bullet  JSONB;
  v_exp_id  UUID;
  v_edu     JSONB;
  v_edu_id  UUID;
  v_lang    JSONB;
  v_skill   JSONB;
  v_cert    JSONB;
  v_proj    JSONB;
  v_item    JSONB;
  v_text    TEXT;
  v_pref    JSONB;
  v_title   JSONB;
  v_country JSONB;
  v_loc     JSONB;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'p_user_id cannot be null';
  END IF;
  IF p_data IS NULL THEN
    RAISE EXCEPTION 'p_data cannot be null';
  END IF;

  -- ────────────────────────────────────────────────────────────────────
  -- profile_personal: upsert
  -- ────────────────────────────────────────────────────────────────────
  INSERT INTO public.profile_personal (
    user_id, first_name, last_name, email,
    phone_country_code, phone_number, headline, summary,
    gender, age_range,
    location_country, location_state, location_city, location_postal_code, location_street_address,
    attribution_source, profile_source, completeness_score,
    last_extracted_at
  )
  VALUES (
    p_user_id,
    p_data->'personal'->>'first_name',
    p_data->'personal'->>'last_name',
    p_data->'personal'->>'email',
    p_data->'personal'->>'phone_country_code',
    p_data->'personal'->>'phone_number',
    p_data->'personal'->>'headline',
    p_data->'personal'->>'summary',
    p_data->'personal'->>'gender',
    p_data->'personal'->>'age_range',
    p_data->'personal'->>'location_country',
    p_data->'personal'->>'location_state',
    p_data->'personal'->>'location_city',
    p_data->'personal'->>'location_postal_code',
    p_data->'personal'->>'location_street_address',
    p_data->'personal'->>'attribution_source',
    COALESCE(p_data->'personal'->>'profile_source', 'imported'),
    COALESCE((p_data->'personal'->>'completeness_score')::INTEGER, 0),
    now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    first_name              = EXCLUDED.first_name,
    last_name               = EXCLUDED.last_name,
    email                   = EXCLUDED.email,
    phone_country_code      = EXCLUDED.phone_country_code,
    phone_number            = EXCLUDED.phone_number,
    headline                = EXCLUDED.headline,
    summary                 = EXCLUDED.summary,
    gender                  = EXCLUDED.gender,
    age_range               = EXCLUDED.age_range,
    location_country        = EXCLUDED.location_country,
    location_state          = EXCLUDED.location_state,
    location_city           = EXCLUDED.location_city,
    location_postal_code    = EXCLUDED.location_postal_code,
    location_street_address = EXCLUDED.location_street_address,
    attribution_source      = EXCLUDED.attribution_source,
    profile_source          = EXCLUDED.profile_source,
    completeness_score      = EXCLUDED.completeness_score,
    last_extracted_at       = now(),
    updated_at              = now();

  -- ────────────────────────────────────────────────────────────────────
  -- Replace: limpa entradas existentes (cascade limpa filhas)
  -- ────────────────────────────────────────────────────────────────────
  DELETE FROM public.profile_experiences WHERE user_id = p_user_id;
  DELETE FROM public.profile_education WHERE user_id = p_user_id;
  DELETE FROM public.profile_languages WHERE user_id = p_user_id;
  DELETE FROM public.profile_skills WHERE user_id = p_user_id;
  DELETE FROM public.profile_certifications WHERE user_id = p_user_id;
  DELETE FROM public.profile_projects WHERE user_id = p_user_id;
  DELETE FROM public.profile_interests WHERE user_id = p_user_id;
  DELETE FROM public.profile_awards WHERE user_id = p_user_id;
  DELETE FROM public.profile_coursework WHERE user_id = p_user_id;
  DELETE FROM public.profile_desired_titles WHERE user_id = p_user_id;
  DELETE FROM public.profile_application_countries WHERE user_id = p_user_id;
  DELETE FROM public.profile_other_locations WHERE user_id = p_user_id;

  -- ────────────────────────────────────────────────────────────────────
  -- profile_experiences + profile_bullets
  -- ────────────────────────────────────────────────────────────────────
  FOR v_exp IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'experiences', '[]'::jsonb))
  LOOP
    INSERT INTO public.profile_experiences (
      user_id, title, company, location,
      start_date, end_date, is_current, order_index, confidence
    )
    VALUES (
      p_user_id,
      v_exp->>'title',
      v_exp->>'company',
      v_exp->>'location',
      (v_exp->>'start_date')::DATE,
      CASE
        WHEN v_exp->>'end_date' IS NULL OR v_exp->>'end_date' = '' OR v_exp->>'end_date' = 'current' THEN NULL
        ELSE (v_exp->>'end_date')::DATE
      END,
      COALESCE((v_exp->>'is_current')::BOOLEAN, FALSE),
      COALESCE((v_exp->>'order_index')::INTEGER, 0),
      NULLIF(v_exp->>'confidence', '')::NUMERIC
    )
    RETURNING id INTO v_exp_id;

    FOR v_bullet IN SELECT * FROM jsonb_array_elements(COALESCE(v_exp->'bullets', '[]'::jsonb))
    LOOP
      INSERT INTO public.profile_bullets (
        experience_id, text, angle, strength_score, verb, order_index
      )
      VALUES (
        v_exp_id,
        v_bullet->>'text',
        v_bullet->>'angle',
        NULLIF(v_bullet->>'strength_score', '')::INTEGER,
        v_bullet->>'verb',
        COALESCE((v_bullet->>'order_index')::INTEGER, 0)
      );
    END LOOP;
  END LOOP;

  -- ────────────────────────────────────────────────────────────────────
  -- profile_education + filhas (majors / minors / activities)
  -- ────────────────────────────────────────────────────────────────────
  FOR v_edu IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'education', '[]'::jsonb))
  LOOP
    INSERT INTO public.profile_education (
      user_id, institution, location, degree,
      start_date, end_date, gpa, max_gpa, order_index, confidence
    )
    VALUES (
      p_user_id,
      v_edu->>'institution',
      v_edu->>'location',
      v_edu->>'degree',
      NULLIF(v_edu->>'start_date', '')::DATE,
      NULLIF(v_edu->>'end_date', '')::DATE,
      NULLIF(v_edu->>'gpa', '')::NUMERIC,
      NULLIF(v_edu->>'max_gpa', '')::NUMERIC,
      COALESCE((v_edu->>'order_index')::INTEGER, 0),
      NULLIF(v_edu->>'confidence', '')::NUMERIC
    )
    RETURNING id INTO v_edu_id;

    FOR v_text IN SELECT jsonb_array_elements_text(COALESCE(v_edu->'majors', '[]'::jsonb))
    LOOP
      INSERT INTO public.profile_education_majors (education_id, name)
      VALUES (v_edu_id, v_text);
    END LOOP;

    FOR v_text IN SELECT jsonb_array_elements_text(COALESCE(v_edu->'minors', '[]'::jsonb))
    LOOP
      INSERT INTO public.profile_education_minors (education_id, name)
      VALUES (v_edu_id, v_text);
    END LOOP;

    FOR v_text IN SELECT jsonb_array_elements_text(COALESCE(v_edu->'activities', '[]'::jsonb))
    LOOP
      INSERT INTO public.profile_education_activities (education_id, text)
      VALUES (v_edu_id, v_text);
    END LOOP;
  END LOOP;

  -- ────────────────────────────────────────────────────────────────────
  -- profile_languages
  -- ────────────────────────────────────────────────────────────────────
  FOR v_lang IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'languages', '[]'::jsonb))
  LOOP
    INSERT INTO public.profile_languages (user_id, name, proficiency, order_index)
    VALUES (
      p_user_id,
      v_lang->>'name',
      v_lang->>'proficiency',
      COALESCE((v_lang->>'order_index')::INTEGER, 0)
    );
  END LOOP;

  -- ────────────────────────────────────────────────────────────────────
  -- profile_skills (dedup case-insensitive)
  -- ────────────────────────────────────────────────────────────────────
  FOR v_skill IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'skills', '[]'::jsonb))
  LOOP
    INSERT INTO public.profile_skills (user_id, name, category, order_index)
    VALUES (
      p_user_id,
      v_skill->>'name',
      v_skill->>'category',
      COALESCE((v_skill->>'order_index')::INTEGER, 0)
    )
    ON CONFLICT (user_id, LOWER(name)) DO NOTHING;
  END LOOP;

  -- ────────────────────────────────────────────────────────────────────
  -- profile_certifications
  -- ────────────────────────────────────────────────────────────────────
  FOR v_cert IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'certifications', '[]'::jsonb))
  LOOP
    INSERT INTO public.profile_certifications (user_id, name, issuer, date, order_index)
    VALUES (
      p_user_id,
      v_cert->>'name',
      v_cert->>'issuer',
      NULLIF(v_cert->>'date', '')::DATE,
      COALESCE((v_cert->>'order_index')::INTEGER, 0)
    );
  END LOOP;

  -- ────────────────────────────────────────────────────────────────────
  -- profile_projects
  -- ────────────────────────────────────────────────────────────────────
  FOR v_proj IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'projects', '[]'::jsonb))
  LOOP
    INSERT INTO public.profile_projects (
      user_id, name, website, description,
      start_date, end_date, is_current, order_index
    )
    VALUES (
      p_user_id,
      v_proj->>'name',
      v_proj->>'website',
      v_proj->>'description',
      NULLIF(v_proj->>'start_date', '')::DATE,
      NULLIF(v_proj->>'end_date', '')::DATE,
      COALESCE((v_proj->>'is_current')::BOOLEAN, FALSE),
      COALESCE((v_proj->>'order_index')::INTEGER, 0)
    );
  END LOOP;

  -- ────────────────────────────────────────────────────────────────────
  -- profile_interests (dedup case-insensitive)
  -- ────────────────────────────────────────────────────────────────────
  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'interests', '[]'::jsonb))
  LOOP
    INSERT INTO public.profile_interests (user_id, name, order_index)
    VALUES (
      p_user_id,
      v_item->>'name',
      COALESCE((v_item->>'order_index')::INTEGER, 0)
    )
    ON CONFLICT (user_id, LOWER(name)) DO NOTHING;
  END LOOP;

  -- ────────────────────────────────────────────────────────────────────
  -- profile_awards
  -- ────────────────────────────────────────────────────────────────────
  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'awards', '[]'::jsonb))
  LOOP
    INSERT INTO public.profile_awards (user_id, name, date, order_index)
    VALUES (
      p_user_id,
      v_item->>'name',
      NULLIF(v_item->>'date', '')::DATE,
      COALESCE((v_item->>'order_index')::INTEGER, 0)
    );
  END LOOP;

  -- ────────────────────────────────────────────────────────────────────
  -- profile_coursework
  -- ────────────────────────────────────────────────────────────────────
  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'coursework', '[]'::jsonb))
  LOOP
    INSERT INTO public.profile_coursework (user_id, name, order_index)
    VALUES (
      p_user_id,
      v_item->>'name',
      COALESCE((v_item->>'order_index')::INTEGER, 0)
    );
  END LOOP;

  -- ────────────────────────────────────────────────────────────────────
  -- profile_job_preferences (upsert) + filhas
  -- (todas só se o bloco vier no payload)
  -- ────────────────────────────────────────────────────────────────────
  IF p_data ? 'job_preferences' THEN
    v_pref := p_data->'job_preferences';

    INSERT INTO public.profile_job_preferences (
      user_id, primary_location_country, primary_location_state, primary_location_city,
      primary_location_postal_code, primary_location_lat, primary_location_lng,
      primary_location_radius_km, experience_level, work_mode, job_types
    )
    VALUES (
      p_user_id,
      v_pref->>'primary_location_country',
      v_pref->>'primary_location_state',
      v_pref->>'primary_location_city',
      v_pref->>'primary_location_postal_code',
      NULLIF(v_pref->>'primary_location_lat', '')::NUMERIC,
      NULLIF(v_pref->>'primary_location_lng', '')::NUMERIC,
      COALESCE((v_pref->>'primary_location_radius_km')::INTEGER, 50),
      CASE WHEN v_pref ? 'experience_level'
           THEN ARRAY(SELECT jsonb_array_elements_text(v_pref->'experience_level'))
           ELSE NULL END,
      CASE WHEN v_pref ? 'work_mode'
           THEN ARRAY(SELECT jsonb_array_elements_text(v_pref->'work_mode'))
           ELSE NULL END,
      CASE WHEN v_pref ? 'job_types'
           THEN ARRAY(SELECT jsonb_array_elements_text(v_pref->'job_types'))
           ELSE NULL END
    )
    ON CONFLICT (user_id) DO UPDATE SET
      primary_location_country     = EXCLUDED.primary_location_country,
      primary_location_state       = EXCLUDED.primary_location_state,
      primary_location_city        = EXCLUDED.primary_location_city,
      primary_location_postal_code = EXCLUDED.primary_location_postal_code,
      primary_location_lat         = EXCLUDED.primary_location_lat,
      primary_location_lng         = EXCLUDED.primary_location_lng,
      primary_location_radius_km   = EXCLUDED.primary_location_radius_km,
      experience_level             = EXCLUDED.experience_level,
      work_mode                    = EXCLUDED.work_mode,
      job_types                    = EXCLUDED.job_types,
      updated_at                   = now();

    FOR v_title IN SELECT * FROM jsonb_array_elements(COALESCE(v_pref->'desired_titles', '[]'::jsonb))
    LOOP
      INSERT INTO public.profile_desired_titles (user_id, title, source, order_index)
      VALUES (
        p_user_id,
        v_title->>'title',
        v_title->>'source',
        COALESCE((v_title->>'order_index')::INTEGER, 0)
      );
    END LOOP;

    FOR v_country IN SELECT * FROM jsonb_array_elements(COALESCE(v_pref->'application_countries', '[]'::jsonb))
    LOOP
      INSERT INTO public.profile_application_countries (user_id, country_code, work_auth)
      VALUES (
        p_user_id,
        v_country->>'country_code',
        v_country->>'work_auth'
      )
      ON CONFLICT (user_id, country_code) DO NOTHING;
    END LOOP;

    FOR v_loc IN SELECT * FROM jsonb_array_elements(COALESCE(v_pref->'other_locations', '[]'::jsonb))
    LOOP
      INSERT INTO public.profile_other_locations (user_id, city, state, country, radius_km)
      VALUES (
        p_user_id,
        v_loc->>'city',
        v_loc->>'state',
        v_loc->>'country',
        COALESCE((v_loc->>'radius_km')::INTEGER, 50)
      );
    END LOOP;
  END IF;

  RETURN jsonb_build_object('status', 'success', 'user_id', p_user_id);

EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'save_profile_from_json failed: % (state %)', SQLERRM, SQLSTATE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.save_profile_from_json(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_profile_from_json(UUID, JSONB) TO service_role;

COMMIT;
