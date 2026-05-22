-- Migration: profile_personal
--
-- Semana 1 da migração profile-first. Tabela 1:1 com o usuário, sucessor
-- estruturado de user_profiles.gamification_data.imported_resume.parsed.
-- Hoje todo dado pessoal vive num JSONB aninhado; aqui vira coluna pra
-- permitir query direta, validação de schema e telemetria estruturada.
--
-- Convive com o JSONB legacy: a edge function extract-profile escreve
-- AMBOS (parsed JSONB + tabelas relacionais) durante a transição.
--
-- RLS policies vivem na migration 20260522000010_profile_rls_policies.sql,
-- agrupando todas as tabelas profile_* num só arquivo pra facilitar review.

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_personal (
  user_id                UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  first_name             TEXT,
  last_name              TEXT,
  email                  TEXT,
  phone_country_code     TEXT,
  phone_number           TEXT,
  headline               TEXT,
  summary                TEXT,
  gender                 TEXT CHECK (gender IN ('male','female','other','prefer_not_to_say')),
  age_range              TEXT CHECK (age_range IN ('under_18','18_24','25_34','35_44','45_54','55_64','65_plus')),
  location_country       TEXT,
  location_state         TEXT,
  location_city          TEXT,
  location_postal_code   TEXT,
  location_street_address TEXT,
  attribution_source     TEXT,
  profile_source         TEXT CHECK (profile_source IN ('imported','manual','mixed')),
  completeness_score     INTEGER NOT NULL DEFAULT 0 CHECK (completeness_score BETWEEN 0 AND 100),
  schema_version         INTEGER NOT NULL DEFAULT 1,
  profile_completed_at   TIMESTAMPTZ,
  last_extracted_at      TIMESTAMPTZ,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.profile_personal ENABLE ROW LEVEL SECURITY;

COMMIT;
