-- Cargo/posição desejada específica (além da área ampla em profile_desired_titles).
-- Campo DEDICADO: coletado na trilha (gap.desired_position) e usado como BÔNUS
-- no match (não como dimensão de peso). Nullable; perfis existentes ficam null.

alter table public.profile_job_preferences
  add column if not exists desired_position text;

comment on column public.profile_job_preferences.desired_position is
  'Cargo/posição específica desejada (ex.: "Desenvolvedor Front-end"). Bônus no match.';
