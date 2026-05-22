-- Migration: profile_skills + profile_certifications
--
-- Skills explícitas (extraídas da seção "Habilidades" do CV) e
-- certificações. Skills têm índice único case-insensitive por user pra
-- evitar duplicatas tipo "Python" vs "python" vs "PYTHON". Categoria
-- é opcional e setada pela IA (ex: "Programming", "Soft Skills", "Tools").

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_skills (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  category     TEXT,
  order_index  INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_profile_skills_user_name
  ON public.profile_skills (user_id, LOWER(name));

CREATE INDEX IF NOT EXISTS idx_profile_skills_name
  ON public.profile_skills (LOWER(name));

ALTER TABLE public.profile_skills ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_certifications (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  issuer       TEXT,
  date         DATE,
  order_index  INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profile_certifications_user
  ON public.profile_certifications (user_id, order_index);

ALTER TABLE public.profile_certifications ENABLE ROW LEVEL SECURITY;

COMMIT;
