-- Adiciona coluna `phone` em user_profiles.
-- Coleta obrigatória no ProfileSetup (Step 1, formato BR mobile),
-- salvamos apenas os dígitos limpos (sem máscara) pra normalizar busca.

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS phone TEXT;

COMMENT ON COLUMN public.user_profiles.phone IS
  'Celular do usuário em dígitos brutos (sem máscara). 10 ou 11 dígitos com DDD.';
