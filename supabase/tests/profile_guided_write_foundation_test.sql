-- Fase 3 / Gate 3.0A — harness LOCAL da fundação de writers guiados.
-- Executado apenas pelo cluster PostgreSQL efêmero criado em
-- scripts/run_profile_guided_write_foundation_test.sh.

\set ON_ERROR_STOP on

DO $$ BEGIN CREATE ROLE authenticated NOLOGIN; EXCEPTION WHEN duplicate_object THEN END $$;
DO $$ BEGIN CREATE ROLE anon NOLOGIN; EXCEPTION WHEN duplicate_object THEN END $$;
DO $$ BEGIN CREATE ROLE service_role NOLOGIN BYPASSRLS; EXCEPTION WHEN duplicate_object THEN END $$;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE auth.users (id uuid PRIMARY KEY);
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb->>'sub',
    ''
  )::uuid
$$;
GRANT USAGE ON SCHEMA auth TO authenticated, anon, service_role;
GRANT SELECT ON auth.users TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated, anon, service_role;

CREATE TABLE public.profile_personal (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  touch_count integer NOT NULL DEFAULT 0
);

CREATE TABLE public.profile_skills (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name text NOT NULL,
  category text,
  canonical_skill_id uuid,
  order_index integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX idx_profile_skills_user_name
  ON public.profile_skills(user_id, lower(name));
-- Espelha a característica relevante de trg_profile_skills_canonical: um
-- UPDATE que inclui `name` recalcula o vínculo. Para uma skill sem catálogo,
-- este stub limpa o ID; um reorder correto (SET apenas order_index) não dispara.
CREATE OR REPLACE FUNCTION public._test_recompute_canonical_skill()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.canonical_skill_id := NULL;
  RETURN NEW;
END
$$;
CREATE TRIGGER trg_profile_skills_canonical
  BEFORE UPDATE OF name ON public.profile_skills
  FOR EACH ROW EXECUTE FUNCTION public._test_recompute_canonical_skill();

-- Espelha o lock relevante de trg_profile_skills_completeness: todo write de
-- skill toca profile_personal. Sem o writer service fenced,
-- import(personal->skill) x manual(skill->personal) pode formar ciclo.
CREATE OR REPLACE FUNCTION public._test_touch_profile_personal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_uid uuid;
BEGIN
  v_uid := CASE WHEN TG_OP = 'DELETE' THEN OLD.user_id ELSE NEW.user_id END;
  UPDATE public.profile_personal
  SET touch_count = touch_count + 1
  WHERE user_id = v_uid;
  RETURN NULL;
END
$$;
CREATE TRIGGER trg_profile_skills_completeness
  AFTER INSERT OR UPDATE OR DELETE ON public.profile_skills
  FOR EACH ROW EXECUTE FUNCTION public._test_touch_profile_personal();

CREATE TABLE public.profile_interests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name text NOT NULL,
  order_index integer NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX idx_profile_interests_user_name
  ON public.profile_interests(user_id, lower(name));

CREATE TABLE public.profile_languages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name text NOT NULL,
  proficiency text CHECK (
    proficiency IS NULL OR proficiency IN (
      'native', 'fluent', 'advanced', 'intermediate', 'basic'
    )
  ),
  order_index integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.profile_desired_titles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title text NOT NULL,
  source text CHECK (
    source IS NULL OR source IN (
      'user_added', 'from_resume', 'legacy_merge', 'inferred'
    )
  ),
  order_index integer NOT NULL DEFAULT 0
);

DO $rls$
DECLARE v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'profile_skills',
    'profile_interests',
    'profile_languages',
    'profile_desired_titles'
  ]
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', v_table);
    EXECUTE format(
      'CREATE POLICY owner_select ON public.%I FOR SELECT TO authenticated '
      'USING (auth.uid() = user_id)',
      v_table
    );
    EXECUTE format(
      'CREATE POLICY owner_insert ON public.%I FOR INSERT TO authenticated '
      'WITH CHECK (auth.uid() = user_id)',
      v_table
    );
    EXECUTE format(
      'CREATE POLICY owner_update ON public.%I FOR UPDATE TO authenticated '
      'USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id)',
      v_table
    );
    EXECUTE format(
      'CREATE POLICY owner_delete ON public.%I FOR DELETE TO authenticated '
      'USING (auth.uid() = user_id)',
      v_table
    );
    EXECUTE format(
      'GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO authenticated',
      v_table
    );
  END LOOP;
END
$rls$;

-- Pré-requisitos equivalentes à fundação de importação de 14/07. O Gate 3.0A
-- reutiliza esses contratos; não os renomeia nem cria um segundo wrapper.
CREATE OR REPLACE FUNCTION public.profile_write_lock_key(p_user_id uuid)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT hashtextextended('profile_write:' || p_user_id::text, 0)
$$;

CREATE OR REPLACE FUNCTION public._fence_profile_writes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF pg_trigger_depth() = 1 AND auth.uid() IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(
      public.profile_write_lock_key(auth.uid())
    );
  END IF;
  RETURN NULL;
END
$$;

DO $fence_prerequisites$
DECLARE v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'profile_skills', 'profile_interests', 'profile_languages'
  ]
  LOOP
    EXECUTE format(
      'CREATE TRIGGER zzz_fence_stmt '
      'BEFORE INSERT OR UPDATE OR DELETE ON public.%I '
      'FOR EACH STATEMENT EXECUTE FUNCTION public._fence_profile_writes()',
      v_table
    );
  END LOOP;
END
$fence_prerequisites$;

