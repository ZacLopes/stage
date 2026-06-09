-- Coleta de preferências não técnicas para futuro fit score cultural.
-- A UI salva localmente primeiro e sincroniza aqui em best-effort.

CREATE TABLE IF NOT EXISTS public.user_culture_fit_preferences (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  work_style text,
  learning_style text,
  collaboration_style text,
  pace_style text,
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT user_culture_fit_work_style_check CHECK (
    work_style IS NULL OR work_style IN (
      'clear_scope',
      'autonomy',
      'guided_autonomy'
    )
  ),
  CONSTRAINT user_culture_fit_learning_style_check CHECK (
    learning_style IS NULL OR learning_style IN (
      'mentor',
      'docs',
      'hands_on'
    )
  ),
  CONSTRAINT user_culture_fit_collaboration_style_check CHECK (
    collaboration_style IS NULL OR collaboration_style IN (
      'high_collaboration',
      'async_focus',
      'balanced_rituals'
    )
  ),
  CONSTRAINT user_culture_fit_pace_style_check CHECK (
    pace_style IS NULL OR pace_style IN (
      'predictable',
      'dynamic',
      'seasonal_intensity'
    )
  )
);

ALTER TABLE public.user_culture_fit_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY users_select_own_culture_fit_preferences
ON public.user_culture_fit_preferences
FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY users_insert_own_culture_fit_preferences
ON public.user_culture_fit_preferences
FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY users_update_own_culture_fit_preferences
ON public.user_culture_fit_preferences
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY users_delete_own_culture_fit_preferences
ON public.user_culture_fit_preferences
FOR DELETE
USING (auth.uid() = user_id);
