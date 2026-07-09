-- Fase 7 · gate-list +10 (Tarefa 2): área custom mapeada "por trás".
--
-- A trilha passa a aceitar QUALQUER área. Cada área fora das 13 canônicas gera,
-- além da linha do usuário (source='user_added'), uma linha CANÔNICA oculta
-- (source='inferred') pra o candidato ficar visível/matchável no match, no feed
-- e na busca do admin (que só entendem as 13). O app esconde 'inferred' das
-- telas do usuário; os readers leem todos os títulos, então funcionam sem
-- alteração.
--
-- ⚠️ Aplicar ANTES de testar/lançar o build +10 — sem isso o write-back da
-- trilha (linha 'inferred') viola o CHECK.

BEGIN;

ALTER TABLE public.profile_desired_titles
  DROP CONSTRAINT IF EXISTS profile_desired_titles_source_check;

ALTER TABLE public.profile_desired_titles
  ADD CONSTRAINT profile_desired_titles_source_check
  CHECK (source IS NULL OR source IN ('user_added', 'from_resume', 'legacy_merge', 'inferred'));

COMMIT;