-- Stub canônico já fenced, representando save_profile_from_json instalado pela
-- fundação anterior. Os campos artificiais existem apenas neste harness local.
CREATE OR REPLACE FUNCTION public.save_profile_from_json(
  p_user_id uuid,
  p_data jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(
    public.profile_write_lock_key(p_user_id)
  );
  INSERT INTO public.profile_personal(user_id, touch_count)
  VALUES (p_user_id, 0)
  ON CONFLICT (user_id) DO UPDATE
    SET touch_count = public.profile_personal.touch_count + 1;
  IF COALESCE(p_data->>'hold_seconds', '') <> '' THEN
    PERFORM pg_sleep((p_data->>'hold_seconds')::numeric);
  END IF;
  IF COALESCE(p_data->>'inject_skill', '') <> '' THEN
    INSERT INTO public.profile_skills(user_id, name, order_index)
    VALUES (p_user_id, p_data->>'inject_skill', 0)
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN jsonb_build_object('ok', true);
END
$$;
REVOKE ALL ON FUNCTION public.save_profile_from_json(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_profile_from_json(uuid, jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.save_profile_fill_empty_service(
  p_user_id uuid,
  p_data jsonb
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.save_profile_from_json(p_user_id, p_data)
$$;
REVOKE ALL ON FUNCTION public.save_profile_fill_empty_service(uuid, jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.save_profile_fill_empty_service(uuid, jsonb)
  TO service_role;

-- Migration REAL sob teste.
\ir ../migrations/20260717130000_profile_guided_write_foundation.sql
\ir ../migrations/20260717140000_assist_skills_cas.sql
\ir ../migrations/20260717150000_manual_skills_replace_authoritative.sql

INSERT INTO auth.users(id) VALUES
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222'),
  ('33333333-3333-3333-3333-333333333333');

-- T1 — replace de skills é atômico, idempotente e preserva ID/metadados.
DO $test$
DECLARE
  u uuid := '11111111-1111-1111-1111-111111111111';
  python_id uuid;
  replay_id uuid;
  result jsonb;
  got_state text;
BEGIN
  INSERT INTO public.profile_skills(
    user_id, name, category, canonical_skill_id, order_index
  )
  VALUES (u, 'Python', 'manual', gen_random_uuid(), 4)
  RETURNING id INTO python_id;

  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u::text, 'role', 'authenticated')::text,
    false
  );
  SET LOCAL ROLE authenticated;
  SELECT public.replace_profile_skills_atomic_v1(
    u, '["  Python  ", "SQL"]'::jsonb
  )
  INTO result;
  RESET ROLE;

  IF result->>'status' <> 'applied' OR (result->>'count')::int <> 2 THEN
    RAISE EXCEPTION 'T1 result inesperado: %', result;
  END IF;
  SELECT id INTO replay_id FROM public.profile_skills
  WHERE user_id = u AND name = 'Python';
  IF replay_id <> python_id THEN
    RAISE EXCEPTION 'T1 perdeu o ID da skill preservada';
  END IF;
  -- Reorder (nome idêntico) NÃO dispara o trigger de taxonomia → canonical
  -- preservado, metadados intactos, nova ordem aplicada.
  IF NOT EXISTS (
    SELECT 1 FROM public.profile_skills
    WHERE id = python_id AND category = 'manual'
      AND canonical_skill_id IS NOT NULL AND order_index = 0
  ) THEN
    RAISE EXCEPTION 'T1 reorder perdeu metadados/canonical';
  END IF;

  SET LOCAL ROLE authenticated;
  SELECT public.replace_profile_skills_atomic_v1(
    u, '["Python", "SQL"]'::jsonb
  )
  INTO result;
  RESET ROLE;
  IF result->>'status' <> 'noop' THEN
    RAISE EXCEPTION 'T1 replay exato não foi noop: %', result;
  END IF;
  SELECT id INTO replay_id FROM public.profile_skills
  WHERE user_id = u AND name = 'Python';
  IF replay_id <> python_id THEN
    RAISE EXCEPTION 'T1 replay trocou ID';
  END IF;

  got_state := (
    SELECT string_agg(name, ',' ORDER BY order_index)
    FROM public.profile_skills WHERE user_id = u
  );
  IF got_state <> 'Python,SQL' THEN
    RAISE EXCEPTION 'T1 estado final inválido: %', got_state;
  END IF;
  RAISE NOTICE 'T1 OK — replace atômico/idempotente; reorder preserva metadados';
END
$test$;

-- T1b — Gate 3.0D: replace manual é AUTORITATIVO sobre a grafia. Uma correção
-- cosmética (case/acento/whitespace) do usuário vence a grafia armazenada,
-- preservando ID e category; incluir `name` no UPDATE recomputa canonical pelo
-- trigger de taxonomia (no harness o stub o zera para skill sem catálogo).
DO $test$
DECLARE
  u uuid := 'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1';
  skill_id uuid;
  live_name text;
  result jsonb;
BEGIN
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.profile_skills(
    user_id, name, category, canonical_skill_id, order_index
  )
  VALUES (u, 'python', 'manual', gen_random_uuid(), 0)
  RETURNING id INTO skill_id;

  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u::text, 'role', 'authenticated')::text,
    false
  );
  SET LOCAL ROLE authenticated;
  SELECT public.replace_profile_skills_atomic_v1(u, '["Python"]'::jsonb)
  INTO result;
  RESET ROLE;

  IF result->>'status' <> 'applied' OR (result->>'count')::int <> 1 THEN
    RAISE EXCEPTION 'T1b rename não foi aplicado: %', result;
  END IF;
  SELECT name INTO live_name FROM public.profile_skills WHERE id = skill_id;
  IF live_name IS DISTINCT FROM 'Python' THEN
    RAISE EXCEPTION 'T1b grafia manual não venceu: % (esperava Python)',
      live_name;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profile_skills
    WHERE id = skill_id AND category = 'manual' AND order_index = 0
  ) THEN
    RAISE EXCEPTION 'T1b rename perdeu ID/category/ordem';
  END IF;

  -- Idempotência: reenviar a mesma grafia agora é noop.
  SET LOCAL ROLE authenticated;
  SELECT public.replace_profile_skills_atomic_v1(u, '["Python"]'::jsonb)
  INTO result;
  RESET ROLE;
  IF result->>'status' <> 'noop' THEN
    RAISE EXCEPTION 'T1b replay do rename não foi noop: %', result;
  END IF;
  RAISE NOTICE 'T1b OK — grafia manual vence (autoritativo); ID/category/ordem';
END
$test$;

-- T2 — payload inválido e limite falham antes da primeira escrita.
DO $test$
DECLARE
  u uuid := '11111111-1111-1111-1111-111111111111';
  got_code text;
  before_state text;
  after_state text;
BEGIN
  SELECT string_agg(name, ',' ORDER BY order_index) INTO before_state
  FROM public.profile_skills WHERE user_id = u;
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u::text, 'role', 'authenticated')::text,
    false
  );
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.replace_profile_skills_atomic_v1(u, '["Rust", 7]'::jsonb);
    RESET ROLE;
    RAISE EXCEPTION 'T2 payload inválido foi aceito';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got_code = RETURNED_SQLSTATE;
    RESET ROLE;
    IF got_code <> '22023' THEN RAISE; END IF;
  END;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.replace_profile_skills_atomic_v1(
      u,
      '["s1","s2","s3","s4","s5","s6","s7",'
      '"s8","s9","s10","s11","s12","s13"]'::jsonb
    );
    RESET ROLE;
    RAISE EXCEPTION 'T2 limite foi ignorado';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got_code = RETURNED_SQLSTATE;
    RESET ROLE;
    IF got_code <> '22023' THEN RAISE; END IF;
  END;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.replace_profile_skills_atomic_v1(
      u,
      to_jsonb(array_fill('duplicada'::text, ARRAY[51]))
    );
    RESET ROLE;
    RAISE EXCEPTION 'T2 limite bruto foi ignorado';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got_code = RETURNED_SQLSTATE;
    RESET ROLE;
    IF got_code <> '22023' THEN RAISE; END IF;
  END;
  SELECT string_agg(name, ',' ORDER BY order_index) INTO after_state
  FROM public.profile_skills WHERE user_id = u;
  IF after_state IS DISTINCT FROM before_state THEN
    RAISE EXCEPTION 'T2 deixou escrita parcial: antes=% depois=%',
      before_state, after_state;
  END IF;
  RAISE NOTICE 'T2 OK — validação/limite fazem rollback total';
END
$test$;

-- T3 — autorização e matriz de privilégios.
DO $test$
DECLARE
  a uuid := '11111111-1111-1111-1111-111111111111';
  b uuid := '22222222-2222-2222-2222-222222222222';
  got_code text;
  q text;
  fn text;
  role_name text;
  visible_rows integer;
