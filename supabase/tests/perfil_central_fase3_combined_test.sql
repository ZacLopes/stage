-- Fase 3 — cadeia combinada das fundações de Fonte importada + edição guiada.
-- Reutiliza primeiro a regressão exaustiva de 14/07 e, no MESMO banco já
-- populado/reaplicado, aplica as migrations de 17/07. Assim contratos, triggers
-- e ACLs são verificados também em conjunto, não apenas em harnesses isolados.

\set ON_ERROR_STOP on

\ir perfil_central_fase3_promote_test.sql

-- Tabelas que já existem no histórico de produção, mas não eram necessárias
-- ao harness autocontido de 14/07.
CREATE TABLE IF NOT EXISTS public.app_feature_flags (
  feature_key text PRIMARY KEY,
  enabled boolean NOT NULL DEFAULT false,
  rollout_pct integer NOT NULL DEFAULT 0
    CHECK (rollout_pct BETWEEN 0 AND 100),
  description text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.profile_desired_titles (
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
ALTER TABLE public.profile_desired_titles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS desired_titles_select ON public.profile_desired_titles;
DROP POLICY IF EXISTS desired_titles_insert ON public.profile_desired_titles;
DROP POLICY IF EXISTS desired_titles_update ON public.profile_desired_titles;
DROP POLICY IF EXISTS desired_titles_delete ON public.profile_desired_titles;
CREATE POLICY desired_titles_select ON public.profile_desired_titles
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY desired_titles_insert ON public.profile_desired_titles
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY desired_titles_update ON public.profile_desired_titles
  FOR UPDATE TO authenticated USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY desired_titles_delete ON public.profile_desired_titles
  FOR DELETE TO authenticated USING (auth.uid() = user_id);
GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.profile_desired_titles TO authenticated;

-- Paridade relevante com o schema/triggers reais de skills. O harness-base de
-- 14/07 não precisava do vínculo canônico nem do trigger de completude; o
-- combinado precisa provar que replace/reorder preservam o vínculo e que o
-- lock aninhado skill -> personal continua seguro.
ALTER TABLE public.profile_skills
  ADD COLUMN IF NOT EXISTS canonical_skill_id uuid,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.profile_languages
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

CREATE OR REPLACE FUNCTION public._test_recompute_canonical_skill()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.canonical_skill_id := NULL;
  RETURN NEW;
END
$$;
DROP TRIGGER IF EXISTS trg_profile_skills_canonical ON public.profile_skills;
CREATE TRIGGER trg_profile_skills_canonical
  BEFORE UPDATE OF name ON public.profile_skills
  FOR EACH ROW EXECUTE FUNCTION public._test_recompute_canonical_skill();

CREATE OR REPLACE FUNCTION public._test_touch_profile_personal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_uid uuid;
BEGIN
  v_uid := CASE WHEN TG_OP = 'DELETE' THEN OLD.user_id ELSE NEW.user_id END;
  INSERT INTO public.profile_personal(user_id)
  VALUES (v_uid)
  ON CONFLICT (user_id) DO UPDATE
    SET updated_at = public.profile_personal.updated_at;
  RETURN NULL;
END
$$;
DROP TRIGGER IF EXISTS trg_profile_skills_completeness
  ON public.profile_skills;
CREATE TRIGGER trg_profile_skills_completeness
  AFTER INSERT OR UPDATE OR DELETE ON public.profile_skills
  FOR EACH ROW EXECUTE FUNCTION public._test_touch_profile_personal();

-- Prova que a migration guiada não renomeia nem reescreve o writer canônico
-- instalado em 14/07.
CREATE TEMP TABLE _pre_guided_import_writer AS
SELECT p.oid AS function_oid, pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
WHERE p.oid = 'public.save_profile_from_json(uuid,jsonb)'::regprocedure;

\ir ../migrations/20260717120000_seed_trilha_assist_v1.sql
\ir ../migrations/20260717130000_profile_guided_write_foundation.sql
\ir ../migrations/20260717140000_assist_skills_cas.sql
\ir ../migrations/20260717150000_manual_skills_replace_authoritative.sql
\ir ../migrations/20260717160000_guided_language_remove_cas.sql
\ir ../migrations/20260719120000_import_revert_snapshot.sql
\ir ../migrations/20260720120000_appside_cas_contracts.sql

-- C1 — cadeia/ACL/trigger: as duas fundações coexistem sem wrapper órfão,
-- reabertura de helper ou perda de fencing nas tabelas anteriores.
DO $test$
DECLARE
  fn text;
  role_name text;
  table_name text;
  trigger_count integer;
  current_oid oid;
  current_definition text;
  client_functions text[] := ARRAY[
    'public.replace_profile_skills_atomic_v1(uuid,jsonb)',
    'public.replace_profile_interests_atomic_v1(uuid,jsonb)',
    'public.replace_profile_desired_titles_atomic_v1(uuid,jsonb)',
    'public.merge_guided_profile_list(uuid,text,jsonb)',
    'public.set_guided_language_level_cas(uuid,text,text,text)',
    'public.open_assist_skills_edit_v1(uuid,uuid)',
    'public.apply_assist_skills_edit_v1(uuid,uuid,jsonb,jsonb)',
    'public.undo_assist_skills_edit_v1(uuid,uuid)'
  ];
  private_functions text[] := ARRAY[
    'public.profile_write_lock_key(uuid)',
    'public._fence_profile_writes()',
    'public._profile_list_key(text)',
    'public._desired_title_source_rank(text)',
    'public._assert_profile_list_unique(uuid,text)',
    'public._replace_profile_simple_list(uuid,text,jsonb,integer)'
  ];
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.app_feature_flags
    WHERE feature_key = 'trilha_assist_v1'
      AND enabled = false AND rollout_pct = 0
  ) THEN
    RAISE EXCEPTION 'C1 flag trilha_assist_v1 não nasceu OFF/0';
  END IF;

  IF to_regprocedure(
       'public._save_profile_from_json_legacy_unfenced(uuid,jsonb)'
     ) IS NOT NULL THEN
    RAISE EXCEPTION 'C1 wrapper legacy redundante foi criado';
  END IF;
  SELECT p.oid, pg_get_functiondef(p.oid)
  INTO current_oid, current_definition
  FROM pg_proc p
  WHERE p.oid = 'public.save_profile_from_json(uuid,jsonb)'::regprocedure;
  IF NOT EXISTS (
    SELECT 1 FROM _pre_guided_import_writer
    WHERE function_oid = current_oid AND definition = current_definition
  ) THEN
    RAISE EXCEPTION 'C1 writer canônico de importação foi renomeado/reescrito';
  END IF;

  IF has_function_privilege(
       'public', 'public.save_profile_from_json(uuid,jsonb)', 'EXECUTE')
     OR has_function_privilege(
       'anon', 'public.save_profile_from_json(uuid,jsonb)', 'EXECUTE')
     OR has_function_privilege(
       'authenticated', 'public.save_profile_from_json(uuid,jsonb)', 'EXECUTE')
     OR NOT has_function_privilege(
       'service_role', 'public.save_profile_from_json(uuid,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'C1 ACL do writer service divergiu';
  END IF;

  FOREACH fn IN ARRAY client_functions LOOP
    IF NOT has_function_privilege('authenticated', fn, 'EXECUTE')
       OR has_function_privilege('anon', fn, 'EXECUTE')
       OR has_function_privilege('service_role', fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'C1 ACL client incorreta em %', fn;
    END IF;
  END LOOP;
  FOREACH fn IN ARRAY private_functions LOOP
    FOREACH role_name IN ARRAY ARRAY[
      'public', 'anon', 'authenticated', 'service_role'
    ] LOOP
      IF has_function_privilege(role_name, fn, 'EXECUTE') THEN
        RAISE EXCEPTION 'C1 helper % executável por %', fn, role_name;
      END IF;
    END LOOP;
  END LOOP;

  IF has_table_privilege(
       'authenticated', 'public.profile_assist_skill_operations', 'SELECT')
     OR has_table_privilege(
       'authenticated', 'public.profile_assist_skill_operations', 'INSERT')
     OR has_table_privilege(
       'anon', 'public.profile_assist_skill_operations', 'SELECT')
     OR has_table_privilege(
       'service_role', 'public.profile_assist_skill_operations', 'SELECT') THEN
    RAISE EXCEPTION 'C1 tabela de recibos do Assistente ficou exposta';
  END IF;

  FOREACH table_name IN ARRAY ARRAY[
    'profile_personal', 'profile_experiences', 'profile_bullets',
    'profile_education', 'profile_education_majors',
    'profile_education_minors', 'profile_education_activities',
    'profile_languages', 'profile_skills', 'profile_certifications',
    'profile_projects', 'profile_project_bullets', 'profile_interests',
    'profile_awards', 'profile_coursework', 'saved_resumes',
    'profile_desired_titles'
  ] LOOP
    SELECT count(*) INTO trigger_count
    FROM pg_trigger
    WHERE tgrelid = format('public.%I', table_name)::regclass
      AND tgname = 'zzz_fence_stmt'
      AND NOT tgisinternal
      AND tgenabled = 'O'
      AND tgfoid = 'public._fence_profile_writes()'::regprocedure
      AND (tgtype & 1) = 0
      AND (tgtype & 2) = 2
      AND (tgtype & 4) = 4
      AND (tgtype & 8) = 8
      AND (tgtype & 16) = 16;
    IF trigger_count <> 1 THEN
      RAISE EXCEPTION 'C1 fencing %: esperado 1, obtido %',
        table_name, trigger_count;
    END IF;
  END LOOP;
  RAISE NOTICE 'C1 OK: upgrade limpo, flag OFF, ACLs e 17 fences íntegros';
END
$test$;

-- C2 — os writers manuais de 14/07 e os guiados de 17/07 compartilham o mesmo
-- estado e a mesma identidade semântica; merge nunca apaga o que já existia.
DO $test$
DECLARE
  u uuid := '77777777-7777-7777-7777-777777777777';
  existing_id uuid;
  replay_id uuid;
  canonical_id uuid := gen_random_uuid();
  result jsonb;
BEGIN
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u::text, 'role', 'authenticated')::text,
    false
  );
  SET LOCAL ROLE authenticated;
  PERFORM public.replace_profile_skills(u, '["Gestão"]'::jsonb);
  RESET ROLE;
  UPDATE public.profile_skills
  SET category = 'manual', canonical_skill_id = canonical_id
  WHERE user_id = u AND name = 'Gestão'
  RETURNING id INTO existing_id;

  SET LOCAL ROLE authenticated;
  result := public.merge_guided_profile_list(
    u, 'skills', '["GESTAO", "SQL"]'::jsonb
  );
  RESET ROLE;
  SELECT id INTO replay_id FROM public.profile_skills
  WHERE user_id = u AND name = 'Gestão';
  IF result->>'status' <> 'applied'
     OR (result->>'inserted')::integer <> 1
     OR replay_id <> existing_id
     OR (SELECT category FROM public.profile_skills WHERE id=existing_id)
        <> 'manual'
     OR (SELECT canonical_skill_id FROM public.profile_skills
         WHERE id=existing_id) <> canonical_id
     OR (SELECT count(*) FROM public.profile_skills WHERE user_id=u) <> 2
     OR NOT EXISTS (
       SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='SQL'
     ) THEN
    RAISE EXCEPTION 'C2 merge guiado/manual divergiu: %', result;
  END IF;

  -- Re-save exato (mesma grafia/ordem) é noop e preserva identidade/metadados.
  -- (A grafia manual autoritativa em variante cosmética é coberta na T1b.)
  SET LOCAL ROLE authenticated;
  result := public.replace_profile_skills_atomic_v1(
    u, '["Gestão", "SQL"]'::jsonb
  );
  RESET ROLE;
  IF result->>'status' <> 'noop'
     OR (SELECT id FROM public.profile_skills
         WHERE user_id=u AND name='Gestão') <> existing_id
     OR (SELECT category FROM public.profile_skills WHERE id=existing_id)
        <> 'manual'
     OR (SELECT canonical_skill_id FROM public.profile_skills
         WHERE id=existing_id) <> canonical_id THEN
    RAISE EXCEPTION 'C2 replace novo perdeu identidade/metadado: %', result;
  END IF;
  RAISE NOTICE 'C2 OK: writer manual + guided preservam identidade e metadados';
END
$test$;

-- C3 — source de objetivo nunca é rebaixada e idioma usa CAS: uma edição
-- manual ocorrida depois da leitura vence a sugestão da IA.
DO $test$
DECLARE
  u uuid := '77777777-7777-7777-7777-777777777777';
  result jsonb;
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u::text, 'role', 'authenticated')::text,
    false
  );
  SET LOCAL ROLE authenticated;
  result := public.merge_guided_profile_list(
    u, 'desired_titles',
    '[{"title":"Dados","source":"inferred"}]'::jsonb
  );
  result := public.merge_guided_profile_list(
    u, 'desired_titles',
    '[{"title":"DÁDOS","source":"user_added"}]'::jsonb
  );
  result := public.merge_guided_profile_list(
    u, 'desired_titles',
    '[{"title":"dados","source":"inferred"}]'::jsonb
  );
  result := public.merge_guided_profile_list(
    u, 'languages', '["Inglês"]'::jsonb
  );
  RESET ROLE;

  UPDATE public.profile_languages SET proficiency='advanced'
  WHERE user_id=u AND name='Inglês';
  SET LOCAL ROLE authenticated;
  result := public.set_guided_language_level_cas(
    u, 'INGLES', NULL, 'basic'
  );
  IF result->>'status' <> 'stale' THEN
    RAISE EXCEPTION 'C3 CAS não protegeu edição manual: %', result;
  END IF;
  result := public.set_guided_language_level_cas(
    u, 'inglês', 'advanced', 'fluent'
  );
  RESET ROLE;
  IF result->>'status' <> 'applied'
     OR (SELECT proficiency FROM public.profile_languages
         WHERE user_id=u AND name='Inglês') <> 'fluent'
     OR (SELECT count(*) FROM public.profile_desired_titles
         WHERE user_id=u) <> 1
     OR (SELECT source FROM public.profile_desired_titles
         WHERE user_id=u) <> 'user_added' THEN
    RAISE EXCEPTION 'C3 source/CAS final divergiu: %', result;
  END IF;
  RAISE NOTICE 'C3 OK: objetivo não rebaixa; CAS faz edição manual vencer';
