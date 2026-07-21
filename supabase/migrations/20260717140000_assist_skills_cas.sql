-- Fase 3 / Gate 3.0B — cutover seguro do editor visual de skills.
--
-- O card abre no servidor antes de ser exibido. A abertura persiste, sob o
-- advisory lock do perfil, a fotografia integral das linhas observadas. Apply:
--   * exige uma abertura prévia para o mesmo user_id + operation_id;
--   * compara a fotografia integral (não apenas nomes) sob o mesmo lock;
--   * uma edição concorrente de identidade, metadado, ordem ou nome retorna
--     stale sem gravar;
--   * persiste o desfecho e o estado resultante no mesmo recibo/transação.
--
-- Replay separa `resulting` (estado histórico causado/observado pela operação)
-- de `live` (estado real no momento da resposta). `can_undo` só é verdadeiro
-- quando o estado vivo ainda coincide integralmente com after_rows. Undo usa o
-- recibo no servidor e restaura id, categoria, vínculo canônico, ordem e data.
-- Qualquer mudança posterior, inclusive duplicata semântica, retorna stale.
--
-- Não aplicar remotamente nesta rodada.

BEGIN;

DO $dependencies$
BEGIN
  IF to_regprocedure(
       'public.profile_write_lock_key(uuid)'
     ) IS NULL
     OR to_regprocedure(
       'public._profile_list_key(text)'
     ) IS NULL
     OR to_regprocedure(
       'public._assert_profile_list_unique(uuid,text)'
     ) IS NULL
     OR to_regprocedure(
       'public._replace_profile_simple_list(uuid,text,jsonb,integer)'
     ) IS NULL THEN
    RAISE EXCEPTION 'profile_guided_write_foundation_missing'
      USING ERRCODE = '55000';
  END IF;
END
$dependencies$;

CREATE TABLE IF NOT EXISTS public.profile_assist_skill_operations (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  operation_id uuid NOT NULL,
  expected_keys jsonb NOT NULL,
  desired_names jsonb NOT NULL DEFAULT '[]'::jsonb,
  desired_keys jsonb NOT NULL DEFAULT '[]'::jsonb,
  outcome text NOT NULL DEFAULT 'opened'
    CHECK (outcome IN ('opened', 'applied', 'noop', 'stale')),
  before_rows jsonb NOT NULL,
  after_rows jsonb NOT NULL DEFAULT '[]'::jsonb,
  undone_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, operation_id),
  CHECK (jsonb_typeof(expected_keys) = 'array'),
  CHECK (jsonb_typeof(desired_names) = 'array'),
  CHECK (jsonb_typeof(desired_keys) = 'array'),
  CHECK (jsonb_typeof(before_rows) = 'array'),
  CHECK (jsonb_typeof(after_rows) = 'array'),
  CHECK (undone_at IS NULL OR outcome = 'applied')
);

CREATE INDEX IF NOT EXISTS profile_assist_skill_operations_user_created_idx
  ON public.profile_assist_skill_operations(user_id, created_at DESC);

ALTER TABLE public.profile_assist_skill_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.profile_assist_skill_operations
  FROM PUBLIC, anon, authenticated, service_role;