BEGIN
  INSERT INTO public.profile_interests(user_id, name, order_index)
  VALUES (b, 'Privado B', 0);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', a::text, 'role', 'authenticated')::text,
    false
  );
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.replace_profile_interests_atomic_v1(b, '["Música"]'::jsonb);
    RESET ROLE;
    RAISE EXCEPTION 'T3 cross-user foi aceito';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got_code = RETURNED_SQLSTATE;
    RESET ROLE;
    IF got_code <> '28000' THEN RAISE; END IF;
  END;

  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO visible_rows
  FROM public.profile_interests
  WHERE user_id = b;
  RESET ROLE;
  IF visible_rows <> 0 THEN
    RAISE EXCEPTION 'T3 RLS deixou A ler linha de B';
  END IF;
  BEGIN
    SET LOCAL ROLE authenticated;
    INSERT INTO public.profile_interests(user_id, name)
    VALUES (b, 'Injeção cross-user');
    RESET ROLE;
    RAISE EXCEPTION 'T3 RLS aceitou INSERT direto cross-user';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got_code = RETURNED_SQLSTATE;
    RESET ROLE;
    IF got_code <> '42501' THEN RAISE; END IF;
  END;

  SELECT count(*) INTO visible_rows
  FROM pg_class
  WHERE oid = ANY (ARRAY[
    'public.profile_skills'::regclass,
    'public.profile_interests'::regclass,
    'public.profile_languages'::regclass,
    'public.profile_desired_titles'::regclass
  ]) AND relrowsecurity;
  IF visible_rows <> 4 THEN
    RAISE EXCEPTION 'T3 matriz RLS incompleta: %/4', visible_rows;
  END IF;
  SELECT count(*) INTO visible_rows
  FROM pg_trigger
  WHERE tgrelid = ANY (ARRAY[
    'public.profile_skills'::regclass,
    'public.profile_interests'::regclass,
    'public.profile_languages'::regclass,
    'public.profile_desired_titles'::regclass
  ])
    AND tgname = 'zzz_fence_stmt'
    AND NOT tgisinternal
    AND tgenabled = 'O'
    AND tgfoid = 'public._fence_profile_writes()'::regprocedure
    AND (tgtype & 1) = 0
    AND (tgtype & 2) = 2
    AND (tgtype & 4) = 4
    AND (tgtype & 8) = 8
    AND (tgtype & 16) = 16;
  IF visible_rows <> 4 THEN
    RAISE EXCEPTION 'T3 matriz de fencing incompleta: %/4', visible_rows;
  END IF;

  FOREACH q IN ARRAY ARRAY[
    'SELECT public.replace_profile_skills_atomic_v1(NULL::uuid,''[]''::jsonb)',
    'SELECT public.replace_profile_interests_atomic_v1(NULL::uuid,''[]''::jsonb)',
    'SELECT public.replace_profile_desired_titles_atomic_v1(NULL::uuid,''[]''::jsonb)',
    'SELECT public.merge_guided_profile_list(NULL::uuid,''skills'',''[]''::jsonb)',
    'SELECT public.set_guided_language_level_cas(NULL::uuid,''X'',NULL,''basic'')'
  ]
  LOOP
    BEGIN
      SET LOCAL ROLE authenticated;
      EXECUTE q;
      RESET ROLE;
      RAISE EXCEPTION 'T3 user_id NULL foi aceito por %', q;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS got_code = RETURNED_SQLSTATE;
      RESET ROLE;
      IF got_code <> '28000' THEN RAISE; END IF;
    END;
  END LOOP;

  FOREACH fn IN ARRAY ARRAY[
    'public.replace_profile_skills_atomic_v1(uuid,jsonb)',
    'public.replace_profile_interests_atomic_v1(uuid,jsonb)',
    'public.replace_profile_desired_titles_atomic_v1(uuid,jsonb)',
    'public.merge_guided_profile_list(uuid,text,jsonb)',
    'public.set_guided_language_level_cas(uuid,text,text,text)'
  ]
  LOOP
    IF NOT has_function_privilege('authenticated', fn, 'EXECUTE')
       OR has_function_privilege('anon', fn, 'EXECUTE')
       OR has_function_privilege('service_role', fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'T3 ACL client incorreta para %', fn;
    END IF;
  END LOOP;

  IF has_function_privilege(
       'authenticated', 'public.save_profile_from_json(uuid,jsonb)', 'EXECUTE')
     OR has_function_privilege(
       'anon', 'public.save_profile_from_json(uuid,jsonb)', 'EXECUTE')
     OR NOT has_function_privilege(
       'service_role', 'public.save_profile_from_json(uuid,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'T3 matriz do writer service incorreta';
  END IF;
  IF to_regprocedure(
       'public._save_profile_from_json_legacy_unfenced(uuid,jsonb)'
     ) IS NOT NULL THEN
    RAISE EXCEPTION 'T3 helper wrapper redundante foi criado';
  END IF;

  FOREACH fn IN ARRAY ARRAY[
    'public.profile_write_lock_key(uuid)',
    'public._profile_list_key(text)',
    'public._desired_title_source_rank(text)',
    'public._assert_profile_list_unique(uuid,text)',
    'public._fence_profile_writes()',
    'public._replace_profile_simple_list(uuid,text,jsonb,integer)'
  ]
  LOOP
    FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated', 'service_role']
    LOOP
      IF has_function_privilege(role_name, fn, 'EXECUTE') THEN
        RAISE EXCEPTION 'T3 helper % executável por %', fn, role_name;
      END IF;
    END LOOP;
  END LOOP;
  PERFORM set_config('request.jwt.claims', '{}'::jsonb::text, false);
  DELETE FROM public.profile_interests
  WHERE user_id = b AND name = 'Privado B';
  RAISE NOTICE 'T3 OK — posse e privilégios mínimos';
END
$test$;

-- T4 — merge guiado é aditivo, idempotente e não apaga metadado manual.
DO $test$
DECLARE
  u uuid := '11111111-1111-1111-1111-111111111111';
  result jsonb;
  before_id uuid;
  accent_id uuid;
BEGIN
  SELECT id INTO before_id FROM public.profile_skills
  WHERE user_id = u AND name = 'Python';
  INSERT INTO public.profile_skills(
    user_id, name, category, canonical_skill_id, order_index
  ) VALUES (u, 'Gestão', 'manual', gen_random_uuid(), 2)
  RETURNING id INTO accent_id;
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u::text, 'role', 'authenticated')::text,
    false
  );
  SET LOCAL ROLE authenticated;
  SELECT public.merge_guided_profile_list(
    u,
    'skills',
    E'[" python ", "\\tPower   BI\\n", " Gestao "]'::jsonb
  ) INTO result;
  RESET ROLE;
  IF result->>'status' <> 'applied' OR (result->>'inserted')::int <> 1 THEN
    RAISE EXCEPTION 'T4 merge inesperado: %', result;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profile_skills
    WHERE id = before_id AND category = 'manual'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.profile_skills
    WHERE user_id = u AND name = 'Power BI'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.profile_skills
    WHERE id = accent_id AND name = 'Gestão' AND category = 'manual'
  ) THEN
    RAISE EXCEPTION 'T4 merge sobrescreveu/perdeu skill ou normalização';
  END IF;
  SET LOCAL ROLE authenticated;
  SELECT public.merge_guided_profile_list(
    u, 'skills', '["Power BI"]'::jsonb
  ) INTO result;
  RESET ROLE;
  IF result->>'status' <> 'noop' THEN
    RAISE EXCEPTION 'T4 replay não foi noop: %', result;
  END IF;
  RAISE NOTICE 'T4 OK — merge aditivo e retry idempotente';
END
$test$;

-- T5 — áreas: escolha explícita promove inferred sem duplicar; replace é noop
-- no replay e conserva o ID da linha.
DO $test$
DECLARE
  u uuid := '11111111-1111-1111-1111-111111111111';
  title_id uuid;
  replay_id uuid;
  null_source_id uuid;
  legacy_source_id uuid;
  result jsonb;