END
$test$;

-- C4 — o writer service de 14/07 continua executável e com o mesmo shape após
-- a migration guiada; não existe helper legado intermediário.
DO $test$
DECLARE
  u uuid := '88888888-8888-8888-8888-888888888888';
  result jsonb;
BEGIN
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('role', 'service_role')::text,
    false
  );
  SET LOCAL ROLE service_role;
  result := public.save_profile_from_json(
    u, '{"personal":{"first_name":"Compat"}}'::jsonb
  );
  RESET ROLE;
  IF result->>'status' <> 'success'
     OR result->>'user_id' <> u::text
     OR (SELECT first_name FROM public.profile_personal WHERE user_id=u)
        <> 'Compat' THEN
    RAISE EXCEPTION 'C4 writer service perdeu contrato: %', result;
  END IF;
  RAISE NOTICE 'C4 OK: writer service canônico preservado e funcional';
END
$test$;

-- C5 — o recibo/CAS de skills convive com os writers importados e restaura o
-- snapshot completo sem reabrir ACL nem perder a identidade preservada.
DO $test$
DECLARE
  u uuid := '77777777-7777-7777-7777-777777777777';
  op uuid := '56565656-5656-4656-8656-565656565656';
  result jsonb;
  before_rows jsonb;
  after_rows jsonb;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', id, 'name', name, 'category', category,
      'canonical_skill_id', canonical_skill_id,
      'order_index', order_index, 'created_at', created_at
    ) ORDER BY order_index, id
  ) INTO before_rows
  FROM public.profile_skills WHERE user_id=u;
  PERFORM set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', u::text, 'role', 'authenticated')::text,
    false
  );
  SET LOCAL ROLE authenticated;
  result := public.open_assist_skills_edit_v1(u, op);
  IF result->>'status' <> 'opened'
     OR result->'baseline' <> '["Gestão","SQL"]'::jsonb THEN
    RAISE EXCEPTION 'C5 open CAS falhou: %', result;
  END IF;
  result := public.apply_assist_skills_edit_v1(
    u, op, '["Gestão","SQL"]', '["Gestão","Dart"]'
  );
  RESET ROLE;
  IF result->>'outcome' <> 'applied' THEN
    RAISE EXCEPTION 'C5 apply CAS falhou: %', result;
  END IF;
  SET LOCAL ROLE authenticated;
  result := public.undo_assist_skills_edit_v1(u, op);
  RESET ROLE;
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', id, 'name', name, 'category', category,
      'canonical_skill_id', canonical_skill_id,
      'order_index', order_index, 'created_at', created_at
    ) ORDER BY order_index, id
  ) INTO after_rows
  FROM public.profile_skills WHERE user_id=u;
  IF result->>'outcome' <> 'undone'
     OR after_rows IS DISTINCT FROM before_rows THEN
    RAISE EXCEPTION 'C5 undo CAS divergiu: %', result;
  END IF;
  RAISE NOTICE 'C5 OK: apply/undo CAS coexistem com a cadeia 14→17';
