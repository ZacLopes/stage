-- Gate 3.0D — o replace MANUAL de listas simples passa a ser AUTORITATIVO sobre
-- a grafia. Quando o usuário edita a caixa/acento/whitespace de um item retido,
-- a grafia enviada vence (como o editor manual antigo fazia via updateSkill).
-- Um reorder puro (nome idêntico) continua atualizando apenas order_index, sem
-- disparar o trigger de taxonomia — canonical/metadados preservados.
--
-- Corrige a regressão introduzida ao ligar o editor manual ao contrato atômico:
-- a versão de 17/07/13h conservava o nome canônico existente e descartava, em
-- silêncio, uma correção de grafia do usuário (viola "manual autoritativo" e
-- "sem falso sucesso").
--
-- Afeta replace_profile_skills_atomic_v1 e replace_profile_interests_atomic_v1
-- (ambos contratos de replace MANUAL). NÃO toca o merge guiado (aditivo, lógica
-- própria) nem os writers de importação. Aditiva/idempotente. Não aplicar
-- remotamente nesta rodada.

BEGIN;

DO $dependencies$
BEGIN
  IF to_regprocedure(
       'public._replace_profile_simple_list(uuid,text,jsonb,integer)'
     ) IS NULL THEN
    RAISE EXCEPTION 'replace_profile_simple_list_missing'
      USING ERRCODE = '55000';
  END IF;
END
$dependencies$;

CREATE OR REPLACE FUNCTION public._replace_profile_simple_list(
  p_user_id uuid,
  p_table text,
  p_names jsonb,
  p_max_items integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_auth_uid uuid := auth.uid();
  v_raw text;
  v_name text;
  v_key text;
  v_seen text[] := ARRAY[]::text[];
  v_names text[] := ARRAY[]::text[];
  v_keep_ids uuid[] := ARRAY[]::uuid[];
  v_id uuid;
  v_old_order integer;
  v_old_name text;
  v_index integer := 0;
  v_changed boolean := false;
  v_rows integer := 0;
BEGIN
  IF v_auth_uid IS NULL OR p_user_id IS NULL OR v_auth_uid <> p_user_id THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '28000';
  END IF;
  IF p_table IS NULL
     OR p_table <> ALL (ARRAY['profile_skills', 'profile_interests']) THEN
    RAISE EXCEPTION 'invalid_table' USING ERRCODE = '22023';
  END IF;
  IF p_names IS NULL OR jsonb_typeof(p_names) <> 'array' THEN
    RAISE EXCEPTION 'names_must_be_array' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_names) > 50 THEN
    RAISE EXCEPTION 'too_many_items' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_names) AS item(value)
    WHERE jsonb_typeof(value) <> 'string'
  ) THEN
    RAISE EXCEPTION 'name_must_be_string' USING ERRCODE = '22023';
  END IF;

  -- Valida e normaliza o payload inteiro ANTES da primeira escrita.
  FOR v_raw IN
    SELECT value
    FROM jsonb_array_elements_text(p_names)
  LOOP
    v_name := btrim(regexp_replace(v_raw, '[[:space:]]+', ' ', 'g'));
    IF length(v_name) > 200 THEN
      RAISE EXCEPTION 'item_too_long' USING ERRCODE = '22023';
    END IF;
    v_key := public._profile_list_key(v_name);
    IF v_name = '' OR v_key = ANY(v_seen) THEN
      CONTINUE;
    END IF;
    v_seen := array_append(v_seen, v_key);
    v_names := array_append(v_names, v_name);
  END LOOP;
  IF p_max_items IS NOT NULL AND cardinality(v_names) > p_max_items THEN
    RAISE EXCEPTION 'too_many_items' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(
    public.profile_write_lock_key(p_user_id)
  );
  PERFORM public._assert_profile_list_unique(p_user_id, p_table);

  FOREACH v_name IN ARRAY v_names
  LOOP
    v_key := public._profile_list_key(v_name);
    EXECUTE format(
      'SELECT id, order_index, name FROM public.%I '
      'WHERE user_id = $1 AND public._profile_list_key(name) = $2 '
      'ORDER BY order_index, id LIMIT 1 FOR UPDATE',
      p_table
    )
    INTO v_id, v_old_order, v_old_name
    USING p_user_id, v_key;

    IF v_id IS NULL THEN
      EXECUTE format(
        'INSERT INTO public.%I (user_id, name, order_index) '
        'VALUES ($1, $2, $3) RETURNING id',
        p_table
      )
      INTO v_id
      USING p_user_id, v_name, v_index;
      v_changed := true;
    ELSIF v_old_name IS DISTINCT FROM v_name THEN
      -- Replace MANUAL: a grafia enviada é o estado desejado do usuário. Uma
      -- variante cosmética (case/acento/whitespace) vence a grafia armazenada,
      -- como o editor manual antigo fazia. Incluir `name` no UPDATE reaciona o
      -- trigger de taxonomia (recomputa canonical_skill_id a partir do novo
      -- nome) — comportamento idêntico ao caminho manual anterior. category é
      -- preservada.
      EXECUTE format(
        'UPDATE public.%I SET name = $1, order_index = $2 '
        'WHERE id = $3 AND user_id = $4',
        p_table
      )
      USING v_name, v_index, v_id, p_user_id;
      v_changed := true;
    ELSIF v_old_order IS DISTINCT FROM v_index THEN
      -- Só reordenação (nome idêntico): NÃO inclui `name` no UPDATE, para não
      -- disparar o trigger nem recalcular metadados sem necessidade.
      EXECUTE format(
        'UPDATE public.%I SET order_index = $1 '
        'WHERE id = $2 AND user_id = $3',
        p_table
      )
      USING v_index, v_id, p_user_id;
      v_changed := true;
    END IF;

    v_keep_ids := array_append(v_keep_ids, v_id);
    v_id := NULL;
    v_index := v_index + 1;
  END LOOP;

  EXECUTE format(
    'DELETE FROM public.%I '
    'WHERE user_id = $1 AND NOT (id = ANY($2))',
    p_table
  )
  USING p_user_id, v_keep_ids;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows > 0 THEN
    v_changed := true;
  END IF;

  RETURN jsonb_build_object(
    'status', CASE WHEN v_changed THEN 'applied' ELSE 'noop' END,
    'count', cardinality(v_names)
  );
END
$$;

-- Helper privado: mantém sem EXECUTE para PUBLIC/roles (CREATE OR REPLACE não
-- reseta privilégios, mas reafirmamos por segurança).
REVOKE ALL ON FUNCTION
  public._replace_profile_simple_list(uuid, text, jsonb, integer)
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