BEGIN
  INSERT INTO public.profile_desired_titles(
    user_id, title, source, order_index
  ) VALUES (u, 'Tecnologia', 'inferred', 0)
  RETURNING id INTO title_id;
  INSERT INTO public.profile_desired_titles(
    user_id, title, source, order_index
  ) VALUES (u, 'Negócios', NULL, 1)
  RETURNING id INTO null_source_id;
  INSERT INTO public.profile_desired_titles(
    user_id, title, source, order_index
  ) VALUES (u, 'Jurídico', 'legacy_merge', 2)
  RETURNING id INTO legacy_source_id;
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u::text, 'role', 'authenticated')::text,
    false
  );
  SET LOCAL ROLE authenticated;
  SELECT public.merge_guided_profile_list(
    u,
    'desired_titles',
    '[{"title":"Tecnológia","source":"inferred"},'
    ' {"title":"Tecnologia","source":"user_added"},'
    ' {"title":"Dados","source":"inferred"},'
    ' {"title":"Negocios","source":"inferred"},'
    ' {"title":"Juridico","source":"inferred"}]'::jsonb
  ) INTO result;
  RESET ROLE;
  IF result->>'status' <> 'applied' THEN
    RAISE EXCEPTION 'T5 merge de áreas falhou: %', result;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profile_desired_titles
    WHERE id = title_id AND source = 'user_added'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.profile_desired_titles
    WHERE id = null_source_id AND source IS NULL AND title = 'Negócios'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.profile_desired_titles
    WHERE id = legacy_source_id AND source = 'legacy_merge'
      AND title = 'Jurídico'
  ) THEN
    RAISE EXCEPTION 'T5 promoção rebaixou fonte manual/legacy';
  END IF;
  IF (result->>'inserted')::int <> 1
     OR (result->>'updated')::int <> 1 THEN
    RAISE EXCEPTION 'T5 recibo insert/update desonesto: %', result;
  END IF;

  SET LOCAL ROLE authenticated;
  SELECT public.replace_profile_desired_titles_atomic_v1(
    u,
    '[{"title":"Tecnológia","source":"inferred"},'
    ' {"title":"Tecnologia","source":"user_added"},'
    ' {"title":"Negócios","source":null},'
    ' {"title":"Jurídico","source":"legacy_merge"},'
    ' {"title":"Dados","source":"inferred"}]'::jsonb
  ) INTO result;
  RESET ROLE;
  IF result->>'status' <> 'noop' THEN
    RAISE EXCEPTION 'T5 replace replay não foi noop: %', result;
  END IF;
  SELECT id INTO replay_id FROM public.profile_desired_titles
  WHERE user_id = u AND title = 'Tecnologia';
  IF replay_id <> title_id THEN
    RAISE EXCEPTION 'T5 replace trocou ID da área';
  END IF;
  RAISE NOTICE 'T5 OK — área explícita vence inferred sem duplicar';
END
$test$;

-- T6 — CAS de idioma: edição manual recente vence; CAS correto aplica.
DO $test$
DECLARE
  u uuid := '11111111-1111-1111-1111-111111111111';
  result jsonb;
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u::text, 'role', 'authenticated')::text,
    false
  );
  SET LOCAL ROLE authenticated;
  PERFORM public.merge_guided_profile_list(
    u, 'languages', '["Português"]'::jsonb
  );
  UPDATE public.profile_languages SET proficiency = 'fluent'
  WHERE user_id = u AND name = 'Português';
  SELECT public.set_guided_language_level_cas(
    u, 'português', NULL, 'native'
  ) INTO result;
  RESET ROLE;
  IF result->>'status' <> 'stale' OR NOT EXISTS (
    SELECT 1 FROM public.profile_languages
    WHERE user_id = u AND name = 'Português' AND proficiency = 'fluent'
  ) THEN
    RAISE EXCEPTION 'T6 CAS stale sobrescreveu edição manual: %', result;
  END IF;

  SET LOCAL ROLE authenticated;
  SELECT public.set_guided_language_level_cas(
    u, 'Português', 'fluent', 'native'
  ) INTO result;
  RESET ROLE;
  IF result->>'status' <> 'applied' OR NOT EXISTS (
    SELECT 1 FROM public.profile_languages
    WHERE user_id = u AND name = 'Português' AND proficiency = 'native'
  ) THEN
    RAISE EXCEPTION 'T6 CAS válido não aplicou: %', result;
  END IF;

  SET LOCAL ROLE authenticated;
  SELECT public.set_guided_language_level_cas(
    u, 'Português', 'fluent', 'native'
  ) INTO result;
  RESET ROLE;
  IF result->>'status' <> 'noop' OR NOT EXISTS (
    SELECT 1 FROM public.profile_languages
    WHERE user_id = u AND name = 'Português' AND proficiency = 'native'
  ) THEN
    RAISE EXCEPTION 'T6 replay idempotente não foi noop: %', result;
  END IF;

  RAISE NOTICE 'T6 OK — CAS manual-vence + replay idempotente';
END
$test$;

-- T7 — erro no item N do merge não deixa o item anterior gravado.
DO $test$
DECLARE
  u uuid := '22222222-2222-2222-2222-222222222222';
  got_code text;
  q text;
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u::text, 'role', 'authenticated')::text,
    false
  );
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.merge_guided_profile_list(
      u, 'interests', '["Corrida", {"bad":true}]'::jsonb
    );
    RESET ROLE;
    RAISE EXCEPTION 'T7 item inválido foi aceito';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got_code = RETURNED_SQLSTATE;
    RESET ROLE;
    IF got_code <> '22023' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM public.profile_interests WHERE user_id = u) THEN
    RAISE EXCEPTION 'T7 deixou gravação parcial';
  END IF;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.merge_guided_profile_list(
      u, NULL::text, '["Área injetada"]'::jsonb
    );
    RESET ROLE;
    RAISE EXCEPTION 'T7 section NULL foi aceita';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got_code = RETURNED_SQLSTATE;
    RESET ROLE;
    IF got_code <> '22023' THEN RAISE; END IF;
  END;
  IF EXISTS (
    SELECT 1 FROM public.profile_desired_titles
    WHERE user_id = u AND title = 'Área injetada'
  ) THEN
    RAISE EXCEPTION 'T7 section NULL escreveu em desired_titles';
  END IF;

  FOREACH q IN ARRAY ARRAY[
    'SELECT public.merge_guided_profile_list('
      || quote_literal(u) || ',''desired_titles'','
      || quote_literal('[{"title":{"texto":"Produto"},'
                       '"source":"user_added"}]') || '::jsonb)',
    'SELECT public.merge_guided_profile_list('
      || quote_literal(u) || ',''desired_titles'','
      || quote_literal('[{"title":"Produto",'
                       '"source":{"origem":"manual"}}]') || '::jsonb)',
    'SELECT public.merge_guided_profile_list('
      || quote_literal(u) || ',''desired_titles'','
      || quote_literal('[{"source":"user_added"}]') || '::jsonb)',
    'SELECT public.merge_guided_profile_list('
      || quote_literal(u) || ',''desired_titles'','
      || quote_literal('[{"title":"Não deve gravar",'
                       '"source":"user_added"},{"title":7}]') || '::jsonb)',
    'SELECT public.replace_profile_desired_titles_atomic_v1('
      || quote_literal(u) || ','
      || quote_literal('[{"title":{"texto":"Produto"},'
                       '"source":"user_added"}]') || '::jsonb)',
    'SELECT public.replace_profile_desired_titles_atomic_v1('
      || quote_literal(u) || ','
      || quote_literal('[{"title":"Produto",'
                       '"source":{"origem":"manual"}}]') || '::jsonb)',
    'SELECT public.replace_profile_desired_titles_atomic_v1('
      || quote_literal(u) || ','
      || quote_literal('[{"source":"user_added"}]') || '::jsonb)',
    'SELECT public.replace_profile_desired_titles_atomic_v1('
      || quote_literal(u) || ','
      || quote_literal('[{"title":"Não deve gravar",'
                       '"source":"user_added"},{"title":7}]') || '::jsonb)'
  ]
  LOOP
    BEGIN
      SET LOCAL ROLE authenticated;
      EXECUTE q;
      RESET ROLE;
      RAISE EXCEPTION 'T7 desired_titles inválido foi aceito: %', q;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS got_code = RETURNED_SQLSTATE;
      RESET ROLE;
      IF got_code <> '22023' THEN RAISE; END IF;
    END;
  END LOOP;
  IF EXISTS (
    SELECT 1 FROM public.profile_desired_titles
    WHERE user_id = u
  ) THEN
    RAISE EXCEPTION 'T7 payload tipado inválido deixou gravação parcial';
  END IF;
  RAISE NOTICE 'T7 OK — payload inteiro validado antes de escrever';
END
$test$;

-- T8 — perfil legado acima do teto: replay existente é noop; item novo falha.
DO $test$
DECLARE
  u uuid := '22222222-2222-2222-2222-222222222222';
  result jsonb;
  got_code text;
  i integer;
