-- Manual onboarding education fields.
--
-- The profile-first schema already stores education as structured rows, but
-- the manual onboarding path needs two extra dimensions that do not belong in
-- free-text fields:
-- - education_level: distinguishes school from college/university rows.
-- - education_status/current_semester/current_school_year: captures the
--   student's current education state for onboarding and reporting.

ALTER TABLE public.profile_education
  ADD COLUMN IF NOT EXISTS education_level TEXT CHECK (
    education_level IS NULL OR education_level IN ('school', 'college', 'technical', 'other')
  ),
  ADD COLUMN IF NOT EXISTS education_status TEXT CHECK (
    education_status IS NULL OR education_status IN (
      'studying',
      'graduated',
      'paused',
      'not_started',
      'not_in_college',
      'not_studying'
    )
  ),
  ADD COLUMN IF NOT EXISTS current_semester SMALLINT CHECK (
    current_semester IS NULL OR current_semester BETWEEN 1 AND 12
  ),
  ADD COLUMN IF NOT EXISTS current_school_year SMALLINT CHECK (
    current_school_year IS NULL OR current_school_year BETWEEN 1 AND 3
  );

CREATE INDEX IF NOT EXISTS idx_profile_education_user_level
  ON public.profile_education (user_id, education_level, order_index);

COMMENT ON COLUMN public.profile_education.education_level IS
  'Education tier. Manual onboarding writes school and college separately.';

COMMENT ON COLUMN public.profile_education.education_status IS
  'Education status captured in manual onboarding: studying, graduated, paused, not_started, not_in_college, not_studying.';

COMMENT ON COLUMN public.profile_education.current_semester IS
  'Current or last college semester captured in manual onboarding.';

COMMENT ON COLUMN public.profile_education.current_school_year IS
  'Current school year captured in manual onboarding: 1, 2 or 3 for high school.';
