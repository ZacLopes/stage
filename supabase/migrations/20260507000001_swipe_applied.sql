-- Adiciona controle de "vaga aplicada" em swipe_actions.
-- Usuário curte uma vaga via swipe → aparece na nova aba "Curtidas".
-- Lá ele marca quando aplicou no site da empresa (`applied = true`).

BEGIN;

ALTER TABLE public.swipe_actions
  ADD COLUMN IF NOT EXISTS applied BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS applied_at TIMESTAMPTZ;

-- Índice parcial pra buscar rapidamente "vagas curtidas e aplicadas/pendentes" do user
CREATE INDEX IF NOT EXISTS idx_swipe_actions_liked_user
  ON public.swipe_actions (user_id, applied)
  WHERE action = 'liked';

COMMIT;