BEGIN
  FOR i IN 1..13 LOOP
    INSERT INTO public.profile_skills(user_id, name, order_index)
    VALUES (u, 'Legacy ' || i, i - 1);
  END LOOP;
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u::text, 'role', 'authenticated')::text,
    false
  );
  SET LOCAL ROLE authenticated;
  SELECT public.merge_guided_profile_list(
    u, 'skills', '["Legacy 1"]'::jsonb
  ) INTO result;
  RESET ROLE;
  IF result->>'status' <> 'noop' THEN
    RAISE EXCEPTION 'T8 replay legado deveria ser noop: %', result;
  END IF;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.merge_guided_profile_list(
      u, 'skills', '["Nova 14"]'::jsonb
    );
    RESET ROLE;
    RAISE EXCEPTION 'T8 permitiu ampliar perfil acima do teto';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got_code = RETURNED_SQLSTATE;
    RESET ROLE;
    IF got_code <> '22023' THEN RAISE; END IF;
  END;
  IF (SELECT count(*) FROM public.profile_skills WHERE user_id = u) <> 13 THEN
    RAISE EXCEPTION 'T8 alterou perfil legado após rejeição';
  END IF;
  RAISE NOTICE 'T8 OK — limite legado preserva noop e bloqueia crescimento';
END
$test$;

-- T9 — writer canônico anterior permanece service-only, fenced e funcional.
DO $test$
DECLARE
  u uuid := '33333333-3333-3333-3333-333333333333';
  result jsonb;
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('role', 'service_role')::text,
    false
  );
  SET LOCAL ROLE service_role;
  SELECT public.save_profile_from_json(
    u, '{"inject_skill":"Importada"}'::jsonb
  ) INTO result;
  RESET ROLE;
  IF result->>'ok' <> 'true' OR NOT EXISTS (
    SELECT 1 FROM public.profile_skills
    WHERE user_id = u AND name = 'Importada'
  ) THEN
    RAISE EXCEPTION 'T9 writer canônico não preservou contrato: %', result;
  END IF;
  RAISE NOTICE 'T9 OK — writer canônico service fenced e funcional';
END
$test$;

-- T10 — duplicata semântica legacy não é apagada nem escolhida em silêncio.
-- Cada caso roda em subtransação: o erro esperado também desfaz o fixture.
DO $test$
DECLARE
  u uuid := '33333333-3333-3333-3333-333333333333';
  setups text[] := ARRAY[
    $q$INSERT INTO public.profile_skills(user_id,name,order_index) VALUES
      ('33333333-3333-3333-3333-333333333333','Gestão',10),
      ('33333333-3333-3333-3333-333333333333','GESTAO',11)$q$,
    $q$INSERT INTO public.profile_interests(user_id,name,order_index) VALUES
      ('33333333-3333-3333-3333-333333333333','Fotografia',10),
      ('33333333-3333-3333-3333-333333333333','FOTOGRÁFIA',11)$q$,
    $q$INSERT INTO public.profile_desired_titles(user_id,title,source,order_index) VALUES
      ('33333333-3333-3333-3333-333333333333','Tecnologia','user_added',10),
      ('33333333-3333-3333-3333-333333333333','TECNOLÓGIA','inferred',11)$q$,
    $q$INSERT INTO public.profile_skills(user_id,name,order_index) VALUES
      ('33333333-3333-3333-3333-333333333333','Gestão',10),
      ('33333333-3333-3333-3333-333333333333','GESTAO',11)$q$,
    $q$INSERT INTO public.profile_interests(user_id,name,order_index) VALUES
      ('33333333-3333-3333-3333-333333333333','Fotografia',10),
      ('33333333-3333-3333-3333-333333333333','FOTOGRÁFIA',11)$q$,
    $q$INSERT INTO public.profile_languages(user_id,name,order_index) VALUES
      ('33333333-3333-3333-3333-333333333333','Inglês',10),
      ('33333333-3333-3333-3333-333333333333','INGLES',11)$q$,
    $q$INSERT INTO public.profile_desired_titles(user_id,title,source,order_index) VALUES
      ('33333333-3333-3333-3333-333333333333','Tecnologia','user_added',10),
      ('33333333-3333-3333-3333-333333333333','TECNOLÓGIA','inferred',11)$q$,
    $q$INSERT INTO public.profile_languages(user_id,name,order_index) VALUES
      ('33333333-3333-3333-3333-333333333333','Inglês',10),
      ('33333333-3333-3333-3333-333333333333','INGLES',11)$q$
  ];
  calls text[] := ARRAY[
    $q$SELECT public.replace_profile_skills_atomic_v1(
      '33333333-3333-3333-3333-333333333333','["Gestão"]'::jsonb)$q$,
    $q$SELECT public.replace_profile_interests_atomic_v1(
      '33333333-3333-3333-3333-333333333333','["Fotografia"]'::jsonb)$q$,
    $q$SELECT public.replace_profile_desired_titles_atomic_v1(
      '33333333-3333-3333-3333-333333333333',
      '[{"title":"Tecnologia","source":"user_added"}]'::jsonb)$q$,
    $q$SELECT public.merge_guided_profile_list(
      '33333333-3333-3333-3333-333333333333','skills','["SQL"]'::jsonb)$q$,
    $q$SELECT public.merge_guided_profile_list(
      '33333333-3333-3333-3333-333333333333','interests','["Cinema"]'::jsonb)$q$,
    $q$SELECT public.merge_guided_profile_list(
      '33333333-3333-3333-3333-333333333333','languages','["Francês"]'::jsonb)$q$,
    $q$SELECT public.merge_guided_profile_list(
      '33333333-3333-3333-3333-333333333333','desired_titles',
      '[{"title":"Dados","source":"user_added"}]'::jsonb)$q$,
    $q$SELECT public.set_guided_language_level_cas(
      '33333333-3333-3333-3333-333333333333','Inglês',NULL,'fluent')$q$
  ];
  expected_messages text[] := ARRAY[
    'duplicate_profile_skills_require_review',
    'duplicate_profile_interests_require_review',
    'duplicate_profile_desired_titles_require_review',
    'duplicate_profile_skills_require_review',
    'duplicate_profile_interests_require_review',
    'duplicate_profile_languages_require_review',
    'duplicate_profile_desired_titles_require_review',
    'duplicate_profile_languages_require_review'
  ];
  i integer;
  got_code text;
  got_message text;
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u::text, 'role', 'authenticated')::text,
    false
  );
  FOR i IN 1..cardinality(calls)
  LOOP
    BEGIN
      SET LOCAL ROLE authenticated;
      EXECUTE setups[i];
      EXECUTE calls[i];
      RESET ROLE;
      RAISE EXCEPTION 'T10 ambiguidade foi aceita no caso %', i;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS
        got_code = RETURNED_SQLSTATE,
        got_message = MESSAGE_TEXT;
      RESET ROLE;
      IF got_code <> '23505' OR got_message <> expected_messages[i] THEN
        RAISE;
      END IF;
    END;
  END LOOP;
  IF EXISTS (
    SELECT 1 FROM public.profile_skills
    WHERE user_id = u AND public._profile_list_key(name) = 'gestao'
    UNION ALL
    SELECT 1 FROM public.profile_interests
    WHERE user_id = u AND public._profile_list_key(name) = 'fotografia'
    UNION ALL
    SELECT 1 FROM public.profile_languages
    WHERE user_id = u AND public._profile_list_key(name) = 'ingles'
    UNION ALL
    SELECT 1 FROM public.profile_desired_titles
    WHERE user_id = u AND public._profile_list_key(title) = 'tecnologia'
  ) THEN
    RAISE EXCEPTION 'T10 fixture ambíguo escapou do rollback';
  END IF;
  RAISE NOTICE 'T10 OK — duplicatas legacy falham sem perda de dados';
END
$test$;

