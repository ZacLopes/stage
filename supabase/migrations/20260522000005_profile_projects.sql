-- Migration: profile_projects
--
-- Projetos pessoais ou freelances. Distinto de experiences (que são
-- empregos formais). Inclui website pra portfolio link, datas opcionais
-- (alguns projetos são pontuais sem data clara).

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_projects (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  website      TEXT,
  description  TEXT,
  start_date   DATE,
  end_date     DATE,
  is_current   BOOLEAN NOT NULL DEFAULT FALSE,
  order_index  INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profile_projects_user
  ON public.profile_projects (user_id, order_index);

ALTER TABLE public.profile_projects ENABLE ROW LEVEL SECURITY;

COMMIT;
