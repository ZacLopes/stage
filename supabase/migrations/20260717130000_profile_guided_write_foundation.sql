-- Fase 3 / Gate 3.0A — fundação transacional para listas do perfil.
--
-- Esta migration NÃO liga a Fase 2 nem muda a navegação. Ela prepara contratos
-- server-side que poderão substituir, num checkpoint posterior, os writers
-- cliente `get -> vários writes -> delete` de skills/interesses/áreas e a
-- atualização de nível de idioma.
--
-- Invariantes deste gate:
--   1. uma operação lógica acontece em uma única transação;
--   2. todo writer autenticado das quatro tabelas participa do mesmo lock por
--      usuário, inclusive os writes PostgREST legados;
--   3. o merge guiado é somente aditivo: nunca apaga nem rebaixa dado manual;
--   4. nível de idioma usa compare-and-set (CAS): valor vivo diferente do
--      esperado retorna `stale` e permanece intacto;
--   5. helpers SECURITY DEFINER não ficam executáveis por PUBLIC;
--   6. o writer legacy do Edge já vem fenced/fill-empty da fundação de
--      importação de 14/07; esta migration valida o pré-requisito e apenas
--      reafirma seu ACL service-only, sem criar uma segunda camada.
--   7. duplicatas semânticas preexistentes falham de forma explícita; este gate
--      não cria índices globais enquanto writers legados usam outra regra.
--
-- Não aplicar remotamente nesta rodada.

BEGIN;

