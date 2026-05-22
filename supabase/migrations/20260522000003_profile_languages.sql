-- Migration: profile_languages
--
-- Idiomas com proficiência normalizada em 5 níveis. O imported_resume
-- JSONB não tem campo dedicado pra idioma — vinha implícito em achievements
-- ou interests. Aqui ganha estrutura: o extrator IA mapeia textos livres
-- ("Avançado", "C1", "Fluente", "Inglês intermediário") pros 5 enums.

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_languages (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  proficiency  TEXT CHECK (proficiency IS NULL OR proficiency IN ('native','fluent','advanced','intermediate','basic')),
  order_index  INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profile_languages_user
  ON public.profile_languages (user_id, order_index);

ALTER TABLE public.profile_languages ENABLE ROW LEVEL SECURITY;

COMMIT;
