-- Fase 1 T1.8 (decisão do fundador #4, 2026-06-10): consent POR CANDIDATO
-- registrado por ops quando o candidato confirma fora do app (WhatsApp).
-- granted_via = canal da confirmação; scope = o que pode ser compartilhado;
-- status_reason (coluna existente) vira a nota de evidência humana
-- ("confirmou por WhatsApp em DD/MM"). O export CSV de shortlists SÓ aceita
-- candidatos com consent status='granted'.

ALTER TABLE public.candidate_data_sharing_consents
  ADD COLUMN IF NOT EXISTS granted_via text
    CHECK (granted_via IS NULL OR granted_via IN ('whatsapp','email','in_app')),
  ADD COLUMN IF NOT EXISTS scope text[] NOT NULL DEFAULT '{contact_info}';

COMMENT ON COLUMN public.candidate_data_sharing_consents.status_reason IS
  'Nota de evidência do consent (ex.: "confirmou por WhatsApp em 10/06"). Preenchida por ops via admin dashboard.';