END
$test$;

-- Reapply da migration de recibos sobre operação já concluída: o contrato é
-- idempotente e não apaga histórico/undo.
\ir ../migrations/20260717140000_assist_skills_cas.sql

DO $test$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profile_assist_skill_operations
    WHERE user_id='77777777-7777-7777-7777-777777777777'
      AND operation_id='56565656-5656-4656-8656-565656565656'
      AND outcome='applied' AND undone_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'C6 reapply perdeu recibo/undo';
  END IF;
  IF NOT has_function_privilege(
       'authenticated',
       'public.open_assist_skills_edit_v1(uuid,uuid)',
       'EXECUTE'
     ) OR NOT has_function_privilege(
       'authenticated',
       'public.apply_assist_skills_edit_v1(uuid,uuid,jsonb,jsonb)',
       'EXECUTE'
     ) OR has_table_privilege(
       'authenticated', 'public.profile_assist_skill_operations', 'SELECT'
     ) THEN
    RAISE EXCEPTION 'C6 reapply alterou ACL';
  END IF;
  RAISE NOTICE 'C6 OK: reapply preserva recibo e ACL';
END
$test$;

-- Trigger exclusivamente do harness: permite manter uma escrita válida do
-- writer service aberta enquanto o runner observa o guided writer esperando o
-- mesmo advisory. O setting só existe na sessão de teste que opta pelo hold.
CREATE OR REPLACE FUNCTION public._test_hold_profile_write()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('test.hold_profile_write', true) = 'on' THEN
    PERFORM pg_sleep(4);
  END IF;
  RETURN NULL;
END
$$;
DROP TRIGGER IF EXISTS zzzz_test_hold_profile_write
  ON public.profile_personal;
CREATE TRIGGER zzzz_test_hold_profile_write
  AFTER INSERT OR UPDATE ON public.profile_personal
  FOR EACH STATEMENT EXECUTE FUNCTION public._test_hold_profile_write();

-- Gate 3.0I — reversão do import revisado (snapshot pré-apply + restore).
\ir perfil_central_fase3_revert_test.sql

-- Gate 3.0H (app-side) — contratos CAS de escalar + item-field.
\ir perfil_central_fase3_appside_cas_test.sql

SELECT 'ALL_COMBINED_SQL_TESTS_OK' AS result;