-- Abre o card de forma autoritativa. O mesmo operation_id do mesmo usuário
-- nunca recaptura um baseline: retry devolve a fotografia original.
CREATE OR REPLACE FUNCTION public.open_assist_skills_edit_v1(
  p_user_id uuid,
  p_operation_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET timezone = 'UTC'
AS $$
DECLARE
  v_auth_uid uuid := auth.uid();
  v_operation public.profile_assist_skill_operations%ROWTYPE;
  v_before_rows jsonb := '[]'::jsonb;
  v_expected_keys text[] := ARRAY[]::text[];
  v_baseline jsonb := '[]'::jsonb;
  v_row_count integer := 0;
BEGIN
  IF v_auth_uid IS NULL OR p_user_id IS NULL OR v_auth_uid <> p_user_id THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '28000';
  END IF;
  IF p_operation_id IS NULL THEN
    RAISE EXCEPTION 'operation_id_required' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(
    public.profile_write_lock_key(p_user_id)
  );

  SELECT * INTO v_operation
  FROM public.profile_assist_skill_operations
  WHERE user_id = p_user_id AND operation_id = p_operation_id
  FOR UPDATE;
  IF FOUND THEN
    SELECT COALESCE(
      jsonb_agg(value->>'name' ORDER BY ordinality),
      '[]'::jsonb
    )
    INTO v_baseline
    FROM jsonb_array_elements(v_operation.before_rows)
      WITH ORDINALITY AS row(value, ordinality);
    RETURN jsonb_build_object(
      'status', 'replay',
      'operation_id', p_operation_id,
      'baseline', v_baseline,
      'count', jsonb_array_length(v_operation.before_rows)
    );
  END IF;

  PERFORM public._assert_profile_list_unique(
    p_user_id,
    'profile_skills'
  );
  SELECT
    count(*)::integer,
    COALESCE(
      array_agg(
        public._profile_list_key(name)
        ORDER BY order_index, id
      ),
      ARRAY[]::text[]
    ),
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', id,
          'name', name,
          'category', category,
          'canonical_skill_id', canonical_skill_id,
          'order_index', order_index,
          'created_at', created_at
        ) ORDER BY order_index, id
      ),
      '[]'::jsonb
    )
  INTO v_row_count, v_expected_keys, v_before_rows
  FROM public.profile_skills
  WHERE user_id = p_user_id;

  -- O payload de apply aceita até 50 itens no baseline para permitir que um
  -- perfil legado acima do teto seja reduzido. Baselines ainda maiores, ou uma
  -- linha vazia/inválida, exigem revisão em vez de criar recibos sem limite.
  IF v_row_count > 50 OR EXISTS (
    SELECT 1
    FROM public.profile_skills
    WHERE user_id = p_user_id
      AND (
        public._profile_list_key(name) = ''
        OR length(btrim(regexp_replace(name, '[[:space:]]+', ' ', 'g'))) > 200
      )
  ) THEN
    RAISE EXCEPTION 'profile_skills_require_review'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.profile_assist_skill_operations(
    user_id,
    operation_id,
    expected_keys,
    before_rows
  ) VALUES (
    p_user_id,
    p_operation_id,
    to_jsonb(v_expected_keys),
    v_before_rows
  );

  SELECT COALESCE(
    jsonb_agg(value->>'name' ORDER BY ordinality),
    '[]'::jsonb
  )
  INTO v_baseline
  FROM jsonb_array_elements(v_before_rows)
    WITH ORDINALITY AS row(value, ordinality);
  RETURN jsonb_build_object(
    'status', 'opened',
    'operation_id', p_operation_id,
    'baseline', v_baseline,
    'count', jsonb_array_length(v_before_rows)
  );
END
$$;

