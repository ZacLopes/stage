-- Gate 3.0F — remoção de idioma com CAS contra o estado observado.
--
-- A remoção avulsa de idioma no Assistente fazia deleteLanguage por nome
-- ambíguo. Este RPC remove o idioma que casa a chave normalizada SOMENTE se o
-- nível vivo ainda for o esperado (observado); se mudou, devolve `stale` e não
-- remove (manual recente vence). Devolve o nível removido para permitir o undo
-- (re-add via merge + set level). Roda sob o advisory lock canônico por usuário.
--
-- Aditiva. Não aplicar remotamente nesta rodada.

BEGIN;

DO $dependencies$
BEGIN
  IF to_regprocedure('public.profile_write_lock_key(uuid)') IS NULL
     OR to_regprocedure('public._profile_list_key(text)') IS NULL
     OR to_regprocedure('public._assert_profile_list_unique(uuid,text)') IS NULL
  THEN
    RAISE EXCEPTION 'guided_language_foundation_missing' USING ERRCODE = '55000';
  END IF;
END
$dependencies$;

CREATE OR REPLACE FUNCTION public.remove_guided_language_cas(
  p_user_id uuid,
  p_name text,
  p_expected_level text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_auth_uid uuid := auth.uid();
  v_id uuid;
  v_live text;
  v_name text := btrim(regexp_replace(
    COALESCE(p_name, ''),
    '[[:space:]]+',
    ' ',
    'g'
  ));
  v_expected text := NULLIF(btrim(COALESCE(p_expected_level, '')), '');
BEGIN
  IF v_auth_uid IS NULL OR p_user_id IS NULL OR v_auth_uid <> p_user_id THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '28000';
  END IF;
  IF v_name = '' THEN
    RAISE EXCEPTION 'language_name_required' USING ERRCODE = '22023';
  END IF;
  IF length(v_name) > 200 THEN
    RAISE EXCEPTION 'language_name_too_long' USING ERRCODE = '22023';
  END IF;
  IF v_expected IS NOT NULL
     AND v_expected <> ALL (
       ARRAY['native', 'fluent', 'advanced', 'intermediate', 'basic']
     ) THEN
    RAISE EXCEPTION 'invalid_expected_level' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(
    public.profile_write_lock_key(p_user_id)
  );
  PERFORM public._assert_profile_list_unique(
    p_user_id,
    'profile_languages'
  );
  SELECT id, proficiency
  INTO v_id, v_live
  FROM public.profile_languages
  WHERE user_id = p_user_id
    AND public._profile_list_key(name) = public._profile_list_key(v_name)
  LIMIT 1
  FOR UPDATE;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('status', 'not_found');
  END IF;
  -- CAS contra o nível observado: se o vivo mudou desde a leitura, o contexto
  -- do usuário está stale e NÃO removemos (manual recente vence).
  IF v_live IS DISTINCT FROM v_expected THEN
    RETURN jsonb_build_object('status', 'stale', 'live_level', v_live);
  END IF;

  DELETE FROM public.profile_languages
  WHERE id = v_id AND user_id = p_user_id;
  -- Devolve o nível removido para permitir o undo (re-add + set level).
  RETURN jsonb_build_object('status', 'applied', 'level', v_live);
END
$$;

REVOKE ALL ON FUNCTION public.remove_guided_language_cas(uuid, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.remove_guided_language_cas(uuid, text, text)
  TO authenticated;

COMMIT;
