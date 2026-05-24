-- Migration: save_profile_from_json com suporte a linkedin_url + website
--
-- Tier 2.2 do plano "1000x melhor". Substitui a função `save_profile_from_json`
-- (versão defensive de 20260522000012) adicionando 2 campos no upsert do
-- profile_personal:
--   - linkedin_url (lido de p_data->'personal'->>'linkedin')
--   - website      (lido de p_data->'personal'->>'website')
--
-- Resto do corpo IDÊNTICO à versão defensive — duplicação intencional
-- porque PL/pgSQL não permite ALTER FUNCTION parcial.
--
-- Dependência: requer migration 20260524000000 já aplicada (colunas
-- linkedin_url + website existem em profile_personal).

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
  v_start_date DATE;
  v_end_date   DATE;
  v_is_current BOOLEAN;
  v_skipped_count INTEGER := 0;
BEGIN
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'p_user_id cannot be null'; END IF;
  IF p_data IS NULL THEN RAISE EXCEPTION 'p_data cannot be null'; END IF;

  -- profile_personal: upsert (+ linkedin_url + website em 2026-05-24)
  INSERT INTO public.profile_personal (
    user_id, first_name, last_name, email,
    phone_country_code, phone_number, headline, summary,
    gender, age_range,
    location_country, location_state, location_city, location_postal_code, location_street_address,
    attribution_source, profile_source, completeness_score,
    linkedin_url, website,
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
    COALESCE(safe_integer(p_data->'personal'->>'completeness_score'), 0),
    -- O JSON_SCHEMA do extract-profile usa `linkedin` (não `linkedin_url`),
    -- então lê do campo legacy. Coluna no DB é `linkedin_url`.
    p_data->'personal'->>'linkedin',
    p_data->'personal'->>'website',
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
    linkedin_url            = EXCLUDED.linkedin_url,
    website                 = EXCLUDED.website,
    last_extracted_at       = now(),
    updated_at              = now();

  -- Replace mode
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

  -- profile_experiences + bullets (cada experience numa subtransaction)
  FOR v_exp IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'experiences', '[]'::jsonb))
  LOOP
    BEGIN
      v_start_date := safe_date(v_exp->>'start_date');
      v_end_date := safe_date(v_exp->>'end_date');
      v_is_current := COALESCE((v_exp->>'is_current')::BOOLEAN, FALSE);
      IF v_end_date IS NULL THEN
        v_is_current := TRUE;
      END IF;
      IF v_start_date IS NULL THEN
        v_skipped_count := v_skipped_count + 1;
        RAISE WARNING 'skipping experience without valid start_date for user %', p_user_id;
        CONTINUE;
      END IF;

      INSERT INTO public.profile_experiences (
        user_id, title, company, location,
        start_date, end_date, is_current, order_index, confidence, needs_review
      )
      VALUES (
        p_user_id,
        v_exp->>'title',
        v_exp->>'company',
        v_exp->>'location',
        v_start_date,
        v_end_date,
        v_is_current,
        COALESCE(safe_integer(v_exp->>'order_index'), 0),
        safe_numeric(v_exp->>'confidence'),
        (safe_numeric(v_exp->>'confidence') < 0.5
          OR (v_end_date IS NULL AND COALESCE((v_exp->>'is_current')::BOOLEAN, FALSE) = FALSE))
      )
      RETURNING id INTO v_exp_id;

      FOR v_bullet IN SELECT * FROM jsonb_array_elements(COALESCE(v_exp->'bullets', '[]'::jsonb))
      LOOP
        BEGIN
          INSERT INTO public.profile_bullets (
            experience_id, text, angle, strength_score, verb, order_index
          )
          VALUES (
            v_exp_id,
            v_bullet->>'text',
            v_bullet->>'angle',
            safe_integer(v_bullet->>'strength_score'),
            v_bullet->>'verb',
            COALESCE(safe_integer(v_bullet->>'order_index'), 0)
          );
        EXCEPTION WHEN OTHERS THEN
          v_skipped_count := v_skipped_count + 1;
          RAISE WARNING 'skipping bullet for exp % user %: %', v_exp_id, p_user_id, SQLERRM;
        END;
      END LOOP;
    EXCEPTION WHEN OTHERS THEN
      v_skipped_count := v_skipped_count + 1;
      RAISE WARNING 'skipping experience for user %: %', p_user_id, SQLERRM;
    END;
  END LOOP;

  -- profile_education + filhas
  FOR v_edu IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'education', '[]'::jsonb))
  LOOP
    BEGIN
      INSERT INTO public.profile_education (
        user_id, institution, location, degree,
        start_date, end_date, gpa, max_gpa, order_index, confidence
      )
      VALUES (
        p_user_id,
        v_edu->>'institution',
        v_edu->>'location',
        v_edu->>'degree',
        safe_date(v_edu->>'start_date'),
        safe_date(v_edu->>'end_date'),
        safe_numeric(v_edu->>'gpa'),
        safe_numeric(v_edu->>'max_gpa'),
        COALESCE(safe_integer(v_edu->>'order_index'), 0),
        safe_numeric(v_edu->>'confidence')
      )
      RETURNING id INTO v_edu_id;

      FOR v_text IN SELECT jsonb_array_elements_text(COALESCE(v_edu->'majors', '[]'::jsonb))
      LOOP
        BEGIN
          INSERT INTO public.profile_education_majors (education_id, name) VALUES (v_edu_id, v_text);
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END LOOP;
      FOR v_text IN SELECT jsonb_array_elements_text(COALESCE(v_edu->'minors', '[]'::jsonb))
      LOOP
        BEGIN
          INSERT INTO public.profile_education_minors (education_id, name) VALUES (v_edu_id, v_text);
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END LOOP;
      FOR v_text IN SELECT jsonb_array_elements_text(COALESCE(v_edu->'activities', '[]'::jsonb))
      LOOP
        BEGIN
          INSERT INTO public.profile_education_activities (education_id, text) VALUES (v_edu_id, v_text);
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END LOOP;
    EXCEPTION WHEN OTHERS THEN
      v_skipped_count := v_skipped_count + 1;
      RAISE WARNING 'skipping education for user %: %', p_user_id, SQLERRM;
    END;
  END LOOP;

  -- profile_languages
  FOR v_lang IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'languages', '[]'::jsonb))
  LOOP
    BEGIN
      INSERT INTO public.profile_languages (user_id, name, proficiency, order_index)
      VALUES (
        p_user_id, v_lang->>'name', v_lang->>'proficiency',
        COALESCE(safe_integer(v_lang->>'order_index'), 0)
      );
    EXCEPTION WHEN OTHERS THEN
      v_skipped_count := v_skipped_count + 1;
    END;
  END LOOP;

  -- profile_skills (dedup case-insensitive)
  FOR v_skill IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'skills', '[]'::jsonb))
  LOOP
    BEGIN
      INSERT INTO public.profile_skills (user_id, name, category, order_index)
      VALUES (
        p_user_id, v_skill->>'name', v_skill->>'category',
        COALESCE(safe_integer(v_skill->>'order_index'), 0)
      )
      ON CONFLICT (user_id, LOWER(name)) DO NOTHING;
    EXCEPTION WHEN OTHERS THEN
      v_skipped_count := v_skipped_count + 1;
    END;
  END LOOP;

  -- profile_certifications
  FOR v_cert IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'certifications', '[]'::jsonb))
  LOOP
    BEGIN
      INSERT INTO public.profile_certifications (user_id, name, issuer, date, order_index)
      VALUES (
        p_user_id, v_cert->>'name', v_cert->>'issuer',
        safe_date(v_cert->>'date'),
        COALESCE(safe_integer(v_cert->>'order_index'), 0)
      );
    EXCEPTION WHEN OTHERS THEN
      v_skipped_count := v_skipped_count + 1;
    END;
  END LOOP;

  -- profile_projects
  FOR v_proj IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'projects', '[]'::jsonb))
  LOOP
    BEGIN
      INSERT INTO public.profile_projects (
        user_id, name, website, description,
        start_date, end_date, is_current, order_index
      )
      VALUES (
        p_user_id, v_proj->>'name', v_proj->>'website', v_proj->>'description',
        safe_date(v_proj->>'start_date'),
        safe_date(v_proj->>'end_date'),
        COALESCE((v_proj->>'is_current')::BOOLEAN, FALSE),
        COALESCE(safe_integer(v_proj->>'order_index'), 0)
      );
    EXCEPTION WHEN OTHERS THEN
      v_skipped_count := v_skipped_count + 1;
    END;
  END LOOP;

  -- profile_interests (dedup case-insensitive)
  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'interests', '[]'::jsonb))
  LOOP
    BEGIN
      INSERT INTO public.profile_interests (user_id, name, order_index)
      VALUES (p_user_id, v_item->>'name', COALESCE(safe_integer(v_item->>'order_index'), 0))
      ON CONFLICT (user_id, LOWER(name)) DO NOTHING;
    EXCEPTION WHEN OTHERS THEN
      v_skipped_count := v_skipped_count + 1;
    END;
  END LOOP;

  -- profile_awards
  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'awards', '[]'::jsonb))
  LOOP
    BEGIN
      INSERT INTO public.profile_awards (user_id, name, date, order_index)
      VALUES (
        p_user_id, v_item->>'name',
        safe_date(v_item->>'date'),
        COALESCE(safe_integer(v_item->>'order_index'), 0)
      );
    EXCEPTION WHEN OTHERS THEN
      v_skipped_count := v_skipped_count + 1;
    END;
  END LOOP;

  -- profile_coursework
  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'coursework', '[]'::jsonb))
  LOOP
    BEGIN
      INSERT INTO public.profile_coursework (user_id, name, order_index)
      VALUES (p_user_id, v_item->>'name', COALESCE(safe_integer(v_item->>'order_index'), 0));
    EXCEPTION WHEN OTHERS THEN
      v_skipped_count := v_skipped_count + 1;
    END;
  END LOOP;

  -- profile_job_preferences (se vier no payload)
  IF p_data ? 'job_preferences' THEN
    v_pref := p_data->'job_preferences';
    BEGIN
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
        safe_numeric(v_pref->>'primary_location_lat'),
        safe_numeric(v_pref->>'primary_location_lng'),
        COALESCE(safe_integer(v_pref->>'primary_location_radius_km'), 50),
        CASE WHEN v_pref ? 'experience_level' THEN ARRAY(SELECT jsonb_array_elements_text(v_pref->'experience_level')) ELSE NULL END,
        CASE WHEN v_pref ? 'work_mode' THEN ARRAY(SELECT jsonb_array_elements_text(v_pref->'work_mode')) ELSE NULL END,
        CASE WHEN v_pref ? 'job_types' THEN ARRAY(SELECT jsonb_array_elements_text(v_pref->'job_types')) ELSE NULL END
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
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'skipping job_preferences for user %: %', p_user_id, SQLERRM;
    END;

    FOR v_title IN SELECT * FROM jsonb_array_elements(COALESCE(v_pref->'desired_titles', '[]'::jsonb))
    LOOP
      BEGIN
        INSERT INTO public.profile_desired_titles (user_id, title, source, order_index)
        VALUES (
          p_user_id, v_title->>'title', v_title->>'source',
          COALESCE(safe_integer(v_title->>'order_index'), 0)
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END LOOP;

    FOR v_country IN SELECT * FROM jsonb_array_elements(COALESCE(v_pref->'application_countries', '[]'::jsonb))
    LOOP
      BEGIN
        INSERT INTO public.profile_application_countries (user_id, country_code, work_auth)
        VALUES (p_user_id, v_country->>'country_code', v_country->>'work_auth')
        ON CONFLICT (user_id, country_code) DO NOTHING;
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END LOOP;

    FOR v_loc IN SELECT * FROM jsonb_array_elements(COALESCE(v_pref->'other_locations', '[]'::jsonb))
    LOOP
      BEGIN
        INSERT INTO public.profile_other_locations (user_id, city, state, country, radius_km)
        VALUES (
          p_user_id, v_loc->>'city', v_loc->>'state', v_loc->>'country',
          COALESCE(safe_integer(v_loc->>'radius_km'), 50)
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'status', 'success',
    'user_id', p_user_id,
    'skipped_rows', v_skipped_count
  );

EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'save_profile_from_json failed: % (state %)', SQLERRM, SQLSTATE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.save_profile_from_json(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_profile_from_json(UUID, JSONB) TO service_role;

COMMIT;
