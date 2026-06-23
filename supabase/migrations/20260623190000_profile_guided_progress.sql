-- Migration: profile_guided_progress
--
-- PLANO-FASE-6 T6.6 (Increment 6): retomada da trilha de coleta entre devices.
-- Hoje os "trechos já abordados" vivem só no SharedPreferences do device
-- (trilha_addressed_<userId>) — trocar de celular re-pergunta tudo. Esta tabela
-- é o espelho server-side: 1 linha por (user, segmento abordado), append-only,
-- idempotente. O TrilhaProgress passa a ser híbrido (local failure-safe + server).
--
-- Segmentos possíveis (TrilhaProgress.segmentForStep): area, workmode, jobtype,
-- city, skills, languages, availability, experience, linkedin, certifications,
-- projects. Texto livre de propósito (vocabulário evolui com a trilha).
--
-- Espelha as convenções das tabelas profile_* (uuid PK + UNIQUE(user_id,…),
-- FK auth.users ON DELETE CASCADE, RLS auth.uid()=user_id, sem GRANT).
-- R2: migration via CLI (`supabase db push`) + manifest; nunca pelo dashboard.

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_guided_progress (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  segment    text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, segment)
);

CREATE INDEX IF NOT EXISTS idx_profile_guided_progress_user
  ON public.profile_guided_progress (user_id);

ALTER TABLE public.profile_guided_progress ENABLE ROW LEVEL SECURITY;

CREATE POLICY users_select_profile_guided_progress ON public.profile_guided_progress
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_guided_progress ON public.profile_guided_progress
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_guided_progress ON public.profile_guided_progress
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_guided_progress ON public.profile_guided_progress
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

COMMIT;