-- T11 — apply/recibo/replay/undo: uma mutação, mesmo recibo e restauração
-- exata de identidade + metadados.
DO $test$
DECLARE
  u uuid := '11111111-1111-1111-1111-111111111111';
  op uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  result jsonb;
  before_rows jsonb;
  restored_rows jsonb;
  got_code text;
BEGIN
  SET LOCAL TIME ZONE 'UTC';
  DELETE FROM public.profile_assist_skill_operations WHERE user_id = u;
  DELETE FROM public.profile_skills WHERE user_id = u;
  INSERT INTO public.profile_skills(
    user_id, name, category, canonical_skill_id, order_index, created_at
  ) VALUES
    (u, 'Excel', 'manual', gen_random_uuid(), 0, '2026-01-01Z'),
    (u, 'Python', 'programming', gen_random_uuid(), 1, '2026-01-02Z');
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', id, 'name', name, 'category', category,
      'canonical_skill_id', canonical_skill_id,
      'order_index', order_index, 'created_at', created_at
    ) ORDER BY order_index, id
  ) INTO before_rows
  FROM public.profile_skills WHERE user_id = u;

  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u::text, 'role', 'authenticated')::text,
    false
  );
  SET LOCAL ROLE authenticated;
  result := public.open_assist_skills_edit_v1(u, op);
  IF result->>'status' <> 'opened'
     OR result->'baseline' <> '["Excel","Python"]'::jsonb
     OR (result->>'count')::integer <> 2 THEN
    RAISE EXCEPTION 'T11 open não capturou baseline: %', result;
  END IF;
  result := public.open_assist_skills_edit_v1(u, op);
  IF result->>'status' <> 'replay'
     OR result->'baseline' <> '["Excel","Python"]'::jsonb THEN
    RAISE EXCEPTION 'T11 replay de open recapturou baseline: %', result;
  END IF;
  SET LOCAL TIME ZONE 'America/Sao_Paulo';
  result := public.apply_assist_skills_edit_v1(
    u, op, '["Excel","Python"]', '["Excel","SQL"]'
  );
  RESET ROLE;
  IF result->>'status' <> 'applied'
     OR result->>'outcome' <> 'applied'
     OR result->>'can_undo' <> 'true'
     OR (SELECT count(*) FROM public.profile_skills WHERE user_id=u) <> 2
     OR NOT EXISTS (
       SELECT 1 FROM public.profile_skills
       WHERE user_id=u AND name='Excel' AND category='manual'
         AND canonical_skill_id IS NOT NULL
     )
     OR NOT EXISTS (
       SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='SQL'
     ) THEN
    RAISE EXCEPTION 'T11 apply/metadata divergiu: %', result;
  END IF;

  SET LOCAL ROLE authenticated;
  result := public.apply_assist_skills_edit_v1(
    u, op, '["Excel","Python"]', '["Excel","SQL"]'
  );
  RESET ROLE;
  IF result->>'status' <> 'replay'
     OR result->>'outcome' <> 'applied'
     OR result->>'can_undo' <> 'true'
     OR result->'resulting' <> '["Excel","SQL"]'::jsonb
     OR result->'live' <> '["Excel","SQL"]'::jsonb
     OR (SELECT count(*) FROM public.profile_assist_skill_operations
         WHERE user_id=u AND operation_id=op) <> 1 THEN
    RAISE EXCEPTION 'T11 replay não devolveu o recibo: %', result;
  END IF;

  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.apply_assist_skills_edit_v1(
      u, op, '["Excel","Python"]', '["Excel","Go"]'
    );
    RESET ROLE;
    RAISE EXCEPTION 'T11 operation_id foi reutilizado com payload diferente';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got_code = RETURNED_SQLSTATE;
    RESET ROLE;
    IF got_code <> '22023' THEN RAISE; END IF;
  END;

  SET LOCAL TIME ZONE 'Asia/Tokyo';
  SET LOCAL ROLE authenticated;
  result := public.undo_assist_skills_edit_v1(u, op);
  RESET ROLE;
  SET LOCAL TIME ZONE 'UTC';
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', id, 'name', name, 'category', category,
      'canonical_skill_id', canonical_skill_id,
      'order_index', order_index, 'created_at', created_at
    ) ORDER BY order_index, id
  ) INTO restored_rows
  FROM public.profile_skills WHERE user_id = u;
  IF result->>'status' <> 'undone'
     OR result->'resulting' <> '["Excel","Python"]'::jsonb
     OR result->'live' <> '["Excel","Python"]'::jsonb
     OR restored_rows IS DISTINCT FROM before_rows THEN
    RAISE EXCEPTION 'T11 undo não restaurou snapshot: %', result;
  END IF;

  SET LOCAL ROLE authenticated;
  result := public.undo_assist_skills_edit_v1(u, op);
  RESET ROLE;
  IF result->>'status' <> 'replay'
     OR result->>'outcome' <> 'undone'
     OR result->'resulting' <> '["Excel","Python"]'::jsonb
     OR result->'live' <> '["Excel","Python"]'::jsonb
     OR restored_rows IS DISTINCT FROM before_rows THEN
    RAISE EXCEPTION 'T11 retry de undo divergiu: %', result;
  END IF;
  RAISE NOTICE 'T11 OK — recibo/replay/undo restauram identidade e metadados';
END
$test$;

-- T12 — CAS strict: edição manual e segundo card sempre vencem um snapshot
-- antigo; nenhuma chamada parcial é executada.
DO $test$
DECLARE
  u uuid := '22222222-2222-2222-2222-222222222222';
  op_stale uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  op_meta uuid := 'bcbcbcbc-bcbc-4bcb-8bcb-bcbcbcbcbcbc';
  op_identity uuid := 'bdbdbdbd-bdbd-4bdb-8bdb-bdbdbdbdbdbd';
  op_a uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  op_b uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  result jsonb;
  names text;
