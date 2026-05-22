-- Adiciona data de nascimento exata em profile_personal.
-- age_range (faixa) é mantida e populada via derivação no app — usada
-- por filtros agregados e por trilhas que dependem só da faixa.
-- date_of_birth permite usos futuros: aniversário, vagas com idade
-- mínima, segmentação demográfica precisa.
ALTER TABLE public.profile_personal
  ADD COLUMN IF NOT EXISTS date_of_birth DATE;

COMMENT ON COLUMN public.profile_personal.date_of_birth IS
  'Data de nascimento exata. Capturada no onboarding (masking question). age_range é derivado automaticamente.';