CREATE OR REPLACE FUNCTION public.apply_assist_skills_edit_v1(
  p_user_id uuid,
  p_operation_id uuid,
  p_expected_names jsonb,
  p_names jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET timezone = 'UTC'
AS $$
DECLARE
  v_auth_uid uuid := auth.uid();
  v_raw text;
  v_name text;
  v_key text;
  v_expected_keys text[] := ARRAY[]::text[];
  v_desired_names text[] := ARRAY[]::text[];
  v_desired_keys text[] := ARRAY[]::text[];
  v_expected_json jsonb;
  v_desired_names_json jsonb;
  v_desired_keys_json jsonb;
  v_current_rows jsonb := '[]'::jsonb;
  v_after_rows jsonb := '[]'::jsonb;
  v_resulting_rows jsonb := '[]'::jsonb;
  v_live jsonb := '[]'::jsonb;
  v_resulting jsonb := '[]'::jsonb;
  v_outcome text;
  v_response_outcome text;
  v_replace_result jsonb;
  v_can_undo boolean := false;
  v_operation public.profile_assist_skill_operations%ROWTYPE;
BEGIN
  IF v_auth_uid IS NULL OR p_user_id IS NULL OR v_auth_uid <> p_user_id THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '28000';
  END IF;
  IF p_operation_id IS NULL THEN
    RAISE EXCEPTION 'operation_id_required' USING ERRCODE = '22023';
  END IF;
  IF p_expected_names IS NULL
     OR jsonb_typeof(p_expected_names) <> 'array'
     OR p_names IS NULL
     OR jsonb_typeof(p_names) <> 'array' THEN
    RAISE EXCEPTION 'names_must_be_array' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_expected_names) > 50
     OR jsonb_array_length(p_names) > 50 THEN
    RAISE EXCEPTION 'too_many_items' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_expected_names) AS item(value)
    WHERE jsonb_typeof(value) <> 'string'
  ) OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_names) AS item(value)
    WHERE jsonb_typeof(value) <> 'string'
  ) THEN
    RAISE EXCEPTION 'name_must_be_string' USING ERRCODE = '22023';
  END IF;

  FOR v_raw IN SELECT value FROM jsonb_array_elements_text(p_expected_names)
  LOOP
    v_name := btrim(regexp_replace(v_raw, '[[:space:]]+', ' ', 'g'));
    IF length(v_name) > 200 THEN
      RAISE EXCEPTION 'item_too_long' USING ERRCODE = '22023';
    END IF;
    v_key := public._profile_list_key(v_name);
    IF v_name <> '' AND NOT (v_key = ANY(v_expected_keys)) THEN
      v_expected_keys := array_append(v_expected_keys, v_key);
    END IF;
  END LOOP;

  FOR v_raw IN SELECT value FROM jsonb_array_elements_text(p_names)
  LOOP
    v_name := btrim(regexp_replace(v_raw, '[[:space:]]+', ' ', 'g'));
    IF length(v_name) > 200 THEN
      RAISE EXCEPTION 'item_too_long' USING ERRCODE = '22023';
    END IF;
    v_key := public._profile_list_key(v_name);
    IF v_name <> '' AND NOT (v_key = ANY(v_desired_keys)) THEN
      v_desired_names := array_append(v_desired_names, v_name);
      v_desired_keys := array_append(v_desired_keys, v_key);
    END IF;
  END LOOP;
  IF cardinality(v_desired_keys) > 12 THEN
    RAISE EXCEPTION 'too_many_items' USING ERRCODE = '22023';
  END IF;

  v_expected_json := to_jsonb(v_expected_keys);
  v_desired_names_json := to_jsonb(v_desired_names);
  v_desired_keys_json := to_jsonb(v_desired_keys);

  PERFORM pg_advisory_xact_lock(
    public.profile_write_lock_key(p_user_id)
  );

  SELECT * INTO v_operation
  FROM public.profile_assist_skill_operations
  WHERE user_id = p_user_id AND operation_id = p_operation_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'operation_not_opened' USING ERRCODE = '22023';
  END IF;

  IF v_operation.expected_keys IS DISTINCT FROM v_expected_json THEN
    RAISE EXCEPTION 'operation_snapshot_mismatch' USING ERRCODE = '22023';
  END IF;

  -- A operação terminal é um recibo imutável. O mesmo request retorna seu
  -- desfecho histórico, mas `live` e `can_undo` são recalculados agora.
  IF v_operation.outcome <> 'opened' THEN
    IF v_operation.desired_names IS DISTINCT FROM v_desired_names_json
       OR v_operation.desired_keys IS DISTINCT FROM v_desired_keys_json THEN
      RAISE EXCEPTION 'operation_id_reused' USING ERRCODE = '22023';
    END IF;

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', id,
          'name', name,
          'category', category,
          'canonical_skill_id', canonical_skill_id,
          'order_index', order_index,
          'created_at', created_at
        ) ORDER BY order_index, id
      ),
      '[]'::jsonb
    )
    INTO v_current_rows
    FROM public.profile_skills
    WHERE user_id = p_user_id;

    v_response_outcome := CASE
      WHEN v_operation.undone_at IS NOT NULL THEN 'undone'
      ELSE v_operation.outcome
    END;
    -- O resulting do apply é sempre o estado pós-apply original. Um undo
    -- posterior muda o outcome/live, não reescreve a autoria histórica.
    v_resulting_rows := v_operation.after_rows;
    v_can_undo := v_operation.outcome = 'applied'
                  AND v_operation.undone_at IS NULL
                  AND v_current_rows IS NOT DISTINCT FROM v_operation.after_rows;

    SELECT COALESCE(
      jsonb_agg(value->>'name' ORDER BY ordinality),
      '[]'::jsonb
    ) INTO v_resulting
    FROM jsonb_array_elements(v_resulting_rows)
      WITH ORDINALITY AS row(value, ordinality);
    SELECT COALESCE(
      jsonb_agg(value->>'name' ORDER BY ordinality),
      '[]'::jsonb
    ) INTO v_live
    FROM jsonb_array_elements(v_current_rows)
      WITH ORDINALITY AS row(value, ordinality);

    RETURN jsonb_build_object(
      'status', 'replay',
      'outcome', v_response_outcome,
      'operation_id', p_operation_id,
      'resulting', v_resulting,
      'live', v_live,
      'count', jsonb_array_length(v_current_rows),
      'can_undo', v_can_undo
    );
  END IF;

  -- O expected enviado pelo cliente precisa ser exatamente o baseline emitido
  -- pela abertura. A proteção de concorrência real, porém, é a igualdade das
  -- linhas completas abaixo — não um hash derivado pelo cliente.
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', id,
        'name', name,
        'category', category,
        'canonical_skill_id', canonical_skill_id,
        'order_index', order_index,
        'created_at', created_at
      ) ORDER BY order_index, id
    ),
    '[]'::jsonb
  )
  INTO v_current_rows
  FROM public.profile_skills
  WHERE user_id = p_user_id;

  IF v_current_rows IS DISTINCT FROM v_operation.before_rows THEN
    v_outcome := 'stale';
    -- Stale não causou mudança: resulting continua sendo o baseline da
    -- operação; o estado divergente é exposto separadamente em `live`.
    v_after_rows := v_operation.before_rows;
  ELSIF v_operation.expected_keys IS NOT DISTINCT FROM v_desired_keys_json THEN
    v_outcome := 'noop';
    v_after_rows := v_current_rows;
  ELSE
    -- Igualdade integral com before_rows implica ausência de duplicata nova.
    -- A função interna ainda valida a seção e preserva os metadados retidos.
    v_replace_result := public._replace_profile_simple_list(
      p_user_id,
      'profile_skills',
      v_desired_names_json,
      12
    );
    v_outcome := COALESCE(v_replace_result->>'status', '');
    IF v_outcome NOT IN ('applied', 'noop') THEN
      RAISE EXCEPTION 'invalid_replace_receipt' USING ERRCODE = '22023';
    END IF;
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', id,
          'name', name,
          'category', category,
          'canonical_skill_id', canonical_skill_id,
          'order_index', order_index,
          'created_at', created_at
        ) ORDER BY order_index, id
      ),
      '[]'::jsonb
    )
    INTO v_after_rows
    FROM public.profile_skills
    WHERE user_id = p_user_id;
  END IF;

  UPDATE public.profile_assist_skill_operations
  SET desired_names = v_desired_names_json,
      desired_keys = v_desired_keys_json,
      outcome = v_outcome,
      after_rows = v_after_rows
  WHERE user_id = p_user_id AND operation_id = p_operation_id;

  SELECT COALESCE(
    jsonb_agg(value->>'name' ORDER BY ordinality),
    '[]'::jsonb
  ) INTO v_resulting
  FROM jsonb_array_elements(v_after_rows)
    WITH ORDINALITY AS row(value, ordinality);
  -- Consulte o estado real mesmo na primeira resposta. Em stale, nenhuma
  -- mutação ocorreu e live pode divergir (inclusive conter legado duplicado).
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', id,
        'name', name,
        'category', category,
        'canonical_skill_id', canonical_skill_id,
        'order_index', order_index,
        'created_at', created_at
      ) ORDER BY order_index, id
    ),
    '[]'::jsonb
  )
  INTO v_current_rows
  FROM public.profile_skills
  WHERE user_id = p_user_id;
  SELECT COALESCE(
    jsonb_agg(value->>'name' ORDER BY ordinality),
    '[]'::jsonb
  ) INTO v_live
  FROM jsonb_array_elements(v_current_rows)
    WITH ORDINALITY AS row(value, ordinality);
  RETURN jsonb_build_object(
    'status', v_outcome,
    'outcome', v_outcome,
    'operation_id', p_operation_id,
    'resulting', v_resulting,
    'live', v_live,
    'count', jsonb_array_length(v_current_rows),
    'can_undo', v_outcome = 'applied'
  );
