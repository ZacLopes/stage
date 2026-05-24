-- Migration: phone_number_e164 + preservação do formato original em phone_number
--
-- Tier 3.1 do plano "1000x melhor". Antes: extract-profile fazia
-- `phone_number.replace(/\D/g, '')` que destruía formatação do CV
-- (`+55 (11) 98216-4700` virava `11982164700`). Adapt v2 mostrava telefone
-- "feio" no PDF adaptado.
--
-- Solução: 2 colunas.
--   - `phone_number`: formato bonito como veio do CV (preservado pela
--      mudança no postProcess do extract-profile em commit acompanhante).
--   - `phone_number_e164`: dígitos puros com prefixo '+' — usado por
--      OneSignal/sync de vagas que precisa formato canônico.
--
-- TRIGGER `_set_phone_e164` mantém `phone_number_e164` sempre em sync
-- com `phone_country_code` + `phone_number`. Sem precisar mudar a RPC
-- save_profile_from_json (mais simples + atômico).
--
-- Backfill: roda UPDATE depois do trigger criado pra popular existentes.

BEGIN;

ALTER TABLE public.profile_personal
  ADD COLUMN IF NOT EXISTS phone_number_e164 TEXT;

COMMENT ON COLUMN public.profile_personal.phone_number_e164 IS
  'Telefone normalizado E.164 (+ prefixo + dígitos). Computado por trigger a partir de phone_country_code + phone_number. Usado por OneSignal/sync.';

-- Trigger function: deriva phone_number_e164 dos campos crus.
-- Edge case: se phone_country_code não tiver '+', adiciona. Se vazio, NULL.
CREATE OR REPLACE FUNCTION public._set_phone_e164()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_cc TEXT;
  v_num TEXT;
  v_e164 TEXT;
BEGIN
  v_cc := COALESCE(NEW.phone_country_code, '');
  v_num := COALESCE(NEW.phone_number, '');
  -- Só dígitos
  v_num := regexp_replace(v_num, '\D', '', 'g');
  v_cc := regexp_replace(v_cc, '\D', '', 'g');
  IF length(v_num) = 0 THEN
    NEW.phone_number_e164 := NULL;
  ELSIF length(v_cc) = 0 THEN
    -- Sem código de país: assume +55 (default BR) — alinhado com a regra
    -- do extract-profile.
    NEW.phone_number_e164 := '+55' || v_num;
  ELSE
    NEW.phone_number_e164 := '+' || v_cc || v_num;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profile_personal_phone_e164 ON public.profile_personal;
CREATE TRIGGER trg_profile_personal_phone_e164
  BEFORE INSERT OR UPDATE OF phone_country_code, phone_number, phone_number_e164
  ON public.profile_personal
  FOR EACH ROW
  EXECUTE FUNCTION public._set_phone_e164();

-- Backfill: força trigger a rodar nas rows existentes.
-- UPDATE com SET phone_number = phone_number (no-op) re-aciona o trigger.
UPDATE public.profile_personal
SET phone_number = phone_number
WHERE phone_number_e164 IS NULL AND phone_number IS NOT NULL;

COMMIT;
