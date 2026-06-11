-- Fase 1 T1.7 — fonte única do gate de onboarding (aposenta hasCampaign).
-- Coluna + backfill a partir de campaigns (min(created_at) por user).
-- O client 2.3.0 passa a ler/escrever onboarding_completed_at; builds antigas
-- continuam criando campaigns e a Bridge 2 (migration seguinte) converte.

ALTER TABLE public.profile_personal
  ADD COLUMN IF NOT EXISTS onboarding_completed_at timestamptz;

-- Backfill 1: users com profile_personal e campaign.
UPDATE public.profile_personal pp
SET onboarding_completed_at = c.first_at
FROM (SELECT user_id, min(created_at) AS first_at
      FROM public.campaigns GROUP BY user_id) c
WHERE c.user_id = pp.user_id
  AND pp.onboarding_completed_at IS NULL;

-- Backfill 2: users com campaign mas SEM linha em profile_personal (fluxo
-- legacy pré-profile-first). INSERT mínimo é seguro: únicos NOT NULL são
-- user_id e colunas com default (verificado em plan mode 2026-06-10).
INSERT INTO public.profile_personal (user_id, onboarding_completed_at)
SELECT c.user_id, min(c.created_at)
FROM public.campaigns c
WHERE NOT EXISTS (SELECT 1 FROM public.profile_personal pp
                  WHERE pp.user_id = c.user_id)
GROUP BY c.user_id
ON CONFLICT (user_id) DO NOTHING;

COMMENT ON COLUMN public.profile_personal.onboarding_completed_at IS
  'Fonte única do gate de onboarding (Fase 1 T1.7). Substitui hasCampaign; backfill de campaigns em 2026-06-10.';
