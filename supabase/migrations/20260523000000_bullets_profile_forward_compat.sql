-- Migration: bullets profile_bullets compat (Semana 2 — forward-only)
--
-- CONTEXTO: schema atual de approved_bullets tem `experience_id UUID` MAS
-- 100% dos 69 bullets existentes têm experience_id=NULL. O matching real é
-- via `experience_phase_id` (texto tipo 'm3.{cat}.{n}'). Por isso NÃO há
-- caminho de migração retroativa limpa pra profile_bullets que respeite FKs.
--
-- DECISÃO: forward-only. A edge function `generate-bullets` será refatorada
-- pra aceitar `target_experience_id` opcional. Quando vier, escreve direto em
-- profile_bullets (além de bullet_versions/approved_bullets pra compat).
-- Bullets HISTÓRICOS permanecem só em approved_bullets — leitura legacy
-- continua funcionando via JSONB imported_resume.parsed em user_profiles.
--
-- Esta migration é só de DOCUMENTAÇÃO: nenhuma DDL real. Existe pra deixar
-- registrado o "porquê" da migration retroativa não ter sido feita, evitando
-- que alguém tente fazer no futuro sem entender o issue.

BEGIN;

-- Sanity check: confirmar que profile_bullets existe (foi criada na Semana 1).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'profile_bullets'
  ) THEN
    RAISE EXCEPTION 'profile_bullets não existe — Semana 1 não aplicada?';
  END IF;
END $$;

-- Sem DDL — só comentário pra auditoria.
COMMENT ON TABLE public.profile_bullets IS
  'Bullets Harvard relacionais (Semana 1 profile-first). Forward-only desde 2026-05-23: '
  'bullets novos via generate-bullets refatorado escrevem aqui + bullet_versions legacy. '
  'Bullets pré-2026-05-23 (~69 rows em approved_bullets) ficam só em approved_bullets — '
  'matching retroativo seria via experience_phase_id (texto), inviável sem FK.';

COMMIT;
