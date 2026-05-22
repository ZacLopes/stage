-- Migration: profile_education
--
-- Formação acadêmica com tabelas filhas pra majors, minors e activities.
-- O modelo atual em imported_resume.parsed achata tudo num campo
-- "details" string-livre; aqui cada major/minor/atividade vira linha
-- separada pra permitir queries (ex: "todos os usuários que cursam
-- Engenharia de Computação"). gpa e max_gpa armazenados separadamente
-- pra suportar escalas diferentes (0-10 BR, 0-4.0 US).
--
-- RLS das filhas é via parent (profile_education.user_id) — EXISTS
-- na migration de policies (000010).

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_education (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  institution  TEXT NOT NULL,
  location     TEXT,
  degree       TEXT,
  start_date   DATE,
  end_date     DATE,
  gpa          NUMERIC(4,2),
  max_gpa      NUMERIC(4,2),
  order_index  INTEGER NOT NULL DEFAULT 0,
  confidence   NUMERIC(3,2) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_profile_education_user
  ON public.profile_education (user_id, order_index);

ALTER TABLE public.profile_education ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_education_majors (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  education_id  UUID NOT NULL REFERENCES public.profile_education(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  order_index   INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_profile_education_majors_edu
  ON public.profile_education_majors (education_id);

ALTER TABLE public.profile_education_majors ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_education_minors (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  education_id  UUID NOT NULL REFERENCES public.profile_education(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  order_index   INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_profile_education_minors_edu
  ON public.profile_education_minors (education_id);

ALTER TABLE public.profile_education_minors ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_education_activities (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  education_id  UUID NOT NULL REFERENCES public.profile_education(id) ON DELETE CASCADE,
  text          TEXT NOT NULL,
  order_index   INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_profile_education_activities_edu
  ON public.profile_education_activities (education_id);

ALTER TABLE public.profile_education_activities ENABLE ROW LEVEL SECURITY;

COMMIT;
