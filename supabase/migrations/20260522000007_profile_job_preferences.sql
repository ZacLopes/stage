-- Migration: profile_job_preferences + filhas
--
-- Preferências de vaga pro matching e feed personalizado. Estruturado em
-- 4 tabelas:
--   - profile_job_preferences (1:1): localização primária + arrays de
--     experience_level/work_mode/job_types
--   - profile_desired_titles: cargos desejados, com origem (user_added
--     vs from_resume) pra a Semana 2 distinguir o que veio da IA
--   - profile_application_countries: países onde aplica + status de
--     autorização de trabalho (pra futuras vagas internacionais)
--   - profile_other_locations: localizações secundárias (ex: trabalha
--     em SP mas considera RJ e remoto)
--
-- Hoje todas essas prefs vivem em JSONB em user_profiles.preferences.
-- A migração será dual-written na edge function extract-profile.

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_job_preferences (
  user_id                    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  primary_location_country   TEXT,
  primary_location_state     TEXT,
  primary_location_city      TEXT,
  primary_location_postal_code TEXT,
  primary_location_lat       NUMERIC,
  primary_location_lng       NUMERIC,
  primary_location_radius_km INTEGER DEFAULT 50,
  experience_level           TEXT[] CHECK (experience_level IS NULL OR experience_level <@ ARRAY['entry','mid','senior']::TEXT[]),
  work_mode                  TEXT[] CHECK (work_mode IS NULL OR work_mode <@ ARRAY['remote','hybrid','in_person']::TEXT[]),
  job_types                  TEXT[] CHECK (job_types IS NULL OR job_types <@ ARRAY['full_time','internship','contract','part_time']::TEXT[]),
  updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.profile_job_preferences ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_desired_titles (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title        TEXT NOT NULL,
  source       TEXT CHECK (source IS NULL OR source IN ('user_added','from_resume')),
  order_index  INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_profile_desired_titles_user
  ON public.profile_desired_titles (user_id, order_index);

ALTER TABLE public.profile_desired_titles ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_application_countries (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  country_code  TEXT NOT NULL,
  work_auth     TEXT CHECK (work_auth IS NULL OR work_auth IN ('citizen','authorized','sponsorship_needed')),
  UNIQUE (user_id, country_code)
);

CREATE INDEX IF NOT EXISTS idx_profile_application_countries_user
  ON public.profile_application_countries (user_id);

ALTER TABLE public.profile_application_countries ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_other_locations (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  city        TEXT,
  state       TEXT,
  country     TEXT,
  radius_km   INTEGER DEFAULT 50
);

CREATE INDEX IF NOT EXISTS idx_profile_other_locations_user
  ON public.profile_other_locations (user_id);

ALTER TABLE public.profile_other_locations ENABLE ROW LEVEL SECURITY;

COMMIT;
