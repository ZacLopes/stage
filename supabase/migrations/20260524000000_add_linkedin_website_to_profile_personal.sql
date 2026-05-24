-- Migration: adiciona colunas linkedin_url + website em profile_personal
--
-- Bug histórico: `PROFILE_JSON_SCHEMA` (extract-profile) capturava
-- `personal.linkedin` desde a Semana 1 e a RPC `save_profile_from_json`
-- tentava inserir o valor (linha 66 da migration 20260522000011), mas
-- a coluna NÃO existia na tabela `profile_personal` (criada em
-- 20260522000000 sem o campo). Resultado: INSERT silenciosamente ignorava
-- o LinkedIn do CV. ~151 users com `profile_source='imported'` afetados.
--
-- Esta migration cria as 2 colunas (linkedin_url + website). A RPC
-- save_profile_from_json é atualizada separadamente em
-- 20260524000001_save_profile_function_linkedin_website.sql.
--
-- Backfill dos users existentes: script
-- supabase/scripts/backfill_linkedin.ts copia direto do
-- gamification_data.imported_resume.parsed.personal.linkedin (sem
-- chamar OpenAI).

BEGIN;

ALTER TABLE public.profile_personal
  ADD COLUMN IF NOT EXISTS linkedin_url TEXT,
  ADD COLUMN IF NOT EXISTS website TEXT;

COMMENT ON COLUMN public.profile_personal.linkedin_url IS
  'URL do LinkedIn do candidato (linkedin.com/in/username ou https://...). Extraído de CV importado.';
COMMENT ON COLUMN public.profile_personal.website IS
  'Site pessoal / portfólio do candidato. Extraído de CV importado.';

COMMIT;
