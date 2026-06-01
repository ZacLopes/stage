-- Backfill legacy onboarding education into relational profile_education.
--
-- Source of truth for older users:
-- - user_profiles.gamification_data->>'university'
-- - user_profiles.course
-- - user_profiles.semester or gamification_data->>'current_semester'
--
-- This migration is intentionally conservative and idempotent:
-- - only uses non-empty, university-like legacy values;
-- - updates an equivalent profile_education row if it already exists;
-- - inserts one college row only when no equivalent row exists;
-- - fills missing relational fields without overwriting existing values;
-- - adds the legacy course as a major when absent.

WITH legacy_raw AS (
  SELECT
    up.id AS user_id,
    NULLIF(regexp_replace(btrim(up.gamification_data->>'university'), '\s+', ' ', 'g'), '') AS institution,
    NULLIF(regexp_replace(btrim(up.course), '\s+', ' ', 'g'), '') AS course,
    COALESCE(up.gamification_data->>'current_semester', up.semester, '') AS semester_text
  FROM public.user_profiles up
),
legacy AS (
  SELECT
    user_id,
    institution,
    course,
    regexp_replace(lower(institution), '\s+', ' ', 'g') AS institution_key,
    CASE
      WHEN NULLIF(substring(semester_text FROM '([0-9]{1,2})'), '')::int BETWEEN 1 AND 12
        THEN NULLIF(substring(semester_text FROM '([0-9]{1,2})'), '')::int
      ELSE NULL
    END AS current_semester,
    CASE
      WHEN lower(semester_text) LIKE '%tranc%' THEN 'paused'
      ELSE 'studying'
    END AS education_status
  FROM legacy_raw
  WHERE institution IS NOT NULL
),
valid_legacy AS (
  SELECT *
  FROM legacy
  WHERE institution_key NOT IN (
    'nenhuma',
    'nenhum',
    'nada',
    'não',
    'nao',
    'não estudo',
    'nao estudo',
    'não informado',
    'nao informado',
    'nem uma',
    'nenhuma faculdade',
    'sem faculdade',
    'escola',
    'outra',
    '.'
  )
  AND institution_key NOT LIKE 'ensino médio%'
  AND institution_key NOT LIKE 'ensino medio%'
),
updated AS (
  UPDATE public.profile_education pe
  SET
    education_level = COALESCE(pe.education_level, 'college'),
    education_status = COALESCE(pe.education_status, vl.education_status),
    current_semester = COALESCE(pe.current_semester, vl.current_semester),
    degree = COALESCE(pe.degree, 'Graduação'),
    updated_at = now()
  FROM valid_legacy vl
  WHERE pe.user_id = vl.user_id
    AND regexp_replace(lower(btrim(pe.institution)), '\s+', ' ', 'g') = vl.institution_key
  RETURNING pe.id
),
inserted AS (
  INSERT INTO public.profile_education (
    user_id,
    institution,
    degree,
    education_level,
    education_status,
    current_semester,
    order_index
  )
  SELECT
    vl.user_id,
    vl.institution,
    'Graduação',
    'college',
    vl.education_status,
    vl.current_semester,
    COALESCE(MAX(existing.order_index), -1) + 1
  FROM valid_legacy vl
  LEFT JOIN public.profile_education existing
    ON existing.user_id = vl.user_id
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.profile_education pe
    WHERE pe.user_id = vl.user_id
      AND regexp_replace(lower(btrim(pe.institution)), '\s+', ' ', 'g') = vl.institution_key
  )
  GROUP BY
    vl.user_id,
    vl.institution,
    vl.education_status,
    vl.current_semester
  RETURNING id
)
SELECT
  (SELECT count(*) FROM updated) AS updated_rows,
  (SELECT count(*) FROM inserted) AS inserted_rows;

WITH legacy_raw AS (
  SELECT
    up.id AS user_id,
    NULLIF(regexp_replace(btrim(up.gamification_data->>'university'), '\s+', ' ', 'g'), '') AS institution,
    NULLIF(regexp_replace(btrim(up.course), '\s+', ' ', 'g'), '') AS course
  FROM public.user_profiles up
),
legacy AS (
  SELECT
    user_id,
    institution,
    course,
    regexp_replace(lower(institution), '\s+', ' ', 'g') AS institution_key
  FROM legacy_raw
  WHERE institution IS NOT NULL
    AND course IS NOT NULL
),
valid_legacy AS (
  SELECT *
  FROM legacy
  WHERE institution_key NOT IN (
    'nenhuma',
    'nenhum',
    'nada',
    'não',
    'nao',
    'não estudo',
    'nao estudo',
    'não informado',
    'nao informado',
    'nem uma',
    'nenhuma faculdade',
    'sem faculdade',
    'escola',
    'outra',
    '.'
  )
  AND institution_key NOT LIKE 'ensino médio%'
  AND institution_key NOT LIKE 'ensino medio%'
),
target_education AS (
  SELECT DISTINCT ON (vl.user_id, vl.institution_key)
    vl.user_id,
    vl.institution_key,
    vl.course,
    pe.id AS education_id
  FROM valid_legacy vl
  JOIN public.profile_education pe
    ON pe.user_id = vl.user_id
   AND regexp_replace(lower(btrim(pe.institution)), '\s+', ' ', 'g') = vl.institution_key
  ORDER BY
    vl.user_id,
    vl.institution_key,
    CASE WHEN pe.education_level = 'college' THEN 0 ELSE 1 END,
    pe.order_index,
    pe.created_at
),
inserted_majors AS (
  INSERT INTO public.profile_education_majors (education_id, name, order_index)
  SELECT
    te.education_id,
    te.course,
    0
  FROM target_education te
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.profile_education_majors pem
    WHERE pem.education_id = te.education_id
      AND lower(btrim(pem.name)) = lower(btrim(te.course))
  )
  RETURNING id
)
SELECT count(*) AS inserted_major_rows
FROM inserted_majors;