BEGIN
  DELETE FROM public.profile_assist_skill_operations WHERE user_id = u;
  DELETE FROM public.profile_skills WHERE user_id = u;
  INSERT INTO public.profile_skills(user_id,name,order_index)
  VALUES (u,'Excel',0), (u,'Python',1);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u::text, 'role', 'authenticated')::text,
    false
  );
  SET LOCAL ROLE authenticated;
  PERFORM public.open_assist_skills_edit_v1(u, op_stale);
  RESET ROLE;
  -- Edição que ocorreu depois da abertura do card.
  INSERT INTO public.profile_skills(user_id,name,order_index) VALUES (u,'Go',2);
  SET LOCAL ROLE authenticated;
  result := public.apply_assist_skills_edit_v1(
    u, op_stale, '["Excel","Python"]', '["Excel","SQL"]'
  );
  RESET ROLE;
  SELECT string_agg(name,',' ORDER BY order_index) INTO names
  FROM public.profile_skills WHERE user_id=u;
  IF result->>'outcome' <> 'stale'
     OR result->'resulting' <> '["Excel","Python"]'::jsonb
     OR result->'live' <> '["Excel","Python","Go"]'::jsonb
     OR (result->>'count')::integer <> 3
     OR names <> 'Excel,Python,Go' THEN
    RAISE EXCEPTION 'T12 manual não venceu: result=% names=%', result, names;
  END IF;

  -- O CAS também cobre identidade/metadados, não apenas nome+ordem.
  DELETE FROM public.profile_assist_skill_operations WHERE user_id = u;
  DELETE FROM public.profile_skills WHERE user_id = u;
  INSERT INTO public.profile_skills(user_id,name,category,order_index)
  VALUES(u,'Excel','baseline',0);
  SET LOCAL ROLE authenticated;
  PERFORM public.open_assist_skills_edit_v1(u, op_meta);
  RESET ROLE;
  UPDATE public.profile_skills SET category='manual-new'
  WHERE user_id=u AND name='Excel';
  SET LOCAL ROLE authenticated;
  result := public.apply_assist_skills_edit_v1(
    u, op_meta, '["Excel"]', '["SQL"]'
  );
  RESET ROLE;
  IF result->>'outcome' <> 'stale'
     OR NOT EXISTS (
       SELECT 1 FROM public.profile_skills
       WHERE user_id=u AND name='Excel' AND category='manual-new'
     ) OR EXISTS (
       SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='SQL'
     ) THEN
    RAISE EXCEPTION 'T12 metadado posterior não venceu: %', result;
  END IF;

  -- Mesmo nome não basta: delete+reinsert troca a identidade da linha e
  -- também precisa invalidar a fotografia aberta.
  DELETE FROM public.profile_assist_skill_operations WHERE user_id = u;
  DELETE FROM public.profile_skills WHERE user_id = u;
  INSERT INTO public.profile_skills(user_id,name,category,order_index)
  VALUES(u,'Excel','original',0);
  SET LOCAL ROLE authenticated;
  PERFORM public.open_assist_skills_edit_v1(u, op_identity);
  RESET ROLE;
  DELETE FROM public.profile_skills WHERE user_id=u AND name='Excel';
  INSERT INTO public.profile_skills(user_id,name,category,order_index)
  VALUES(u,'Excel','reinserted',0);
  SET LOCAL ROLE authenticated;
  result := public.apply_assist_skills_edit_v1(
    u, op_identity, '["Excel"]', '["SQL"]'
  );
  RESET ROLE;
  IF result->>'outcome' <> 'stale'
     OR NOT EXISTS (
       SELECT 1 FROM public.profile_skills
       WHERE user_id=u AND name='Excel' AND category='reinserted'
     ) OR EXISTS (
       SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='SQL'
     ) THEN
    RAISE EXCEPTION 'T12 identidade posterior não venceu: %', result;
  END IF;

  DELETE FROM public.profile_assist_skill_operations WHERE user_id = u;
  DELETE FROM public.profile_skills WHERE user_id = u;
  INSERT INTO public.profile_skills(user_id,name,order_index) VALUES(u,'Excel',0);
  SET LOCAL ROLE authenticated;
  PERFORM public.open_assist_skills_edit_v1(u, op_a);
  PERFORM public.open_assist_skills_edit_v1(u, op_b);
  result := public.apply_assist_skills_edit_v1(
    u, op_a, '["Excel"]', '["Excel","SQL"]'
  );
  result := public.apply_assist_skills_edit_v1(
    u, op_b, '["Excel"]', '["Excel","Python"]'
  );
  RESET ROLE;
  SELECT string_agg(name,',' ORDER BY order_index) INTO names
  FROM public.profile_skills WHERE user_id=u;
  IF result->>'outcome' <> 'stale' OR names <> 'Excel,SQL' THEN
    RAISE EXCEPTION 'T12 dois cards não serializaram: % / %', result, names;
  END IF;
  RAISE NOTICE 'T12 OK — snapshot integral faz manual/segundo card vencer';
END
$test$;

-- T13 — uma mudança posterior (inclusive só metadado) bloqueia o undo.
DO $test$
DECLARE
  u uuid := '22222222-2222-2222-2222-222222222222';
  op uuid := 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  result jsonb;
BEGIN
  DELETE FROM public.profile_assist_skill_operations WHERE user_id = u;
  DELETE FROM public.profile_skills WHERE user_id = u;
  INSERT INTO public.profile_skills(user_id,name,category,order_index)
  VALUES(u,'Excel','manual',0);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u::text, 'role', 'authenticated')::text,
    false
  );
  SET LOCAL ROLE authenticated;
  PERFORM public.open_assist_skills_edit_v1(u, op);
  PERFORM public.apply_assist_skills_edit_v1(
    u, op, '["Excel"]', '["Excel","SQL"]'
  );
  RESET ROLE;
  UPDATE public.profile_skills SET category='manual-new'
  WHERE user_id=u AND name='Excel';
  SET LOCAL ROLE authenticated;
  result := public.apply_assist_skills_edit_v1(
    u, op, '["Excel"]', '["Excel","SQL"]'
  );
  IF result->>'status' <> 'replay'
     OR result->>'outcome' <> 'applied'
     OR result->>'can_undo' <> 'false'
     OR result->'resulting' <> '["Excel","SQL"]'::jsonb
     OR result->'live' <> '["Excel","SQL"]'::jsonb THEN
    RAISE EXCEPTION 'T13 replay não refletiu estado/can_undo real: %', result;
  END IF;
  result := public.undo_assist_skills_edit_v1(u, op);
  RESET ROLE;
  IF result->>'outcome' <> 'stale'
     OR NOT EXISTS (
       SELECT 1 FROM public.profile_skills
       WHERE user_id=u AND name='Excel' AND category='manual-new'
     )
     OR NOT EXISTS (
       SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='SQL'
     ) THEN
    RAISE EXCEPTION 'T13 undo sobrescreveu mudança nova: %', result;
  END IF;
  RAISE NOTICE 'T13 OK — undo stale preserva edição posterior';
END
$test$;

-- T13b — duplicata semântica criada depois do apply é uma edição posterior:
-- undo retorna stale (não 23505) e não apaga nenhuma das linhas.
DO $test$
DECLARE
  u uuid := '22222222-2222-2222-2222-222222222222';
  op uuid := 'edededed-eded-4ede-8ded-edededededed';
  result jsonb;
BEGIN
  DELETE FROM public.profile_assist_skill_operations WHERE user_id = u;
  DELETE FROM public.profile_skills WHERE user_id = u;
  INSERT INTO public.profile_skills(user_id,name,order_index)
  VALUES(u,'Gestão',0);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u::text, 'role', 'authenticated')::text,
    false
  );
  SET LOCAL ROLE authenticated;
  PERFORM public.open_assist_skills_edit_v1(u, op);
  PERFORM public.apply_assist_skills_edit_v1(
    u, op, '["Gestão"]', '["Gestão","SQL"]'
  );
  RESET ROLE;
  INSERT INTO public.profile_skills(user_id,name,order_index)
  VALUES(u,'Gestao',2);
  SET LOCAL ROLE authenticated;
  result := public.undo_assist_skills_edit_v1(u, op);
  RESET ROLE;
  IF result->>'outcome' <> 'stale'
     OR (SELECT count(*) FROM public.profile_skills WHERE user_id=u) <> 3
     OR NOT EXISTS (
       SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='Gestão'
     ) OR NOT EXISTS (
       SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='Gestao'
     ) THEN
    RAISE EXCEPTION 'T13b duplicata posterior não virou stale: %', result;
  END IF;
  RAISE NOTICE 'T13b OK — duplicata posterior retorna stale sem perda';
END
$test$;

CREATE OR REPLACE FUNCTION public._test_fail_assist_skill()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.name IN ('FAIL_APPLY', 'Python') THEN
    RAISE EXCEPTION 'injected_skill_failure' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END
$$;

-- T14 — falha no item N faz rollback conjunto de perfil + recibo no apply e
-- também no undo.
DO $test$
DECLARE
  u uuid := '33333333-3333-3333-3333-333333333333';
  op_apply uuid := 'ffffffff-ffff-4fff-8fff-ffffffffffff';
  op_undo uuid := '12121212-1212-4212-8212-121212121212';
  got_code text;
  names text;
  result jsonb;
