-- Migration: adiciona min_match_score ao user_preferences
--
-- Filtro client-side: vagas com score < min_match_score são ocultadas no feed.
-- O score combina cache de match_analyses (preciso, IA) + fallback
-- determinístico do MatchScoreCalculator (instantâneo). Sem custo IA extra.
--
-- null = sem filtro. Valor entre 0-100.

BEGIN;

ALTER TABLE public.user_preferences
ADD COLUMN IF NOT EXISTS min_match_score INT
  CHECK (min_match_score IS NULL OR (min_match_score >= 0 AND min_match_score <= 100));

COMMIT;
