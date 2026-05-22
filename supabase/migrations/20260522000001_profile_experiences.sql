-- Migration: profile_experiences
--
-- Experiências profissionais + bullets categorizados por ângulo Harvard
-- (leadership / technical / impact). Hoje o imported_resume JSONB guarda
-- bullets como "description" string \n-separada; aqui cada bullet vira
-- linha própria pra permitir edição, regeneração e análise de força.
--
-- Bullets têm RLS via parent (profile_experiences.user_id) — policy
-- baseada em EXISTS fica na migration de policies (000010).
--
-- confidence (0-1) é setada pelo extrator IA; needs_review é flag manual
-- usada pela tela da Semana 2 pra destacar campos suspeitos.

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_experiences (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title         TEXT NOT NULL,
  company       TEXT NOT NULL,
  location      TEXT,
  start_date    DATE NOT NULL,
  end_date      DATE,
  is_current    BOOLEAN NOT NULL DEFAULT FALSE,
  order_index   INTEGER NOT NULL DEFAULT 0,
  confidence    NUMERIC(3,2) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  needs_review  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (is_current = TRUE OR end_date IS NOT NULL),
  CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_profile_experiences_user
  ON public.profile_experiences (user_id, order_index);

ALTER TABLE public.profile_experiences ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_bullets (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  experience_id   UUID NOT NULL REFERENCES public.profile_experiences(id) ON DELETE CASCADE,
  text            TEXT NOT NULL,
  angle           TEXT CHECK (angle IS NULL OR angle IN ('leadership','technical','impact')),
  strength_score  INTEGER CHECK (strength_score IS NULL OR strength_score BETWEEN 0 AND 100),
  verb            TEXT,
  order_index     INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profile_bullets_experience
  ON public.profile_bullets (experience_id, order_index);

ALTER TABLE public.profile_bullets ENABLE ROW LEVEL SECURITY;

COMMIT;