BEGIN
  DELETE FROM public.profile_assist_skill_operations WHERE user_id = u;
  DELETE FROM public.profile_skills WHERE user_id = u;
  INSERT INTO public.profile_skills(user_id,name,order_index) VALUES(u,'Excel',0);
  CREATE TRIGGER zzzz_test_fail_assist_skill
    BEFORE INSERT ON public.profile_skills
    FOR EACH ROW EXECUTE FUNCTION public._test_fail_assist_skill();
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u::text, 'role', 'authenticated')::text,
    false
  );
  SET LOCAL ROLE authenticated;
  PERFORM public.open_assist_skills_edit_v1(u, op_apply);
  RESET ROLE;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.apply_assist_skills_edit_v1(
      u, op_apply, '["Excel"]', '["Excel","FAIL_APPLY"]'
    );
    RESET ROLE;
    RAISE EXCEPTION 'T14 apply injetado não falhou';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got_code = RETURNED_SQLSTATE;
    RESET ROLE;
    IF got_code <> '23514' THEN RAISE; END IF;
  END;
  SELECT string_agg(name,',' ORDER BY order_index) INTO names
  FROM public.profile_skills WHERE user_id=u;
  IF names <> 'Excel' OR NOT EXISTS (
    SELECT 1 FROM public.profile_assist_skill_operations
    WHERE user_id=u AND operation_id=op_apply
      AND outcome='opened'
      AND desired_names='[]'::jsonb
      AND after_rows='[]'::jsonb
  ) THEN
    RAISE EXCEPTION 'T14 apply deixou parcial/recibo terminal: %', names;
  END IF;

  DROP TRIGGER zzzz_test_fail_assist_skill ON public.profile_skills;
  SET LOCAL ROLE authenticated;
  result := public.apply_assist_skills_edit_v1(
    u, op_apply, '["Excel"]', '["Excel","SQL"]'
  );
  RESET ROLE;
  SELECT string_agg(name,',' ORDER BY order_index) INTO names
  FROM public.profile_skills WHERE user_id=u;
  IF result->>'outcome' <> 'applied' OR names <> 'Excel,SQL' THEN
    RAISE EXCEPTION 'T14 retry corrigido do apply falhou: % / %', result, names;
  END IF;

  DELETE FROM public.profile_skills WHERE user_id = u;
  INSERT INTO public.profile_skills(user_id,name,order_index) VALUES(u,'Excel',0);
  INSERT INTO public.profile_skills(user_id,name,category,order_index)
  VALUES(u,'Python','old-meta',1);
  SET LOCAL ROLE authenticated;
  PERFORM public.open_assist_skills_edit_v1(u, op_undo);
  PERFORM public.apply_assist_skills_edit_v1(
    u, op_undo, '["Excel","Python"]', '["Excel","SQL"]'
  );
  RESET ROLE;
  CREATE TRIGGER zzzz_test_fail_assist_skill
    BEFORE INSERT ON public.profile_skills
    FOR EACH ROW EXECUTE FUNCTION public._test_fail_assist_skill();
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.undo_assist_skills_edit_v1(u, op_undo);
    RESET ROLE;
    RAISE EXCEPTION 'T14 undo injetado não falhou';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got_code = RETURNED_SQLSTATE;
    RESET ROLE;
    IF got_code <> '23514' THEN RAISE; END IF;
  END;
  SELECT string_agg(name,',' ORDER BY order_index) INTO names
  FROM public.profile_skills WHERE user_id=u;
  IF names <> 'Excel,SQL' OR EXISTS (
    SELECT 1 FROM public.profile_assist_skill_operations
    WHERE user_id=u AND operation_id=op_undo AND undone_at IS NOT NULL
  ) OR NOT EXISTS (
    SELECT 1 FROM public.profile_assist_skill_operations
    WHERE user_id=u AND operation_id=op_undo
      AND outcome='applied' AND undone_at IS NULL
  ) THEN
    RAISE EXCEPTION 'T14 undo deixou parcial/recibo: %', names;
  END IF;
  DROP TRIGGER zzzz_test_fail_assist_skill ON public.profile_skills;
  SET LOCAL ROLE authenticated;
  result := public.undo_assist_skills_edit_v1(u, op_undo);
  RESET ROLE;
  SELECT string_agg(name,',' ORDER BY order_index) INTO names
  FROM public.profile_skills WHERE user_id=u;
  IF result->>'outcome' <> 'undone'
     OR names <> 'Excel,Python'
     OR NOT EXISTS (
       SELECT 1 FROM public.profile_skills
       WHERE user_id=u AND name='Python' AND category='old-meta'
     ) THEN
    RAISE EXCEPTION 'T14 retry corrigido do undo falhou: % / %', result, names;
  END IF;
  RAISE NOTICE 'T14 OK — apply/undo e recibo fazem rollback juntos';
END
$test$;

DROP FUNCTION public._test_fail_assist_skill();

-- T15 — contratos novos são client-only, tabela de recibos é privada e
-- cross-user falha antes de criar operação.
DO $test$
DECLARE
  a uuid := '11111111-1111-1111-1111-111111111111';
  b uuid := '22222222-2222-2222-2222-222222222222';
  op uuid := '34343434-3434-4434-8434-343434343434';
  fn text;
  got_code text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.open_assist_skills_edit_v1(uuid,uuid)',
    'public.apply_assist_skills_edit_v1(uuid,uuid,jsonb,jsonb)',
    'public.undo_assist_skills_edit_v1(uuid,uuid)'
  ] LOOP
    IF NOT has_function_privilege('authenticated', fn, 'EXECUTE')
       OR has_function_privilege('anon', fn, 'EXECUTE')
       OR has_function_privilege('service_role', fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'T15 ACL incorreta em %', fn;
    END IF;
  END LOOP;
  FOREACH fn IN ARRAY ARRAY[
    'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
  ] LOOP
    IF has_table_privilege(
         'authenticated', 'public.profile_assist_skill_operations', fn)
       OR has_table_privilege(
         'anon', 'public.profile_assist_skill_operations', fn)
       OR has_table_privilege(
         'service_role', 'public.profile_assist_skill_operations', fn) THEN
      RAISE EXCEPTION 'T15 tabela de recibos expôs privilégio %', fn;
    END IF;
  END LOOP;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint AS c
    WHERE c.conrelid = 'public.profile_assist_skill_operations'::regclass
      AND c.contype = 'p'
      AND (
        SELECT array_agg(a.attname::text ORDER BY key.ordinality)
        FROM unnest(c.conkey) WITH ORDINALITY AS key(attnum, ordinality)
        JOIN pg_attribute AS a
          ON a.attrelid=c.conrelid AND a.attnum=key.attnum
      ) = ARRAY['user_id','operation_id']::text[]
  ) THEN
    RAISE EXCEPTION 'T15 PK não é composta por user_id+operation_id';
  END IF;
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', a::text, 'role', 'authenticated')::text,
    false
  );
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.apply_assist_skills_edit_v1(
      b, op, '[]'::jsonb, '[]'::jsonb
    );
    RESET ROLE;
    RAISE EXCEPTION 'T15 cross-user foi aceito';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got_code = RETURNED_SQLSTATE;
    RESET ROLE;
    IF got_code <> '28000' THEN RAISE; END IF;
  END;
  IF EXISTS (
    SELECT 1 FROM public.profile_assist_skill_operations
    WHERE operation_id=op
  ) THEN
    RAISE EXCEPTION 'T15 cross-user criou recibo';
  END IF;

  -- operation_id é idempotente dentro do usuário, não um namespace global.
  DELETE FROM public.profile_skills WHERE user_id IN (a,b);
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', a::text, 'role', 'authenticated')::text,
    false
  );
  SET LOCAL ROLE authenticated;
  PERFORM public.open_assist_skills_edit_v1(a, op);
  RESET ROLE;
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', b::text, 'role', 'authenticated')::text,
    false
  );
  SET LOCAL ROLE authenticated;
  PERFORM public.open_assist_skills_edit_v1(b, op);
  RESET ROLE;
  IF (SELECT count(*) FROM public.profile_assist_skill_operations
      WHERE operation_id=op AND user_id IN (a,b)) <> 2 THEN
    RAISE EXCEPTION 'T15 operation_id global colidiu entre usuários';
  END IF;
  RAISE NOTICE 'T15 OK — ACL/posse/tabela privada';
END
$test$;

SELECT 'ALL_PROFILE_GUIDED_WRITE_SQL_TESTS_OK' AS result;