END
$$;

CREATE OR REPLACE FUNCTION public.undo_assist_skills_edit_v1(
  p_user_id uuid,
  p_operation_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET timezone = 'UTC'
AS $$
DECLARE
  v_auth_uid uuid := auth.uid();
  v_operation public.profile_assist_skill_operations%ROWTYPE;
  v_current_rows jsonb := '[]'::jsonb;
  v_live jsonb := '[]'::jsonb;
  v_resulting jsonb := '[]'::jsonb;
  v_restored_rows jsonb := '[]'::jsonb;
  v_row jsonb;
BEGIN
  IF v_auth_uid IS NULL OR p_user_id IS NULL OR v_auth_uid <> p_user_id THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '28000';
  END IF;
  IF p_operation_id IS NULL THEN
    RAISE EXCEPTION 'operation_id_required' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(
    public.profile_write_lock_key(p_user_id)
  );
  SELECT * INTO v_operation
  FROM public.profile_assist_skill_operations
  WHERE user_id = p_user_id AND operation_id = p_operation_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'operation_not_found' USING ERRCODE = '22023';
  END IF;
  IF v_operation.outcome <> 'applied' THEN
    RAISE EXCEPTION 'operation_not_undoable' USING ERRCODE = '22023';
  END IF;

  -- Sempre devolvemos o baseline como resulting do undo. `live` é consultado
  -- de verdade inclusive em replay, pois pode ter mudado após o undo.
  SELECT COALESCE(
    jsonb_agg(value->>'name' ORDER BY ordinality),
    '[]'::jsonb
  ) INTO v_resulting
  FROM jsonb_array_elements(v_operation.before_rows)
    WITH ORDINALITY AS row(value, ordinality);

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', id,
        'name', name,
        'category', category,
        'canonical_skill_id', canonical_skill_id,
        'order_index', order_index,
        'created_at', created_at
      ) ORDER BY order_index, id
    ),
    '[]'::jsonb
  )
  INTO v_current_rows
  FROM public.profile_skills
  WHERE user_id = p_user_id;

  SELECT COALESCE(
    jsonb_agg(value->>'name' ORDER BY ordinality),
    '[]'::jsonb
  ) INTO v_live
  FROM jsonb_array_elements(v_current_rows)
    WITH ORDINALITY AS row(value, ordinality);

  IF v_operation.undone_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status', 'replay',
      'outcome', 'undone',
      'operation_id', p_operation_id,
      'resulting', v_resulting,
      'live', v_live,
      'count', jsonb_array_length(v_current_rows)
    );
  END IF;

  -- A comparação vem ANTES de qualquer assert de unicidade. Assim uma
  -- duplicata semântica introduzida depois do apply é uma edição nova/stale,
  -- não uma exceção que esconde o desfecho honesto.
  IF v_current_rows IS DISTINCT FROM v_operation.after_rows THEN
    RETURN jsonb_build_object(
      'status', 'stale',
      'outcome', 'stale',
      'operation_id', p_operation_id,
      'resulting', v_resulting,
      'live', v_live,
      'count', jsonb_array_length(v_current_rows)
    );
  END IF;

  DELETE FROM public.profile_skills WHERE user_id = p_user_id;
  FOR v_row IN
    SELECT value FROM jsonb_array_elements(v_operation.before_rows)
  LOOP
    INSERT INTO public.profile_skills(
      id,
      user_id,
      name,
      category,
      canonical_skill_id,
      order_index,
      created_at
    ) VALUES (
      (v_row->>'id')::uuid,
      p_user_id,
      v_row->>'name',
      v_row->>'category',
      NULLIF(v_row->>'canonical_skill_id', '')::uuid,
      (v_row->>'order_index')::integer,
      (v_row->>'created_at')::timestamptz
    );
    -- O trigger de taxonomia pode recomputar canonical_skill_id no INSERT.
    -- Reafirmamos o valor capturado sem tocar `name`, preservando o recibo.
    UPDATE public.profile_skills
    SET canonical_skill_id = NULLIF(v_row->>'canonical_skill_id', '')::uuid
    WHERE id = (v_row->>'id')::uuid AND user_id = p_user_id;
  END LOOP;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', id,
        'name', name,
        'category', category,
        'canonical_skill_id', canonical_skill_id,
        'order_index', order_index,
        'created_at', created_at
      ) ORDER BY order_index, id
    ),
    '[]'::jsonb
  )
  INTO v_restored_rows
  FROM public.profile_skills
  WHERE user_id = p_user_id;
  IF v_restored_rows IS DISTINCT FROM v_operation.before_rows THEN
    RAISE EXCEPTION 'undo_verification_failed' USING ERRCODE = '23514';
  END IF;

  UPDATE public.profile_assist_skill_operations
  SET undone_at = now()
  WHERE user_id = p_user_id AND operation_id = p_operation_id;

  RETURN jsonb_build_object(
    'status', 'undone',
    'outcome', 'undone',
    'operation_id', p_operation_id,
    'resulting', v_resulting,
    'live', v_resulting,
    'count', jsonb_array_length(v_operation.before_rows)
  );
END
$$;

REVOKE ALL ON FUNCTION public.open_assist_skills_edit_v1(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.apply_assist_skills_edit_v1(
  uuid, uuid, jsonb, jsonb
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.undo_assist_skills_edit_v1(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.open_assist_skills_edit_v1(uuid, uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.apply_assist_skills_edit_v1(
  uuid, uuid, jsonb, jsonb
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.undo_assist_skills_edit_v1(uuid, uuid)
  TO authenticated;

COMMIT;
