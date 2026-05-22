-- Migration: profile_projects (role + context) + profile_project_bullets
--
-- Adiciona campos `role` (qual papel o user teve) e `context` (onde/em qual
-- contexto rolou — universidade, hackathon, pessoal, etc.) à tabela
-- profile_projects pra ajudar o user a articular melhor a história do projeto.
--
-- Cria profile_project_bullets espelhando profile_bullets de experience:
-- bullets de impacto/responsabilidade. Permite reordenar e (futuro) gerar com
-- IA. Description (textão livre) fica como tech debt: novos projetos usam
-- bullets; description antigo continua sendo mostrado se preenchido.

BEGIN;

-- 1. Novos campos em profile_projects
ALTER TABLE public.profile_projects
  ADD COLUMN IF NOT EXISTS role    TEXT,
  ADD COLUMN IF NOT EXISTS context TEXT;

-- 2. Tabela de bullets
CREATE TABLE IF NOT EXISTS public.profile_project_bullets (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id   UUID NOT NULL REFERENCES public.profile_projects(id) ON DELETE CASCADE,
  text         TEXT NOT NULL,
  order_index  INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profile_project_bullets_project
  ON public.profile_project_bullets (project_id, order_index);

ALTER TABLE public.profile_project_bullets ENABLE ROW LEVEL SECURITY;

-- 3. RLS — bullets herdam owner via parent (profile_projects.user_id)
CREATE POLICY users_select_profile_project_bullets ON public.profile_project_bullets
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profile_projects p
      WHERE p.id = profile_project_bullets.project_id AND p.user_id = auth.uid()
    )
  );

CREATE POLICY users_insert_profile_project_bullets ON public.profile_project_bullets
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profile_projects p
      WHERE p.id = profile_project_bullets.project_id AND p.user_id = auth.uid()
    )
  );

CREATE POLICY users_update_profile_project_bullets ON public.profile_project_bullets
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.profile_projects p
      WHERE p.id = profile_project_bullets.project_id AND p.user_id = auth.uid()
    )
  );

CREATE POLICY users_delete_profile_project_bullets ON public.profile_project_bullets
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.profile_projects p
      WHERE p.id = profile_project_bullets.project_id AND p.user_id = auth.uid()
    )
  );

COMMIT;
