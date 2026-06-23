-- Migration: profile_personal_availability
--
-- PLANO-FASE-6 T6.3 (extra da trilha de coleta): disponibilidade do candidato
-- ("quando pode começar?"). Guarda o id da opção escolhida na trilha
-- (immediate / within_month / after_graduation / flexible) — recrutadores
-- filtram por isso na shortlist.
--
-- Aditiva, nullable, idempotente: inerte até a trilha (atrás da flag
-- trilha_coleta_v1) escrever. RLS herda das policies de profile_personal
-- (row-level), sem policy nova.
--
-- R2: migration via CLI (`supabase db push`) + manifest; nunca pelo dashboard.

BEGIN;

ALTER TABLE public.profile_personal
  ADD COLUMN IF NOT EXISTS availability text;

COMMENT ON COLUMN public.profile_personal.availability IS
  'Disponibilidade pra começar (id da opção da trilha): immediate | within_month | after_graduation | flexible. Coletado pela trilha de IA (PLANO-FASE-6).';

COMMIT;
