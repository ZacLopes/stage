-- Fase 7 · Onda 2 — venda da shortlist
--
-- (C) Memória comercial da operação B2B:
--   - candidate_list_items.outcome: resultado por candidato entregue (o único
--     ground truth do valor da shortlist — base de case de venda e pricing).
--   - candidate_list_exports.client_id: PARA QUEM cada PII foi (rastreabilidade;
--     o cliente vira obrigatório na criação de lista, enforce no edge).
--
-- FORA do escopo desta onda (decisão do fundador — é teste, não valida modelo
-- ainda): ciclo de vida do consent (expired/expires_at), coleta in-app de
-- consent, campanha retroativa. O export desta onda IGNORA o consent.

BEGIN;

-- (C-T3) Resultado por candidato entregue à empresa.
ALTER TABLE public.candidate_list_items
  ADD COLUMN IF NOT EXISTS outcome TEXT
    CHECK (outcome IS NULL OR outcome IN (
      'interviewing', 'interviewed', 'hired', 'not_selected', 'no_response'
    )),
  ADD COLUMN IF NOT EXISTS outcome_note TEXT,
  ADD COLUMN IF NOT EXISTS outcome_at TIMESTAMPTZ;

COMMENT ON COLUMN public.candidate_list_items.outcome IS
  'Resultado do candidato entregue (Fase 7 Onda 2): interviewing/interviewed/hired/not_selected/no_response. NULL = sem retorno registrado.';

-- (C-T2) Rastreabilidade do compartilhamento: para qual cliente cada export foi.
ALTER TABLE public.candidate_list_exports
  ADD COLUMN IF NOT EXISTS client_id UUID
    REFERENCES public.employer_clients(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_candidate_list_exports_client
  ON public.candidate_list_exports (client_id, created_at DESC);

COMMENT ON COLUMN public.candidate_list_exports.client_id IS
  'Cliente destinatário do export (Fase 7 Onda 2). Cliente é obrigatório na criação da lista (enforce no edge admin-candidate-lists).';

COMMIT;