-- Esta fundação é deliberadamente posterior à fundação de Fonte importada.
-- Falhar cedo é mais seguro que recriar parcialmente o protocolo de lock ou o
-- writer de importação e abrir uma janela com contratos divergentes.
DO $dependencies$
BEGIN
  IF to_regprocedure('public.profile_write_lock_key(uuid)') IS NULL
     OR to_regprocedure('public._fence_profile_writes()') IS NULL
     OR to_regprocedure('public.save_profile_fill_empty_service(uuid,jsonb)') IS NULL
     OR to_regprocedure('public.save_profile_from_json(uuid,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'profile_import_foundation_missing'
      USING ERRCODE = '55000';
  END IF;
END
$dependencies$;

-- Chave textual única do contrato. Usa a mesma normalização do controller:
-- trim, colapso de whitespace, case-insensitive e dobra dos acentos latinos que
-- o domínio Dart também dobra. Não tenta resolver aliases semânticos.
CREATE OR REPLACE FUNCTION public._profile_list_key(p_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT lower(
    translate(
      translate(
        btrim(
          regexp_replace(COALESCE(p_value, ''), '[[:space:]]+', ' ', 'g')
        ),
        'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
        'AAAAAEEEEIIIIOOOOOUUUUCN'
      ),
      'áàâãäéèêëíìîïóòôõöúùûüçñ',
      'aaaaaeeeeiiiiooooouuuucn'
    )
  )
$$;

-- Menor número = fonte mais forte. NULL e legacy_merge são dados explícitos
-- legados do usuário, portanto ficam acima de CV/inferência; user_added pode
-- promovê-los sem esconder nem rebaixar informação manual.
CREATE OR REPLACE FUNCTION public._desired_title_source_rank(p_source text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE p_source
    WHEN 'user_added' THEN 0
    WHEN 'legacy_merge' THEN 1
    WHEN 'from_resume' THEN 2
    WHEN 'inferred' THEN 3
    ELSE 1
  END
$$;

-- Fail-closed local da operação. Os índices normalizados globais pertencem ao
-- futuro cutover, quando TODOS os writers (incluindo os estacionados da fonte
-- importada) usarem a mesma chave. Criá-los antes poderia fazer um writer
-- legado DELETE->INSERT falhar depois do DELETE. Enquanto isso, o advisory
-- estabiliza a seção e cada RPC nova recusa ambiguidades sem apagar/mesclar.
CREATE OR REPLACE FUNCTION public._assert_profile_list_unique(
  p_user_id uuid,
  p_table text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_column text;
  v_duplicate boolean;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user_id_required' USING ERRCODE = '22023';
  END IF;
  v_column := CASE p_table
    WHEN 'profile_skills' THEN 'name'
    WHEN 'profile_interests' THEN 'name'
    WHEN 'profile_languages' THEN 'name'
    WHEN 'profile_desired_titles' THEN 'title'
    ELSE NULL
  END;
  IF v_column IS NULL THEN
    RAISE EXCEPTION 'invalid_profile_list' USING ERRCODE = '22023';
  END IF;

  EXECUTE format(
    'SELECT EXISTS ('
      'SELECT 1 FROM public.%I '
      'WHERE user_id = $1 AND public._profile_list_key(%I) <> '''' '
      'GROUP BY public._profile_list_key(%I) HAVING count(*) > 1'
    ')',
    p_table,
    v_column,
    v_column
  )
  INTO v_duplicate
  USING p_user_id;

  IF v_duplicate THEN
    RAISE EXCEPTION USING
      MESSAGE = 'duplicate_' || p_table || '_require_review',
      ERRCODE = '23505';
  END IF;
END
$$;

-- Skills, interesses e idiomas já estão fenced pela migration de 14/07. A
-- única tabela nova neste protocolo é desired_titles; reutilizamos exatamente
-- a mesma trigger BEFORE STATEMENT (ordem advisory -> tuple).
DROP TRIGGER IF EXISTS zzz_fence_stmt ON public.profile_desired_titles;
CREATE TRIGGER zzz_fence_stmt
  BEFORE INSERT OR UPDATE OR DELETE ON public.profile_desired_titles
  FOR EACH STATEMENT EXECUTE FUNCTION public._fence_profile_writes();

-- Replace-all atômico para listas simples usadas pelas telas manuais. Mantém
-- IDs e metadados (category/canonical_skill_id) dos itens que continuam na
-- lista; só cria/remove o necessário. Repetir o mesmo payload retorna noop.
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
      'SELECT id, order_index FROM public.%I '
      'WHERE user_id = $1 AND public._profile_list_key(name) = $2 '
      'ORDER BY order_index, id LIMIT 1 FOR UPDATE',
      p_table
    )
    INTO v_id, v_old_order
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
    ELSIF v_old_order IS DISTINCT FROM v_index THEN
      -- Uma variante apenas cosmética (case/acento/whitespace) representa a
      -- mesma identidade normalizada. Conservamos o nome canônico existente e
      -- não acionamos `UPDATE OF name`, que poderia recalcular metadados.
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

CREATE OR REPLACE FUNCTION public.replace_profile_skills_atomic_v1(
  p_user_id uuid,
  p_names jsonb
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public._replace_profile_simple_list(
    p_user_id,
    'profile_skills',
    p_names,
    12
  )
$$;

CREATE OR REPLACE FUNCTION public.replace_profile_interests_atomic_v1(
  p_user_id uuid,
  p_names jsonb
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public._replace_profile_simple_list(
    p_user_id,
    'profile_interests',
    p_names,
    50
  )
$$;

-- Áreas carregam source; por isso têm contrato próprio. A lista recebida é o
-- estado FINAL (incluindo as linhas inferred já derivadas pelo domínio).
CREATE OR REPLACE FUNCTION public.replace_profile_desired_titles_atomic_v1(
  p_user_id uuid,
  p_titles jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_auth_uid uuid := auth.uid();
  v_item jsonb;
  v_title text;
  v_source text;
  v_key text;
  v_seen text[] := ARRAY[]::text[];
  v_titles text[] := ARRAY[]::text[];
  v_sources text[] := ARRAY[]::text[];
  v_keep_ids uuid[] := ARRAY[]::uuid[];
  v_id uuid;
  v_old_title text;
  v_old_source text;
  v_old_order integer;
  v_duplicate_index integer;
  v_index integer := 0;
  v_changed boolean := false;
  v_rows integer := 0;
BEGIN
  IF v_auth_uid IS NULL OR p_user_id IS NULL OR v_auth_uid <> p_user_id THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '28000';
  END IF;
  IF p_titles IS NULL OR jsonb_typeof(p_titles) <> 'array' THEN
    RAISE EXCEPTION 'titles_must_be_array' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_titles) > 50 THEN
    RAISE EXCEPTION 'too_many_titles' USING ERRCODE = '22023';
  END IF;

  -- Valida tudo antes de escrever. Em duplicatas normalizadas, conserva a
  -- fonte mais forte mesmo quando ela aparece depois no payload.
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_titles)
  LOOP
    IF jsonb_typeof(v_item) <> 'object' THEN
      RAISE EXCEPTION 'title_must_be_object' USING ERRCODE = '22023';
    END IF;
    IF NOT (v_item ? 'title')
       OR jsonb_typeof(v_item->'title') <> 'string' THEN
      RAISE EXCEPTION 'title_must_be_string' USING ERRCODE = '22023';
    END IF;
    IF v_item ? 'source'
       AND jsonb_typeof(v_item->'source') NOT IN ('string', 'null') THEN
      RAISE EXCEPTION 'title_source_must_be_string_or_null'
        USING ERRCODE = '22023';
    END IF;
    v_title := btrim(regexp_replace(
      COALESCE(v_item->>'title', ''),
      '[[:space:]]+',
      ' ',
      'g'
    ));
    v_source := NULLIF(btrim(COALESCE(v_item->>'source', '')), '');
    IF v_title = '' THEN
      CONTINUE;
    END IF;
    IF length(v_title) > 200 THEN
      RAISE EXCEPTION 'title_too_long' USING ERRCODE = '22023';
    END IF;
    IF v_source IS NOT NULL
       AND v_source <> ALL (
         ARRAY['user_added', 'from_resume', 'legacy_merge', 'inferred']
       ) THEN
      RAISE EXCEPTION 'invalid_title_source' USING ERRCODE = '22023';
    END IF;
    v_key := public._profile_list_key(v_title);
    v_duplicate_index := array_position(v_seen, v_key);
    IF v_duplicate_index IS NOT NULL THEN
      IF public._desired_title_source_rank(v_source)
         < public._desired_title_source_rank(
             v_sources[v_duplicate_index]
           ) THEN
        v_titles[v_duplicate_index] := v_title;
        v_sources[v_duplicate_index] := v_source;
      END IF;
      CONTINUE;
    END IF;
    v_seen := array_append(v_seen, v_key);
    v_titles := array_append(v_titles, v_title);
    v_sources := array_append(v_sources, v_source);
  END LOOP;

  PERFORM pg_advisory_xact_lock(
    public.profile_write_lock_key(p_user_id)
  );
  PERFORM public._assert_profile_list_unique(
    p_user_id,
    'profile_desired_titles'
  );

  IF cardinality(v_titles) > 0 THEN
    FOR v_index IN 1..cardinality(v_titles)
    LOOP
      v_title := v_titles[v_index];
      v_source := v_sources[v_index];
      v_key := public._profile_list_key(v_title);
      SELECT id, title, source, order_index
      INTO v_id, v_old_title, v_old_source, v_old_order
      FROM public.profile_desired_titles
      WHERE user_id = p_user_id
        AND public._profile_list_key(title) = v_key
      ORDER BY order_index, id
      LIMIT 1
      FOR UPDATE;

      IF v_id IS NULL THEN
        INSERT INTO public.profile_desired_titles(
          user_id, title, source, order_index
        )
        VALUES (p_user_id, v_title, v_source, v_index - 1)
        RETURNING id INTO v_id;
        v_changed := true;
      ELSE
        IF v_old_title IS DISTINCT FROM v_title
           OR v_old_source IS DISTINCT FROM v_source
           OR v_old_order IS DISTINCT FROM v_index - 1 THEN
          UPDATE public.profile_desired_titles
          SET title = v_title,
              source = v_source,
              order_index = v_index - 1
          WHERE id = v_id AND user_id = p_user_id;
          v_changed := true;
        END IF;
      END IF;
      v_keep_ids := array_append(v_keep_ids, v_id);
      v_id := NULL;
    END LOOP;
  END IF;

  DELETE FROM public.profile_desired_titles
  WHERE user_id = p_user_id AND NOT (id = ANY(v_keep_ids));
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows > 0 THEN
    v_changed := true;
  END IF;

  RETURN jsonb_build_object(
    'status', CASE WHEN v_changed THEN 'applied' ELSE 'noop' END,
    'count', cardinality(v_titles)
  );
END
$$;

-- Merge aditivo usado pela coleta guiada. Nunca faz replace-all. Um retry do
-- mesmo passo é naturalmente idempotente graças às chaves normalizadas.
CREATE OR REPLACE FUNCTION public.merge_guided_profile_list(
  p_user_id uuid,
  p_section text,
  p_items jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_auth_uid uuid := auth.uid();
  v_item jsonb;
  v_raw text;
  v_name text;
  v_source text;
  v_key text;
  v_seen text[] := ARRAY[]::text[];
  v_names text[] := ARRAY[]::text[];
  v_sources text[] := ARRAY[]::text[];
  v_index integer;
  v_order integer;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_updated_total integer := 0;
  v_existing integer := 0;
  v_duplicate_index integer;
BEGIN
  IF v_auth_uid IS NULL OR p_user_id IS NULL OR v_auth_uid <> p_user_id THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '28000';
  END IF;
  IF p_section IS NULL OR p_section <> ALL (
    ARRAY['skills', 'interests', 'languages', 'desired_titles']
  ) THEN
    RAISE EXCEPTION 'invalid_section' USING ERRCODE = '22023';
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'items_must_be_array' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_items) > 50 THEN
    RAISE EXCEPTION 'too_many_items' USING ERRCODE = '22023';
  END IF;

  -- Validação completa antes da primeira escrita.
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    IF p_section = 'desired_titles' THEN
      IF jsonb_typeof(v_item) <> 'object' THEN
        RAISE EXCEPTION 'title_must_be_object' USING ERRCODE = '22023';
      END IF;
      IF NOT (v_item ? 'title')
         OR jsonb_typeof(v_item->'title') <> 'string' THEN
        RAISE EXCEPTION 'title_must_be_string' USING ERRCODE = '22023';
      END IF;
      IF v_item ? 'source'
         AND jsonb_typeof(v_item->'source') NOT IN ('string', 'null') THEN
        RAISE EXCEPTION 'title_source_must_be_string_or_null'
          USING ERRCODE = '22023';
      END IF;
      v_raw := COALESCE(v_item->>'title', '');
      v_source := COALESCE(
        NULLIF(btrim(COALESCE(v_item->>'source', '')), ''),
        'user_added'
      );
      IF v_source <> ALL (
        ARRAY['user_added', 'inferred']
      ) THEN
        RAISE EXCEPTION 'invalid_title_source' USING ERRCODE = '22023';
      END IF;
    ELSE
      IF jsonb_typeof(v_item) <> 'string' THEN
        RAISE EXCEPTION 'item_must_be_string' USING ERRCODE = '22023';
      END IF;
      v_raw := v_item #>> '{}';
      v_source := NULL;
    END IF;

    v_name := btrim(regexp_replace(v_raw, '[[:space:]]+', ' ', 'g'));
    IF length(v_name) > 200 THEN
      RAISE EXCEPTION 'item_too_long' USING ERRCODE = '22023';
    END IF;
    v_key := public._profile_list_key(v_name);
    IF v_name = '' THEN
      CONTINUE;
    END IF;
    v_duplicate_index := array_position(v_seen, v_key);
    IF v_duplicate_index IS NOT NULL THEN
      IF p_section = 'desired_titles'
         AND public._desired_title_source_rank(v_source)
             < public._desired_title_source_rank(
                 v_sources[v_duplicate_index]
               ) THEN
        v_names[v_duplicate_index] := v_name;
        v_sources[v_duplicate_index] := v_source;
      END IF;
      CONTINUE;
    END IF;
    v_seen := array_append(v_seen, v_key);
    v_names := array_append(v_names, v_name);
    v_sources := array_append(v_sources, v_source);
  END LOOP;

  PERFORM pg_advisory_xact_lock(
    public.profile_write_lock_key(p_user_id)
  );
  PERFORM public._assert_profile_list_unique(
    p_user_id,
    CASE p_section
      WHEN 'skills' THEN 'profile_skills'
      WHEN 'interests' THEN 'profile_interests'
      WHEN 'languages' THEN 'profile_languages'
      ELSE 'profile_desired_titles'
    END
  );

  IF p_section = 'skills' THEN
    SELECT count(DISTINCT public._profile_list_key(name))
    INTO v_existing
    FROM public.profile_skills
    WHERE user_id = p_user_id
      AND public._profile_list_key(name) <> '';
    SELECT count(*)
    INTO v_index
    FROM unnest(v_names) AS candidate(name)
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.profile_skills AS current
      WHERE current.user_id = p_user_id
        AND public._profile_list_key(current.name)
            = public._profile_list_key(candidate.name)
    );
    -- Perfil legado pode já ter >12. Repetir um item existente continua noop;
    -- só bloqueamos uma tentativa de AUMENTAR ainda mais a lista.
    IF v_index > 0 AND v_existing + v_index > 12 THEN
      RAISE EXCEPTION 'too_many_items' USING ERRCODE = '22023';
    END IF;
  END IF;

  IF cardinality(v_names) > 0 THEN
    FOR v_index IN 1..cardinality(v_names)
    LOOP
      v_name := v_names[v_index];
      v_source := v_sources[v_index];

      IF p_section = 'skills' THEN
        IF NOT EXISTS (
          SELECT 1 FROM public.profile_skills
          WHERE user_id = p_user_id
            AND public._profile_list_key(name)
                = public._profile_list_key(v_name)
        ) THEN
          SELECT COALESCE(max(order_index), -1) + 1 INTO v_order
          FROM public.profile_skills WHERE user_id = p_user_id;
          INSERT INTO public.profile_skills(user_id, name, order_index)
          VALUES (p_user_id, v_name, v_order);
          v_inserted := v_inserted + 1;
        END IF;
      ELSIF p_section = 'interests' THEN
        IF NOT EXISTS (
          SELECT 1 FROM public.profile_interests
          WHERE user_id = p_user_id
            AND public._profile_list_key(name)
                = public._profile_list_key(v_name)
        ) THEN
          SELECT COALESCE(max(order_index), -1) + 1 INTO v_order
          FROM public.profile_interests WHERE user_id = p_user_id;
          INSERT INTO public.profile_interests(user_id, name, order_index)
          VALUES (p_user_id, v_name, v_order);
          v_inserted := v_inserted + 1;
        END IF;
      ELSIF p_section = 'languages' THEN
        IF NOT EXISTS (
          SELECT 1 FROM public.profile_languages
          WHERE user_id = p_user_id
            AND public._profile_list_key(name)
                = public._profile_list_key(v_name)
        ) THEN
          SELECT COALESCE(max(order_index), -1) + 1 INTO v_order
          FROM public.profile_languages WHERE user_id = p_user_id;
          INSERT INTO public.profile_languages(
            user_id, name, proficiency, order_index
          )
          VALUES (p_user_id, v_name, NULL, v_order);
          v_inserted := v_inserted + 1;
        END IF;
      ELSE
        -- Uma escolha explícita do usuário pode promover uma linha que antes
        -- existia apenas como inferência/import. O caminho inverso nunca
        -- rebaixa user_added.
        UPDATE public.profile_desired_titles
        SET title = v_name,
            source = v_source
        WHERE user_id = p_user_id
          AND public._profile_list_key(title)
              = public._profile_list_key(v_name)
          AND public._desired_title_source_rank(source)
              > public._desired_title_source_rank(v_source);
        GET DIAGNOSTICS v_updated = ROW_COUNT;
        IF v_updated = 0 AND NOT EXISTS (
          SELECT 1 FROM public.profile_desired_titles
          WHERE user_id = p_user_id
            AND public._profile_list_key(title)
                = public._profile_list_key(v_name)
        ) THEN
          SELECT COALESCE(max(order_index), -1) + 1 INTO v_order
          FROM public.profile_desired_titles WHERE user_id = p_user_id;
          INSERT INTO public.profile_desired_titles(
            user_id, title, source, order_index
          )
          VALUES (p_user_id, v_name, v_source, v_order);
          v_inserted := v_inserted + 1;
        ELSIF v_updated > 0 THEN
          v_updated_total := v_updated_total + v_updated;
        END IF;
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'status', CASE
      WHEN v_inserted + v_updated_total > 0 THEN 'applied'
      ELSE 'noop'
    END,
    'inserted', v_inserted,
    'updated', v_updated_total,
    'changed', v_inserted + v_updated_total
  );
END
$$;

-- O passo de nível só pode preencher o valor que ele observou. No fluxo
-- guiado atual o esperado normal é NULL; se o usuário editar manualmente para
-- outro nível enquanto o card está aberto, o resultado é stale e nada muda.
CREATE OR REPLACE FUNCTION public.set_guided_language_level_cas(
  p_user_id uuid,
  p_name text,
  p_expected_level text,
  p_new_level text
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
  v_new text := NULLIF(btrim(COALESCE(p_new_level, '')), '');
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
  IF v_new IS NULL
     OR v_new <> ALL (
       ARRAY['native', 'fluent', 'advanced', 'intermediate', 'basic']
     ) THEN
    RAISE EXCEPTION 'invalid_new_level' USING ERRCODE = '22023';
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
  IF v_live IS NOT DISTINCT FROM v_new THEN
    RETURN jsonb_build_object('status', 'noop');
  END IF;
  IF v_live IS DISTINCT FROM v_expected THEN
    RETURN jsonb_build_object('status', 'stale', 'live_level', v_live);
  END IF;

  UPDATE public.profile_languages
  SET proficiency = v_new
  WHERE id = v_id AND user_id = p_user_id;
  RETURN jsonb_build_object('status', 'applied');
END
$$;

-- Matriz de privilégios explícita. Helpers ficam privados; somente os cinco
-- contratos autenticados e o writer canônico do Edge recebem EXECUTE.
REVOKE ALL ON FUNCTION public.profile_write_lock_key(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public._profile_list_key(text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public._desired_title_source_rank(text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public._assert_profile_list_unique(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public._fence_profile_writes()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public._replace_profile_simple_list(uuid, text, jsonb, integer)
  FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.replace_profile_skills_atomic_v1(uuid, jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.replace_profile_interests_atomic_v1(uuid, jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.replace_profile_desired_titles_atomic_v1(uuid, jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.merge_guided_profile_list(uuid, text, jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.set_guided_language_level_cas(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.save_profile_from_json(uuid, jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.replace_profile_skills_atomic_v1(uuid, jsonb)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.replace_profile_interests_atomic_v1(uuid, jsonb)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.replace_profile_desired_titles_atomic_v1(uuid, jsonb)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.merge_guided_profile_list(uuid, text, jsonb)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_guided_language_level_cas(uuid, text, text, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_profile_from_json(uuid, jsonb)
  TO service_role;

COMMIT;
