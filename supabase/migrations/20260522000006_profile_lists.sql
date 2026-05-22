-- Migration: profile_interests + profile_awards + profile_coursework
--
-- Três listas auxiliares. Interests tem índice único case-insensitive
-- pra evitar duplicatas; awards e coursework não — premiação pode ter
-- nome igual em anos diferentes, e cursos com mesmo nome também.

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_interests (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  order_index  INTEGER NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_profile_interests_user_name
  ON public.profile_interests (user_id, LOWER(name));

ALTER TABLE public.profile_interests ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_awards (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  date         DATE,
  order_index  INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_profile_awards_user
  ON public.profile_awards (user_id, order_index);

ALTER TABLE public.profile_awards ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_coursework (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  order_index  INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_profile_coursework_user
  ON public.profile_coursework (user_id, order_index);

ALTER TABLE public.profile_coursework ENABLE ROW LEVEL SECURITY;

COMMIT;
