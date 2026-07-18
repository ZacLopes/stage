-- Fase 3 (Perfil Central) / Gate 2.0 — teste LOCAL sob RLS da migration de
-- metadados + promoção atômica + fill-empty. Auto-contido: harness mínimo
-- (roles Supabase, auth.uid() via JWT claim, RLS + policies + grants), inclui
-- as migrations REAIS via \ir e roda asserções EXECUTANDO como `authenticated`
-- (RLS de verdade), validando SQLSTATE específico. NÃO destrutivo: roda contra
-- um Postgres EFÊMERO (ver scripts/run_fase3_sql_test.sh), nunca prod.

\set ON_ERROR_STOP on

-- ── Roles Supabase ──────────────────────────────────────────────────────────
DO $$ BEGIN CREATE ROLE authenticated NOLOGIN; EXCEPTION WHEN duplicate_object THEN END $$;
DO $$ BEGIN CREATE ROLE anon NOLOGIN; EXCEPTION WHEN duplicate_object THEN END $$;
DO $$ BEGIN CREATE ROLE service_role NOLOGIN; EXCEPTION WHEN duplicate_object THEN END $$;
ALTER ROLE service_role BYPASSRLS;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── auth: users + uid() lendo o JWT claim (request.jwt.claims) ──────────────
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users (id uuid PRIMARY KEY);
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $fn$
  -- Paridade com Supabase: claim ausente/'' é sessão sem uid, não JSON inválido.
  SELECT NULLIF(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb->>'sub', '')::uuid
$fn$;
GRANT USAGE ON SCHEMA auth TO authenticated, anon;
GRANT SELECT ON auth.users TO authenticated, anon;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated, anon;

-- safe_integer (usado por save_profile_fill_empty)
CREATE OR REPLACE FUNCTION public.safe_integer(p text) RETURNS integer
  LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE WHEN p ~ '^-?\d+$' THEN p::integer ELSE NULL END
$fn$;

-- user_profiles (FK de saved_resumes). gamification_data guarda o cache legacy
-- ATIVO (imported_resume.raw_text) usado por match/adaptação — só a promoção o toca.
CREATE TABLE IF NOT EXISTS public.user_profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  gamification_data jsonb);

-- saved_resumes baseline
-- PARIDADE com o schema real (lib/data/saved_resumes_schema.sql): user_id tem
-- DEFAULT auth.uid() — é o que torna o insert do cliente SEM user_id válido sob
-- o grant por-coluna (blocker 1). O harness antigo omitia o default e por isso
-- não pegou a regressão do grant (blocker 8).
CREATE TABLE IF NOT EXISTS public.saved_resumes (
  id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  title text NOT NULL, file_path text NOT NULL,
  created_at timestamptz DEFAULT now() NOT NULL,
  source text DEFAULT 'manual' NOT NULL
    CHECK (source = ANY (ARRAY['manual', 'imported', 'adapted'])),
  resume_data jsonb, template_id text
);

-- profile_personal (FK -> auth.users)
CREATE TABLE IF NOT EXISTS public.profile_personal (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  first_name text, last_name text, email text,
  phone_country_code text, phone_number text, headline text, summary text,
  gender text, age_range text,
  location_country text, location_state text, location_city text,
  location_postal_code text, location_street_address text,
  date_of_birth date, availability text,
  attribution_source text, profile_source text,
  completeness_score integer NOT NULL DEFAULT 0,
  linkedin_url text, website text,
  last_extracted_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- safe_date/safe_numeric (usados por save_profile_fill_empty nas filhas)
CREATE OR REPLACE FUNCTION public.safe_date(p text) RETURNS date
  LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE WHEN p ~ '^\d{4}-\d{2}-\d{2}' THEN (left(p,10))::date ELSE NULL END
$fn$;
CREATE OR REPLACE FUNCTION public.safe_numeric(p text) RETURNS numeric
  LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE WHEN p ~ '^-?\d+(\.\d+)?$' THEN p::numeric ELSE NULL END
$fn$;

-- Tabelas-filhas com as RESTRIÇÕES REAIS (NOT NULL, CHECKs de datas/is_current,
-- confidence/needs_review, FKs parent→child). Escritas SÓ pela RPC SECURITY
-- DEFINER (owner, bypassa RLS) → não precisam de RLS/policy aqui.
-- Colunas espelham o modelo REAL das entidades (blocker 4): experiences.kind,
-- bullets.verb, education.institution_id/level/status/semester/school_year,
-- projects.role/context. Sem elas o harness não detectaria campos descartados.
CREATE TABLE IF NOT EXISTS public.profile_experiences (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title text NOT NULL, company text NOT NULL, location text,
  start_date date NOT NULL, end_date date,
  is_current boolean NOT NULL DEFAULT false, order_index integer NOT NULL DEFAULT 0,
  confidence numeric(3,2) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  needs_review boolean NOT NULL DEFAULT false, kind text,
  CHECK (is_current = true OR end_date IS NOT NULL),
  CHECK (end_date IS NULL OR end_date >= start_date));
CREATE TABLE IF NOT EXISTS public.profile_bullets (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  experience_id uuid NOT NULL REFERENCES public.profile_experiences(id) ON DELETE CASCADE,
  text text NOT NULL, angle text, strength_score integer, verb text, order_index integer NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS public.profile_education (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  institution text NOT NULL, institution_id uuid, education_level text, education_status text,
  location text, degree text, current_semester integer, current_school_year integer,
  start_date date, end_date date,
  gpa numeric(4,2), max_gpa numeric(4,2), order_index integer NOT NULL DEFAULT 0,
  confidence numeric(3,2) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date));
CREATE TABLE IF NOT EXISTS public.profile_education_majors (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  education_id uuid NOT NULL REFERENCES public.profile_education(id) ON DELETE CASCADE,
  name text NOT NULL, order_index integer NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS public.profile_education_minors (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  education_id uuid NOT NULL REFERENCES public.profile_education(id) ON DELETE CASCADE,
  name text NOT NULL, order_index integer NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS public.profile_education_activities (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  education_id uuid NOT NULL REFERENCES public.profile_education(id) ON DELETE CASCADE,
  text text NOT NULL, order_index integer NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS public.profile_languages (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY, user_id uuid NOT NULL,
  name text, proficiency text, order_index integer DEFAULT 0);
CREATE TABLE IF NOT EXISTS public.profile_skills (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY, user_id uuid NOT NULL,
  name text, category text, order_index integer DEFAULT 0);
CREATE UNIQUE INDEX IF NOT EXISTS profile_skills_uq ON public.profile_skills (user_id, lower(name));
CREATE TABLE IF NOT EXISTS public.profile_certifications (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY, user_id uuid NOT NULL,
  name text, issuer text, date date, order_index integer DEFAULT 0);
CREATE TABLE IF NOT EXISTS public.profile_projects (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY, user_id uuid NOT NULL,
  name text, role text, context text, website text, description text, start_date date, end_date date,
  is_current boolean DEFAULT false, order_index integer DEFAULT 0);
CREATE TABLE IF NOT EXISTS public.profile_project_bullets (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id uuid NOT NULL REFERENCES public.profile_projects(id) ON DELETE CASCADE,
  text text NOT NULL, order_index integer NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS public.profile_interests (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY, user_id uuid NOT NULL,
  name text, order_index integer DEFAULT 0);
CREATE UNIQUE INDEX IF NOT EXISTS profile_interests_uq ON public.profile_interests (user_id, lower(name));
CREATE TABLE IF NOT EXISTS public.profile_awards (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY, user_id uuid NOT NULL,
  name text, date date, order_index integer DEFAULT 0);
CREATE TABLE IF NOT EXISTS public.profile_coursework (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY, user_id uuid NOT NULL,
  name text, order_index integer DEFAULT 0);

-- Estado realmente PREEXISTENTE ao deploy: A produziu o cache; depois B salvou
-- a row, mas teve texto inutilizável e nunca atualizou o cache. Como o protocolo
-- não leva candidate_id, a migration pode marcar B como mais recente na
-- biblioteca, mas NÃO pode mentir que o cache de A pertence a B.
INSERT INTO auth.users(id) VALUES
  ('0b000000-0000-0000-0000-000000000001');
INSERT INTO public.user_profiles(id, gamification_data) VALUES
  ('0b000000-0000-0000-0000-000000000001',
   '{"imported_resume":{"raw_text":"LEGACY_PRE_DEPLOY","parsed":{"name":"Old"}},"keep":"yes"}'::jsonb);
INSERT INTO public.saved_resumes(id,user_id,title,file_path,source,created_at) VALUES
  ('0b000000-0000-0000-0000-000000000011','0b000000-0000-0000-0000-000000000001',
   'legacy older','0b000000-0000-0000-0000-000000000001/older.pdf','imported','2026-01-01T00:00:00Z'),
  ('0b000000-0000-0000-0000-000000000012','0b000000-0000-0000-0000-000000000001',
   'legacy latest','0b000000-0000-0000-0000-000000000001/latest.pdf','imported','2026-01-02T00:00:00Z');

-- Paridade com 00000000000000_baseline.sql: antes destas migrations os três
-- papéis herdavam ALL. O teste precisa partir desse grant real para provar que
-- service_role perde DELETE (sem mascarar a regressão por ausência de grant).
GRANT ALL ON public.saved_resumes TO anon, authenticated, service_role;
ALTER TABLE public.saved_resumes ENABLE ROW LEVEL SECURITY;
CREATE POLICY sr_baseline_select ON public.saved_resumes FOR SELECT TO authenticated
  USING (user_id=auth.uid());
CREATE POLICY sr_baseline_insert ON public.saved_resumes FOR INSERT TO authenticated
  WITH CHECK (user_id=auth.uid());
CREATE POLICY sr_baseline_update ON public.saved_resumes FOR UPDATE TO authenticated
  USING (user_id=auth.uid()) WITH CHECK (user_id=auth.uid());
CREATE POLICY "Users can delete their own resumes" ON public.saved_resumes
  FOR DELETE TO authenticated USING (user_id=auth.uid());

-- ── Migrations REAIS sob teste ──────────────────────────────────────────────
\ir ../migrations/20260714120000_saved_resumes_import_metadata.sql

-- REGRESSÃO DE DEPLOY: cada migration é uma transação/commit separado. Ao fim
-- da 120000 o HEAD^ já precisa conseguir apagar a própria row depois do blob;
-- cross-user e path fora do namespace continuam invisíveis, service_role não
-- conserva DELETE direto. Este teste roda deliberadamente ANTES da 130000.
DO $t$
DECLARE
  u uuid := '0a120000-0000-0000-0000-000000000001';
  other uuid := '0a120000-0000-0000-0000-000000000002';
  own_id uuid; other_id uuid; bad_path_id uuid; affected int;
  got_code text; got_message text;
BEGIN
  INSERT INTO auth.users(id) VALUES (u),(other) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u),(other) ON CONFLICT DO NOTHING;
  INSERT INTO public.saved_resumes(user_id,title,file_path,source)
    VALUES (u,'post-120-own',u::text||'/own.pdf','manual') RETURNING id INTO own_id;
  INSERT INTO public.saved_resumes(user_id,title,file_path,source)
    VALUES (other,'post-120-other',other::text||'/other.pdf','manual') RETURNING id INTO other_id;
  -- Row histórica insegura pode existir antes do hardening; a policy não deixa
  -- o client usá-la para induzir remoção fora do próprio namespace.
  INSERT INTO public.saved_resumes(user_id,title,file_path,source)
    VALUES (u,'post-120-bad-path',other::text||'/foreign.pdf','manual') RETURNING id INTO bad_path_id;

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub',u::text,'role','authenticated')::text, false);
  SET LOCAL ROLE authenticated;
  DELETE FROM public.saved_resumes WHERE id=own_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'FALHOU POST-120: own DELETE bloqueado'; END IF;
  DELETE FROM public.saved_resumes WHERE id=other_id;
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 0 THEN RAISE EXCEPTION 'FALHOU POST-120: cross-user DELETE afetou %',affected; END IF;
  DELETE FROM public.saved_resumes WHERE id=bad_path_id;
  GET DIAGNOSTICS affected = ROW_COUNT;
  RESET ROLE;
  IF affected <> 0 THEN RAISE EXCEPTION 'FALHOU POST-120: path alheio foi deletado'; END IF;
  IF EXISTS (SELECT 1 FROM public.saved_resumes WHERE id=own_id)
     OR NOT EXISTS (SELECT 1 FROM public.saved_resumes WHERE id IN (other_id,bad_path_id))
     OR NOT has_table_privilege('authenticated','public.saved_resumes','DELETE')
     OR has_table_privilege('service_role','public.saved_resumes','DELETE') THEN
    RAISE EXCEPTION 'FALHOU POST-120: estado/grants divergiram'; END IF;

  -- A segunda migration ainda não entrou: a Edge HEAD^ encontra a assinatura,
  -- mas recebe erro estável em vez de executar o writer destrutivo legacy.
  INSERT INTO public.profile_personal(user_id,email,last_extracted_at)
    VALUES (u,'manual@corp.com','2026-01-01T00:00:00Z');
  SET LOCAL ROLE service_role;
  BEGIN
    PERFORM public.save_profile_from_json(u,'{"personal":{"email":"import@cv.com"}}'::jsonb);
    RAISE EXCEPTION 'post_120_stub_returned_success';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got_code = RETURNED_SQLSTATE, got_message = MESSAGE_TEXT;
  END;
  RESET ROLE;
  IF got_code <> '55000' OR got_message <> 'profile_import_temporarily_unavailable'
     OR (SELECT email FROM public.profile_personal WHERE user_id=u) <> 'manual@corp.com'
     OR has_function_privilege('authenticated','public.save_profile_from_json(uuid,jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.save_profile_from_json(uuid,jsonb)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.save_profile_from_json(uuid,jsonb)','EXECUTE')
     OR has_function_privilege('public','public.profile_write_lock_key(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.profile_write_lock_key(uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.profile_write_lock_key(uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.profile_write_lock_key(uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.promote_imported_source(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'FALHOU POST-120: stub inseguro code=% msg=%',got_code,got_message; END IF;

  DELETE FROM public.saved_resumes WHERE id IN (other_id,bad_path_id);
  DELETE FROM public.user_profiles WHERE id IN (u,other);
  DELETE FROM auth.users WHERE id IN (u,other);
  RAISE NOTICE 'T-POST-120 OK: own delete seguro; shim fail-closed; lock helper/promoção privados; manual intacto';
END $t$;

\ir ../migrations/20260714130000_save_profile_fill_empty.sql

-- ── RLS + policies + grants (equivalente às migrations de prod) ─────────────
-- saved_resumes: NÃO re-concede UPDATE/INSERT amplos — a migration 20260714120000
-- já revogou e concedeu por-COLUNA. DELETE vem exclusivamente da ponte segura
-- instalada por 130000 (fence+cleanup), nunca do harness.
GRANT SELECT ON public.saved_resumes TO authenticated;
-- Em prod o build antigo e Edge legacy escrevem gamification_data diretamente.
-- O harness concede exatamente essa coluna para exercitar o guard sob RLS.
GRANT SELECT, UPDATE (gamification_data) ON public.user_profiles TO authenticated;
GRANT SELECT, UPDATE (gamification_data) ON public.user_profiles TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profile_personal TO authenticated;
ALTER TABLE public.saved_resumes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profile_personal ENABLE ROW LEVEL SECURITY;
-- SELECT/INSERT/UPDATE equivalentes ao baseline. DELETE não é recriado pelo
-- harness: depende EXCLUSIVAMENTE da policy backward-compatible da migration
-- 20260714130000, para o teste não mascarar uma ponte ausente.
DROP POLICY IF EXISTS sr_own ON public.saved_resumes;
DROP POLICY IF EXISTS sr_select ON public.saved_resumes;
DROP POLICY IF EXISTS sr_insert ON public.saved_resumes;
DROP POLICY IF EXISTS sr_update ON public.saved_resumes;
DROP POLICY IF EXISTS sr_baseline_select ON public.saved_resumes;
DROP POLICY IF EXISTS sr_baseline_insert ON public.saved_resumes;
DROP POLICY IF EXISTS sr_baseline_update ON public.saved_resumes;
CREATE POLICY sr_select ON public.saved_resumes FOR SELECT TO authenticated
  USING (user_id = auth.uid());
CREATE POLICY sr_insert ON public.saved_resumes FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND split_part(file_path, '/', 1) = auth.uid()::text
    AND cardinality(string_to_array(file_path, '/')) >= 2
    AND array_position(string_to_array(file_path, '/'), '') IS NULL
    AND NOT (string_to_array(file_path, '/') && ARRAY['.','..']::text[])
    AND strpos(file_path, E'\\') = 0
  );
CREATE POLICY sr_update ON public.saved_resumes FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS up_own ON public.user_profiles;
DROP POLICY IF EXISTS up_select ON public.user_profiles;
CREATE POLICY up_select ON public.user_profiles FOR SELECT TO authenticated
  USING (id = auth.uid());
CREATE POLICY up_own ON public.user_profiles FOR UPDATE TO authenticated
  USING (id = auth.uid()) WITH CHECK (id = auth.uid());

-- ── Ponte legacy/cache: backfill real + guard fail-closed ──────────────────────────────
DO $t$
DECLARE
  u uuid := '0b000000-0000-0000-0000-000000000001';
  older uuid := '0b000000-0000-0000-0000-000000000011';
  latest uuid := '0b000000-0000-0000-0000-000000000012';
BEGIN
  IF (SELECT is_latest_legacy_source FROM public.saved_resumes WHERE id=older)
     OR NOT (SELECT is_latest_legacy_source FROM public.saved_resumes WHERE id=latest)
     OR (SELECT count(*) FROM public.saved_resumes WHERE user_id=u AND is_latest_legacy_source) <> 1 THEN
    RAISE EXCEPTION 'FALHOU LEGACY-BACKFILL: marker não escolheu a row mais nova';
  END IF;
  IF EXISTS (SELECT 1 FROM public.saved_resumes WHERE user_id=u
              AND (extraction_status IS NOT NULL OR is_current_source)) THEN
    RAISE EXCEPTION 'FALHOU LEGACY-BACKFILL: inventou status/current';
  END IF;
  IF (SELECT gamification_data->'imported_resume' ? 'source_resume_id'
        FROM public.user_profiles WHERE id=u)
     OR (SELECT gamification_data#>>'{imported_resume,raw_text}'
           FROM public.user_profiles WHERE id=u) <> 'LEGACY_PRE_DEPLOY'
     OR (SELECT gamification_data->>'keep' FROM public.user_profiles WHERE id=u) <> 'yes' THEN
    RAISE EXCEPTION 'FALHOU LEGACY-BACKFILL: cache de A foi perdido ou falsamente vinculado a B';
  END IF;
  RAISE NOTICE 'T-LEGACY-BACKFILL OK: marker B não rotula cache A; cache preservado UNBOUND; sem status/current inventado';
END $t$;
DROP POLICY IF EXISTS pp_own ON public.profile_personal;
CREATE POLICY pp_own ON public.profile_personal FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- profile_skills: writer REAL (INSERT direto do app via PostgREST, sob RLS). É a
-- tabela que o teste de concorrência usa como "outro escritor" — a trigger de
-- fencing (zzz_fence) adquire o advisory lock por-usuário nesse INSERT, do mesmo
-- jeito que aconteceria em produção.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profile_skills TO authenticated;
ALTER TABLE public.profile_skills ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS psk_own ON public.profile_skills;
CREATE POLICY psk_own ON public.profile_skills FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- profile_experiences: writer autenticado direto (UPDATE) sob RLS — usado no
-- teste de INVERSÃO advisory↔tuple (composite RPC vs UPDATE manual da mesma linha).
GRANT UPDATE ON public.profile_experiences TO authenticated;
ALTER TABLE public.profile_experiences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pe_own ON public.profile_experiences;
CREATE POLICY pe_own ON public.profile_experiences FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- Leitura sob RLS das demais tabelas de perfil (o app lê o próprio perfil como
-- authenticated). As ESCRITAS compostas passam pelas RPCs SECURITY DEFINER; aqui
-- só habilitamos as verificações dos testes (SELECT) como authenticated.
GRANT SELECT ON public.profile_experiences, public.profile_bullets,
  public.profile_education, public.profile_education_majors, public.profile_education_minors,
  public.profile_education_activities, public.profile_languages, public.profile_certifications,
  public.profile_projects, public.profile_project_bullets, public.profile_interests,
  public.profile_awards, public.profile_coursework TO authenticated;

-- seed (como postgres)
INSERT INTO auth.users(id) VALUES
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222') ON CONFLICT DO NOTHING;
INSERT INTO public.user_profiles(id) VALUES
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222') ON CONFLICT DO NOTHING;

-- ════════════════════════════════════════════════════════════════════════════
-- ITEM 2 — CHECK de status: a fonte ATIVA precisa ser imported + ready.
-- ════════════════════════════════════════════════════════════════════════════
DO $t$
DECLARE u uuid := '11111111-1111-1111-1111-111111111111'; st text;
BEGIN
  DELETE FROM public.saved_resumes WHERE user_id = u;
  -- semeia uma importada em cada status não-ready + manual + adapted
  FOREACH st IN ARRAY ARRAY['pending','extracting','failed']
  LOOP
    BEGIN
      INSERT INTO public.saved_resumes(user_id,title,file_path,source,extraction_status,is_current_source)
        VALUES (u,'x','p','imported',st,true);
      RAISE EXCEPTION 'FALHOU 2A: current permitido com status=%', st;
    EXCEPTION WHEN check_violation THEN NULL; END;
  END LOOP;
  BEGIN
    INSERT INTO public.saved_resumes(user_id,title,file_path,source,is_current_source)
      VALUES (u,'m','p','manual',true);
    RAISE EXCEPTION 'FALHOU 2B: current permitido em manual';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.saved_resumes(user_id,title,file_path,source,extraction_status,is_current_source)
      VALUES (u,'a','p','adapted','ready',true);
    RAISE EXCEPTION 'FALHOU 2C: current permitido em adapted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  -- ready imported PODE ser current
  INSERT INTO public.saved_resumes(user_id,title,file_path,source,extraction_status,is_current_source)
    VALUES (u,'ok','p','imported','ready',true);
  RAISE NOTICE 'T2 OK: só imported+ready pode ser current (pending/extracting/failed/manual/adapted rejeitados)';
  DELETE FROM public.saved_resumes WHERE user_id = u;
END $t$;

-- ════════════════════════════════════════════════════════════════════════════
-- ITEM 1 — fill-empty à prova de TOCTOU (sob RLS, como authenticated).
-- ════════════════════════════════════════════════════════════════════════════
SELECT set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111"}', false);
SET ROLE authenticated;
DO $t$
DECLARE u uuid := '11111111-1111-1111-1111-111111111111';
BEGIN
  DELETE FROM public.profile_personal WHERE user_id = u;
  -- edição MANUAL concorrente: e-mail preenchido, headline vazio.
  INSERT INTO public.profile_personal(user_id, email, headline) VALUES (u, 'manual@user.com', NULL);
  -- extração traz e-mail DIFERENTE + headline.
  PERFORM public.save_profile_fill_empty(u,
    '{"personal":{"email":"extracted@ai.com","headline":"Headline extraída","first_name":"Ana"}}'::jsonb);
  IF (SELECT email FROM public.profile_personal WHERE user_id = u) <> 'manual@user.com' THEN
    RAISE EXCEPTION 'FALHOU 1: e-mail manual foi sobrescrito';
  END IF;
  IF (SELECT headline FROM public.profile_personal WHERE user_id = u) <> 'Headline extraída' THEN
    RAISE EXCEPTION 'FALHOU 1: headline vazio não foi preenchido';
  END IF;
  IF (SELECT first_name FROM public.profile_personal WHERE user_id = u) <> 'Ana' THEN
    RAISE EXCEPTION 'FALHOU 1: first_name vazio não foi preenchido';
  END IF;
  RAISE NOTICE 'T1 OK: fill-empty — e-mail manual sobrevive, só campos vazios preenchidos';
END $t$;
RESET ROLE;

-- 1b: anon/PUBLIC NÃO executa save_profile_fill_empty (permission denied)
SET ROLE anon;
DO $t$
DECLARE raised boolean := false;
BEGIN
  BEGIN
    PERFORM public.save_profile_fill_empty('11111111-1111-1111-1111-111111111111', '{}'::jsonb);
  EXCEPTION WHEN insufficient_privilege THEN raised := true; END;
  IF NOT raised THEN RAISE EXCEPTION 'FALHOU 1b: anon executou fill-empty'; END IF;
  RAISE NOTICE 'T1b OK: anon negado (insufficient_privilege) em fill-empty';
END $t$;
RESET ROLE;

-- R7 hardening: payload totalmente vazio é failure tipada e ZERO escrita.
DO $t$
DECLARE u uuid := '11111111-1111-1111-1111-111111111112'; res jsonb;
BEGIN
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111112"}', false);
  SET LOCAL ROLE authenticated;
  res := public.save_profile_fill_empty(u, '{}'::jsonb);
  RESET ROLE;
  IF (res->>'status') <> 'failure' OR NOT (res->'failed' @> '["empty_payload"]'::jsonb) THEN
    RAISE EXCEPTION 'FALHOU R7-EMPTY: outcome não fail-closed (%)', res; END IF;
  IF EXISTS (SELECT 1 FROM public.profile_personal WHERE user_id=u)
     OR EXISTS (SELECT 1 FROM public.profile_experiences WHERE user_id=u)
     OR EXISTS (SELECT 1 FROM public.profile_education WHERE user_id=u)
     OR EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u)
     OR EXISTS (SELECT 1 FROM public.profile_projects WHERE user_id=u) THEN
    RAISE EXCEPTION 'FALHOU R7-EMPTY: criou personal/filha'; END IF;
  -- Hardening não pode rejeitar um perfil parcial legítimo só de localização.
  SET LOCAL ROLE authenticated;
  res := public.save_profile_fill_empty(u, '{"personal":{"location_city":"São Paulo"}}'::jsonb);
  RESET ROLE;
  IF (res->>'status') <> 'success'
     OR (SELECT location_city FROM public.profile_personal WHERE user_id=u) <> 'São Paulo' THEN
    RAISE EXCEPTION 'FALHOU R7-EMPTY: hardening rejeitou personal parcial legítimo (%)', res; END IF;
  RAISE NOTICE 'R7-EMPTY OK: {} → failure/zero write; personal parcial legítimo ainda aplica';
END $t$;

-- 1c/1d: SEÇÃO FILHA fill-only (skills). Já preenchida → NÃO mistura; vazia →
-- preenche. Seed/assert como postgres; a RPC (DEFINER) roda sob authenticated.
DO $t$
DECLARE u uuid := '11111111-1111-1111-1111-111111111111';
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111"}', false);
  DELETE FROM public.profile_skills WHERE user_id = u;
  -- (1c) seção já preenchida (manual) → importados NÃO entram
  INSERT INTO public.profile_skills(user_id, name) VALUES (u, 'Skill Manual');
  SET LOCAL ROLE authenticated;
  PERFORM public.save_profile_fill_empty(u,
    '{"personal":{},"skills":[{"name":"Skill Extraída A"},{"name":"Skill Extraída B"}]}'::jsonb);
  RESET ROLE;
  IF (SELECT count(*) FROM public.profile_skills WHERE user_id=u) <> 1
     OR (SELECT name FROM public.profile_skills WHERE user_id=u) <> 'Skill Manual' THEN
    RAISE EXCEPTION 'FALHOU 1c: seção skills preenchida foi misturada/alterada';
  END IF;
  -- (1d) seção vazia → preenche com os importados
  DELETE FROM public.profile_skills WHERE user_id = u;
  SET LOCAL ROLE authenticated;
  PERFORM public.save_profile_fill_empty(u,
    '{"personal":{},"skills":[{"name":"Skill Extraída A"},{"name":"Skill Extraída B"}]}'::jsonb);
  RESET ROLE;
  IF (SELECT count(*) FROM public.profile_skills WHERE user_id=u) <> 2 THEN
    RAISE EXCEPTION 'FALHOU 1d: seção skills vazia não foi preenchida';
  END IF;
  RAISE NOTICE 'T1c/1d OK: filha fill-only (preenchida não mistura; vazia preenche)';
END $t$;

-- 1p: PROBE do sucesso parcial. Exp válida + exp(end_date null, is_current
-- false). Com os CHECKs reais, a 2ª violaria `is_current OR end_date`; a
-- NORMALIZAÇÃO (end_date null → is_current true) a torna válida → AMBAS entram,
-- status=success. Antes (swallow + sem normalizar): só 1 + sucesso silencioso.
DO $t$
DECLARE u uuid := '11111111-1111-1111-1111-111111111111'; res jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111"}', false);
  DELETE FROM public.profile_experiences WHERE user_id = u;
  SET LOCAL ROLE authenticated;
  res := public.save_profile_fill_empty(u, '{"personal":{},"experiences":[
    {"title":"A","company":"X","start_date":"2020-01-01","end_date":"2021-01-01","is_current":false,"confidence":0.9},
    {"title":"B","company":"Y","start_date":"2022-01-01","end_date":null,"is_current":false,"confidence":0.8}]}'::jsonb);
  RESET ROLE;
  IF (res->>'status') <> 'success' THEN RAISE EXCEPTION 'FALHOU 1p: status=% (esperava success)', res; END IF;
  IF (SELECT count(*) FROM public.profile_experiences WHERE user_id=u) <> 2 THEN
    RAISE EXCEPTION 'FALHOU 1p: descarte silencioso (só % exp)', (SELECT count(*) FROM public.profile_experiences WHERE user_id=u);
  END IF;
  IF (SELECT is_current FROM public.profile_experiences WHERE user_id=u AND title='B') <> true THEN
    RAISE EXCEPTION 'FALHOU 1p: end_date null não normalizou is_current=true';
  END IF;
  IF (SELECT needs_review FROM public.profile_experiences WHERE user_id=u AND title='B') <> true
     OR (SELECT needs_review FROM public.profile_experiences WHERE user_id=u AND title='A') <> false THEN
    RAISE EXCEPTION 'FALHOU 1p: needs_review incorreto';
  END IF;
  IF (SELECT confidence FROM public.profile_experiences WHERE user_id=u AND title='A') <> 0.9 THEN
    RAISE EXCEPTION 'FALHOU 1p: confidence não persistido';
  END IF;
  RAISE NOTICE 'T1p OK: sem descarte (2 exps); normalização + needs_review + confidence';
END $t$;

-- 1a: erro INESPERADO no 2º item → rollback da SEÇÃO INTEIRA + status=partial;
-- retry (sem o erro) COMPLETA. Trigger de teste explode no title 'BOOM'.
CREATE OR REPLACE FUNCTION public._t_exp_boom() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  IF NEW.title = 'BOOM' THEN RAISE EXCEPTION 'boom_exp'; END IF;
  RETURN NEW;
END $fn$;
CREATE TRIGGER _t_exp_boom_trg BEFORE INSERT ON public.profile_experiences
  FOR EACH ROW EXECUTE FUNCTION public._t_exp_boom();
DO $t$
DECLARE u uuid := '11111111-1111-1111-1111-111111111111'; res jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111"}', false);
  DELETE FROM public.profile_experiences WHERE user_id = u;
  SET LOCAL ROLE authenticated;
  res := public.save_profile_fill_empty(u, '{"personal":{},"experiences":[
    {"title":"OK","company":"X","start_date":"2020-01-01","end_date":"2021-01-01"},
    {"title":"BOOM","company":"Y","start_date":"2022-01-01","end_date":"2023-01-01"}]}'::jsonb);
  RESET ROLE;
  IF (res->>'status') <> 'partial' THEN RAISE EXCEPTION 'FALHOU 1a: status=% (esperava partial)', res; END IF;
  IF NOT (res->'failed' @> '["experiences"]'::jsonb) THEN
    RAISE EXCEPTION 'FALHOU 1a: experiences não marcada em failed_sections (%)', res;
  END IF;
  IF (SELECT count(*) FROM public.profile_experiences WHERE user_id=u) <> 0 THEN
    RAISE EXCEPTION 'FALHOU 1a: seção não desfeita por inteiro (%)', (SELECT count(*) FROM public.profile_experiences WHERE user_id=u);
  END IF;
END $t$;
DROP TRIGGER _t_exp_boom_trg ON public.profile_experiences;
DO $t$
DECLARE u uuid := '11111111-1111-1111-1111-111111111111'; res jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111"}', false);
  SET LOCAL ROLE authenticated;
  res := public.save_profile_fill_empty(u, '{"personal":{},"experiences":[
    {"title":"OK","company":"X","start_date":"2020-01-01","end_date":"2021-01-01"},
    {"title":"BOOM","company":"Y","start_date":"2022-01-01","end_date":"2023-01-01"}]}'::jsonb);
  RESET ROLE;
  IF (res->>'status') <> 'success' THEN RAISE EXCEPTION 'FALHOU 1a-retry: status=% ', res; END IF;
  IF (SELECT count(*) FROM public.profile_experiences WHERE user_id=u) <> 2 THEN
    RAISE EXCEPTION 'FALHOU 1a-retry: não completou (%)', (SELECT count(*) FROM public.profile_experiences WHERE user_id=u);
  END IF;
  RAISE NOTICE 'T1a OK: erro no item 2 → seção desfeita (partial); retry completa (success)';
END $t$;

-- 1e: profile_source existente NÃO é sobrescrito (mesmo com payload personal)
SELECT set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111"}', false);
SET ROLE authenticated;
DO $t$
DECLARE u uuid := '11111111-1111-1111-1111-111111111111';
BEGIN
  DELETE FROM public.profile_personal WHERE user_id = u;
  INSERT INTO public.profile_personal(user_id, profile_source) VALUES (u, 'manual');
  PERFORM public.save_profile_fill_empty(u, '{"personal":{"profile_source":"imported","first_name":"Ana"}}'::jsonb);
  IF (SELECT profile_source FROM public.profile_personal WHERE user_id=u) <> 'manual' THEN
    RAISE EXCEPTION 'FALHOU 1e: profile_source foi sobrescrito';
  END IF;
  RAISE NOTICE 'T1e OK: profile_source existente preservado';
END $t$;
RESET ROLE;

-- 1f: escalar SÓ-ESPAÇO conta como vazio → é preenchido (alinhado ao trim)
SELECT set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111"}', false);
SET ROLE authenticated;
DO $t$
DECLARE u uuid := '11111111-1111-1111-1111-111111111111';
BEGIN
  DELETE FROM public.profile_personal WHERE user_id = u;
  INSERT INTO public.profile_personal(user_id, email, first_name) VALUES (u, '   ', 'Já Tem');
  PERFORM public.save_profile_fill_empty(u, '{"personal":{"email":"novo@x.com","first_name":"Outro"}}'::jsonb);
  IF (SELECT email FROM public.profile_personal WHERE user_id=u) <> 'novo@x.com' THEN
    RAISE EXCEPTION 'FALHOU 1f: e-mail só-espaço não foi tratado como vazio';
  END IF;
  IF (SELECT first_name FROM public.profile_personal WHERE user_id=u) <> 'Já Tem' THEN
    RAISE EXCEPTION 'FALHOU 1f: first_name com conteúdo foi alterado';
  END IF;
  RAISE NOTICE 'T1f OK: só-espaço = vazio (preenche); conteúdo real preservado';
END $t$;
RESET ROLE;

-- 1g: authenticated B → p_user_id de A em fill-empty → not_authorized, A intacto
DO $t$
DECLARE ua uuid := '11111111-1111-1111-1111-111111111111'; before text; got text;
BEGIN
  -- prepara A com um first_name conhecido (como postgres)
  DELETE FROM public.profile_personal WHERE user_id = ua;
  INSERT INTO public.profile_personal(user_id, first_name) VALUES (ua, 'Ana A');
  SELECT first_name INTO before FROM public.profile_personal WHERE user_id = ua;
  PERFORM set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222"}', false);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.save_profile_fill_empty(ua, '{"personal":{"first_name":"Hacker"}}'::jsonb);
    RAISE EXCEPTION 'FALHOU 1g: B escreveu no perfil de A';
  EXCEPTION WHEN SQLSTATE '28000' THEN got := 'ok'; END;
  RESET ROLE;
  IF got IS NULL THEN RAISE EXCEPTION 'FALHOU 1g: SQLSTATE inesperado'; END IF;
  IF (SELECT first_name FROM public.profile_personal WHERE user_id = ua) <> before THEN
    RAISE EXCEPTION 'FALHOU 1g: dados de A mudaram';
  END IF;
  RAISE NOTICE 'T1g OK: B negado (28000) em fill-empty de A; A intacto';
END $t$;

-- 1h: tentativa DIRETA de duas fontes current imported+ready → unique_violation
DO $t$
DECLARE u uuid := '11111111-1111-1111-1111-111111111111'; got text;
BEGIN
  DELETE FROM public.saved_resumes WHERE user_id = u;
  INSERT INTO public.saved_resumes(user_id,title,file_path,source,extraction_status,is_current_source)
    VALUES (u,'c1','p1','imported','ready',true);
  BEGIN
    INSERT INTO public.saved_resumes(user_id,title,file_path,source,extraction_status,is_current_source)
      VALUES (u,'c2','p2','imported','ready',true);
    RAISE EXCEPTION 'FALHOU 1h: permitiu 2 current imported+ready';
  EXCEPTION WHEN unique_violation THEN got := 'ok'; END;
  IF got IS NULL THEN RAISE EXCEPTION 'FALHOU 1h'; END IF;
  DELETE FROM public.saved_resumes WHERE user_id = u;
  RAISE NOTICE 'T1h OK: índice único bloqueia 2 current imported+ready (direto)';
END $t$;

-- ════════════════════════════════════════════════════════════════════════════
-- ITEM 1/2 — BLINDAGEM DE PRIVILÉGIOS: nenhuma helper SECURITY DEFINER interna é
-- executável por PUBLIC/anon/authenticated; promoção direta (promote_imported_
-- source) aposentada; RPCs de service_role fora do alcance do cliente. Inclui o
-- REPRO do exploit (anon promovendo candidata de vítima) — agora NEGADO.
-- ════════════════════════════════════════════════════════════════════════════
-- (a) matriz de has_function_privilege: internas NEGADAS a anon+authenticated;
--     client-callable liberadas a authenticated; service só a service_role.
DO $t$
DECLARE fn text; bad int := 0;
  internals text[] := ARRAY[
    'public._promote_imported_and_activate(uuid,uuid,text)','public._save_profile_fill_empty_core(uuid,jsonb)',
    'public._validate_profile_payload(jsonb)','public._assert_jtype(jsonb,text,text[],text)',
    'public._profile_has_protected_data(uuid)','public._replace_simple_list(uuid,text,jsonb)',
    'public._fence_profile_writes()','public._mark_latest_legacy_source_on_insert()',
    'public._canonical_import_cache(uuid)','public._guard_user_profile_import_cache()',
    'public._cleanup_import_cache_after_saved_resume_delete()',
    'public.profile_write_lock_key(uuid)',
    'public._norm_txt(text)','public._payload_list_key(text)',
    'public._cas_write_personal_field(uuid,text,text,text,text,text)',
    'public.promote_imported_source(uuid)'];  -- aposentada: sem grant a cliente
  client text[] := ARRAY[
    'public.apply_and_promote_imported_source(uuid,uuid)','public.apply_reviewed_conflicts_and_promote(uuid,uuid,jsonb)',
    'public.save_experience_with_bullets(uuid,jsonb)','public.save_education_with_children(uuid,jsonb)',
    'public.cas_write_profile_scalar(uuid,text,text,text,text,text)',
    'public.begin_import_source(text,text,text,uuid)',
    'public.abort_import_source(uuid,uuid)','public.delete_user()'];
  service text[] := ARRAY[
    'public.complete_import_extraction(uuid,uuid,jsonb,text,jsonb,jsonb)','public.save_profile_fill_empty_service(uuid,jsonb)',
    'public.save_profile_from_json(uuid,jsonb)'];
BEGIN
  FOREACH fn IN ARRAY internals LOOP
    IF has_function_privilege('anon', fn, 'EXECUTE') THEN RAISE EXCEPTION 'FALHOU priv: anon EXECUTA % (interna)', fn; END IF;
    IF has_function_privilege('authenticated', fn, 'EXECUTE') THEN RAISE EXCEPTION 'FALHOU priv: authenticated EXECUTA % (interna/aposentada)', fn; END IF;
    IF has_function_privilege('service_role', fn, 'EXECUTE') THEN RAISE EXCEPTION 'FALHOU priv: service_role EXECUTA % (interna)', fn; END IF;
    IF has_function_privilege('public', fn, 'EXECUTE') THEN RAISE EXCEPTION 'FALHOU priv: PUBLIC EXECUTA % (interna)', fn; END IF;
  END LOOP;
  FOREACH fn IN ARRAY client LOOP
    IF NOT has_function_privilege('authenticated', fn, 'EXECUTE') THEN RAISE EXCEPTION 'FALHOU priv: authenticated NÃO executa % (contrato)', fn; END IF;
    IF has_function_privilege('anon', fn, 'EXECUTE') OR has_function_privilege('public', fn, 'EXECUTE')
       OR has_function_privilege('service_role', fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'FALHOU priv: RPC client % vazou para anon/PUBLIC/service', fn; END IF;
  END LOOP;
  FOREACH fn IN ARRAY service LOOP
    IF has_function_privilege('authenticated', fn, 'EXECUTE') THEN RAISE EXCEPTION 'FALHOU priv: authenticated executa % (só service)', fn; END IF;
    IF has_function_privilege('anon', fn, 'EXECUTE') THEN RAISE EXCEPTION 'FALHOU priv: anon executa % (só service)', fn; END IF;
    IF NOT has_function_privilege('service_role', fn, 'EXECUTE') THEN RAISE EXCEPTION 'FALHOU priv: service_role NÃO executa % (contrato)', fn; END IF;
    IF has_function_privilege('public', fn, 'EXECUTE') THEN RAISE EXCEPTION 'FALHOU priv: PUBLIC executa % (só service)', fn; END IF;
  END LOOP;
  IF to_regprocedure('public.begin_import_source(text,text,text)') IS NOT NULL
     OR to_regprocedure('public.cas_write_profile_scalar(uuid,text,text,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'FALHOU priv: overload antigo/bypass ainda existe'; END IF;
  RAISE NOTICE 'T-PRIV(matriz) OK: internas negadas a PUBLIC/anon/authenticated; client/service nos contratos';
END $t$;

-- (b) REPRO do exploit crítico: anon tenta a helper de promoção com IDs de vítima
--     → NEGADO (insufficient_privilege), sem promover nem tocar o cache.
DO $t$
DECLARE u uuid := '11111111-1111-1111-1111-111111111111'; cand uuid; denied boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claims', NULL, false);
  DELETE FROM public.saved_resumes WHERE user_id=u;
  INSERT INTO public.saved_resumes(user_id,title,file_path,source,extraction_status,extraction_raw_text)
    VALUES (u,'victim','p','imported','ready','ORIGINAL') RETURNING id INTO cand;
  UPDATE public.user_profiles SET gamification_data = jsonb_build_object('imported_resume', jsonb_build_object('raw_text','ORIGINAL')) WHERE id=u;
  SET LOCAL ROLE anon;
  BEGIN PERFORM public._promote_imported_and_activate(u, cand, 'PWNED');
  EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  RESET ROLE;
  IF NOT denied THEN RAISE EXCEPTION 'FALHOU EXPLOIT: anon executou _promote_imported_and_activate'; END IF;
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=cand) <> false THEN RAISE EXCEPTION 'FALHOU EXPLOIT: candidata promovida'; END IF;
  IF (SELECT gamification_data->'imported_resume'->>'raw_text' FROM public.user_profiles WHERE id=u) <> 'ORIGINAL' THEN
    RAISE EXCEPTION 'FALHOU EXPLOIT: cache foi trocado para PWNED'; END IF;
  DELETE FROM public.saved_resumes WHERE user_id=u;
  UPDATE public.user_profiles SET gamification_data=NULL WHERE id=u;
  RAISE NOTICE 'T-EXPLOIT OK: anon NÃO promove candidata de vítima nem troca cache (bug crítico fechado)';
END $t$;

-- (c) authenticated NÃO promove diretamente (promote_imported_source aposentada):
--     mesmo dono/imported/ready → insufficient_privilege (só via apply/revisão).
DO $t$
DECLARE u uuid := '11111111-1111-1111-1111-111111111111'; cand uuid; denied boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111"}', false);
  DELETE FROM public.saved_resumes WHERE user_id=u;
  INSERT INTO public.saved_resumes(user_id,title,file_path,source,extraction_status)
    VALUES (u,'ready-cand','p','imported','ready') RETURNING id INTO cand;
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM public.promote_imported_source(cand);
  EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  RESET ROLE;
  IF NOT denied THEN RAISE EXCEPTION 'FALHOU B2: authenticated promoveu candidata ready DIRETO (bypass)'; END IF;
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=cand) <> false THEN RAISE EXCEPTION 'FALHOU B2: candidata virou current'; END IF;
  DELETE FROM public.saved_resumes WHERE user_id=u;
  RAISE NOTICE 'T-B2 OK: promoção direta aposentada — só apply-and-promote / reviewed-apply-and-promote promovem';
END $t$;

-- seed usuários 3, 4 e 5 para os testes de ordinality/projeto/apply+promote/revisão
INSERT INTO auth.users(id) VALUES
  ('33333333-3333-3333-3333-333333333333'),
  ('44444444-4444-4444-4444-444444444444'),
  ('55555555-5555-5555-5555-555555555555'),
  ('66666666-6666-6666-6666-666666666666') ON CONFLICT DO NOTHING;
INSERT INTO public.user_profiles(id) VALUES
  ('33333333-3333-3333-3333-333333333333'),
  ('44444444-4444-4444-4444-444444444444'),
  ('55555555-5555-5555-5555-555555555555'),
  ('66666666-6666-6666-6666-666666666666') ON CONFLICT DO NOTHING;

-- ════════════════════════════════════════════════════════════════════════════
-- ITEM 1 (Round 7) — item SIGNIFICATIVO inválido torna a seção atômica:
-- start_date ausente no segundo item desfaz também o irmão válido, marca failed
-- e não avança timestamp. Retry com o payload corrigido grava os dois; chamada
-- posterior preserva a seção sem duplicar.
-- ════════════════════════════════════════════════════════════════════════════
DO $t$
DECLARE u uuid := '11111111-1111-1111-1111-111111111111'; res jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111"}', false);
  DELETE FROM public.profile_experiences WHERE user_id = u;
  INSERT INTO public.profile_personal(user_id) VALUES(u) ON CONFLICT DO NOTHING;
  UPDATE public.profile_personal SET last_extracted_at = '2000-01-01T00:00:00Z' WHERE user_id = u;
  SET LOCAL ROLE authenticated;
  res := public.save_profile_fill_empty(u, '{"personal":{},"experiences":[
    {"title":"Good","company":"X","start_date":"2020-01-01","end_date":"2021-01-01"},
    {"title":"NoStart","company":"Y","end_date":"2023-01-01"}]}'::jsonb);
  RESET ROLE;
  IF (res->>'status') <> 'partial' OR NOT (res->'failed' @> '["experiences"]'::jsonb) THEN
    RAISE EXCEPTION 'FALHOU 1inv: significativo inválido não falhou a seção (%)', res; END IF;
  IF EXISTS (SELECT 1 FROM public.profile_experiences WHERE user_id=u) THEN
    RAISE EXCEPTION 'FALHOU 1inv: irmão válido sobreviveu ao rollback da seção'; END IF;
  IF (SELECT last_extracted_at FROM public.profile_personal WHERE user_id=u)
       IS DISTINCT FROM '2000-01-01T00:00:00Z'::timestamptz THEN
    RAISE EXCEPTION 'FALHOU 1inv: last_extracted_at avançou no partial'; END IF;

  -- Retry corrigido da MESMA operação direta: a seção segue vazia e aceita ambos.
  SET LOCAL ROLE authenticated;
  res := public.save_profile_fill_empty(u, '{"personal":{},"experiences":[
    {"title":"Good","company":"X","start_date":"2020-01-01","end_date":"2021-01-01"},
    {"title":"NoStart","company":"Y","start_date":"2022-01-01","end_date":"2023-01-01"}]}'::jsonb);
  RESET ROLE;
  IF (res->>'status') <> 'success' OR (SELECT count(*) FROM public.profile_experiences WHERE user_id=u) <> 2 THEN
    RAISE EXCEPTION 'FALHOU 1inv-retry: corrigido não gravou ambos (%)', res; END IF;
END $t$;
DO $t$
DECLARE u uuid := '11111111-1111-1111-1111-111111111111'; res jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111"}', false);
  SET LOCAL ROLE authenticated;
  -- seção JÁ não-vazia → preserve-mode; não duplica nem re-adiciona.
  res := public.save_profile_fill_empty(u, '{"personal":{},"experiences":[
    {"title":"Other","company":"Z","start_date":"2019-01-01","end_date":"2020-01-01"}]}'::jsonb);
  RESET ROLE;
  IF (res->>'status') <> 'success' THEN RAISE EXCEPTION 'FALHOU 1inv-idem: status=%', res; END IF;
  IF NOT (res->'preserved' @> '["experiences"]'::jsonb) THEN
    RAISE EXCEPTION 'FALHOU 1inv-idem: seção existente devia ser "preserved" (%)', res; END IF;
  IF (SELECT count(*) FROM public.profile_experiences WHERE user_id=u) <> 2 THEN
    RAISE EXCEPTION 'FALHOU 1inv-idem: duplicou/alterou (%)', (SELECT count(*) FROM public.profile_experiences WHERE user_id=u); END IF;
  RAISE NOTICE 'T-INV OK: significativo inválido desfaz seção; retry corrigido grava ambos; preserve sem dup';
END $t$;

-- ════════════════════════════════════════════════════════════════════════════
-- ITEM 6 — FIDELIDADE: order_index vem da ORDEM do array (WITH ORDINALITY),
-- inclusive nas bullets. Sem order_index no schema → a posição é a fonte.
-- ════════════════════════════════════════════════════════════════════════════
DO $t$
DECLARE u uuid := '33333333-3333-3333-3333-333333333333'; eid uuid;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333"}', false);
  DELETE FROM public.profile_experiences WHERE user_id=u;
  DELETE FROM public.profile_skills WHERE user_id=u;
  SET LOCAL ROLE authenticated;
  PERFORM public.save_profile_fill_empty(u, '{"personal":{},
    "skills":[{"name":"Zeta"},{"name":"Alpha"},{"name":"Mid"}],
    "experiences":[{"title":"E1","company":"C","start_date":"2020-01-01","end_date":"2021-01-01",
      "bullets":[{"text":"b0"},{"text":"b1"},{"text":"b2"}]}]}'::jsonb);
  RESET ROLE;
  IF (SELECT string_agg(name, ',' ORDER BY order_index) FROM public.profile_skills WHERE user_id=u)
       <> 'Zeta,Alpha,Mid' THEN
    RAISE EXCEPTION 'FALHOU 6ord: skills fora de ordem (%)',
      (SELECT string_agg(name||'#'||order_index, ',' ORDER BY order_index) FROM public.profile_skills WHERE user_id=u); END IF;
  SELECT id INTO eid FROM public.profile_experiences WHERE user_id=u;
  IF (SELECT string_agg(text, ',' ORDER BY order_index) FROM public.profile_bullets WHERE experience_id=eid)
       <> 'b0,b1,b2' THEN
    RAISE EXCEPTION 'FALHOU 6ord: bullets fora de ordem (%)',
      (SELECT string_agg(text||'#'||order_index, ',' ORDER BY order_index) FROM public.profile_bullets WHERE experience_id=eid); END IF;
  RAISE NOTICE 'T-ORD OK: order_index segue a ordem do array (skills + bullets) via ordinality';
END $t$;

-- ════════════════════════════════════════════════════════════════════════════
-- ITEM 6 — PROJETOS preservam o is_current extraído (NÃO têm o CHECK das
-- experiências): end_date NULL + is_current=false NÃO é forçado a true.
-- ════════════════════════════════════════════════════════════════════════════
DO $t$
DECLARE u uuid := '33333333-3333-3333-3333-333333333333';
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333"}', false);
  DELETE FROM public.profile_projects WHERE user_id=u;
  SET LOCAL ROLE authenticated;
  PERFORM public.save_profile_fill_empty(u, '{"personal":{},"projects":[
    {"name":"Ongoing","is_current":true},
    {"name":"NoEndNotCurrent","is_current":false},
    {"name":"Finished","end_date":"2022-01-01","is_current":false}]}'::jsonb);
  RESET ROLE;
  IF (SELECT is_current FROM public.profile_projects WHERE user_id=u AND name='NoEndNotCurrent') <> false THEN
    RAISE EXCEPTION 'FALHOU 6proj: is_current forçado a true (projeto não tem o CHECK das exps)'; END IF;
  IF (SELECT is_current FROM public.profile_projects WHERE user_id=u AND name='Ongoing') <> true THEN
    RAISE EXCEPTION 'FALHOU 6proj: is_current=true extraído não preservado'; END IF;
  IF (SELECT end_date FROM public.profile_projects WHERE user_id=u AND name='NoEndNotCurrent') IS NOT NULL THEN
    RAISE EXCEPTION 'FALHOU 6proj: end_date deveria continuar NULL'; END IF;
  RAISE NOTICE 'T-PROJ OK: projetos preservam is_current extraído (sem forçar por end_date)';
END $t$;

-- ════════════════════════════════════════════════════════════════════════════
-- ITEM 3 — apply_and_promote_imported_source (importação INICIAL): all-or-nothing
-- REAL, payload VINCULADO à candidata (attempt_id), schema fail-closed, e
-- separação inicial×substituição. NUNCA promove sem success; qualquer não-sucesso
-- desfaz TUDO (personal + seções + last_extracted_at + promoção).
-- ════════════════════════════════════════════════════════════════════════════
-- Reset: perfil COMPLETO + saved_resumes de um usuário (apply inicial exige vazio).
CREATE OR REPLACE FUNCTION public._t_reset(p uuid) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  DELETE FROM public.profile_bullets WHERE experience_id IN (SELECT id FROM public.profile_experiences WHERE user_id=p);
  DELETE FROM public.profile_experiences WHERE user_id=p;
  DELETE FROM public.profile_education WHERE user_id=p;
  DELETE FROM public.profile_skills WHERE user_id=p;
  DELETE FROM public.profile_languages WHERE user_id=p;
  DELETE FROM public.profile_certifications WHERE user_id=p;
  DELETE FROM public.profile_projects WHERE user_id=p;
  DELETE FROM public.profile_interests WHERE user_id=p;
  DELETE FROM public.profile_awards WHERE user_id=p;
  DELETE FROM public.profile_coursework WHERE user_id=p;
  DELETE FROM public.profile_personal WHERE user_id=p;
  DELETE FROM public.saved_resumes WHERE user_id=p;
  -- Blocker 9: a promoção agora SEMPRE reescreve o cache legacy (mesmo sem
  -- raw_text). Um reset de estado precisa zerar o cache também, senão o
  -- imported_resume de um bloco anterior "vaza" para o próximo teste.
  UPDATE public.user_profiles SET gamification_data = NULL WHERE id = p;
END $fn$;

-- Path determinístico usado pelo app e agora imposto pelo begin server-side.
CREATE OR REPLACE FUNCTION public._t_import_path(p_uid uuid, p_token uuid)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  SELECT p_uid::text || '/imports/' || p_token::text || '.pdf'
$fn$;

-- Semeia uma candidata imported+ready com payload VINCULADO + attempt (como
-- postgres — authenticated não pode setar colunas de integridade).
CREATE OR REPLACE FUNCTION public._t_seed_candidate(p uuid, p_title text, p_payload jsonb, p_attempt uuid, p_status text DEFAULT 'ready')
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v uuid;
BEGIN
  INSERT INTO public.saved_resumes(user_id,title,file_path,source,extraction_status,extraction_payload,extraction_attempt_id)
    VALUES (p, p_title, 'p/'||p_title, 'imported', p_status, p_payload, p_attempt) RETURNING id INTO v;
  RETURN v;
END $fn$;

-- 3.1 — A success em perfil VAZIO → promove; dados aplicados.
DO $t$
DECLARE u uuid := '44444444-4444-4444-4444-444444444444';
  att uuid := '000000a0-0000-0000-0000-0000000000a0'; ca uuid; res jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444"}', false);
  PERFORM public._t_reset(u);
  ca := public._t_seed_candidate(u,'A','{"personal":{"first_name":"Ann"},"skills":[{"name":"Excel"}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(ca, att);
  RESET ROLE;
  IF (res#>>'{apply,status}') <> 'success' THEN RAISE EXCEPTION 'FALHOU 3.1: apply não success (%)', res; END IF;
  IF (res->>'promoted') <> 'true' THEN RAISE EXCEPTION 'FALHOU 3.1: não promoveu (%)', res; END IF;
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=ca) <> true THEN RAISE EXCEPTION 'FALHOU 3.1: A não é atual'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='Excel') THEN RAISE EXCEPTION 'FALHOU 3.1: não preencheu'; END IF;
  RAISE NOTICE 'T-AP 3.1 OK: A success em perfil vazio → promove + preenche';
END $t$;

-- 3.2 — B success com valores DIFERENTES (perfil resetado).
DO $t$
DECLARE u uuid := '44444444-4444-4444-4444-444444444444';
  att uuid := '000000b0-0000-0000-0000-0000000000b0'; cb uuid; res jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444"}', false);
  PERFORM public._t_reset(u);
  cb := public._t_seed_candidate(u,'B','{"personal":{"first_name":"Bob"},"skills":[{"name":"Python"}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(cb, att);
  RESET ROLE;
  IF (res->>'promoted') <> 'true' THEN RAISE EXCEPTION 'FALHOU 3.2: B não promovida (%)', res; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='Python') THEN RAISE EXCEPTION 'FALHOU 3.2: valores de B não aplicados'; END IF;
  RAISE NOTICE 'T-AP 3.2 OK: B success com valores diferentes';
END $t$;

-- 3.3 — B PARCIAL por ERRO INESPERADO (trigger) numa seção → ZERO dados de B
-- (rollback global), não promove e transiciona ready→failed para reextração.
CREATE OR REPLACE FUNCTION public._t_ap33_boom() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN IF NEW.title = 'BOOM33' THEN RAISE EXCEPTION 'boom33' USING ERRCODE='P0001'; END IF; RETURN NEW; END $fn$;
CREATE TRIGGER _t_ap33_boom_trg BEFORE INSERT ON public.profile_experiences
  FOR EACH ROW EXECUTE FUNCTION public._t_ap33_boom();
DO $t$
DECLARE u uuid := '44444444-4444-4444-4444-444444444444';
  att uuid := '000000c0-0000-0000-0000-0000000000c0'; cb uuid; res jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444"}', false);
  PERFORM public._t_reset(u);
  -- skill válida + experiência que dispara ERRO REAL (trigger) → seção falha → partial.
  cb := public._t_seed_candidate(u,'B','{"personal":{"first_name":"Bea"},"skills":[{"name":"GoodSkill"}],
    "experiences":[{"title":"BOOM33","company":"X","start_date":"2020-01-01","end_date":"2021-01-01"}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(cb, att);
  RESET ROLE;
  IF (res->>'promoted') <> 'false' THEN RAISE EXCEPTION 'FALHOU 3.3: promoveu apesar de partial (%)', res; END IF;
  IF EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='GoodSkill') THEN
    RAISE EXCEPTION 'FALHOU 3.3: seção VÁLIDA de B sobreviveu (não foi all-or-nothing)'; END IF;
  IF EXISTS (SELECT 1 FROM public.profile_personal WHERE user_id=u AND first_name='Bea') THEN
    RAISE EXCEPTION 'FALHOU 3.3: personal de B sobreviveu (não foi all-or-nothing)'; END IF;
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=cb) <> false THEN RAISE EXCEPTION 'FALHOU 3.3: B virou atual'; END IF;
  -- retry elegível e honesto: failed faz o Edge reextrair no MESMO attempt.
  IF (SELECT extraction_status FROM public.saved_resumes WHERE id=cb) <> 'failed'
     OR (SELECT extraction_error_code FROM public.saved_resumes WHERE id=cb) <> 'apply_failed' THEN
    RAISE EXCEPTION 'FALHOU 3.3: candidata não foi para failed/apply_failed'; END IF;
  RAISE NOTICE 'T-AP 3.3 OK: erro real → rollback global + candidate failed para reextração';
END $t$;
DROP TRIGGER _t_ap33_boom_trg ON public.profile_experiences;

-- 3.4 — candidato B + payload/attempt de A REJEITADO (vínculo).
DO $t$
DECLARE u uuid := '44444444-4444-4444-4444-444444444444';
  att_b uuid := '000000b1-0000-0000-0000-0000000000b1';
  att_wrong uuid := '000000a1-0000-0000-0000-0000000000a1'; cb uuid;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444"}', false);
  PERFORM public._t_reset(u);
  cb := public._t_seed_candidate(u,'B','{"skills":[{"name":"X"}]}'::jsonb, att_b);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.apply_and_promote_imported_source(cb, att_wrong);  -- attempt errado
    RESET ROLE; RAISE EXCEPTION 'FALHOU 3.4: attempt errado aceito';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
  RESET ROLE;
  IF EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u) THEN RAISE EXCEPTION 'FALHOU 3.4: aplicou apesar do mismatch'; END IF;
  RAISE NOTICE 'T-AP 3.4 OK: payload/attempt de A não aplica em B (vínculo)';
END $t$;

-- 3.5 — payload VAZIO/MALFORMADO/null rejeitado (fail-closed, antes de escrever).
DO $t$
DECLARE u uuid := '44444444-4444-4444-4444-444444444444';
  att uuid := '000000d0-0000-0000-0000-0000000000d0'; c1 uuid; c2 uuid; c3 uuid; ok int;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444"}', false);
  PERFORM public._t_reset(u);
  c1 := public._t_seed_candidate(u,'Empty','{}'::jsonb, att);
  c2 := public._t_seed_candidate(u,'Malformed','{"skills":"nope"}'::jsonb, att);
  c3 := public._t_seed_candidate(u,'Null', NULL, att);
  SET LOCAL ROLE authenticated;
  ok := 0;
  BEGIN PERFORM public.apply_and_promote_imported_source(c1, att); EXCEPTION WHEN SQLSTATE '22023' THEN ok := ok+1; END;
  BEGIN PERFORM public.apply_and_promote_imported_source(c2, att); EXCEPTION WHEN SQLSTATE '22023' THEN ok := ok+1; END;
  BEGIN PERFORM public.apply_and_promote_imported_source(c3, att); EXCEPTION WHEN SQLSTATE '22023' THEN ok := ok+1; END;
  RESET ROLE;
  IF ok <> 3 THEN RAISE EXCEPTION 'FALHOU 3.5: nem todos {}/malformado/null rejeitados (ok=%)', ok; END IF;
  IF EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u) THEN RAISE EXCEPTION 'FALHOU 3.5: escreveu apesar de payload inválido'; END IF;
  RAISE NOTICE 'T-AP 3.5 OK: {}/malformado/null rejeitados fail-closed, zero escrita';
END $t$;

-- 3.6 — perfil NÃO vazio → apply inicial REJEITADO (substituição usa review).
DO $t$
DECLARE u uuid := '44444444-4444-4444-4444-444444444444';
  att uuid := '000000e0-0000-0000-0000-0000000000e0'; c uuid;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444"}', false);
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, first_name) VALUES (u, 'JáTem');  -- perfil com dado
  c := public._t_seed_candidate(u,'Later','{"skills":[{"name":"Y"}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.apply_and_promote_imported_source(c, att);
    RESET ROLE; RAISE EXCEPTION 'FALHOU 3.6: aplicou em perfil não-vazio (fill-empty automático)';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
  RESET ROLE;
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=c) <> false THEN RAISE EXCEPTION 'FALHOU 3.6: promoveu candidata posterior'; END IF;
  RAISE NOTICE 'T-AP 3.6 OK: perfil não-vazio → apply inicial rejeitado (não promove por preserved)';
END $t$;

-- 3.7 — falha DEPOIS de personal e ANTES da promoção → rollback GLOBAL.
CREATE OR REPLACE FUNCTION public._t_promote_boom() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  IF NEW.is_current_source AND NOT COALESCE(OLD.is_current_source,false) THEN
    RAISE EXCEPTION 'boom_promote' USING ERRCODE='P0001';
  END IF; RETURN NEW;
END $fn$;
CREATE TRIGGER _t_promote_boom_trg BEFORE UPDATE ON public.saved_resumes
  FOR EACH ROW EXECUTE FUNCTION public._t_promote_boom();
DO $t$
DECLARE u uuid := '44444444-4444-4444-4444-444444444444';
  att uuid := '000000f0-0000-0000-0000-0000000000f0'; c uuid; res jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444"}', false);
  PERFORM public._t_reset(u);
  c := public._t_seed_candidate(u,'Boom','{"personal":{"first_name":"Zoe"},"skills":[{"name":"K"}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(c, att);  -- apply OK, promoção explode → savepoint desfaz
  RESET ROLE;
  IF (res->>'promoted') <> 'false' THEN RAISE EXCEPTION 'FALHOU 3.7: promoted true apesar do boom (%)', res; END IF;
  -- (blocker 6) a resposta reflete o ESTADO PERSISTIDO: nada persistiu → apply=failure, NUNCA success.
  IF (res#>>'{apply,status}') <> 'failure' THEN RAISE EXCEPTION 'FALHOU 3.7: apply.status=% (rollback deveria ser failure)', res; END IF;
  IF EXISTS (SELECT 1 FROM public.profile_personal WHERE user_id=u AND first_name='Zoe') THEN RAISE EXCEPTION 'FALHOU 3.7: personal sobreviveu ao rollback'; END IF;
  IF EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='K') THEN RAISE EXCEPTION 'FALHOU 3.7: skill sobreviveu ao rollback'; END IF;
  IF (SELECT last_extracted_at FROM public.profile_personal WHERE user_id=u) IS NOT NULL THEN RAISE EXCEPTION 'FALHOU 3.7: last_extracted avançou'; END IF;
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=c) <> false THEN RAISE EXCEPTION 'FALHOU 3.7: virou atual'; END IF;
  RAISE NOTICE 'T-AP 3.7 OK: falha na promoção → rollback global (personal+seções+timestamp desfeitos)';
END $t$;
DROP TRIGGER _t_promote_boom_trg ON public.saved_resumes;

-- ════════════════════════════════════════════════════════════════════════════
-- BLOCKER 2/3 — LIFECYCLE real: begin(pending,attempt) → extracting → complete
-- (ready, service_role, payload+raw_text+attempt) → apply+promote(current+cache).
-- authenticated NÃO marca ready; complete só service_role; cache legacy ATIVO só
-- é tocado na PROMOÇÃO; 2ª importação = nova candidata/attempt (não reusa payload).
-- ════════════════════════════════════════════════════════════════════════════
DO $t$
DECLARE u uuid := '44444444-4444-4444-4444-444444444444';
  lc jsonb; cand uuid; att uuid; cand2 uuid; att2 uuid; res jsonb; denied boolean;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444"}', false);
  PERFORM public._t_reset(u);
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;

  SET LOCAL ROLE authenticated;
  -- 1. begin → candidata pending + attempt.
  lc := public.begin_import_source('Meu CV', public._t_import_path(u,
    '00000701-0000-0000-0000-000000000701'), '  CV.pdf  ',
    '00000701-0000-0000-0000-000000000701');
  cand := (lc->>'candidate_id')::uuid; att := (lc->>'attempt_id')::uuid;
  IF cand IS NULL OR att IS NULL THEN RAISE EXCEPTION 'FALHOU lifecycle: begin sem ids'; END IF;
  IF (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) <> 'pending'
     OR (SELECT source FROM public.saved_resumes WHERE id=cand) <> 'imported' THEN
    RAISE EXCEPTION 'FALHOU lifecycle: candidata não pending/imported'; END IF;
  -- Crash/replay: o título pode ter sido recalculado, mas token+path canônicos
  -- recuperam a MESMA row/attempt e devolvem o path persistido.
  lc := public.begin_import_source('Meu CV 2 (título recalculado)', public._t_import_path(u,
    '00000701-0000-0000-0000-000000000701'), 'CV.pdf',
    '00000701-0000-0000-0000-000000000701');
  IF (lc->>'candidate_id')::uuid <> cand OR (lc->>'attempt_id')::uuid <> att
     OR (lc->>'file_path') <> public._t_import_path(u, '00000701-0000-0000-0000-000000000701')
     OR (lc->>'replayed') <> 'true'
     OR (SELECT original_filename FROM public.saved_resumes WHERE id=cand) <> 'CV.pdf'
     OR (SELECT count(*) FROM public.saved_resumes WHERE user_id=u
          AND client_import_id='00000701-0000-0000-0000-000000000701') <> 1 THEN
    RAISE EXCEPTION 'FALHOU R7-B3: replay de begin não foi idempotente (%)', lc; END IF;
  denied := false;
  BEGIN PERFORM public.begin_import_source('Outro', 'u/OUTRO.pdf', 'CV.pdf',
    '00000701-0000-0000-0000-000000000701');
  EXCEPTION WHEN SQLSTATE '22023' THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'FALHOU R7-B3: token reutilizado em outro path'; END IF;
  -- 2ª importação → NOVA candidata + NOVO attempt (não reusa).
  lc := public.begin_import_source('Meu CV 2', public._t_import_path(u,
    '00000702-0000-0000-0000-000000000702'), 'CV2.pdf',
    '00000702-0000-0000-0000-000000000702');
  cand2 := (lc->>'candidate_id')::uuid; att2 := (lc->>'attempt_id')::uuid;
  IF cand2 = cand OR att2 = att THEN RAISE EXCEPTION 'FALHOU lifecycle: 2ª importação reusou candidata/attempt'; END IF;

  -- 2. (Round 5 blocker E) set_import_extraction_status é OWNER-ONLY agora (sem grant):
  -- authenticated não pode chamá-lo (nem p/ 'extracting') — não há caller e o caminho
  -- rebaixava a fonte atual sem limpar o cache. A candidata segue 'pending', e o
  -- complete (service_role) aceita 'pending' normalmente.
  denied := false;
  BEGIN PERFORM public.set_import_extraction_status(cand, 'extracting');
  EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'FALHOU lifecycle: set_import_extraction_status callable por authenticated (deveria ser owner-only)'; END IF;

  -- 3. authenticated NÃO pode chamar complete (sem grant).
  denied := false;
  BEGIN PERFORM public.complete_import_extraction(cand, att, '{"skills":[{"name":"X"}]}'::jsonb, 'raw');
  EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'FALHOU lifecycle: authenticated chamou complete'; END IF;
  RESET ROLE;

  -- 4. complete como service_role: attempt errado rejeitado; correto → ready.
  SET LOCAL ROLE service_role;
  denied := false;
  BEGIN PERFORM public.complete_import_extraction(cand, gen_random_uuid(), '{"skills":[{"name":"X"}]}'::jsonb, 'raw');
  EXCEPTION WHEN SQLSTATE '22023' THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'FALHOU lifecycle: complete aceitou attempt errado'; END IF;
  -- payload malformado rejeitado (fail-closed) antes de ready.
  denied := false;
  BEGIN PERFORM public.complete_import_extraction(cand, att, '{"personal":{"first_name":{}}}'::jsonb, 'raw');
  EXCEPTION WHEN SQLSTATE '22023' THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'FALHOU lifecycle: complete aceitou payload malformado'; END IF;
  PERFORM public.complete_import_extraction(cand, att, '{"personal":{"first_name":"Ann"},"skills":[{"name":"Excel"}]}'::jsonb, 'RAWTEXT',
    '{"fullName":"Ann"}'::jsonb, '{"parser_version":"v1","parsed_at":"2026-01-01T00:00:00Z"}'::jsonb);
  RESET ROLE;
  IF (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) <> 'ready' THEN RAISE EXCEPTION 'FALHOU lifecycle: não ready'; END IF;
  IF (SELECT extraction_raw_text FROM public.saved_resumes WHERE id=cand) <> 'RAWTEXT' THEN RAISE EXCEPTION 'FALHOU lifecycle: raw_text não na candidata'; END IF;

  -- blocker 3: cache legacy ATIVO ainda NÃO tocado (raw_text vive só na candidata).
  IF (SELECT gamification_data->'imported_resume' FROM public.user_profiles WHERE id=u) IS NOT NULL THEN
    RAISE EXCEPTION 'FALHOU blocker3: cache ativo tocado ANTES da promoção'; END IF;

  -- 5. apply+promote (perfil vazio) → current + cache legacy ativado na mesma tx.
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444"}', false);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(cand, att);
  RESET ROLE;
  IF (res->>'promoted') <> 'true' THEN RAISE EXCEPTION 'FALHOU lifecycle: não promoveu (%)', res; END IF;
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=cand) <> true THEN RAISE EXCEPTION 'FALHOU lifecycle: não é current'; END IF;
  IF (SELECT gamification_data->'imported_resume'->>'raw_text' FROM public.user_profiles WHERE id=u) <> 'RAWTEXT' THEN
    RAISE EXCEPTION 'FALHOU blocker3: cache ativo NÃO recebeu raw_text na promoção'; END IF;
  RAISE NOTICE 'T-LIFECYCLE OK: begin idempotente por token/path server-side + filename normalizado; complete→apply+promote→current+cache; 2ª import nova';
END $t$;

-- R7-B3 — compensador attempt-bound: só pending/extracting/failed, owner exato,
-- non-current e sem recibo. Retorna path canônico e deleta a row atomicamente.
DO $t$
DECLARE
  u uuid := '44444444-4444-4444-4444-444444444445';
  other uuid := '44444444-4444-4444-4444-444444444446';
  lc jsonb; cand uuid; att uuid; cand_pending uuid; att_pending uuid;
  got_path text; denied boolean;
BEGIN
  INSERT INTO auth.users(id) VALUES (u),(other) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u),(other) ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444445"}', false);
  SET LOCAL ROLE authenticated;
  lc := public.begin_import_source('Abortável',public._t_import_path(u,
    '00000703-0000-0000-0000-000000000703'),'original.pdf',
    '00000703-0000-0000-0000-000000000703');
  cand := (lc->>'candidate_id')::uuid; att := (lc->>'attempt_id')::uuid;

  denied := false;
  BEGIN PERFORM public.abort_import_source(cand, gen_random_uuid());
  EXCEPTION WHEN SQLSTATE '22023' THEN denied := true; END;
  IF NOT denied OR NOT EXISTS (SELECT 1 FROM public.saved_resumes WHERE id=cand) THEN
    RAISE EXCEPTION 'FALHOU R7-ABORT: wrong attempt removeu/foi aceito'; END IF;

  -- Pending exata é o compensador principal (begin confirmou, handle falhou).
  lc := public.begin_import_source('Pending',public._t_import_path(u,
    '00000704-0000-0000-0000-000000000704'),'pending.pdf',
    '00000704-0000-0000-0000-000000000704');
  cand_pending := (lc->>'candidate_id')::uuid; att_pending := (lc->>'attempt_id')::uuid;
  got_path := public.abort_import_source(cand_pending, att_pending);
  IF got_path <> public._t_import_path(u, '00000704-0000-0000-0000-000000000704')
     OR EXISTS (SELECT 1 FROM public.saved_resumes WHERE id=cand_pending) THEN
    RAISE EXCEPTION 'FALHOU R7-ABORT: pending exata não retornou path/deletou'; END IF;
  RESET ROLE;

  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444446"}', false);
  SET LOCAL ROLE authenticated; denied := false;
  BEGIN PERFORM public.abort_import_source(cand, att);
  EXCEPTION WHEN SQLSTATE 'P0002' THEN denied := true; END;
  RESET ROLE;
  IF NOT denied OR NOT EXISTS (SELECT 1 FROM public.saved_resumes WHERE id=cand) THEN
    RAISE EXCEPTION 'FALHOU R7-ABORT: outro owner removeu/obteve match'; END IF;

  -- ready mesmo não-current é conclusão da extração: não aborta.
  UPDATE public.saved_resumes SET extraction_status='ready', is_current_source=false WHERE id=cand;
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444445"}', false);
  SET LOCAL ROLE authenticated; denied := false;
  BEGIN PERFORM public.abort_import_source(cand, att);
  EXCEPTION WHEN SQLSTATE '22023' THEN denied := true; END;
  RESET ROLE;
  IF NOT denied OR NOT EXISTS (SELECT 1 FROM public.saved_resumes WHERE id=cand) THEN
    RAISE EXCEPTION 'FALHOU R7-ABORT: ready não-current foi abortada'; END IF;

  -- current também é sempre intocável pelo compensador.
  UPDATE public.saved_resumes SET is_current_source=true WHERE id=cand;
  SET LOCAL ROLE authenticated; denied := false;
  BEGIN PERFORM public.abort_import_source(cand, att);
  EXCEPTION WHEN SQLSTATE '22023' THEN denied := true; END;
  RESET ROLE;
  IF NOT denied OR NOT EXISTS (SELECT 1 FROM public.saved_resumes WHERE id=cand) THEN
    RAISE EXCEPTION 'FALHOU R7-ABORT: current foi abortada'; END IF;

  UPDATE public.saved_resumes SET extraction_status='failed', is_current_source=false WHERE id=cand;
  INSERT INTO public.import_apply_receipts(candidate_id,attempt_id,operation,result)
    VALUES (cand,att,'apply_initial','{"promoted":true}'::jsonb);
  SET LOCAL ROLE authenticated; denied := false;
  BEGIN PERFORM public.abort_import_source(cand, att);
  EXCEPTION WHEN SQLSTATE '22023' THEN denied := true; END;
  RESET ROLE;
  IF NOT denied OR NOT EXISTS (SELECT 1 FROM public.saved_resumes WHERE id=cand) THEN
    RAISE EXCEPTION 'FALHOU R7-ABORT: candidata com receipt foi abortada'; END IF;

  DELETE FROM public.import_apply_receipts WHERE candidate_id=cand AND attempt_id=att;
  SET LOCAL ROLE authenticated;
  got_path := public.abort_import_source(cand, att);
  RESET ROLE;
  IF got_path <> public._t_import_path(u, '00000703-0000-0000-0000-000000000703')
     OR EXISTS (SELECT 1 FROM public.saved_resumes WHERE id=cand) THEN
    RAISE EXCEPTION 'FALHOU R7-ABORT: failed exata não retornou path/deletou (%)', got_path; END IF;
  RAISE NOTICE 'R7-ABORT OK: owner+attempt+estado+receipt validados; path canônico retornado';
END $t$;

-- ════════════════════════════════════════════════════════════════════════════
-- COMPAT HEAD^ — a migration NÃO pode quebrar o build anterior. Ele envia
-- `user_id` explicitamente em saveResume; o build novo omite e usa auth.uid().
-- Os DOIS formatos precisam funcionar para o próprio uid, sem reabrir forge:
-- user_id alheio continua negado pela RLS e colunas de integridade continuam
-- fora do grant por-coluna (cobertas em T4-GRANT).
-- ════════════════════════════════════════════════════════════════════════════
DO $t$
DECLARE u uuid := '11111111-1111-1111-1111-111111111111'; other uuid := '22222222-2222-2222-2222-222222222222';
        k text; got_uid uuid; denied boolean := false; bad_path_denied boolean; bad_path text;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111"}', false);
  DELETE FROM public.saved_resumes WHERE user_id IN (u, other);
  SET LOCAL ROLE authenticated;
  -- HEAD^: manual / adapted / imported COM user_id explícito do próprio user.
  FOREACH k IN ARRAY ARRAY['manual','adapted','imported'] LOOP
    INSERT INTO public.saved_resumes(user_id, title, file_path, source)
      VALUES (u, 'old-'||k, u::text||'/old/'||k||'.pdf', k)
      RETURNING user_id INTO got_uid;
    IF got_uid <> u THEN RAISE EXCEPTION 'FALHOU B1: HEAD^ user_id do insert % = %', k, got_uid; END IF;
  END LOOP;
  -- Build novo: sem user_id, default auth.uid().
  INSERT INTO public.saved_resumes(title, file_path, source)
    VALUES ('new-manual', u::text||'/new/manual.pdf', 'manual') RETURNING user_id INTO got_uid;
  IF got_uid <> u THEN RAISE EXCEPTION 'FALHOU B1: default auth.uid() = %', got_uid; END IF;
  -- Mesmo com grant de INSERT(user_id), RLS barra explicitamente outro dono.
  BEGIN
    INSERT INTO public.saved_resumes(user_id, title, file_path, source)
      VALUES (other, 'x', other::text||'/x.pdf', 'manual');
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
            WHEN OTHERS THEN IF SQLSTATE = '42501' THEN denied := true; ELSE RAISE; END IF;
  END;
  -- Mesmo dono: outro namespace, '.', '..', segmento vazio e '\' são negados.
  FOREACH bad_path IN ARRAY ARRAY[
    other::text||'/x.pdf', u::text||'/../x.pdf', u::text||'/./x.pdf',
    u::text||'//x.pdf', u::text||'/dir\\x.pdf']
  LOOP
    bad_path_denied := false;
    BEGIN
      INSERT INTO public.saved_resumes(user_id, title, file_path, source)
        VALUES (u, 'wrong-path', bad_path, 'manual');
    EXCEPTION WHEN insufficient_privilege THEN bad_path_denied := true;
              WHEN OTHERS THEN IF SQLSTATE = '42501' THEN bad_path_denied := true; ELSE RAISE; END IF;
    END;
    IF NOT bad_path_denied THEN RAISE EXCEPTION 'FALHOU B1: path inseguro aceito: %', bad_path; END IF;
  END LOOP;
  RESET ROLE;
  IF NOT denied THEN RAISE EXCEPTION 'FALHOU B1: cross-user insert (user_id de outro) não foi negado'; END IF;
  IF NOT has_column_privilege('authenticated','public.saved_resumes','user_id','INSERT')
     OR has_column_privilege('authenticated','public.saved_resumes','is_current_source','INSERT')
     OR has_column_privilege('authenticated','public.saved_resumes','is_latest_legacy_source','INSERT')
     OR has_column_privilege('authenticated','public.saved_resumes','extraction_status','INSERT')
     OR has_column_privilege('authenticated','public.saved_resumes','extraction_payload','INSERT') THEN
    RAISE EXCEPTION 'FALHOU B1: grant compatível reabriu/fechou colunas erradas'; END IF;
  RAISE NOTICE 'T-B1 OK: HEAD^ com user_id + build novo sem user_id; owner/path protegidos por RLS';
END $t$;

-- COMPAT CACHE — no onboarding HEAD^, Edge/cache e upload/row são fire-and-forget
-- concorrentes. Sem candidate_id não existe vínculo demonstrável: cache fica
-- UNBOUND, inclusive se chegar antes da row ou se o upload falhar. Marker é só
-- estado da biblioteca; id explícito divergente continua fail-closed.
DO $t$
DECLARE
  u uuid := '0c000000-0000-0000-0000-000000000001';
  failed_u uuid := '0c000000-0000-0000-0000-000000000002';
  a uuid; b uuid; c uuid; canonical uuid; manual_id uuid; affected int;
  legacy_blocked boolean := false;
BEGIN
  INSERT INTO auth.users(id) VALUES (u),(failed_u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id, gamification_data) VALUES
    (u, '{"keep":"initial","imported_resume":{"raw_text":"OLD-TO-CLEAR"}}'::jsonb),
    (failed_u, '{"keep":"upload-failed"}'::jsonb)
    ON CONFLICT (id) DO NOTHING;

  -- Padrão estrutural EXATO do HEAD^ `_clearLegacyImportedResume`: leitura do
  -- OLD e write do mesmo JSON menos a chave. Deve honrar o clear autenticado.
  PERFORM set_config('request.jwt.claims',
    '{"sub":"0c000000-0000-0000-0000-000000000001","role":"authenticated"}', false);
  SET LOCAL ROLE authenticated;
  UPDATE public.user_profiles SET gamification_data='{"keep":"initial"}'::jsonb WHERE id=u;
  GET DIAGNOSTICS affected = ROW_COUNT;
  RESET ROLE;
  IF affected <> 1
     OR (SELECT gamification_data ? 'imported_resume' FROM public.user_profiles WHERE id=u)
     OR (SELECT gamification_data->>'keep' FROM public.user_profiles WHERE id=u) <> 'initial' THEN
    RAISE EXCEPTION 'FALHOU CACHE exact-clear: remoção HEAD^ não foi honrada'; END IF;

  -- Repro real do onboarding: a Edge termina ANTES de saveResume criar a row.
  -- O cache deve sobreviver, mas sem source_resume_id inventado.
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', false);
  SET LOCAL ROLE service_role;
  UPDATE public.user_profiles
     SET gamification_data='{"imported_resume":{"raw_text":"RAW-BEFORE-ROW","parsed":{"name":"A"},"parsed_at":"2026-07-16T10:00:00Z","parser_source":"extract-profile-v1.0"},"keep":"edge"}'::jsonb
   WHERE id=u;
  -- Variante em que o upload falha para sempre: cache também não desaparece.
  UPDATE public.user_profiles
     SET gamification_data='{"imported_resume":{"raw_text":"RAW-UPLOAD-FAILED","parsed":{"name":"F"},"parsed_at":"2026-07-16T10:00:01Z","parser_source":"extract-profile-v1.0"},"keep":"upload-failed"}'::jsonb
   WHERE id=failed_u;
  RESET ROLE;
  IF (SELECT gamification_data#>>'{imported_resume,raw_text}' FROM public.user_profiles WHERE id=u) <> 'RAW-BEFORE-ROW'
     OR (SELECT gamification_data->'imported_resume' ? 'source_resume_id' FROM public.user_profiles WHERE id=u)
     OR (SELECT gamification_data#>>'{imported_resume,raw_text}' FROM public.user_profiles WHERE id=failed_u) <> 'RAW-UPLOAD-FAILED'
     OR EXISTS (SELECT 1 FROM public.saved_resumes WHERE user_id=failed_u) THEN
    RAISE EXCEPTION 'FALHOU CACHE-before-row/upload-failed: cache sumiu, foi vinculado ou row apareceu'; END IF;

  PERFORM set_config('request.jwt.claims',
    '{"sub":"0c000000-0000-0000-0000-000000000001","role":"authenticated"}', false);
  SET LOCAL ROLE authenticated;
  INSERT INTO public.saved_resumes(user_id,title,file_path,source)
    VALUES (u,'legacy-A',u::text||'/A.pdf','imported') RETURNING id INTO a;
  RESET ROLE;
  IF NOT (SELECT is_latest_legacy_source FROM public.saved_resumes WHERE id=a)
     OR (SELECT gamification_data#>>'{imported_resume,raw_text}' FROM public.user_profiles WHERE id=u) <> 'RAW-BEFORE-ROW'
     OR (SELECT gamification_data->'imported_resume' ? 'source_resume_id' FROM public.user_profiles WHERE id=u) THEN
    RAISE EXCEPTION 'FALHOU CACHE-before-row: INSERT posterior apagou/rotulou cache'; END IF;

  -- Omit/clear sem identidade não prova qual fonte apagar: preserva UNBOUND.
  SET LOCAL ROLE authenticated;
  UPDATE public.user_profiles SET gamification_data='{"partial":"kept"}'::jsonb WHERE id=u;
  RESET ROLE;
  IF (SELECT gamification_data#>>'{imported_resume,raw_text}'
        FROM public.user_profiles WHERE id=u) <> 'RAW-BEFORE-ROW'
     OR (SELECT gamification_data->>'partial' FROM public.user_profiles WHERE id=u) <> 'kept' THEN
    RAISE EXCEPTION 'FALHOU CACHE parcial: apagou UNBOUND/outra chave'; END IF;

  -- B salva a row, mas extração/texto falha e NÃO atualiza cache. O marker pode
  -- mover para B; RAW de A permanece honesto UNBOUND, nunca rotulado como B.
  SET LOCAL ROLE authenticated;
  INSERT INTO public.saved_resumes(user_id,title,file_path,source)
    VALUES (u,'legacy-B',u::text||'/B.pdf','imported') RETURNING id INTO b;
  RESET ROLE;
  IF (SELECT count(*) FROM public.saved_resumes WHERE user_id=u AND is_latest_legacy_source) <> 1
     OR NOT (SELECT is_latest_legacy_source FROM public.saved_resumes WHERE id=b)
     OR (SELECT gamification_data#>>'{imported_resume,raw_text}' FROM public.user_profiles WHERE id=u) <> 'RAW-BEFORE-ROW'
     OR (SELECT gamification_data->'imported_resume' ? 'source_resume_id' FROM public.user_profiles WHERE id=u) THEN
    RAISE EXCEPTION 'FALHOU CACHE B-sem-cache: cache A perdido ou falsamente associado a B'; END IF;

  -- Quando B realmente grava cache pelo protocolo HEAD^ ele continua UNBOUND.
  IF auth.uid() IS DISTINCT FROM u THEN
    RAISE EXCEPTION 'FALHOU CACHE B setup: auth.uid=% esperado %',auth.uid(),u; END IF;
  SET LOCAL ROLE authenticated;
  UPDATE public.user_profiles
     SET gamification_data='{"imported_resume":{"raw_text":"RAW-B","imported_at":"2026-07-16T10:01:00Z","source_resume_id":"   "}}'::jsonb
   WHERE id=u;
  GET DIAGNOSTICS affected = ROW_COUNT;
  RESET ROLE;
  IF affected <> 1
     OR (SELECT gamification_data#>>'{imported_resume,raw_text}' FROM public.user_profiles WHERE id=u) <> 'RAW-B'
     OR (SELECT gamification_data->'imported_resume' ? 'source_resume_id' FROM public.user_profiles WHERE id=u) THEN
    RAISE EXCEPTION 'FALHOU CACHE B: write sem candidate_id não persistiu unbound (rows=%, gd=%)',
      affected,(SELECT gamification_data FROM public.user_profiles WHERE id=u); END IF;

  -- Resposta atrasada com id EXPLÍCITO A diverge da marker B: preserva RAW-B
  -- unbound e demais chaves do novo write, sem rebind.
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', false);
  SET LOCAL ROLE service_role;
  UPDATE public.user_profiles SET gamification_data=jsonb_build_object(
    'imported_resume',jsonb_build_object('raw_text','LATE-A','source_resume_id',a::text),
    'edge_other','preserved') WHERE id=u;
  RESET ROLE;
  IF (SELECT gamification_data#>>'{imported_resume,raw_text}' FROM public.user_profiles WHERE id=u) <> 'RAW-B'
     OR (SELECT gamification_data->'imported_resume' ? 'source_resume_id' FROM public.user_profiles WHERE id=u)
     OR (SELECT gamification_data->>'edge_other' FROM public.user_profiles WHERE id=u) <> 'preserved' THEN
    RAISE EXCEPTION 'FALHOU CACHE stale: Edge A substituiu B (%)',
      (SELECT gamification_data FROM public.user_profiles WHERE id=u); END IF;

  -- Promoção canônica aposenta marker. Meta não pode colidir com as chaves
  -- canônicas; os três Edges antigos equivalem a este UPDATE service_role.
  INSERT INTO public.saved_resumes(
    user_id,title,file_path,source,extraction_status,is_current_source,
    extraction_completed_at,extraction_raw_text,extraction_legacy_parsed,extraction_meta)
  VALUES (u,'canonical',u::text||'/imports/canonical.pdf','imported','ready',false,
    '2026-07-16T11:00:00Z','CANON-RAW','{"fullName":"Canonical"}'::jsonb,
    '{"parser_version":"v1","parsed_at":"2026-07-16T11:00:00Z","raw_text":"META-EVIL","parsed":{"evil":true},"source_resume_id":"META-EVIL","imported_at":"META-EVIL","safe_meta":"kept"}'::jsonb)
  RETURNING id INTO canonical;
  PERFORM public._promote_imported_and_activate(u, canonical, 'IGNORED');
  IF EXISTS (SELECT 1 FROM public.saved_resumes WHERE user_id=u AND is_latest_legacy_source) THEN
    RAISE EXCEPTION 'FALHOU CACHE promote: marker legacy sobreviveu'; END IF;
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', false);
  SET LOCAL ROLE service_role;
  UPDATE public.user_profiles SET gamification_data='{"imported_resume":{"raw_text":"EDGE-EVIL","parsed":{"evil":true}},"edge":"legacy-edges"}'::jsonb WHERE id=u;
  RESET ROLE;
  IF (SELECT gamification_data#>>'{imported_resume,raw_text}' FROM public.user_profiles WHERE id=u) <> 'CANON-RAW'
     OR (SELECT gamification_data#>>'{imported_resume,parsed,fullName}' FROM public.user_profiles WHERE id=u) <> 'Canonical'
     OR (SELECT gamification_data#>>'{imported_resume,source_resume_id}' FROM public.user_profiles WHERE id=u) <> canonical::text
     OR (SELECT gamification_data#>>'{imported_resume,safe_meta}' FROM public.user_profiles WHERE id=u) <> 'kept'
     OR (SELECT gamification_data->>'edge' FROM public.user_profiles WHERE id=u) <> 'legacy-edges' THEN
    RAISE EXCEPTION 'FALHOU CACHE canonical: Edge/meta sobrescreveu fonte/outra chave'; END IF;

  -- Com current canônica, INSERT legacy não pode retornar falso sucesso como
  -- histórico. Falha estável antes de marker/cache; Edge tardia também não vence.
  PERFORM set_config('request.jwt.claims',
    '{"sub":"0c000000-0000-0000-0000-000000000001","role":"authenticated"}', false);
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO public.saved_resumes(user_id,title,file_path,source)
      VALUES (u,'head-after-current',u::text||'/after.pdf','imported');
  EXCEPTION WHEN SQLSTATE '55000' THEN
    legacy_blocked := SQLERRM = 'legacy_import_blocked_by_canonical_source';
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', false);
  SET LOCAL ROLE service_role;
  UPDATE public.user_profiles SET gamification_data='{"imported_resume":{"raw_text":"HEAD-OLD"},"head_other":1}'::jsonb WHERE id=u;
  RESET ROLE;
  IF NOT legacy_blocked
     OR EXISTS (SELECT 1 FROM public.saved_resumes WHERE user_id=u AND title='head-after-current')
     OR (SELECT gamification_data#>>'{imported_resume,raw_text}' FROM public.user_profiles WHERE id=u) <> 'CANON-RAW'
     OR (SELECT gamification_data->>'head_other' FROM public.user_profiles WHERE id=u) <> '1' THEN
    RAISE EXCEPTION 'FALHOU CACHE canonical: HEAD^ teve falso sucesso/marker/cache alterado'; END IF;

  -- Delete current limpa o cache CANÔNICO exato. Um write posterior sem id pode
  -- existir apenas como UNBOUND; não é revinculado às rows legacy.
  PERFORM set_config('request.jwt.claims',
    '{"sub":"0c000000-0000-0000-0000-000000000001","role":"authenticated"}', false);
  SET LOCAL ROLE authenticated;
  DELETE FROM public.saved_resumes WHERE id=canonical;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', false);
  SET LOCAL ROLE service_role;
  UPDATE public.user_profiles SET gamification_data=jsonb_build_object(
    'imported_resume',jsonb_build_object('raw_text','LATE-UNBOUND'),
    'late_other',true) WHERE id=u;
  RESET ROLE;
  IF (SELECT gamification_data#>>'{imported_resume,raw_text}' FROM public.user_profiles WHERE id=u) <> 'LATE-UNBOUND'
     OR (SELECT gamification_data->'imported_resume' ? 'source_resume_id' FROM public.user_profiles WHERE id=u)
     OR (SELECT gamification_data->>'late_other' FROM public.user_profiles WHERE id=u) <> 'true' THEN
    RAISE EXCEPTION 'FALHOU CACHE pós-delete: unbound perdido/vinculado ou outra chave perdida'; END IF;

  INSERT INTO public.saved_resumes(user_id,title,file_path,source)
    VALUES (u,'manual-multi',u::text||'/manual.pdf','manual') RETURNING id INTO manual_id;
  PERFORM set_config('request.jwt.claims',
    '{"sub":"0c000000-0000-0000-0000-000000000001","role":"authenticated"}', false);
  SET LOCAL ROLE authenticated;
  DELETE FROM public.saved_resumes WHERE id IN (a,b,manual_id);
  GET DIAGNOSTICS affected = ROW_COUNT;
  RESET ROLE;
  IF affected <> 3 OR EXISTS (SELECT 1 FROM public.saved_resumes WHERE id IN (a,b,manual_id))
     OR (SELECT gamification_data#>>'{imported_resume,raw_text}' FROM public.user_profiles WHERE id=u) <> 'LATE-UNBOUND' THEN
    RAISE EXCEPTION 'FALHOU CACHE multi-delete: affected=%', affected; END IF;

  -- Controle positivo do cleanup: cache com id EXATO é removido com sua row.
  SET LOCAL ROLE authenticated;
  INSERT INTO public.saved_resumes(user_id,title,file_path,source)
    VALUES (u,'legacy-exact',u::text||'/exact.pdf','imported') RETURNING id INTO c;
  UPDATE public.user_profiles SET gamification_data=jsonb_build_object(
    'imported_resume',jsonb_build_object('raw_text','EXACT','source_resume_id',c::text)) WHERE id=u;
  DELETE FROM public.saved_resumes WHERE id=c;
  RESET ROLE;
  IF (SELECT gamification_data ? 'imported_resume' FROM public.user_profiles WHERE id=u) THEN
    RAISE EXCEPTION 'FALHOU CACHE exact-delete: cache ligado sobreviveu à row exata'; END IF;
  RAISE NOTICE 'T-CACHE-BRIDGE OK: cache-before-row/upload-failed preservado UNBOUND; B sem cache não rotula A; canonical/ids exatos fail-closed';
END $t$;

-- Account delete: a FK dispara DELETE saved_resumes aninhado. Cleanup pula o
-- pai em deleção e nunca tenta advisory depois de tuple.
CREATE OR REPLACE FUNCTION public._t_assert_account_delete_fenced()
RETURNS trigger LANGUAGE plpgsql AS $t$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_locks
     WHERE pid=pg_backend_pid() AND locktype='advisory' AND granted
  ) THEN
    RAISE EXCEPTION 'delete_user chegou em auth.users sem advisory';
  END IF;
  RETURN NULL;
END $t$;
CREATE TRIGGER zzzz_test_account_delete_fenced
  BEFORE DELETE ON auth.users FOR EACH STATEMENT
  EXECUTE FUNCTION public._t_assert_account_delete_fenced();
DO $t$
DECLARE u uuid := '0d000000-0000-0000-0000-000000000001'; c uuid;
BEGIN
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"0d000000-0000-0000-0000-000000000001"}', false);
  INSERT INTO public.saved_resumes(
    user_id,title,file_path,source,extraction_status,is_current_source,
    extraction_completed_at,extraction_raw_text,extraction_legacy_parsed,extraction_meta)
  VALUES (u,'cascade-current',u::text||'/imports/c.pdf','imported','ready',true,
    now(),'R','{"name":"Cascade"}'::jsonb,
    '{"parser_version":"v1","parsed_at":"2026-07-16T00:00:00Z"}'::jsonb)
  RETURNING id INTO c;
  UPDATE public.user_profiles SET gamification_data='{"imported_resume":{"raw_text":"bad"}}'::jsonb WHERE id=u;
  SET LOCAL ROLE authenticated;
  PERFORM public.delete_user();
  RESET ROLE;
  IF EXISTS (SELECT 1 FROM auth.users WHERE id=u)
     OR EXISTS (SELECT 1 FROM public.user_profiles WHERE id=u)
     OR EXISTS (SELECT 1 FROM public.saved_resumes WHERE user_id=u) THEN
    RAISE EXCEPTION 'FALHOU CACHE cascade: pai/filhas sobreviveram'; END IF;
  RAISE NOTICE 'T-CACHE-CASCADE OK: delete_user advisory→auth→profile→saved; cascata sem lock tardio';
END $t$;
DROP TRIGGER zzzz_test_account_delete_fenced ON auth.users;
DROP FUNCTION public._t_assert_account_delete_fenced();

-- ════════════════════════════════════════════════════════════════════════════
-- ITEM 4 — colunas de INTEGRIDADE de saved_resumes protegidas: authenticated NÃO
-- pode alterá-las direto (só via RPC validada); colunas de biblioteca OK.
-- ════════════════════════════════════════════════════════════════════════════
DO $t$
DECLARE u uuid := '11111111-1111-1111-1111-111111111111'; c uuid; denied int := 0;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111"}', false);
  DELETE FROM public.saved_resumes WHERE user_id=u;
  INSERT INTO public.saved_resumes(user_id,title,file_path,source,extraction_status)
    VALUES (u,'lib','p','imported','ready') RETURNING id INTO c;  -- postgres seed
  SET LOCAL ROLE authenticated;

  -- UPDATE direto das colunas de integridade → NEGADO (42501).
  BEGIN UPDATE public.saved_resumes SET is_current_source=true WHERE id=c;
  EXCEPTION WHEN insufficient_privilege THEN denied := denied+1; END;
  BEGIN UPDATE public.saved_resumes SET extraction_status='failed' WHERE id=c;
  EXCEPTION WHEN insufficient_privilege THEN denied := denied+1; END;
  BEGIN UPDATE public.saved_resumes SET extraction_payload='{}'::jsonb WHERE id=c;
  EXCEPTION WHEN insufficient_privilege THEN denied := denied+1; END;
  BEGIN UPDATE public.saved_resumes SET client_import_id=gen_random_uuid() WHERE id=c;
  EXCEPTION WHEN insufficient_privilege THEN denied := denied+1; END;
  -- INSERT tentando forjar is_current_source → NEGADO (coluna fora do grant).
  BEGIN INSERT INTO public.saved_resumes(user_id,title,file_path,source,is_current_source)
    VALUES (u,'forge','p2','imported',true);
  EXCEPTION WHEN insufficient_privilege THEN denied := denied+1; END;
  BEGIN INSERT INTO public.saved_resumes(title,file_path,source,client_import_id)
    VALUES ('forge-token','p3','imported',gen_random_uuid());
  EXCEPTION WHEN insufficient_privilege THEN denied := denied+1; END;
  IF denied <> 6 THEN RAISE EXCEPTION 'FALHOU 4grant: alteração direta de integridade não bloqueada (denied=%)', denied; END IF;

  -- Coluna de BIBLIOTECA (title) → PERMITIDO.
  UPDATE public.saved_resumes SET title='Renomeado' WHERE id=c;
  IF (SELECT title FROM public.saved_resumes WHERE id=c) <> 'Renomeado' THEN
    RAISE EXCEPTION 'FALHOU 4grant: UPDATE de title (biblioteca) deveria ser permitido'; END IF;

  -- (Round 5 blocker E) set_import_extraction_status agora é OWNER-ONLY (sem caller Dart;
  -- rebaixava a fonte atual sem limpar o cache). authenticated → NEGADO (42501).
  denied := 0;
  BEGIN PERFORM public.set_import_extraction_status(c, 'extracting');
  EXCEPTION WHEN insufficient_privilege THEN denied := denied+1; END;
  IF denied <> 1 THEN RAISE EXCEPTION 'FALHOU 4grant: set_import_extraction_status deveria ser owner-only (denied=%)', denied; END IF;
  RESET ROLE;
  RAISE NOTICE 'T4-GRANT OK: integridade só via RPC; biblioteca (title) editável; set_import owner-only';
END $t$;

-- ════════════════════════════════════════════════════════════════════════════
-- ITEM 2 — WRITERS COMPOSTOS transacionais: pai + filhas numa transação; falha
-- no item N desfaz TUDO; ordinality preservada. (authenticated chama a RPC.)
-- ════════════════════════════════════════════════════════════════════════════
DO $t$
DECLARE u uuid := '33333333-3333-3333-3333-333333333333'; eid uuid; edid uuid; pid uuid; got text;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333"}', false);
  PERFORM public._t_reset(u);
  SET LOCAL ROLE authenticated;

  -- experiência + bullets (ordinality)
  eid := public.save_experience_with_bullets(u, '{"title":"Eng","company":"C","start_date":"2020-01-01","end_date":"2021-01-01",
    "bullets":[{"text":"b0"},{"text":"b1"},{"text":"b2"}]}'::jsonb);
  IF (SELECT string_agg(text, ',' ORDER BY order_index) FROM public.profile_bullets WHERE experience_id=eid) <> 'b0,b1,b2' THEN
    RAISE EXCEPTION 'FALHOU 2comp: bullets fora de ordem'; END IF;

  -- ATOMICIDADE: update da MESMA experiência com um VALOR inválido (end_date <
  -- start_date viola o CHECK) → RAISE → TUDO desfeito: título não muda e as bullets
  -- antigas permanecem. (Round 5: bullet vazio deixou de ser poison — agora é PULADO
  -- como ruído; a atomicidade é testada por uma violação de constraint real.)
  BEGIN
    PERFORM public.save_experience_with_bullets(u, jsonb_build_object('id', eid, 'title','ENG-EDIT','company','C',
      'start_date','2020-01-01','end_date','2019-01-01','bullets', '[{"text":"new0"}]'::jsonb));
    RAISE EXCEPTION 'FALHOU 2comp: valor inválido não abortou';
  EXCEPTION WHEN SQLSTATE '23514' THEN got := 'ok'; END;
  IF (SELECT title FROM public.profile_experiences WHERE id=eid) <> 'Eng' THEN
    RAISE EXCEPTION 'FALHOU 2comp: título mudou apesar do rollback (não foi atômico)'; END IF;
  IF (SELECT string_agg(text, ',' ORDER BY order_index) FROM public.profile_bullets WHERE experience_id=eid) <> 'b0,b1,b2' THEN
    RAISE EXCEPTION 'FALHOU 2comp: bullets mudaram apesar do rollback'; END IF;

  -- formação + majors/minors/activities
  edid := public.save_education_with_children(u, '{"institution":"USP","degree":"CC","start_date":"2019-01-01",
    "majors":["M1","M2"],"minors":["Mi1"],"activities":["A1","A2","A3"]}'::jsonb);
  IF (SELECT count(*) FROM public.profile_education_majors WHERE education_id=edid) <> 2
     OR (SELECT count(*) FROM public.profile_education_minors WHERE education_id=edid) <> 1
     OR (SELECT string_agg(text, ',' ORDER BY order_index) FROM public.profile_education_activities WHERE education_id=edid) <> 'A1,A2,A3' THEN
    RAISE EXCEPTION 'FALHOU 2comp: filhas de educação erradas'; END IF;

  -- projeto + project_bullets
  pid := public.save_project_with_bullets(u, '{"name":"P","bullets":[{"text":"pb0"},{"text":"pb1"}]}'::jsonb);
  IF (SELECT string_agg(text, ',' ORDER BY order_index) FROM public.profile_project_bullets WHERE project_id=pid) <> 'pb0,pb1' THEN
    RAISE EXCEPTION 'FALHOU 2comp: project_bullets erradas'; END IF;

  -- replace_profile_skills atômico (dedup + ordinality)
  PERFORM public.replace_profile_skills(u, '["Alpha","Beta","alpha"]'::jsonb);  -- 'alpha' dup
  IF (SELECT string_agg(name, ',' ORDER BY order_index) FROM public.profile_skills WHERE user_id=u) <> 'Alpha,Beta' THEN
    RAISE EXCEPTION 'FALHOU 2comp: replace_skills dedup/ordem'; END IF;
  PERFORM public.replace_profile_skills(u, '["Solo"]'::jsonb);  -- replace-all
  IF (SELECT string_agg(name, ',') FROM public.profile_skills WHERE user_id=u) <> 'Solo' THEN
    RAISE EXCEPTION 'FALHOU 2comp: replace_skills não é replace-all'; END IF;

  RESET ROLE;
  RAISE NOTICE 'T2-COMP OK: exp+bullets, edu+filhas, proj+bullets, replace_skills — transacionais + ordinality; item inválido desfaz tudo';
END $t$;

-- ════════════════════════════════════════════════════════════════════════════
-- BLOCKER 4 — FIDELIDADE: as RPCs preservam o modelo COMPLETO (kind, confidence,
-- needs_review, angle/strength/verb, institution_id/level/status/semester/ano,
-- role/context) + preservam IDs de bullets (update existentes, insere novas,
-- remove só ausentes).
-- ════════════════════════════════════════════════════════════════════════════
DO $t$
DECLARE u uuid := '33333333-3333-3333-3333-333333333333'; eid uuid; edid uuid; pid uuid;
        b0 uuid; b1 uuid; b0_after uuid;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333"}', false);
  PERFORM public._t_reset(u);
  SET LOCAL ROLE authenticated;

  -- experiência COMPLETA + bullet completa
  eid := public.save_experience_with_bullets(u, '{"title":"Eng","company":"C","start_date":"2020-01-01","end_date":"2021-01-01",
    "kind":"estagio","confidence":0.77,"needs_review":true,
    "bullets":[{"text":"liderou","angle":"leadership","strength_score":88,"verb":"Liderou"}]}'::jsonb);
  IF (SELECT kind FROM public.profile_experiences WHERE id=eid) <> 'estagio'
     OR (SELECT confidence FROM public.profile_experiences WHERE id=eid) <> 0.77
     OR (SELECT needs_review FROM public.profile_experiences WHERE id=eid) <> true THEN
    RAISE EXCEPTION 'FALHOU 4fid: campos da experiência descartados'; END IF;
  SELECT id INTO b0 FROM public.profile_bullets WHERE experience_id=eid;
  IF (SELECT angle FROM public.profile_bullets WHERE id=b0) <> 'leadership'
     OR (SELECT strength_score FROM public.profile_bullets WHERE id=b0) <> 88
     OR (SELECT verb FROM public.profile_bullets WHERE id=b0) <> 'Liderou' THEN
    RAISE EXCEPTION 'FALHOU 4fid: campos da bullet descartados'; END IF;

  -- id-preservation: update enviando b0 (com id, texto editado) + uma nova bullet;
  -- b0 mantém o id, a nova é inserida, e (implícito) ausentes seriam removidas.
  PERFORM public.save_experience_with_bullets(u, jsonb_build_object(
    'id', eid, 'title','Eng','company','C','start_date','2020-01-01','end_date','2021-01-01',
    'bullets', jsonb_build_array(
      jsonb_build_object('id', b0::text, 'text','liderou-EDIT','angle','leadership','strength_score',90),
      jsonb_build_object('text','nova bullet'))));
  SELECT id INTO b0_after FROM public.profile_bullets WHERE experience_id=eid AND text='liderou-EDIT';
  IF b0_after <> b0 THEN RAISE EXCEPTION 'FALHOU 4fid: id da bullet existente NÃO preservado'; END IF;
  IF (SELECT count(*) FROM public.profile_bullets WHERE experience_id=eid) <> 2 THEN
    RAISE EXCEPTION 'FALHOU 4fid: reconciliação errada (esperava 2 bullets)'; END IF;
  IF (SELECT strength_score FROM public.profile_bullets WHERE id=b0) <> 90 THEN
    RAISE EXCEPTION 'FALHOU 4fid: update de bullet existente não aplicou'; END IF;

  -- remoção: update sem b0 (só uma bullet nova) → b0 removida.
  PERFORM public.save_experience_with_bullets(u, jsonb_build_object(
    'id', eid, 'title','Eng','company','C','start_date','2020-01-01','end_date','2021-01-01',
    'bullets', jsonb_build_array(jsonb_build_object('text','só essa'))));
  IF EXISTS (SELECT 1 FROM public.profile_bullets WHERE id=b0) THEN
    RAISE EXCEPTION 'FALHOU 4fid: bullet ausente do payload NÃO foi removida'; END IF;
  IF (SELECT count(*) FROM public.profile_bullets WHERE experience_id=eid) <> 1 THEN
    RAISE EXCEPTION 'FALHOU 4fid: reconciliação de remoção errada'; END IF;

  -- educação COMPLETA
  edid := public.save_education_with_children(u, jsonb_build_object(
    'institution','USP','institution_id','55555555-5555-5555-5555-555555555555',
    'education_level','bacharelado','education_status','cursando','current_semester',6,'current_school_year',3,
    'degree','CC','gpa',8.5,'majors', '["M1"]'::jsonb));
  IF (SELECT institution_id FROM public.profile_education WHERE id=edid) <> '55555555-5555-5555-5555-555555555555'
     OR (SELECT education_level FROM public.profile_education WHERE id=edid) <> 'bacharelado'
     OR (SELECT education_status FROM public.profile_education WHERE id=edid) <> 'cursando'
     OR (SELECT current_semester FROM public.profile_education WHERE id=edid) <> 6
     OR (SELECT current_school_year FROM public.profile_education WHERE id=edid) <> 3 THEN
    RAISE EXCEPTION 'FALHOU 4fid: campos de educação descartados'; END IF;

  -- projeto COMPLETO
  pid := public.save_project_with_bullets(u, '{"name":"P","role":"Fundador","context":"Empresa Júnior","website":"x.com","bullets":[{"text":"pb"}]}'::jsonb);
  IF (SELECT role FROM public.profile_projects WHERE id=pid) <> 'Fundador'
     OR (SELECT context FROM public.profile_projects WHERE id=pid) <> 'Empresa Júnior' THEN
    RAISE EXCEPTION 'FALHOU 4fid: campos de projeto (role/context) descartados'; END IF;
  RESET ROLE;
  RAISE NOTICE 'T-FIDELITY OK: modelo completo preservado; bullets update/insert/remove por id';
END $t$;

-- ════════════════════════════════════════════════════════════════════════════
-- BLOCKER 6 — validação ESTRUTURAL fail-closed: escalar com tipo errado (ex.:
-- first_name como objeto/array) é REJEITADO (nunca coage p/ texto). Payload
-- válido passa. Mesma validação p/ authenticated e service_role (via _core).
-- ════════════════════════════════════════════════════════════════════════════
DO $t$
DECLARE bad jsonb; oks int := 0; total int := 0;
  bads jsonb[] := ARRAY[
    '{"personal":{"first_name":{}}}'::jsonb,               -- objeto no escalar
    '{"personal":{"first_name":[1,2]}}'::jsonb,            -- array no escalar
    '{"personal":{"email":123}}'::jsonb,                   -- number no escalar
    '{"foo":1}'::jsonb,                                    -- chave de topo desconhecida
    '{"experiences":"nope"}'::jsonb,                       -- seção não-array
    '{"experiences":[{"title":"x","confidence":"alta"}]}'::jsonb,  -- number esperado
    '{"experiences":[{"is_current":"sim"}]}'::jsonb,       -- boolean esperado
    '{"education":[{"institution":"USP","majors":[1,2]}]}'::jsonb, -- lista não-string
    '{"education":[{"institution":"USP","confidence":"alta"}]}'::jsonb, -- number esperado
    '{"experiences":[{"bullets":[{"text":{}}]}]}'::jsonb,  -- bullet.text objeto
    '{"skills":[{"name":{"a":1}}]}'::jsonb,                -- name objeto
    '{"skills":[{"name":"Excel","category":{"x":1}}]}'::jsonb]; -- category string
BEGIN
  FOREACH bad IN ARRAY bads LOOP
    total := total + 1;
    BEGIN PERFORM public._validate_profile_payload(bad);
    EXCEPTION WHEN SQLSTATE '22023' THEN oks := oks + 1; END;
  END LOOP;
  IF oks <> total THEN RAISE EXCEPTION 'FALHOU 6val: nem todos os malformados rejeitados (% de %)', oks, total; END IF;
  -- payload VÁLIDO completo NÃO deve levantar.
  PERFORM public._validate_profile_payload('{
    "personal":{"first_name":"Ana","completeness_score":80},
    "experiences":[{"title":"E","company":"C","start_date":"2020-01-01","is_current":true,"confidence":0.8,
      "bullets":[{"text":"t","angle":"impact","strength_score":90}]}],
    "education":[{"institution":"USP","current_semester":6,"gpa":8.5,"confidence":0.9,"majors":["M"]}],
    "skills":[{"name":"Excel","category":"technical"}],"awards":[{"name":"A","date":"2021-01-01"}]}'::jsonb);
  RAISE NOTICE 'T6-VALIDATE OK: % malformados rejeitados fail-closed; válido passa', total;
END $t$;

-- reorder atômico: um id não-possuído aborta e NADA muda.
DO $t$
DECLARE u uuid := '33333333-3333-3333-3333-333333333333'; a uuid; b uuid; ord_before int[];
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333"}', false);
  PERFORM public._t_reset(u);
  SET LOCAL ROLE authenticated;
  a := public.save_experience_with_bullets(u, '{"title":"A","company":"C","start_date":"2020-01-01","end_date":"2021-01-01"}'::jsonb);
  b := public.save_experience_with_bullets(u, '{"title":"B","company":"C","start_date":"2020-01-01","end_date":"2021-01-01"}'::jsonb);
  -- reorder válido: [b,a] → b.order_index=0, a=1
  PERFORM public.reorder_profile_section(u, 'profile_experiences', jsonb_build_array(b::text, a::text));
  IF (SELECT order_index FROM public.profile_experiences WHERE id=b) <> 0
     OR (SELECT order_index FROM public.profile_experiences WHERE id=a) <> 1 THEN
    RAISE EXCEPTION 'FALHOU 2reorder: ordem não aplicada'; END IF;
  -- reorder com id alheio → aborta, ordem intacta.
  BEGIN
    PERFORM public.reorder_profile_section(u, 'profile_experiences', jsonb_build_array(a::text, '00000000-0000-0000-0000-000000000009'));
    RAISE EXCEPTION 'FALHOU 2reorder: id alheio aceito';
  EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL; END;
  IF (SELECT order_index FROM public.profile_experiences WHERE id=b) <> 0 THEN
    RAISE EXCEPTION 'FALHOU 2reorder: ordem mudou apesar do abort'; END IF;
  RESET ROLE;
  RAISE NOTICE 'T2-REORDER OK: reorder atômico; id alheio aborta sem mudar nada';
END $t$;

-- reorder de bullets (filho) atômico + posse do pai validada.
DO $t$
DECLARE u uuid := '33333333-3333-3333-3333-333333333333'; eid uuid; b0 uuid; b1 uuid;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333"}', false);
  PERFORM public._t_reset(u);
  SET LOCAL ROLE authenticated;
  eid := public.save_experience_with_bullets(u, '{"title":"E","company":"C","start_date":"2020-01-01","end_date":"2021-01-01","bullets":[{"text":"x0"},{"text":"x1"}]}'::jsonb);
  SELECT id INTO b0 FROM public.profile_bullets WHERE experience_id=eid AND text='x0';
  SELECT id INTO b1 FROM public.profile_bullets WHERE experience_id=eid AND text='x1';
  PERFORM public.reorder_child_bullets('experience', eid, jsonb_build_array(b1::text, b0::text));
  IF (SELECT string_agg(text, ',' ORDER BY order_index) FROM public.profile_bullets WHERE experience_id=eid) <> 'x1,x0' THEN
    RAISE EXCEPTION 'FALHOU 2reorder-bullets: ordem não aplicada'; END IF;
  -- pai alheio → aborta.
  BEGIN
    PERFORM public.reorder_child_bullets('experience', '00000000-0000-0000-0000-000000000009', jsonb_build_array(b0::text));
    RAISE EXCEPTION 'FALHOU 2reorder-bullets: pai alheio aceito';
  EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL; END;
  RESET ROLE;
  RAISE NOTICE 'T2-REORDER-BULLETS OK: reorder de bullets atômico; pai alheio aborta';
END $t$;

-- ════════════════════════════════════════════════════════════════════════════
-- ITEM 6 — COMPARE-AND-SET real ("manual vence"). Cenário do revisor: o diff
-- observa A; o usuário edita para C; o import tenta aplicar B esperando A; C
-- permanece e o resultado informa STALE. + lote transacional + agregado.
-- ════════════════════════════════════════════════════════════════════════════
DO $t$
DECLARE u uuid := '33333333-3333-3333-3333-333333333333'; r text; cand uuid; batch jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333"}', false);
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, summary) VALUES (u, 'A');  -- diff observou 'A'
  cand := public._t_seed_candidate(u,'Cand','{"skills":[{"name":"z"}]}'::jsonb,'00000099-0000-0000-0000-000000000099');
  SET LOCAL ROLE authenticated;

  -- caso APPLIED: valor vivo ainda é 'A' → aplica 'B'.
  r := public.cas_write_profile_scalar(u, 'summary', 'A', 'B', NULL, NULL);
  IF r <> 'applied' THEN RAISE EXCEPTION 'FALHOU 6cas: esperava applied (%)', r; END IF;
  IF (SELECT summary FROM public.profile_personal WHERE user_id=u) <> 'B' THEN RAISE EXCEPTION 'FALHOU 6cas: não gravou B'; END IF;

  -- edição manual concorrente para 'C'; import tenta aplicar 'B2' esperando 'A'.
  UPDATE public.profile_personal SET summary='C' WHERE user_id=u;
  r := public.cas_write_profile_scalar(u, 'summary', 'A', 'B2', NULL, NULL);
  IF r <> 'stale' THEN RAISE EXCEPTION 'FALHOU 6cas: esperava stale (%)', r; END IF;
  IF (SELECT summary FROM public.profile_personal WHERE user_id=u) <> 'C' THEN
    RAISE EXCEPTION 'FALHOU 6cas: C (manual) foi sobrescrito — manual NÃO venceu'; END IF;

  -- lote transacional + agregado + PROMOÇÃO (blocker 5): candidata com payload que
  -- ORIGINA os conflitos (vínculo à revisão). summary applied (vive 'A' == esperado),
  -- city STALE (esperado '' mas vive 'SP'), add Docker. Depois PROMOVE atomicamente.
  UPDATE public.profile_personal SET summary='A', location_city='SP' WHERE user_id=u;
  DECLARE cand2 uuid; att2 uuid := '000000aa-0000-0000-0000-0000000000aa'; agg jsonb;
  BEGIN
    RESET ROLE;  -- postgres p/ semear colunas de integridade da candidata
    cand2 := public._t_seed_candidate(u,'Cand2',
      '{"personal":{"summary":"CV sum","location_city":"RJ"},"skills":[{"name":"Docker"}]}'::jsonb, att2);
    SET LOCAL ROLE authenticated;
    batch := jsonb_build_array(
      jsonb_build_object('kind','personal','field','summary','expected','A','value','NEW'),
      jsonb_build_object('kind','personal','field','city','expected','','value','RJ'),
      jsonb_build_object('kind','add','section','skill','source','Docker','value','Docker'));
    agg := public.apply_reviewed_conflicts_and_promote(cand2, att2, batch);
    IF NOT (agg->'applied' @> '["summary"]'::jsonb) THEN RAISE EXCEPTION 'FALHOU 6batch: summary não aplicado (%)', agg; END IF;
    IF NOT (agg->'stale' @> '["city"]'::jsonb) THEN RAISE EXCEPTION 'FALHOU 6batch: city não marcada stale (%)', agg; END IF;
    IF (agg->>'promoted') <> 'true' THEN RAISE EXCEPTION 'FALHOU 6batch: não promoveu (%)', agg; END IF;
    IF (SELECT summary FROM public.profile_personal WHERE user_id=u) <> 'NEW' THEN RAISE EXCEPTION 'FALHOU 6batch: summary não gravou'; END IF;
    IF (SELECT location_city FROM public.profile_personal WHERE user_id=u) <> 'SP' THEN RAISE EXCEPTION 'FALHOU 6batch: city stale foi sobrescrita'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='Docker') THEN RAISE EXCEPTION 'FALHOU 6batch: skill não adicionada'; END IF;
    IF (SELECT is_current_source FROM public.saved_resumes WHERE id=cand2) <> true THEN RAISE EXCEPTION 'FALHOU 6batch: candidata não virou atual'; END IF;
  END;
  RESET ROLE;
  RAISE NOTICE 'T6-CAS OK: manual vence (stale), lote transacional + agregado + promoção atômica';
END $t$;

-- R7-CAS-PHONE — telefone é composto (número+DDI). Mudar qualquer metade
-- entre diff e apply torna STALE; quando ambas casam, atualiza as duas na mesma tx.
DO $t$
DECLARE u uuid := '33333333-3333-3333-3333-333333333334'; r text;
  cand uuid; att uuid := '00000710-0000-0000-0000-000000000710'; agg jsonb;
BEGIN
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333334"}', false);
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id,first_name,phone_number,phone_country_code)
    VALUES (u,'Pessoa','1111','+55');
  SET LOCAL ROLE authenticated;
  r := public.cas_write_profile_scalar(u,'phone','1111','2222','+55','+1');
  IF r <> 'applied' OR (SELECT phone_number FROM public.profile_personal WHERE user_id=u) <> '2222'
     OR (SELECT phone_country_code FROM public.profile_personal WHERE user_id=u) <> '+1' THEN
    RAISE EXCEPTION 'FALHOU R7-CAS-PHONE: update composto não foi atômico (%)', r; END IF;
  UPDATE public.profile_personal SET phone_country_code='+44' WHERE user_id=u;
  r := public.cas_write_profile_scalar(u,'phone','2222','3333','+1','+33');
  IF r <> 'stale' OR (SELECT phone_number FROM public.profile_personal WHERE user_id=u) <> '2222'
     OR (SELECT phone_country_code FROM public.profile_personal WHERE user_id=u) <> '+44' THEN
    RAISE EXCEPTION 'FALHOU R7-CAS-PHONE: mudança manual de DDI foi sobrescrita (%)', r; END IF;
  RESET ROLE;

  cand := public._t_seed_candidate(u,'PhoneCV',
    '{"personal":{"phone_number":"9999","phone_country_code":"+55"}}'::jsonb,att);
  UPDATE public.profile_personal SET phone_country_code='+49' WHERE user_id=u;
  SET LOCAL ROLE authenticated;
  agg := public.apply_reviewed_conflicts_and_promote(cand,att,jsonb_build_array(
    jsonb_build_object('kind','personal','field','phone','expected','2222',
      'expected_country_code','+44','value','9999','country_code','+55')));
  RESET ROLE;
  IF (agg->>'promoted') <> 'true' OR NOT (agg->'stale' @> '["phone"]'::jsonb)
     OR (SELECT phone_number FROM public.profile_personal WHERE user_id=u) <> '2222'
     OR (SELECT phone_country_code FROM public.profile_personal WHERE user_id=u) <> '+49' THEN
    RAISE EXCEPTION 'FALHOU R7-CAS-PHONE reviewed: DDI concorrente não venceu (%)', agg; END IF;
  RAISE NOTICE 'R7-CAS-PHONE OK: expected phone+DDI; qualquer metade manual → stale; update conjunto atômico';
END $t$;

-- ════════════════════════════════════════════════════════════════════════════
-- BLOCKER 5 — apply_reviewed_conflicts_and_promote: attempt mismatch; lote
-- desvinculado da revisão recusado; rejeitar tudo (vazio) promove; falha desfaz
-- lote+promoção (failed≠[] nunca com promoted=true).
-- ════════════════════════════════════════════════════════════════════════════
DO $t$
DECLARE u uuid := '33333333-3333-3333-3333-333333333333'; cand uuid;
  att uuid := '000000bb-0000-0000-0000-0000000000bb'; agg jsonb; got boolean;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333"}', false);
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, first_name) VALUES (u, 'JáTem');  -- perfil com dado (substituição)
  cand := public._t_seed_candidate(u,'C','{"personal":{"summary":"S"},"skills":[{"name":"Rust"}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;

  -- attempt errado → rejeitado, nada muda.
  got := false;
  BEGIN PERFORM public.apply_reviewed_conflicts_and_promote(cand, gen_random_uuid(), '[]'::jsonb);
  EXCEPTION WHEN SQLSTATE '22023' THEN got := true; END;
  IF NOT got THEN RAISE EXCEPTION 'FALHOU 5: attempt errado aceito'; END IF;

  -- lote NÃO-vazio totalmente desvinculado (skill 'Ghost' não está no payload) →
  -- recusado: failed≠[], promoted=false, nada persistido (rollback do lote).
  agg := public.apply_reviewed_conflicts_and_promote(cand, att,
    jsonb_build_array(jsonb_build_object('kind','add','section','skill','value','Ghost')));
  IF (agg->>'promoted') <> 'false' OR jsonb_array_length(agg->'failed') = 0 THEN
    RAISE EXCEPTION 'FALHOU 5: lote desvinculado não recusado (%)', agg; END IF;
  IF EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='Ghost') THEN RAISE EXCEPTION 'FALHOU 5: Ghost persistiu'; END IF;
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=cand) <> false THEN RAISE EXCEPTION 'FALHOU 5: promoveu com lote desvinculado'; END IF;

  -- REJEITAR TUDO (choices vazio) é válido: perfil igual, candidata PROMOVE.
  agg := public.apply_reviewed_conflicts_and_promote(cand, att, '[]'::jsonb);
  IF (agg->>'promoted') <> 'true' THEN RAISE EXCEPTION 'FALHOU 5: reject-all não promoveu (%)', agg; END IF;
  IF (SELECT first_name FROM public.profile_personal WHERE user_id=u) <> 'JáTem' THEN RAISE EXCEPTION 'FALHOU 5: reject-all mudou o perfil'; END IF;
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=cand) <> true THEN RAISE EXCEPTION 'FALHOU 5: reject-all não virou atual'; END IF;
  RESET ROLE;
  RAISE NOTICE 'T-REVIEW OK: attempt/vínculo validados; reject-all promove; sem promoção com lote desvinculado';
END $t$;

-- falha durante a promoção → rollback do LOTE + sem promoção; failed≠[] sem promoted.
CREATE OR REPLACE FUNCTION public._t_rev_boom() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN IF NEW.is_current_source AND NOT COALESCE(OLD.is_current_source,false) THEN
  RAISE EXCEPTION 'boom_rev' USING ERRCODE='P0001'; END IF; RETURN NEW; END $fn$;
CREATE TRIGGER _t_rev_boom_trg BEFORE UPDATE ON public.saved_resumes
  FOR EACH ROW EXECUTE FUNCTION public._t_rev_boom();
DO $t$
DECLARE u uuid := '33333333-3333-3333-3333-333333333333'; cand uuid;
  att uuid := '000000cc-0000-0000-0000-0000000000cc'; agg jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333"}', false);
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, summary) VALUES (u, 'Old');
  cand := public._t_seed_candidate(u,'C','{"personal":{"summary":"CV"},"skills":[{"name":"Go"}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  agg := public.apply_reviewed_conflicts_and_promote(cand, att,
    jsonb_build_array(jsonb_build_object('kind','add','section','skill','value','Go')));
  RESET ROLE;
  IF (agg->>'promoted') <> 'false' THEN RAISE EXCEPTION 'FALHOU 5boom: promoted apesar do boom (%)', agg; END IF;
  IF jsonb_array_length(agg->'failed') = 0 THEN RAISE EXCEPTION 'FALHOU 5boom: failed vazio (%)', agg; END IF;
  IF EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='Go') THEN RAISE EXCEPTION 'FALHOU 5boom: skill sobreviveu ao rollback do lote'; END IF;
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=cand) <> false THEN RAISE EXCEPTION 'FALHOU 5boom: virou atual'; END IF;
  RAISE NOTICE 'T-REVIEW-BOOM OK: falha na promoção → rollback do lote; failed≠[] nunca com promoted=true';
END $t$;
DROP TRIGGER _t_rev_boom_trg ON public.saved_resumes;

-- ════════════════════════════════════════════════════════════════════════════
-- BLOCKER 12 — apply_reviewed_conflicts_and_promote cobre TODOS os tipos de
-- conflito numa ÚNICA transação: pessoais compostos (name/city), listas
-- (skill/award/project), cert, idioma (add + nível), experiência (conflito de
-- cargo + adição inteira c/ bullets) e formação (conflito de curso + adição
-- inteira). CAS "manual vence" nos campos; adições inteiras usam dados CANÔNICOS
-- do payload; tudo promove atomicamente.
-- ════════════════════════════════════════════════════════════════════════════
DO $t$
DECLARE
  u uuid := '55555555-5555-5555-5555-555555555555';
  att uuid := '000000dd-0000-0000-0000-0000000000dd'; cand uuid; agg jsonb;
  e1 uuid; d1 uuid; newexp uuid;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"55555555-5555-5555-5555-555555555555"}', false);
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM public._t_reset(u);
  -- Perfil COM dados (substituição): nome, cidade, 1 experiência, 1 formação, 1 idioma.
  INSERT INTO public.profile_personal(user_id, first_name, last_name, location_city, location_state, summary)
    VALUES (u, 'João', 'Silva', 'Recife', 'PE', 'resumo antigo');
  INSERT INTO public.profile_experiences(user_id, company, title, start_date, end_date)
    VALUES (u, 'Ambev', 'Estagiário', '2020-01-01', '2020-12-01') RETURNING id INTO e1;
  INSERT INTO public.profile_education(user_id, institution, degree) VALUES (u, 'USP', 'Bacharelado') RETURNING id INTO d1;
  INSERT INTO public.profile_languages(user_id, name, proficiency) VALUES (u, 'Inglês', 'basic');

  RESET ROLE;  -- postgres semeia a candidata (colunas de integridade)
  cand := public._t_seed_candidate(u, 'CandFull', jsonb_build_object(
    'personal', jsonb_build_object('first_name','João','last_name','Souza','location_city','São Paulo','location_state','SP','summary','novo resumo'),
    'skills', jsonb_build_array(jsonb_build_object('name','Kubernetes')),
    'awards', jsonb_build_array(jsonb_build_object('name','Prêmio X')),
    'projects', jsonb_build_array(jsonb_build_object('name','Projeto Y')),
    'certifications', jsonb_build_array(jsonb_build_object('name','AWS','issuer','Amazon')),
    'languages', jsonb_build_array(jsonb_build_object('name','Inglês','proficiency','advanced'), jsonb_build_object('name','Espanhol','proficiency','fluent')),
    'experiences', jsonb_build_array(
      jsonb_build_object('company','Ambev','title','Analista','start_date','2021-01-01','end_date','2021-12-01','bullets',jsonb_build_array(jsonb_build_object('text','Fez X'))),
      jsonb_build_object('company','Nova Corp','title','Dev','start_date','2022-01-01','end_date','2022-06-01','bullets',jsonb_build_array(jsonb_build_object('text','Codou')))),
    'education', jsonb_build_array(
      jsonb_build_object('institution','USP','degree','Mestrado'),
      jsonb_build_object('institution','UFPE','degree','Doutorado'))
  ), att);
  PERFORM set_config('request.jwt.claims', '{"sub":"55555555-5555-5555-5555-555555555555"}', false);
  SET LOCAL ROLE authenticated;

  agg := public.apply_reviewed_conflicts_and_promote(cand, att, jsonb_build_array(
    jsonb_build_object('kind','personal','field','name','expected','João Silva','value','João Souza'),
    jsonb_build_object('kind','personal','field','city','expected','Recife, PE','value','São Paulo|SP'),
    jsonb_build_object('kind','add','section','skill','source','Kubernetes','value','Kubernetes'),
    jsonb_build_object('kind','add','section','award','source','Prêmio X','value','Prêmio X'),
    jsonb_build_object('kind','add','section','project','source','Projeto Y','value','Projeto Y'),
    jsonb_build_object('kind','add_cert','source','AWS','name','AWS','issuer','Amazon'),
    jsonb_build_object('kind','lang_level','name','Inglês','expected','basic','proficiency','advanced'),
    jsonb_build_object('kind','add_lang','source','Espanhol','name','Espanhol','proficiency','fluent'),
    jsonb_build_object('kind','item_field','section','experience','ref_id',e1::text,'field','title','expected','Estagiário','value','Analista'),
    jsonb_build_object('kind','add_experience','company','Nova Corp','title','Dev'),
    jsonb_build_object('kind','item_field','section','education','ref_id',d1::text,'field','degree','expected','Bacharelado','value','Mestrado'),
    jsonb_build_object('kind','add_education','institution','UFPE','degree','Doutorado')));
  RESET ROLE;

  IF (agg->>'promoted') <> 'true' OR jsonb_array_length(agg->'failed') <> 0 THEN
    RAISE EXCEPTION 'FALHOU 12: não promoveu / failed≠[] (%)', agg; END IF;
  -- pessoais compostos
  IF (SELECT first_name||' '||last_name FROM public.profile_personal WHERE user_id=u) <> 'João Souza' THEN
    RAISE EXCEPTION 'FALHOU 12: nome não aplicado'; END IF;
  IF (SELECT location_city FROM public.profile_personal WHERE user_id=u) <> 'São Paulo'
     OR (SELECT location_state FROM public.profile_personal WHERE user_id=u) <> 'SP' THEN
    RAISE EXCEPTION 'FALHOU 12: cidade/UF não aplicada'; END IF;
  -- listas
  IF NOT EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='Kubernetes') THEN RAISE EXCEPTION 'FALHOU 12: skill'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_awards WHERE user_id=u AND name='Prêmio X') THEN RAISE EXCEPTION 'FALHOU 12: award'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_projects WHERE user_id=u AND name='Projeto Y') THEN RAISE EXCEPTION 'FALHOU 12: project'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_certifications WHERE user_id=u AND name='AWS' AND issuer='Amazon') THEN RAISE EXCEPTION 'FALHOU 12: cert'; END IF;
  -- idioma: nível de Inglês atualizado + Espanhol adicionado
  IF (SELECT proficiency FROM public.profile_languages WHERE user_id=u AND name='Inglês') <> 'advanced' THEN RAISE EXCEPTION 'FALHOU 12: nível idioma'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_languages WHERE user_id=u AND name='Espanhol' AND proficiency='fluent') THEN RAISE EXCEPTION 'FALHOU 12: add idioma'; END IF;
  -- experiência: conflito de cargo (E1 → Analista) + adição inteira (Nova Corp c/ bullet)
  IF (SELECT title FROM public.profile_experiences WHERE id=e1) <> 'Analista' THEN RAISE EXCEPTION 'FALHOU 12: cargo E1 não atualizado'; END IF;
  SELECT id INTO newexp FROM public.profile_experiences WHERE user_id=u AND company='Nova Corp' AND title='Dev';
  IF newexp IS NULL THEN RAISE EXCEPTION 'FALHOU 12: experiência nova não inserida'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_bullets WHERE experience_id=newexp AND text='Codou') THEN RAISE EXCEPTION 'FALHOU 12: bullet da experiência nova ausente'; END IF;
  -- formação: conflito de curso (D1 → Mestrado) + adição inteira (UFPE/Doutorado)
  IF (SELECT degree FROM public.profile_education WHERE id=d1) <> 'Mestrado' THEN RAISE EXCEPTION 'FALHOU 12: curso D1 não atualizado'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_education WHERE user_id=u AND institution='UFPE' AND degree='Doutorado') THEN RAISE EXCEPTION 'FALHOU 12: formação nova ausente'; END IF;
  -- promoção
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=cand) <> true THEN RAISE EXCEPTION 'FALHOU 12: candidata não virou atual'; END IF;
  RAISE NOTICE 'T12-ALLTYPES OK: name/city/skill/award/project/cert/idioma(add+nível)/exp(cargo+add)/edu(curso+add) numa transação + promoção';
END $t$;

-- item_field CAS "manual vence": se o cargo VIVO mudou desde o diff → stale (não sobrescreve).
DO $t$
DECLARE u uuid := '55555555-5555-5555-5555-555555555555'; att uuid := '000000ee-0000-0000-0000-0000000000ee';
  cand uuid; e1 uuid; agg jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"55555555-5555-5555-5555-555555555555"}', false);
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, first_name) VALUES (u, 'X');  -- perfil com dado
  INSERT INTO public.profile_experiences(user_id, company, title, start_date, end_date)
    VALUES (u, 'Ambev', 'CargoManual', '2020-01-01', '2020-12-01') RETURNING id INTO e1;
  RESET ROLE;
  cand := public._t_seed_candidate(u, 'C', jsonb_build_object(
    'personal', jsonb_build_object('first_name','X'),
    'experiences', jsonb_build_array(jsonb_build_object('company','Ambev','title','CargoCV','start_date','2021-01-01','end_date','2021-12-01'))), att);
  PERFORM set_config('request.jwt.claims', '{"sub":"55555555-5555-5555-5555-555555555555"}', false);
  SET LOCAL ROLE authenticated;
  -- o diff observou 'Estagiário', mas o vivo é 'CargoManual' → CAS stale, cargo intacto.
  agg := public.apply_reviewed_conflicts_and_promote(cand, att, jsonb_build_array(
    jsonb_build_object('kind','item_field','section','experience','ref_id',e1::text,'field','title','expected','Estagiário','value','CargoCV')));
  RESET ROLE;
  IF (agg->>'promoted') <> 'true' THEN RAISE EXCEPTION 'FALHOU 12stale: não promoveu (%)', agg; END IF;
  IF NOT (agg->'stale' @> to_jsonb(ARRAY['experience.title:'||e1::text])) THEN RAISE EXCEPTION 'FALHOU 12stale: não marcou stale (%)', agg; END IF;
  IF (SELECT title FROM public.profile_experiences WHERE id=e1) <> 'CargoManual' THEN RAISE EXCEPTION 'FALHOU 12stale: manual sobrescrito'; END IF;
  RAISE NOTICE 'T12-STALE OK: item_field CAS — cargo manual venceu (stale), promoção segue';
END $t$;

-- Review adversarial (poison pill): um item ACEITO cujo dado canônico é inaplicável
-- (adição de formação SEM instituição) NÃO pode abortar o lote — é rejeitado e as
-- outras escolhas aceitas ainda aplicam + a fonte ainda promove.
DO $t$
DECLARE u uuid := '55555555-5555-5555-5555-555555555555'; att uuid := '000000ff-0000-0000-0000-0000000000ff';
  cand uuid; agg jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"55555555-5555-5555-5555-555555555555"}', false);
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, first_name) VALUES (u, 'X');  -- perfil com dado
  RESET ROLE;
  cand := public._t_seed_candidate(u, 'C', jsonb_build_object(
    'skills', jsonb_build_array(jsonb_build_object('name','Kubernetes')),
    'education', jsonb_build_array(jsonb_build_object('institution','','degree','Curso X'))), att);
  PERFORM set_config('request.jwt.claims', '{"sub":"55555555-5555-5555-5555-555555555555"}', false);
  SET LOCAL ROLE authenticated;
  agg := public.apply_reviewed_conflicts_and_promote(cand, att, jsonb_build_array(
    jsonb_build_object('kind','add','section','skill','source','Kubernetes','value','Kubernetes'),
    jsonb_build_object('kind','add_education','institution','','degree','Curso X')));
  RESET ROLE;
  -- promoveu apesar do item inaplicável; skill aplicada; formação sem instituição NÃO gravada.
  IF (agg->>'promoted') <> 'true' OR jsonb_array_length(agg->'failed') <> 0 THEN
    RAISE EXCEPTION 'FALHOU 12poison: lote abortado por item inaplicável (%)', agg; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='Kubernetes') THEN
    RAISE EXCEPTION 'FALHOU 12poison: skill boa perdida junto com o item ruim'; END IF;
  IF EXISTS (SELECT 1 FROM public.profile_education WHERE user_id=u) THEN
    RAISE EXCEPTION 'FALHOU 12poison: formação sem instituição foi gravada'; END IF;
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=cand) <> true THEN
    RAISE EXCEPTION 'FALHOU 12poison: não promoveu'; END IF;
  RAISE NOTICE 'T12-POISON OK: item inaplicável rejeitado sem abortar o lote; resto aplica + promove';
END $t$;

-- ════════════════════════════════════════════════════════════════════════════
-- BLOCKER 8/14 — complete_import_extraction: idempotência de replay + rejeição de
-- payload vazio (não marca ready uma extração sem conteúdo).
-- ════════════════════════════════════════════════════════════════════════════
DO $t$
DECLARE u uuid := '55555555-5555-5555-5555-555555555555'; att uuid; lc jsonb; cand uuid; got boolean;
  tok uuid := gen_random_uuid();
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"55555555-5555-5555-5555-555555555555"}', false);
  PERFORM public._t_reset(u);
  SET LOCAL ROLE authenticated;
  lc := public.begin_import_source('CV', public._t_import_path(u,tok), 'x.pdf', tok);
  cand := (lc->>'candidate_id')::uuid; att := (lc->>'attempt_id')::uuid;
  RESET ROLE;

  -- payload VAZIO ({}) → rejeitado (blocker 14): não vira ready.
  SET LOCAL ROLE service_role;
  got := false;
  BEGIN PERFORM public.complete_import_extraction(cand, att, '{}'::jsonb, NULL);
  EXCEPTION WHEN SQLSTATE '22023' THEN got := true; END;
  RESET ROLE;
  IF NOT got THEN RAISE EXCEPTION 'FALHOU 14: complete aceitou payload vazio'; END IF;
  IF (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) = 'ready' THEN RAISE EXCEPTION 'FALHOU 14: vazio virou ready'; END IF;

  -- conclusão real com conteúdo → ready.
  SET LOCAL ROLE service_role;
  PERFORM public.complete_import_extraction(cand, att, '{"skills":[{"name":"Go"}]}'::jsonb, 'RAW', '{"skills":["Go"]}'::jsonb, '{"parser_version":"v1","parsed_at":"2026-01-01T00:00:00Z"}'::jsonb);
  RESET ROLE;
  IF (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) <> 'ready' THEN RAISE EXCEPTION 'FALHOU 8: não ready'; END IF;

  -- REPLAY idêntico (mesmo attempt + payload) → idempotente; DIFERENTE → rejeitado.
  SET LOCAL ROLE service_role;
  PERFORM public.complete_import_extraction(cand, att, '{"skills":[{"name":"Go"}]}'::jsonb, 'RAW', '{"skills":["Go"]}'::jsonb, '{"parser_version":"v1","parsed_at":"2026-01-01T00:00:00Z"}'::jsonb);  -- no-op
  got := false;
  BEGIN PERFORM public.complete_import_extraction(cand, att, '{"skills":[{"name":"Rust"}]}'::jsonb, 'RAW', '{"skills":["Rust"]}'::jsonb, '{"parser_version":"v1","parsed_at":"2026-01-01T00:00:00Z"}'::jsonb);
  EXCEPTION WHEN SQLSTATE '22023' THEN got := true; END;
  RESET ROLE;
  IF NOT got THEN RAISE EXCEPTION 'FALHOU 8: replay com payload diferente aceito'; END IF;
  IF (SELECT count(*) FROM public.saved_resumes WHERE id=cand) <> 1 THEN RAISE EXCEPTION 'FALHOU 8: replay duplicou'; END IF;
  IF (SELECT extraction_payload->'skills'->0->>'name' FROM public.saved_resumes WHERE id=cand) <> 'Go' THEN
    RAISE EXCEPTION 'FALHOU 8: payload sobrescrito no replay divergente'; END IF;
  RAISE NOTICE 'T8-14 OK: complete rejeita {} e replay divergente; replay idêntico idempotente';
END $t$;

-- ════════════════════════════════════════════════════════════════════════════
-- ITEM 7 — CAS do resumo (generate-profile-summary não clobbera); fill-empty
-- via service_role (extract-profile); append fenced+dedup de bullets.
-- ════════════════════════════════════════════════════════════════════════════
DO $t$
DECLARE u uuid := '33333333-3333-3333-3333-333333333333'; r text; eid uuid; n int;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333"}', false);
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, summary, headline) VALUES (u, 'lida-pela-IA', 'H1');
  SET LOCAL ROLE authenticated;
  -- IA leu summary='lida-pela-IA', headline='H1'; ninguém editou → aplica os dois.
  r := public.set_profile_summary_cas(u, 'gerado', 'H-novo', 'lida-pela-IA', 'H1');
  IF r <> 'applied' OR (SELECT summary FROM public.profile_personal WHERE user_id=u) <> 'gerado'
     OR (SELECT headline FROM public.profile_personal WHERE user_id=u) <> 'H-novo' THEN
    RAISE EXCEPTION 'FALHOU 7summary: applied falhou (%)', r; END IF;
  -- edição manual concorrente do SUMMARY; IA (leu 'gerado'/'H-novo') tenta → stale.
  UPDATE public.profile_personal SET summary='edicao-manual' WHERE user_id=u;
  r := public.set_profile_summary_cas(u, 'gerado2', 'H2', 'gerado', 'H-novo');
  IF r <> 'stale' OR (SELECT summary FROM public.profile_personal WHERE user_id=u) <> 'edicao-manual'
     OR (SELECT headline FROM public.profile_personal WHERE user_id=u) <> 'H-novo' THEN
    RAISE EXCEPTION 'FALHOU 7summary: summary manual clobbered (%)', r; END IF;
  -- cenário do revisor: só o HEADLINE muda manualmente; IA tenta gravar summary →
  -- stale, e NENHUM dos dois é sobrescrito.
  UPDATE public.profile_personal SET summary='gerado', headline='H2-manual' WHERE user_id=u;  -- summary volta ao lido; headline muda
  r := public.set_profile_summary_cas(u, 'novo-sum', 'novo-head', 'gerado', 'H-novo');
  IF r <> 'stale' THEN RAISE EXCEPTION 'FALHOU 7summary: headline mudado não deu stale (%)', r; END IF;
  IF (SELECT summary FROM public.profile_personal WHERE user_id=u) <> 'gerado'
     OR (SELECT headline FROM public.profile_personal WHERE user_id=u) <> 'H2-manual' THEN
    RAISE EXCEPTION 'FALHOU 7summary: headline stale sobrescreveu summary/headline'; END IF;
  -- append fenced + dedup de bullets.
  eid := public.save_experience_with_bullets(u, '{"title":"E","company":"C","start_date":"2020-01-01","end_date":"2021-01-01","bullets":[{"text":"orig"}]}'::jsonb);
  n := public.append_experience_bullets(u, eid, '[{"text":"orig"},{"text":"nova"},{"text":"nova"}]'::jsonb);  -- 'orig' dup, 'nova' dup interno
  IF n <> 1 THEN RAISE EXCEPTION 'FALHOU 7bullets: dedup falhou (inseriu %)', n; END IF;
  IF (SELECT string_agg(text, ',' ORDER BY order_index) FROM public.profile_bullets WHERE experience_id=eid) <> 'orig,nova' THEN
    RAISE EXCEPTION 'FALHOU 7bullets: ordem/dedup errada'; END IF;
  RESET ROLE;
  RAISE NOTICE 'T7-EDGE OK: summary CAS (stale não clobbera), append bullets fenced+dedup';
END $t$;

-- ════════════════════════════════════════════════════════════════════════════
-- ITEM 8 — MATRIZ COMPLETA: as 9 seções + TODAS as filhas (incl. project_bullets)
-- num único fill-empty, com persistência + ordinality verificadas por seção.
-- ════════════════════════════════════════════════════════════════════════════
DO $t$
DECLARE u uuid := '44444444-4444-4444-4444-444444444444'; res jsonb; eid uuid; edid uuid; pid uuid;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444"}', false);
  PERFORM public._t_reset(u);
  SET LOCAL ROLE authenticated;
  res := public.save_profile_fill_empty(u, '{
    "personal":{"first_name":"Full","summary":"S"},
    "experiences":[
      {"title":"E1","company":"C","start_date":"2020-01-01","end_date":"2021-01-01","bullets":[{"text":"eb0"},{"text":"eb1"}]},
      {"title":"E2","company":"C","start_date":"2019-01-01","end_date":"2020-01-01"}],
    "education":[{"institution":"USP","degree":"CC","start_date":"2018-01-01",
      "majors":["Maj0","Maj1"],"minors":["Min0"],"activities":["Act0","Act1","Act2"]}],
    "languages":[{"name":"L0"},{"name":"L1"}],
    "skills":[{"name":"Sk0"},{"name":"Sk1"}],
    "certifications":[{"name":"Cert0","issuer":"Iss"}],
    "projects":[{"name":"Proj0"}],
    "interests":[{"name":"In0"},{"name":"In1"}],
    "awards":[{"name":"Aw0"}],
    "coursework":[{"name":"Cw0"},{"name":"Cw1"}]}'::jsonb);
  RESET ROLE;
  IF (res->>'status') <> 'success' THEN RAISE EXCEPTION 'FALHOU 8matrix: status % ', res; END IF;
  -- persistência + ordinality por seção
  IF (SELECT count(*) FROM public.profile_experiences WHERE user_id=u) <> 2 THEN RAISE EXCEPTION 'FALHOU 8: experiences'; END IF;
  SELECT id INTO eid FROM public.profile_experiences WHERE user_id=u AND title='E1';
  IF (SELECT string_agg(text, ',' ORDER BY order_index) FROM public.profile_bullets WHERE experience_id=eid) <> 'eb0,eb1' THEN RAISE EXCEPTION 'FALHOU 8: bullets ord'; END IF;
  SELECT id INTO edid FROM public.profile_education WHERE user_id=u;
  IF (SELECT string_agg(name, ',' ORDER BY order_index) FROM public.profile_education_majors WHERE education_id=edid) <> 'Maj0,Maj1' THEN RAISE EXCEPTION 'FALHOU 8: majors ord'; END IF;
  IF (SELECT string_agg(name, ',' ORDER BY order_index) FROM public.profile_education_minors WHERE education_id=edid) <> 'Min0' THEN RAISE EXCEPTION 'FALHOU 8: minors'; END IF;
  IF (SELECT string_agg(text, ',' ORDER BY order_index) FROM public.profile_education_activities WHERE education_id=edid) <> 'Act0,Act1,Act2' THEN RAISE EXCEPTION 'FALHOU 8: activities ord'; END IF;
  IF (SELECT string_agg(name, ',' ORDER BY order_index) FROM public.profile_languages WHERE user_id=u) <> 'L0,L1' THEN RAISE EXCEPTION 'FALHOU 8: languages ord'; END IF;
  IF (SELECT string_agg(name, ',' ORDER BY order_index) FROM public.profile_skills WHERE user_id=u) <> 'Sk0,Sk1' THEN RAISE EXCEPTION 'FALHOU 8: skills ord'; END IF;
  IF (SELECT count(*) FROM public.profile_certifications WHERE user_id=u AND name='Cert0' AND issuer='Iss') <> 1 THEN RAISE EXCEPTION 'FALHOU 8: certifications'; END IF;
  IF (SELECT count(*) FROM public.profile_projects WHERE user_id=u AND name='Proj0') <> 1 THEN RAISE EXCEPTION 'FALHOU 8: projects'; END IF;
  IF (SELECT string_agg(name, ',' ORDER BY order_index) FROM public.profile_interests WHERE user_id=u) <> 'In0,In1' THEN RAISE EXCEPTION 'FALHOU 8: interests ord'; END IF;
  IF (SELECT count(*) FROM public.profile_awards WHERE user_id=u AND name='Aw0') <> 1 THEN RAISE EXCEPTION 'FALHOU 8: awards'; END IF;
  IF (SELECT string_agg(name, ',' ORDER BY order_index) FROM public.profile_coursework WHERE user_id=u) <> 'Cw0,Cw1' THEN RAISE EXCEPTION 'FALHOU 8: coursework ord'; END IF;
  -- + project_bullets via a RPC composta (fill-empty não produz bullets de projeto)
  SELECT id INTO pid FROM public.profile_projects WHERE user_id=u AND name='Proj0';
  SET LOCAL ROLE authenticated;
  pid := public.save_project_with_bullets(u, jsonb_build_object(
    'id', pid::text, 'name', 'Proj0',
    'bullets', '[{"text":"pb0"},{"text":"pb1"}]'::jsonb));
  RESET ROLE;
  IF (SELECT string_agg(text, ',' ORDER BY order_index) FROM public.profile_project_bullets WHERE project_id=pid) <> 'pb0,pb1' THEN RAISE EXCEPTION 'FALHOU 8: project_bullets ord'; END IF;
  RAISE NOTICE 'T8-MATRIX OK: 9 seções + todas as filhas (incl. project_bullets) persistidas com ordinality';
END $t$;

-- fill-empty via service_role (sem JWT): a Edge de extração aplica sem auth.uid().
DO $t$
DECLARE u uuid := '22222222-2222-2222-2222-222222222222'; res jsonb; denied boolean := false;
BEGIN
  PERFORM public._t_reset(u);
  SET LOCAL ROLE service_role;
  res := public.save_profile_fill_empty_service(u, '{"personal":{"first_name":"Svc"},"skills":[{"name":"SvcSkill"}]}'::jsonb);
  RESET ROLE;
  IF (res->>'status') <> 'success' THEN RAISE EXCEPTION 'FALHOU 7svc: status % ', res; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='SvcSkill') THEN RAISE EXCEPTION 'FALHOU 7svc: não preencheu'; END IF;
  -- authenticated NÃO pode chamar a versão service (sem grant).
  PERFORM set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222"}', false);
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM public.save_profile_fill_empty_service(u, '{}'::jsonb);
  EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  RESET ROLE;
  IF NOT denied THEN RAISE EXCEPTION 'FALHOU 7svc: authenticated executou a RPC service'; END IF;
  RAISE NOTICE 'T7-SERVICE OK: fill-empty service_role (sem JWT); authenticated negado';
END $t$;

-- ════════════════════════════════════════════════════════════════════════════
-- A janela migration-first ainda recebe chamadas da Edge HEAD^ pelo nome antigo.
-- Prova compatibilidade do retorno, manual-wins, fill-empty e rollback GLOBAL.
DO $t$
DECLARE
  u uuid := '22222222-2222-2222-2222-222222222222';
  res jsonb; before_ts timestamptz; got_code text; got_message text;
  denied_auth boolean := false; denied_anon boolean := false;
BEGIN
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id,email,last_extracted_at)
    VALUES (u,'manual@corp.com','2026-01-01T00:00:00Z');
  INSERT INTO public.profile_skills(user_id,name,order_index) VALUES (u,'ManualSkill',0);

  SET LOCAL ROLE service_role;
  res := public.save_profile_from_json(u, '{
    "personal":{"first_name":"Importada","email":"import@cv.com"},
    "skills":[{"name":"ImportedSkill"}],
    "languages":[{"name":"Português","proficiency":"Nativo"}]
  }'::jsonb);
  RESET ROLE;
  IF res <> jsonb_build_object('status','success','user_id',u,'skipped_rows',0) THEN
    RAISE EXCEPTION 'FALHOU LEGACY-SHIM: shape incompatível %',res; END IF;
  IF (SELECT email FROM public.profile_personal WHERE user_id=u) <> 'manual@corp.com'
     OR (SELECT first_name FROM public.profile_personal WHERE user_id=u) <> 'Importada'
     OR (SELECT string_agg(name,',' ORDER BY order_index) FROM public.profile_skills WHERE user_id=u) <> 'ManualSkill'
     OR NOT EXISTS (SELECT 1 FROM public.profile_languages WHERE user_id=u AND name='Português') THEN
    RAISE EXCEPTION 'FALHOU LEGACY-SHIM: manual-wins/fill-empty'; END IF;

  SELECT last_extracted_at INTO before_ts FROM public.profile_personal WHERE user_id=u;
  SET LOCAL ROLE service_role;
  BEGIN
    PERFORM public.save_profile_from_json(u, '{
      "personal":{"last_name":"DEVE_ROLLBACK"},
      "experiences":[
        {"title":"Válida","company":"C","start_date":"2025-01-01","end_date":null,"is_current":true,"bullets":[]},
        {"title":"Inválida","company":"C","end_date":null,"is_current":true,"bullets":[]}
      ],
      "interests":[{"name":"DEVE_ROLLBACK"}]
    }'::jsonb);
    RAISE EXCEPTION 'shim_partial_returned_success';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got_code = RETURNED_SQLSTATE, got_message = MESSAGE_TEXT;
  END;
  RESET ROLE;
  IF got_code <> 'P0001' OR got_message <> 'profile_import_apply_failed'
     OR (SELECT last_name FROM public.profile_personal WHERE user_id=u) IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.profile_experiences WHERE user_id=u)
     OR EXISTS (SELECT 1 FROM public.profile_interests WHERE user_id=u)
     OR (SELECT last_extracted_at FROM public.profile_personal WHERE user_id=u) IS DISTINCT FROM before_ts THEN
    RAISE EXCEPTION 'FALHOU LEGACY-SHIM: partial sem rollback/erro genérico code=% msg=%',got_code,got_message; END IF;

  got_code := NULL; got_message := NULL;
  SET LOCAL ROLE service_role;
  BEGIN
    PERFORM public.save_profile_from_json(u, '{"personal":{"summary":{"secret":"nao-vazar"}}}'::jsonb);
    RAISE EXCEPTION 'shim_malformed_returned_success';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS got_code = RETURNED_SQLSTATE, got_message = MESSAGE_TEXT;
  END;
  RESET ROLE;
  IF got_code <> 'P0001' OR got_message <> 'profile_import_apply_failed'
     OR (SELECT summary FROM public.profile_personal WHERE user_id=u) IS NOT NULL
     OR (SELECT last_extracted_at FROM public.profile_personal WHERE user_id=u) IS DISTINCT FROM before_ts THEN
    RAISE EXCEPTION 'FALHOU LEGACY-SHIM: malformed vazou detalhe/alterou estado code=% msg=%',got_code,got_message; END IF;

  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u)::text,false);
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM public.save_profile_from_json(u,'{"personal":{"first_name":"x"}}'::jsonb);
  EXCEPTION WHEN insufficient_privilege THEN denied_auth := true; END;
  RESET ROLE;
  SET LOCAL ROLE anon;
  BEGIN PERFORM public.save_profile_from_json(u,'{"personal":{"first_name":"x"}}'::jsonb);
  EXCEPTION WHEN insufficient_privilege THEN denied_anon := true; END;
  RESET ROLE;
  IF NOT denied_auth OR NOT denied_anon THEN
    RAISE EXCEPTION 'FALHOU LEGACY-SHIM: auth/anon executaram auth=% anon=%',denied_auth,denied_anon; END IF;
  RAISE NOTICE 'T-LEGACY-SHIM OK: HEAD^ fenced/fill-empty; partial/malformed rollback genérico; auth+anon negados';
END $t$;

-- ROUND 4 — blockers E/F/G/H/I/J. Idempotência real, "manual vence" idioma,
-- conteúdo semântico, fidelidade de campos, contrato de cache, remoção transacional.
-- ════════════════════════════════════════════════════════════════════════════

-- Helper: candidata READY com TODAS as colunas canônicas (raw/legacy/meta), semeada
-- como postgres (authenticated não pode setar colunas de integridade).
CREATE OR REPLACE FUNCTION public._t_seed_ready(p uuid, p_title text, p_payload jsonb, p_attempt uuid,
  p_raw text DEFAULT 'RAW', p_legacy jsonb DEFAULT '{"parsed":true}'::jsonb, p_meta jsonb DEFAULT '{"parser_version":"v1","parsed_at":"2026-01-01T00:00:00Z"}'::jsonb)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v uuid;
BEGIN
  INSERT INTO public.saved_resumes(user_id,title,file_path,source,extraction_status,extraction_payload,
    extraction_attempt_id,extraction_raw_text,extraction_legacy_parsed,extraction_meta)
    VALUES (p, p_title, 'p/'||p_title, 'imported', 'ready', p_payload, p_attempt, p_raw, p_legacy, p_meta)
    RETURNING id INTO v;
  RETURN v;
END $fn$;

-- R4.1 — lang_level CONCORRENTE: manual mudou o nível depois do diff → manual vence (stale).
DO $t$
DECLARE u uuid := '66666666-6666-6666-6666-666666666666'; att uuid := '00000401-0000-0000-0000-000000000401';
  cand uuid; agg jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"66666666-6666-6666-6666-666666666666"}', false);
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, first_name) VALUES (u, 'X');
  INSERT INTO public.profile_languages(user_id, name, proficiency) VALUES (u, 'Francês', 'basic');
  cand := public._t_seed_ready(u, 'C', '{"languages":[{"name":"Francês","proficiency":"intermediate"}]}'::jsonb, att);
  -- edição MANUAL concorrente (depois do diff que viu 'basic'):
  UPDATE public.profile_languages SET proficiency='fluent' WHERE user_id=u AND name='Francês';
  SET LOCAL ROLE authenticated;
  agg := public.apply_reviewed_conflicts_and_promote(cand, att, jsonb_build_array(
    jsonb_build_object('kind','lang_level','name','Francês','expected','basic','proficiency','intermediate')));
  RESET ROLE;
  IF (agg->>'promoted') <> 'true' THEN RAISE EXCEPTION 'FALHOU R4.1: não promoveu (%)', agg; END IF;
  IF NOT (agg->'stale' @> '["language:Francês"]'::jsonb) THEN RAISE EXCEPTION 'FALHOU R4.1: não marcou stale (%)', agg; END IF;
  IF (SELECT proficiency FROM public.profile_languages WHERE user_id=u AND name='Francês') <> 'fluent' THEN
    RAISE EXCEPTION 'FALHOU R4.1: manual sobrescrito (nível não é fluent)'; END IF;
  RAISE NOTICE 'R4.1 OK: lang_level CAS — manual vence (stale), promoção segue';
END $t$;

-- R4.2 — add_lang CONCORRENTE: idioma apareceu manualmente depois do diff → stale, não sobrescreve.
DO $t$
DECLARE u uuid := '66666666-6666-6666-6666-666666666666'; att uuid := '00000402-0000-0000-0000-000000000402';
  cand uuid; agg jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"66666666-6666-6666-6666-666666666666"}', false);
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, first_name) VALUES (u, 'X');
  cand := public._t_seed_ready(u, 'C', '{"languages":[{"name":"Alemão","proficiency":"basic"}]}'::jsonb, att);
  -- o idioma APARECEU manualmente (o diff o viu ausente):
  INSERT INTO public.profile_languages(user_id, name, proficiency) VALUES (u, 'Alemão', 'fluent');
  SET LOCAL ROLE authenticated;
  agg := public.apply_reviewed_conflicts_and_promote(cand, att, jsonb_build_array(
    jsonb_build_object('kind','add_lang','source','Alemão','name','Alemão','proficiency','basic')));
  RESET ROLE;
  IF (agg->>'promoted') <> 'true' THEN RAISE EXCEPTION 'FALHOU R4.2: não promoveu (%)', agg; END IF;
  IF NOT (agg->'stale' @> '["language:Alemão"]'::jsonb) THEN RAISE EXCEPTION 'FALHOU R4.2: não marcou stale (%)', agg; END IF;
  IF (SELECT count(*) FROM public.profile_languages WHERE user_id=u AND name='Alemão') <> 1
     OR (SELECT proficiency FROM public.profile_languages WHERE user_id=u AND name='Alemão') <> 'fluent' THEN
    RAISE EXCEPTION 'FALHOU R4.2: add_lang sobrescreveu/duplicou o manual'; END IF;
  RAISE NOTICE 'R4.2 OK: add_lang — idioma manual preservado (stale), sem sobrescrever';
END $t$;

-- R4.3 — REPLAY do apply inicial: mesmo sucesso persistido, ZERO duplicação, sem profile_not_empty_use_review.
DO $t$
DECLARE u uuid := '66666666-6666-6666-6666-666666666666'; att uuid := '00000403-0000-0000-0000-000000000403';
  cand uuid; r1 jsonb; r2 jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"66666666-6666-6666-6666-666666666666"}', false);
  PERFORM public._t_reset(u);
  cand := public._t_seed_ready(u, 'C', '{"personal":{"first_name":"Ada"},"skills":[{"name":"Rust"}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  r1 := public.apply_and_promote_imported_source(cand, att);
  r2 := public.apply_and_promote_imported_source(cand, att);  -- REPLAY (resposta perdida)
  RESET ROLE;
  IF (r1->>'promoted') <> 'true' THEN RAISE EXCEPTION 'FALHOU R4.3: 1ª não promoveu (%)', r1; END IF;
  IF r2 IS DISTINCT FROM r1 THEN RAISE EXCEPTION 'FALHOU R4.3: replay devolveu resultado DIFERENTE (% vs %)', r2, r1; END IF;
  IF (SELECT count(*) FROM public.profile_skills WHERE user_id=u AND name='Rust') <> 1 THEN
    RAISE EXCEPTION 'FALHOU R4.3: replay DUPLICOU skill'; END IF;
  RAISE NOTICE 'R4.3 OK: replay do apply inicial idempotente (mesmo sucesso, zero dup)';
END $t$;

-- R4.4/R4.5 — REPLAY reviewed idêntico = mesmo resultado, zero dup; reviewed DIFERENTE após conclusão = rejeitado.
DO $t$
DECLARE u uuid := '66666666-6666-6666-6666-666666666666'; att uuid := '00000404-0000-0000-0000-000000000404';
  cand uuid; r1 jsonb; r2 jsonb; ch jsonb; denied boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"66666666-6666-6666-6666-666666666666"}', false);
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, first_name) VALUES (u, 'X');  -- perfil com dado (substituição)
  cand := public._t_seed_ready(u, 'C', '{"skills":[{"name":"Docker"}]}'::jsonb, att);
  ch := jsonb_build_array(jsonb_build_object('kind','add','section','skill','source','Docker','value','Docker'));
  SET LOCAL ROLE authenticated;
  r1 := public.apply_reviewed_conflicts_and_promote(cand, att, ch);
  r2 := public.apply_reviewed_conflicts_and_promote(cand, att, ch);  -- REPLAY idêntico
  IF (r1->>'promoted') <> 'true' THEN RAISE EXCEPTION 'FALHOU R4.4: 1ª não promoveu (%)', r1; END IF;
  IF r2 IS DISTINCT FROM r1 THEN RAISE EXCEPTION 'FALHOU R4.4: replay reviewed devolveu DIFERENTE (% vs %)', r2, r1; END IF;
  IF (SELECT count(*) FROM public.profile_skills WHERE user_id=u AND name='Docker') <> 1 THEN
    RAISE EXCEPTION 'FALHOU R4.4: replay reviewed DUPLICOU'; END IF;
  -- reviewed DIFERENTE após conclusão → rejeitado.
  BEGIN PERFORM public.apply_reviewed_conflicts_and_promote(cand, att,
    jsonb_build_array(jsonb_build_object('kind','add','section','skill','source','Docker','value','Kafka')));
  EXCEPTION WHEN SQLSTATE '22023' THEN denied := true; END;
  RESET ROLE;
  IF NOT denied THEN RAISE EXCEPTION 'FALHOU R4.5: reviewed diferente após conclusão NÃO foi rejeitado'; END IF;
  RAISE NOTICE 'R4.4/R4.5 OK: replay reviewed idempotente; conjunto diferente após conclusão rejeitado';
END $t$;

-- R4.6 — payload semanticamente VAZIO/RUÍDO nunca vira ready/current.
DO $t$
DECLARE u uuid := '66666666-6666-6666-6666-666666666666'; att uuid; lc jsonb; cand uuid; n int := 0; p jsonb; tok uuid;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"66666666-6666-6666-6666-666666666666"}', false);
  PERFORM public._t_reset(u);
  FOR p IN SELECT * FROM jsonb_array_elements('[{"skills":[{}]},{"skills":[{"name":"  "}]},{"experiences":[{}]},{"interests":[{"name":""}]},{"education":[{}]}]'::jsonb) LOOP
    tok := gen_random_uuid();
    SET LOCAL ROLE authenticated;
    lc := public.begin_import_source('C',public._t_import_path(u,tok),'x.pdf',tok);
    cand := (lc->>'candidate_id')::uuid; att := (lc->>'attempt_id')::uuid;
    RESET ROLE;
    SET LOCAL ROLE service_role;
    BEGIN
      PERFORM public.complete_import_extraction(cand, att, p, 'RAW', '{"parsed":true}'::jsonb, '{"parser_version":"v1","parsed_at":"2026-01-01T00:00:00Z"}'::jsonb);
    EXCEPTION WHEN SQLSTATE '22023' THEN n := n + 1; END;
    RESET ROLE;
    IF (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) = 'ready' THEN
      RAISE EXCEPTION 'FALHOU R4.6: payload ruído % virou ready', p; END IF;
  END LOOP;
  IF n <> 5 THEN RAISE EXCEPTION 'FALHOU R4.6: só % dos 5 payloads-ruído rejeitados', n; END IF;
  RAISE NOTICE 'R4.6 OK: arrays de objetos vazios/whitespace/ruído nunca viram ready/current';
END $t$;

-- R4.7 — FIDELIDADE: prêmio.date, cert.date e projeto (role/context/website/description/datas/is_current/bullet) preservados.
DO $t$
DECLARE u uuid := '66666666-6666-6666-6666-666666666666'; att uuid := '00000407-0000-0000-0000-000000000407';
  cand uuid; agg jsonb; pid uuid;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"66666666-6666-6666-6666-666666666666"}', false);
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, first_name) VALUES (u, 'X');
  cand := public._t_seed_ready(u, 'C', jsonb_build_object(
    'awards', jsonb_build_array(jsonb_build_object('name','Prêmio Z','date','2021-05-01')),
    'certifications', jsonb_build_array(jsonb_build_object('name','GCP','issuer','Google','date','2022-03-01')),
    'projects', jsonb_build_array(jsonb_build_object('name','Proj Q','role','Líder','context','ONG','website','http://q.dev',
      'description','Descr','start_date','2020-01-01','end_date','2020-12-01','is_current',false,
      'bullets',jsonb_build_array(jsonb_build_object('text','Fez A'))))), att);
  SET LOCAL ROLE authenticated;
  agg := public.apply_reviewed_conflicts_and_promote(cand, att, jsonb_build_array(
    jsonb_build_object('kind','add','section','award','source','Prêmio Z','value','Prêmio Z'),
    jsonb_build_object('kind','add_cert','source','GCP','name','GCP','issuer','Google'),
    jsonb_build_object('kind','add','section','project','source','Proj Q','value','Proj Q')));
  RESET ROLE;
  IF (agg->>'promoted') <> 'true' OR jsonb_array_length(agg->'failed') <> 0 THEN RAISE EXCEPTION 'FALHOU R4.7: não promoveu (%)', agg; END IF;
  IF (SELECT date FROM public.profile_awards WHERE user_id=u AND name='Prêmio Z') <> '2021-05-01' THEN RAISE EXCEPTION 'FALHOU R4.7: award.date perdida'; END IF;
  IF (SELECT date FROM public.profile_certifications WHERE user_id=u AND name='GCP') <> '2022-03-01' THEN RAISE EXCEPTION 'FALHOU R4.7: cert.date perdida'; END IF;
  SELECT id INTO pid FROM public.profile_projects WHERE user_id=u AND name='Proj Q';
  IF pid IS NULL THEN RAISE EXCEPTION 'FALHOU R4.7: projeto não inserido'; END IF;
  IF (SELECT role FROM public.profile_projects WHERE id=pid) <> 'Líder'
     OR (SELECT context FROM public.profile_projects WHERE id=pid) <> 'ONG'
     OR (SELECT website FROM public.profile_projects WHERE id=pid) <> 'http://q.dev'
     OR (SELECT description FROM public.profile_projects WHERE id=pid) <> 'Descr'
     OR (SELECT start_date FROM public.profile_projects WHERE id=pid) <> '2020-01-01'
     OR (SELECT end_date FROM public.profile_projects WHERE id=pid) <> '2020-12-01' THEN
    RAISE EXCEPTION 'FALHOU R4.7: campos canônicos do projeto perdidos'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_project_bullets WHERE project_id=pid AND text='Fez A') THEN
    RAISE EXCEPTION 'FALHOU R4.7: bullet do projeto perdido'; END IF;
  RAISE NOTICE 'R4.7 OK: award.date/cert.date/projeto (role/context/site/desc/datas/bullets) preservados';
END $t$;

-- R4.8 — erro INESPERADO (não-validação) dentro de UMA escolha → rollback GLOBAL + promoted:false.
CREATE OR REPLACE FUNCTION public._t_r48_boom() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN IF NEW.name = 'BOOMSKILL' THEN RAISE EXCEPTION 'boom48' USING ERRCODE='XX000'; END IF; RETURN NEW; END $fn$;
CREATE TRIGGER _t_r48_boom_trg BEFORE INSERT ON public.profile_skills
  FOR EACH ROW EXECUTE FUNCTION public._t_r48_boom();
DO $t$
DECLARE u uuid := '66666666-6666-6666-6666-666666666666'; att uuid := '00000408-0000-0000-0000-000000000408';
  cand uuid; agg jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"66666666-6666-6666-6666-666666666666"}', false);
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, first_name, summary) VALUES (u, 'X', 'antigo');
  cand := public._t_seed_ready(u, 'C', '{"personal":{"summary":"novo"},"skills":[{"name":"BOOMSKILL"}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  -- escolha 1: summary (aplicaria) + escolha 2: skill que dispara XX000 (não-whitelist → re-raise).
  agg := public.apply_reviewed_conflicts_and_promote(cand, att, jsonb_build_array(
    jsonb_build_object('kind','personal','field','summary','expected','antigo','value','novo'),
    jsonb_build_object('kind','add','section','skill','source','BOOMSKILL','value','BOOMSKILL')));
  RESET ROLE;
  IF (agg->>'promoted') <> 'false' OR jsonb_array_length(agg->'failed') = 0 THEN
    RAISE EXCEPTION 'FALHOU R4.8: erro inesperado não abortou o lote (%)', agg; END IF;
  IF (SELECT summary FROM public.profile_personal WHERE user_id=u) <> 'antigo' THEN
    RAISE EXCEPTION 'FALHOU R4.8: summary da escolha 1 sobreviveu (rollback global falhou)'; END IF;
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=cand) <> false THEN RAISE EXCEPTION 'FALHOU R4.8: promoveu'; END IF;
  RAISE NOTICE 'R4.8 OK: erro inesperado numa escolha → rollback GLOBAL + promoted:false';
END $t$;
DROP TRIGGER _t_r48_boom_trg ON public.profile_skills;

-- R4.9 — remover a fonte ATUAL: cache imported_resume limpo, profile_* intacto.
DO $t$
DECLARE u uuid := '66666666-6666-6666-6666-666666666666'; att uuid := '00000409-0000-0000-0000-000000000409';
  cand uuid; res jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"66666666-6666-6666-6666-666666666666"}', false);
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_skills(user_id, name) VALUES (u, 'SkillIncorporada');  -- dado já no perfil
  cand := public._t_seed_ready(u, 'C', '{"skills":[{"name":"X"}]}'::jsonb, att);
  UPDATE public.saved_resumes SET is_current_source=true WHERE id=cand;
  UPDATE public.user_profiles SET gamification_data='{"imported_resume":{"raw_text":"R"}}'::jsonb WHERE id=u;
  SET LOCAL ROLE authenticated;
  res := public.remove_imported_source(cand);
  RESET ROLE;
  IF (res->>'removed') <> 'true' OR (res->>'was_current') <> 'true' THEN RAISE EXCEPTION 'FALHOU R4.9: retorno (%)', res; END IF;
  IF EXISTS (SELECT 1 FROM public.saved_resumes WHERE id=cand) THEN RAISE EXCEPTION 'FALHOU R4.9: row não removida'; END IF;
  IF (SELECT gamification_data->'imported_resume' FROM public.user_profiles WHERE id=u) IS NOT NULL THEN
    RAISE EXCEPTION 'FALHOU R4.9: cache imported_resume NÃO foi limpo'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='SkillIncorporada') THEN
    RAISE EXCEPTION 'FALHOU R4.9: profile_* foi tocado (skill incorporada sumiu)'; END IF;
  RAISE NOTICE 'R4.9 OK: remove fonte atual → cache limpo, profile_* intacto';
END $t$;

-- R4.10 — remover fonte HISTÓRICA (não-atual): cache atual permanece.
DO $t$
DECLARE u uuid := '66666666-6666-6666-6666-666666666666';
  attA uuid := '0000040a-0000-0000-0000-00000000040a'; attB uuid := '0000040b-0000-0000-0000-00000000040b';
  candA uuid; candB uuid; res jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"66666666-6666-6666-6666-666666666666"}', false);
  PERFORM public._t_reset(u);
  candA := public._t_seed_ready(u, 'A', '{"skills":[{"name":"X"}]}'::jsonb, attA);
  candB := public._t_seed_ready(u, 'B', '{"skills":[{"name":"Y"}]}'::jsonb, attB);
  PERFORM public._promote_imported_and_activate(u,candA,'RAW');  -- A é a atual
  SET LOCAL ROLE authenticated;
  res := public.remove_imported_source(candB);  -- remove a HISTÓRICA
  RESET ROLE;
  IF (res->>'was_current') <> 'false' THEN RAISE EXCEPTION 'FALHOU R4.10: was_current errado (%)', res; END IF;
  IF (SELECT gamification_data->'imported_resume'->>'raw_text' FROM public.user_profiles WHERE id=u) <> 'RAW'
     OR (SELECT gamification_data#>>'{imported_resume,source_resume_id}' FROM public.user_profiles WHERE id=u) <> candA::text THEN
    RAISE EXCEPTION 'FALHOU R4.10: cache da fonte ATUAL foi tocado ao remover histórica'; END IF;
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=candA) <> true THEN RAISE EXCEPTION 'FALHOU R4.10: A deixou de ser atual'; END IF;
  RAISE NOTICE 'R4.10 OK: remove fonte histórica → cache/fonte atual intactos';
END $t$;

-- R4.11 — complete com legacy/meta ausente/inválido → fail-closed.
DO $t$
DECLARE u uuid := '66666666-6666-6666-6666-666666666666'; att uuid; lc jsonb; cand uuid; n int := 0;
  tok uuid := gen_random_uuid();
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"66666666-6666-6666-6666-666666666666"}', false);
  PERFORM public._t_reset(u);
  SET LOCAL ROLE authenticated;
  lc := public.begin_import_source('C',public._t_import_path(u,tok),'x.pdf',tok); cand := (lc->>'candidate_id')::uuid; att := (lc->>'attempt_id')::uuid;
  RESET ROLE;
  SET LOCAL ROLE service_role;
  BEGIN PERFORM public.complete_import_extraction(cand, att, '{"skills":[{"name":"Go"}]}'::jsonb, 'RAW', NULL, '{"parser_version":"v1","parsed_at":"2026-01-01T00:00:00Z"}'::jsonb);
  EXCEPTION WHEN SQLSTATE '22023' THEN n := n + 1; END;  -- legacy null
  BEGIN PERFORM public.complete_import_extraction(cand, att, '{"skills":[{"name":"Go"}]}'::jsonb, 'RAW', '{}'::jsonb, '{"parser_version":"v1","parsed_at":"2026-01-01T00:00:00Z"}'::jsonb);
  EXCEPTION WHEN SQLSTATE '22023' THEN n := n + 1; END;  -- legacy {}
  BEGIN PERFORM public.complete_import_extraction(cand, att, '{"skills":[{"name":"Go"}]}'::jsonb, 'RAW', '{"parsed":true}'::jsonb, NULL);
  EXCEPTION WHEN SQLSTATE '22023' THEN n := n + 1; END;  -- meta null
  RESET ROLE;
  IF n <> 3 THEN RAISE EXCEPTION 'FALHOU R4.11: só % dos 3 casos legacy/meta rejeitados', n; END IF;
  IF (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) = 'ready' THEN RAISE EXCEPTION 'FALHOU R4.11: virou ready sem legacy/meta'; END IF;
  RAISE NOTICE 'R4.11 OK: complete fail-closed sem legacy_parsed/meta';
END $t$;

-- R4.12 — nova fonte SEM raw_text → o raw ANTERIOR é removido do cache na promoção.
DO $t$
DECLARE u uuid := '66666666-6666-6666-6666-666666666666'; att uuid := '0000040c-0000-0000-0000-00000000040c';
  cand uuid; r1 jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"66666666-6666-6666-6666-666666666666"}', false);
  PERFORM public._t_reset(u);
  -- cache legacy de uma fonte anterior COM raw_text:
  UPDATE public.user_profiles SET gamification_data='{"imported_resume":{"raw_text":"OLDRAW","parsed":{"x":1}}}'::jsonb WHERE id=u;
  -- nova candidata READY com raw_text NULL:
  cand := public._t_seed_ready(u, 'C', '{"personal":{"first_name":"Ada"}}'::jsonb, att, NULL, '{"parsed":{"y":2}}'::jsonb, '{"parser_version":"v1","parsed_at":"2026-01-01T00:00:00Z"}'::jsonb);
  SET LOCAL ROLE authenticated;
  r1 := public.apply_and_promote_imported_source(cand, att);
  RESET ROLE;
  IF (r1->>'promoted') <> 'true' THEN RAISE EXCEPTION 'FALHOU R4.12: não promoveu (%)', r1; END IF;
  IF (SELECT gamification_data->'imported_resume' ? 'raw_text' FROM public.user_profiles WHERE id=u) THEN
    RAISE EXCEPTION 'FALHOU R4.12: raw_text ANTIGO permaneceu no cache (nova fonte sem raw)'; END IF;
  IF (SELECT gamification_data->'imported_resume'->'parsed'->>'y' FROM public.user_profiles WHERE id=u) <> '2' THEN
    RAISE EXCEPTION 'FALHOU R4.12: cache não foi trocado pelo parsed da nova fonte'; END IF;
  RAISE NOTICE 'R4.12 OK: nova fonte sem raw → raw antigo removido; cache trocado por inteiro';
END $t$;

-- R4.13 (review Finding 1) — experiência com data NÃO-ISO NÃO promove perfil vazio.
-- has_content precisa casar com o writer: title/company sozinhos NÃO bastam se o
-- writer vai PULAR a experiência por safe_date(start_date) IS NULL. Antes: passava
-- no has_content, gravava 0 linhas, status='success', promovia a fonte com o perfil
-- relacional VAZIO (só o cache legacy tinha o dado). Agora: rejeitado como vazio.
DO $t$
DECLARE u uuid := '66666666-6666-6666-6666-666666666666'; att uuid := '0000040d-0000-0000-0000-00000000040d';
  cand uuid; lc jsonb; att2 uuid; raised boolean; st text;
  tok uuid := gen_random_uuid();
  -- só uma experiência, title+company reais, mas start_date NÃO-ISO ("2020").
  bad_payload jsonb := '{"experiences":[{"title":"Analyst","company":"Acme","start_date":"2020"}]}'::jsonb;
  ok_payload  jsonb := '{"experiences":[{"title":"Analyst","company":"Acme","start_date":"2020-01-01","end_date":"2021-01-01","is_current":false}]}'::jsonb;
  res jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"66666666-6666-6666-6666-666666666666"}', false);
  PERFORM public._t_reset(u);

  -- (A) REPRODUÇÃO DIRETA no apply: candidata READY (seed bypassa o complete) com o
  -- payload não-ISO → apply DEVE recusar (empty_payload), NÃO promover, 0 experiências.
  cand := public._t_seed_ready(u, 'BadDate', bad_payload, att);
  raised := false;
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM public.apply_and_promote_imported_source(cand, att);
  EXCEPTION WHEN SQLSTATE '22023' THEN raised := true; END;
  RESET ROLE;
  IF NOT raised THEN RAISE EXCEPTION 'FALHOU R4.13a: apply não recusou payload só-experiência não-ISO'; END IF;
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=cand) THEN
    RAISE EXCEPTION 'FALHOU R4.13a: fonte foi promovida a atual sem gravar nada'; END IF;
  IF EXISTS (SELECT 1 FROM public.profile_experiences WHERE user_id=u) THEN
    RAISE EXCEPTION 'FALHOU R4.13a: gravou experiência apesar de start_date não parseável'; END IF;

  -- (B) MESMA rejeição no complete: a candidata nem vira ready.
  PERFORM public._t_reset(u);
  SET LOCAL ROLE authenticated;
  lc := public.begin_import_source('C',public._t_import_path(u,tok),'x.pdf',tok);
  cand := (lc->>'candidate_id')::uuid; att2 := (lc->>'attempt_id')::uuid;
  RESET ROLE;
  raised := false;
  SET LOCAL ROLE service_role;
  BEGIN PERFORM public.complete_import_extraction(cand, att2, bad_payload, 'RAW', '{"parsed":true}'::jsonb, '{"parser_version":"v1","parsed_at":"2026-01-01T00:00:00Z"}'::jsonb);
  EXCEPTION WHEN SQLSTATE '22023' THEN raised := true; END;
  RESET ROLE;
  IF NOT raised THEN RAISE EXCEPTION 'FALHOU R4.13b: complete não recusou experiência não-ISO'; END IF;
  IF (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) = 'ready' THEN
    RAISE EXCEPTION 'FALHOU R4.13b: candidata virou ready com experiência não-persistível'; END IF;

  -- (C) CONTROLE POSITIVO: a MESMA experiência com data ISO promove e GRAVA a linha —
  -- a correção não rejeita import legítimo só-experiência.
  PERFORM public._t_reset(u);
  cand := public._t_seed_ready(u, 'GoodDate', ok_payload, att);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(cand, att);
  RESET ROLE;
  IF (res#>>'{apply,status}') <> 'success' OR (res->>'promoted') <> 'true' THEN
    RAISE EXCEPTION 'FALHOU R4.13c: experiência ISO não promoveu (%)', res; END IF;
  IF (SELECT count(*) FROM public.profile_experiences WHERE user_id=u AND title='Analyst' AND company='Acme') <> 1 THEN
    RAISE EXCEPTION 'FALHOU R4.13c: experiência ISO não foi gravada'; END IF;

  RAISE NOTICE 'R4.13 OK: experiência não-ISO não promove perfil vazio (has_content casado com o writer); ISO grava normal';
END $t$;

-- ════════════════════════════════════════════════════════════════════════════
-- ROUND 5 — novos bloqueadores (E delete/RLS, F recibos, G fidelidade, C email, I meta)
-- ════════════════════════════════════════════════════════════════════════════

-- R5-E / COMPAT HEAD^ — o build anterior apaga o blob PRIMEIRO e depois faz
-- DELETE direto na row. O segundo passo precisa continuar permitido para rows
-- próprias; um trigger transacional limpa o cache se era a imported current.
-- Cross-user segue invisível por RLS, profile_* nunca é tocado, e a RPC nova
-- continua sendo o caminho canônico (DB primeiro, blob depois).
DO $t$
DECLARE u uuid := '77777777-7777-7777-7777-777777777771';
  other uuid := '77777777-7777-7777-7777-777777777779';
  cimp uuid; cimp_rpc uuid; chist uuid; clegacy uuid; cman uuid; cadp uuid; cother uuid;
  res jsonb; affected integer; service_delete_denied boolean := false;
BEGIN
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO auth.users(id) VALUES (other) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (other) ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', '{"sub":"77777777-7777-7777-7777-777777777771"}', false);
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_skills(user_id,name) VALUES (u,'Guardado');
  INSERT INTO public.saved_resumes(user_id,title,file_path,source,extraction_status,is_current_source)
    VALUES (u,'imp-cur',u::text||'/c.pdf','imported','ready',true) RETURNING id INTO cimp;
  INSERT INTO public.saved_resumes(user_id,title,file_path,source,extraction_status)
    VALUES (u,'imp-hist',u::text||'/h.pdf','imported','ready') RETURNING id INTO chist;
  INSERT INTO public.saved_resumes(user_id,title,file_path,source) VALUES (u,'man',u::text||'/m.pdf','manual') RETURNING id INTO cman;
  INSERT INTO public.saved_resumes(user_id,title,file_path,source) VALUES (u,'adp',u::text||'/a.pdf','adapted') RETURNING id INTO cadp;
  INSERT INTO public.saved_resumes(user_id,title,file_path,source) VALUES (other,'other',other::text||'/o.pdf','manual') RETURNING id INTO cother;
  UPDATE public.user_profiles SET gamification_data='{"imported_resume":{"raw_text":"R","parsed":{"x":1}}}'::jsonb WHERE id=u;

  -- service_role herdava ALL no baseline. Sem auth.uid(), o fence statement não
  -- consegue escolher advisory; DELETE direto criaria saved tuple→profile no
  -- cleanup e poderia inverter a cascata canônica da conta. Deve ficar negado.
  SET LOCAL ROLE service_role;
  BEGIN
    DELETE FROM public.saved_resumes WHERE id=cman;
  EXCEPTION WHEN insufficient_privilege THEN
    service_delete_denied := true;
  END;
  RESET ROLE;
  IF NOT service_delete_denied OR NOT EXISTS (SELECT 1 FROM public.saved_resumes WHERE id=cman) THEN
    RAISE EXCEPTION 'FALHOU R5-E: service_role conservou DELETE direto'; END IF;

  SET LOCAL ROLE authenticated;
  -- HEAD^, passo 2 (o blob já foi removido): DELETE direto de manual funciona.
  DELETE FROM public.saved_resumes WHERE id=cman;
  IF EXISTS (SELECT 1 FROM public.saved_resumes WHERE id=cman) THEN
    RAISE EXCEPTION 'FALHOU R5-E: HEAD^ deixou row manual após remover blob'; END IF;
  -- RLS: tentar deletar row de outro uid afeta zero linhas.
  DELETE FROM public.saved_resumes WHERE id=cother;
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 0 THEN RAISE EXCEPTION 'FALHOU R5-E: DELETE cross-user afetou % row', affected; END IF;

  -- HEAD^ deletando a fonte ATUAL: row + cache coerentes na mesma transação.
  DELETE FROM public.saved_resumes WHERE id=cimp;
  IF EXISTS (SELECT 1 FROM public.saved_resumes WHERE id=cimp) THEN
    RAISE EXCEPTION 'FALHOU R5-E: row current direta não removida'; END IF;
  IF (SELECT gamification_data ? 'imported_resume' FROM public.user_profiles WHERE id=u) THEN
    RAISE EXCEPTION 'FALHOU R5-E: trigger não limpou cache da current direta'; END IF;

  -- Cache de uma legacy marker viva sobrevive ao delete de outra row histórica.
  INSERT INTO public.saved_resumes(user_id,title,file_path,source)
    VALUES (u,'legacy-live',u::text||'/legacy-live.pdf','imported') RETURNING id INTO clegacy;
  UPDATE public.user_profiles SET gamification_data='{"imported_resume":{"raw_text":"R2"}}'::jsonb WHERE id=u;
  DELETE FROM public.saved_resumes WHERE id=chist;
  IF NOT (SELECT gamification_data ? 'imported_resume' FROM public.user_profiles WHERE id=u) THEN
    RAISE EXCEPTION 'FALHOU R5-E: histórica direta limpou cache indevidamente'; END IF;

  -- Caminho novo/canônico continua válido para output e current.
  res := public.delete_saved_resume(cadp);
  IF (res->>'was_current')<>'false' THEN RAISE EXCEPTION 'FALHOU R5-E: adapted marcada current'; END IF;
  RESET ROLE;
  INSERT INTO public.saved_resumes(user_id,title,file_path,source,extraction_status,is_current_source)
    VALUES (u,'imp-rpc',u::text||'/rpc.pdf','imported','ready',false) RETURNING id INTO cimp_rpc;
  PERFORM public._promote_imported_and_activate(u,cimp_rpc,NULL);
  SET LOCAL ROLE authenticated;
  res := public.delete_saved_resume(cimp_rpc);
  IF (res->>'was_current')<>'true' OR EXISTS (SELECT 1 FROM public.saved_resumes WHERE id=cimp_rpc)
     OR (SELECT gamification_data ? 'imported_resume' FROM public.user_profiles WHERE id=u) THEN
    RAISE EXCEPTION 'FALHOU R5-E: RPC canônica não removeu current/cache (%)', res; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='Guardado') THEN
    RAISE EXCEPTION 'FALHOU R5-E: delete tocou profile_* (invariante 10)'; END IF;

  BEGIN
    PERFORM public.delete_saved_resume('00000000-0000-0000-0000-0000000000ff'::uuid);
    RAISE EXCEPTION 'FALHOU R5-E: RPC de row inexistente/alheia não rejeitou';
  EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL; END;
  RESET ROLE;
  IF NOT EXISTS (SELECT 1 FROM public.saved_resumes WHERE id=cother) THEN
    RAISE EXCEPTION 'FALHOU R5-E: row alheia sumiu'; END IF;
  RAISE NOTICE 'R5-E OK: HEAD^ blob→DELETE compatível; current limpa cache; RLS/profile intactos; RPC canônica OK';
END $t$;

-- R5-E-LOCK — prova executável da ordem advisory→tuple no DELETE legado.
-- Triggers BEFORE STATEMENT do mesmo evento disparam por nome: a probe `zzzz_*`
-- roda depois de `zzz_fence_stmt` e exige que o advisory já esteja concedido,
-- ainda antes de o executor tocar qualquer row.
DO $t$
DECLARE cleanup_def text;
BEGIN
  SELECT pg_get_functiondef('public._cleanup_import_cache_after_saved_resume_delete()'::regprocedure)
    INTO cleanup_def;
  IF cleanup_def ILIKE '%pg_advisory%' THEN
    RAISE EXCEPTION 'FALHOU R5-E-LOCK: cleanup ROW tenta adquirir advisory'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
     WHERE tgrelid='public.saved_resumes'::regclass
       AND tgname='zzz_fence_stmt' AND NOT tgisinternal
       AND (tgtype & 1)=0 AND (tgtype & 2)=2
       AND (tgtype & 4)=4 AND (tgtype & 8)=8 AND (tgtype & 16)=16
  ) THEN
    RAISE EXCEPTION 'FALHOU R5-E-LOCK: fence saved_resumes não é BEFORE STATEMENT I/U/D'; END IF;
END $t$;

CREATE OR REPLACE FUNCTION public._t_assert_saved_resume_fenced()
RETURNS trigger LANGUAGE plpgsql AS $t$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_locks
     WHERE pid=pg_backend_pid() AND locktype='advisory' AND granted
  ) THEN
    RAISE EXCEPTION 'saved_resumes DELETE chegou sem advisory em BEFORE STATEMENT';
  END IF;
  RETURN NULL;
END $t$;
DROP TRIGGER IF EXISTS zzzz_test_saved_resume_fenced ON public.saved_resumes;
CREATE TRIGGER zzzz_test_saved_resume_fenced
  BEFORE DELETE ON public.saved_resumes FOR EACH STATEMENT
  EXECUTE FUNCTION public._t_assert_saved_resume_fenced();

INSERT INTO public.saved_resumes(user_id,title,file_path,source)
  VALUES ('77777777-7777-7777-7777-777777777771','lock-probe',
          '77777777-7777-7777-7777-777777777771/lock.pdf','manual');
SELECT set_config('request.jwt.claims', '{"sub":"77777777-7777-7777-7777-777777777771"}', false);
SET ROLE authenticated;
DELETE FROM public.saved_resumes WHERE title='lock-probe';
RESET ROLE;
DROP TRIGGER zzzz_test_saved_resume_fenced ON public.saved_resumes;
DROP FUNCTION public._t_assert_saved_resume_fenced();
DO $$ BEGIN RAISE NOTICE 'R5-E-LOCK OK: saved_resumes adquire advisory em BEFORE STATEMENT, antes de tuple'; END $$;

-- R5-F — UM terminal por candidata+attempt (initial×reviewed mutuamente exclusivos);
-- hash canônico por ordem; reviewed exige perfil protegido; recibo único sempre.
DO $t$
DECLARE u uuid := '77777777-7777-7777-7777-777777777772';
  att uuid := '000000f0-0000-0000-0000-0000000000f0'; cand uuid; r1 jsonb; r2 jsonb; imp1 text; imp2 text;
  n int;
BEGIN
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', '{"sub":"77777777-7777-7777-7777-777777777772"}', false);

  -- Probe 1 + 5: initial → replay initial (resposta perdida) → mesmo resultado, 1 recibo.
  PERFORM public._t_reset(u);
  cand := public._t_seed_ready(u, 'Fi', '{"personal":{"first_name":"Zé"},"skills":[{"name":"Go"}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  r1 := public.apply_and_promote_imported_source(cand, att);
  imp1 := (SELECT gamification_data->'imported_resume'->>'imported_at' FROM public.user_profiles WHERE id=u);
  r2 := public.apply_and_promote_imported_source(cand, att);  -- REPLAY
  imp2 := (SELECT gamification_data->'imported_resume'->>'imported_at' FROM public.user_profiles WHERE id=u);
  RESET ROLE;
  IF r1 IS DISTINCT FROM r2 THEN RAISE EXCEPTION 'FALHOU R5-F1: replay initial devolveu resultado diferente'; END IF;
  IF imp1 IS DISTINCT FROM imp2 THEN RAISE EXCEPTION 'FALHOU R5-F1: replay initial re-promoveu (imported_at mudou)'; END IF;
  SELECT count(*) INTO n FROM public.import_apply_receipts WHERE candidate_id=cand AND attempt_id=att;
  IF n <> 1 THEN RAISE EXCEPTION 'FALHOU R5-F1: recibos=% (esperado 1)', n; END IF;

  -- Probe 2: initial → reviewed (cross-op) → SEM 2ª promoção, 1 recibo.
  SET LOCAL ROLE authenticated;
  r2 := public.apply_reviewed_conflicts_and_promote(cand, att, '[]'::jsonb);
  imp2 := (SELECT gamification_data->'imported_resume'->>'imported_at' FROM public.user_profiles WHERE id=u);
  RESET ROLE;
  IF (r2->>'promoted')<>'true' THEN RAISE EXCEPTION 'FALHOU R5-F2: reviewed pós-initial não reconheceu terminal'; END IF;
  IF imp1 IS DISTINCT FROM imp2 THEN RAISE EXCEPTION 'FALHOU R5-F2: reviewed pós-initial re-promoveu'; END IF;
  SELECT count(*) INTO n FROM public.import_apply_receipts WHERE candidate_id=cand AND attempt_id=att;
  IF n <> 1 THEN RAISE EXCEPTION 'FALHOU R5-F2: recibos=% (esperado 1 após cross-op)', n; END IF;

  -- Probe 3: reviewed → initial (cross-op) → SEM 2ª promoção, 1 recibo. Perfil PROTEGIDO.
  att := '000000f1-0000-0000-0000-0000000000f1';
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, first_name) VALUES (u, 'Pré');
  cand := public._t_seed_ready(u, 'Fr', '{"personal":{"first_name":"Zé"},"skills":[{"name":"Rust"}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  r1 := public.apply_reviewed_conflicts_and_promote(cand, att,
    jsonb_build_array(jsonb_build_object('kind','add','section','skill','source','Rust','value','Rust')));
  imp1 := (SELECT gamification_data->'imported_resume'->>'imported_at' FROM public.user_profiles WHERE id=u);
  r2 := public.apply_and_promote_imported_source(cand, att);  -- cross-op
  imp2 := (SELECT gamification_data->'imported_resume'->>'imported_at' FROM public.user_profiles WHERE id=u);
  RESET ROLE;
  IF (r2->'apply'->>'status')<>'success' OR (r2->>'promoted')<>'true' THEN
    RAISE EXCEPTION 'FALHOU R5-F3: initial pós-reviewed não reconheceu terminal (%)', r2; END IF;
  IF imp1 IS DISTINCT FROM imp2 THEN RAISE EXCEPTION 'FALHOU R5-F3: initial pós-reviewed re-promoveu'; END IF;
  SELECT count(*) INTO n FROM public.import_apply_receipts WHERE candidate_id=cand AND attempt_id=att;
  IF n <> 1 THEN RAISE EXCEPTION 'FALHOU R5-F3: recibos=% (esperado 1)', n; END IF;

  -- Probe 4: reviewed-vazio em perfil VAZIO → profile_empty_use_initial, 0 recibos.
  att := '000000f2-0000-0000-0000-0000000000f2';
  PERFORM public._t_reset(u);  -- zera o perfil protegido
  cand := public._t_seed_ready(u, 'Fe', '{"skills":[{"name":"X"}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  n := 0;
  BEGIN PERFORM public.apply_reviewed_conflicts_and_promote(cand, att, '[]'::jsonb);
  EXCEPTION WHEN SQLSTATE '22023' THEN n := 1; END;
  RESET ROLE;
  IF n <> 1 THEN RAISE EXCEPTION 'FALHOU R5-F4: reviewed-vazio em perfil vazio NÃO rejeitado'; END IF;
  IF EXISTS (SELECT 1 FROM public.import_apply_receipts WHERE candidate_id=cand AND attempt_id=att) THEN
    RAISE EXCEPTION 'FALHOU R5-F4: recibo gravado num reviewed rejeitado'; END IF;

  -- Probe 6: MESMO conjunto de escolhas em ordem DIFERENTE → replay idempotente.
  att := '000000f3-0000-0000-0000-0000000000f3';
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, first_name) VALUES (u, 'Pré');
  cand := public._t_seed_ready(u, 'Fo', '{"personal":{"first_name":"Zé"},"skills":[{"name":"Docker"},{"name":"K8s"}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  r1 := public.apply_reviewed_conflicts_and_promote(cand, att, jsonb_build_array(
    jsonb_build_object('kind','add','section','skill','source','Docker','value','Docker'),
    jsonb_build_object('kind','add','section','skill','source','K8s','value','K8s')));
  r2 := public.apply_reviewed_conflicts_and_promote(cand, att, jsonb_build_array(
    jsonb_build_object('kind','add','section','skill','source','K8s','value','K8s'),
    jsonb_build_object('kind','add','section','skill','source','Docker','value','Docker')));  -- ordem invertida
  RESET ROLE;
  IF r1 IS DISTINCT FROM r2 THEN RAISE EXCEPTION 'FALHOU R5-F6: replay em ordem diferente não idempotente (%/%)', r1, r2; END IF;
  SELECT count(*) INTO n FROM public.import_apply_receipts WHERE candidate_id=cand AND attempt_id=att;
  IF n <> 1 THEN RAISE EXCEPTION 'FALHOU R5-F6: recibos=% (esperado 1)', n; END IF;
  -- conjunto GENUINAMENTE diferente ainda é rejeitado.
  n := 0;
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM public.apply_reviewed_conflicts_and_promote(cand, att, jsonb_build_array(
    jsonb_build_object('kind','add','section','skill','source','Docker','value','Docker')));  -- só 1
  EXCEPTION WHEN SQLSTATE '22023' THEN n := 1; END;
  RESET ROLE;
  IF n <> 1 THEN RAISE EXCEPTION 'FALHOU R5-F6: conjunto diferente não rejeitado (already_applied_different)'; END IF;

  RAISE NOTICE 'R5-F OK: 1 terminal por candidata+attempt (initial×reviewed exclusivos); hash canônico por ordem; reviewed exige perfil protegido';
END $t$;

-- R5-G — MATRIZ DE FIDELIDADE: initial e reviewed preservam o MESMO payload canônico
-- (sentinelas únicas em todo campo/filha) + campos não-editáveis vêm do payload (tamper).
DO $t$
DECLARE u uuid := '77777777-7777-7777-7777-777777777773';
  att uuid := '000000f4-0000-0000-0000-0000000000f4'; cand uuid; res jsonb; agg jsonb;
  full_payload jsonb := jsonb_build_object(
    'personal', jsonb_build_object('first_name','Fid'),
    'experiences', jsonb_build_array(jsonb_build_object(
      'title','ExpT','company','ExpC','location','ExpL','start_date','2020-01-01','end_date','2021-01-01',
      'is_current',false,'confidence',0.77,'kind','estagio',
      'bullets', jsonb_build_array(
        jsonb_build_object('text','B1','angle','leadership','strength_score',88,'verb','Liderou'),
        jsonb_build_object('text','B2')))),
    'education', jsonb_build_array(jsonb_build_object(
      'institution','EduInst','institution_id','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','education_level','college',
      'education_status','cursando','current_semester',6,'current_school_year',3,'location','EduLoc','degree','EduDeg',
      'start_date','2019-01-01','end_date','2023-01-01','gpa',8.5,'max_gpa',10,'confidence',0.9,
      'majors', jsonb_build_array('MajorX'), 'minors', jsonb_build_array('MinorY'), 'activities', jsonb_build_array('ActZ'))),
    'projects', jsonb_build_array(jsonb_build_object(
      'name','ProjN','role','ProjR','context','ProjX','website','https://ex.com','description','ProjD',
      'start_date','2021-01-01','is_current',true,
      'bullets', jsonb_build_array(jsonb_build_object('text','PB1'), jsonb_build_object('text','PB2')))),
    'skills', jsonb_build_array(jsonb_build_object('name','SkillN','category','CatX')),
    'certifications', jsonb_build_array(jsonb_build_object('name','CertN','issuer','IssuerX','date','2022-05-01')),
    'languages', jsonb_build_array(jsonb_build_object('name','LangN','proficiency','advanced')),
    'awards', jsonb_build_array(jsonb_build_object('name','AwardN','date','2021-06-01')));
  eid uuid; edid uuid; pid uuid;
BEGIN
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', '{"sub":"77777777-7777-7777-7777-777777777773"}', false);
  PERFORM public._t_reset(u);
  cand := public._t_seed_ready(u, 'Full', full_payload, att);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(cand, att);  -- INICIAL (perfil vazio)
  RESET ROLE;
  IF (res->>'promoted')<>'true' THEN RAISE EXCEPTION 'FALHOU R5-G(initial): não promoveu (%)', res; END IF;
  -- experiência: kind, confidence, needs_review derivado, order_index, bullets angle/verb/strength/order
  SELECT id INTO eid FROM public.profile_experiences WHERE user_id=u AND title='ExpT';
  IF (SELECT kind FROM public.profile_experiences WHERE id=eid) <> 'estagio' THEN RAISE EXCEPTION 'FALHOU R5-G(initial): exp.kind dropado'; END IF;
  IF (SELECT confidence FROM public.profile_experiences WHERE id=eid) <> 0.77 THEN RAISE EXCEPTION 'FALHOU R5-G(initial): exp.confidence dropado'; END IF;
  IF (SELECT needs_review FROM public.profile_experiences WHERE id=eid) <> false THEN RAISE EXCEPTION 'FALHOU R5-G(initial): exp.needs_review derivação errada'; END IF;
  IF (SELECT order_index FROM public.profile_experiences WHERE id=eid) <> 0 THEN RAISE EXCEPTION 'FALHOU R5-G(initial): exp.order_index'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_bullets WHERE experience_id=eid AND text='B1' AND angle='leadership' AND verb='Liderou' AND strength_score=88 AND order_index=0) THEN
    RAISE EXCEPTION 'FALHOU R5-G(initial): bullet B1 angle/verb/strength/order dropado'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_bullets WHERE experience_id=eid AND text='B2' AND order_index=1) THEN
    RAISE EXCEPTION 'FALHOU R5-G(initial): bullet B2 ordinality'; END IF;
  -- educação: institution_id, level, status, semester, school_year, gpa/max_gpa, filhas
  SELECT id INTO edid FROM public.profile_education WHERE user_id=u AND institution='EduInst';
  IF (SELECT institution_id FROM public.profile_education WHERE id=edid) <> 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid THEN RAISE EXCEPTION 'FALHOU R5-G(initial): edu.institution_id dropado'; END IF;
  IF (SELECT education_level FROM public.profile_education WHERE id=edid) <> 'college'
     OR (SELECT education_status FROM public.profile_education WHERE id=edid) <> 'cursando'
     OR (SELECT current_semester FROM public.profile_education WHERE id=edid) <> 6
     OR (SELECT current_school_year FROM public.profile_education WHERE id=edid) <> 3
     OR (SELECT gpa FROM public.profile_education WHERE id=edid) <> 8.5
     OR (SELECT max_gpa FROM public.profile_education WHERE id=edid) <> 10 THEN
    RAISE EXCEPTION 'FALHOU R5-G(initial): campos de educação dropados'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_education_majors WHERE education_id=edid AND name='MajorX')
     OR NOT EXISTS (SELECT 1 FROM public.profile_education_minors WHERE education_id=edid AND name='MinorY')
     OR NOT EXISTS (SELECT 1 FROM public.profile_education_activities WHERE education_id=edid AND text='ActZ') THEN
    RAISE EXCEPTION 'FALHOU R5-G(initial): filhas de educação dropadas'; END IF;
  -- projeto: role, context E project_bullets (que o fill-empty inline NÃO gravava)
  SELECT id INTO pid FROM public.profile_projects WHERE user_id=u AND name='ProjN';
  IF (SELECT role FROM public.profile_projects WHERE id=pid) <> 'ProjR' OR (SELECT context FROM public.profile_projects WHERE id=pid) <> 'ProjX' THEN
    RAISE EXCEPTION 'FALHOU R5-G(initial): proj.role/context dropado'; END IF;
  IF (SELECT count(*) FROM public.profile_project_bullets WHERE project_id=pid) <> 2 THEN
    RAISE EXCEPTION 'FALHOU R5-G(initial): project_bullets dropados (fill-empty não produzia)'; END IF;
  -- listas: skill.category, cert.issuer/date, lang.proficiency, award.date
  IF (SELECT category FROM public.profile_skills WHERE user_id=u AND name='SkillN') <> 'CatX' THEN RAISE EXCEPTION 'FALHOU R5-G(initial): skill.category dropado'; END IF;
  IF (SELECT issuer FROM public.profile_certifications WHERE user_id=u AND name='CertN') <> 'IssuerX'
     OR (SELECT date FROM public.profile_certifications WHERE user_id=u AND name='CertN') <> '2022-05-01' THEN
    RAISE EXCEPTION 'FALHOU R5-G(initial): cert.issuer/date dropado'; END IF;
  IF (SELECT proficiency FROM public.profile_languages WHERE user_id=u AND name='LangN') <> 'advanced' THEN RAISE EXCEPTION 'FALHOU R5-G(initial): lang.proficiency dropado'; END IF;
  IF (SELECT date FROM public.profile_awards WHERE user_id=u AND name='AwardN') <> '2021-06-01' THEN RAISE EXCEPTION 'FALHOU R5-G(initial): award.date dropado'; END IF;

  -- ── REVIEWED (perfil protegido): mesmas sentinelas + TAMPER (não-editáveis do payload) ──
  att := '000000f5-0000-0000-0000-0000000000f5';
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, first_name) VALUES (u, 'Pré');  -- protegido
  cand := public._t_seed_ready(u, 'FullR', full_payload
    || jsonb_build_object('languages', jsonb_build_array(jsonb_build_object('name','LangN','proficiency','advanced')))
    || jsonb_build_object('certifications', jsonb_build_array(
         jsonb_build_object('name','AWS','issuer','Amazon','date','2020-01-01'),
         jsonb_build_object('name','AWS','issuer','Google','date','2021-01-01'))), att);
  SET LOCAL ROLE authenticated;
  agg := public.apply_reviewed_conflicts_and_promote(cand, att, jsonb_build_array(
    jsonb_build_object('kind','add_experience','company','ExpC','title','ExpT'),
    jsonb_build_object('kind','add_education','institution','EduInst','degree','EduDeg'),
    jsonb_build_object('kind','add','section','project','source','ProjN','value','ProjN'),
    -- TAMPER: cliente NÃO manda category (vem do payload); proficiency/issuer mentidos são IGNORADOS.
    jsonb_build_object('kind','add','section','skill','source','SkillN','value','SkillN'),
    jsonb_build_object('kind','add_lang','name','LangN','proficiency','MENTIRA','source','LangN'),
    jsonb_build_object('kind','add_cert','name','AWS','issuer','Google','source','AWS')));  -- desambigua p/ o 2º
  RESET ROLE;
  IF (agg->>'promoted')<>'true' THEN RAISE EXCEPTION 'FALHOU R5-G(reviewed): não promoveu (%)', agg; END IF;
  -- experiência inteira com fidelidade (kind + bullet strength)
  SELECT id INTO eid FROM public.profile_experiences WHERE user_id=u AND title='ExpT';
  IF (SELECT kind FROM public.profile_experiences WHERE id=eid) <> 'estagio' THEN RAISE EXCEPTION 'FALHOU R5-G(reviewed): add_experience.kind'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_bullets WHERE experience_id=eid AND text='B1' AND strength_score=88 AND verb='Liderou') THEN
    RAISE EXCEPTION 'FALHOU R5-G(reviewed): add_experience bullet fidelidade'; END IF;
  -- educação inteira: institution_id + semester
  SELECT id INTO edid FROM public.profile_education WHERE user_id=u AND institution='EduInst';
  IF (SELECT current_semester FROM public.profile_education WHERE id=edid) <> 6 THEN RAISE EXCEPTION 'FALHOU R5-G(reviewed): add_education.current_semester'; END IF;
  -- projeto: role/context + bullets
  SELECT id INTO pid FROM public.profile_projects WHERE user_id=u AND name='ProjN';
  IF (SELECT role FROM public.profile_projects WHERE id=pid) <> 'ProjR' THEN RAISE EXCEPTION 'FALHOU R5-G(reviewed): project add.role'; END IF;
  IF (SELECT count(*) FROM public.profile_project_bullets WHERE project_id=pid) <> 2 THEN RAISE EXCEPTION 'FALHOU R5-G(reviewed): project add bullets'; END IF;
  -- TAMPER: category do payload (não do cliente)
  IF (SELECT category FROM public.profile_skills WHERE user_id=u AND name='SkillN') <> 'CatX' THEN RAISE EXCEPTION 'FALHOU R5-G(reviewed): skill.category não veio do payload'; END IF;
  -- TAMPER: proficiency do payload (advanced), não a MENTIRA do cliente
  IF (SELECT proficiency FROM public.profile_languages WHERE user_id=u AND name='LangN') <> 'advanced' THEN RAISE EXCEPTION 'FALHOU R5-G(reviewed): lang.proficiency não veio do payload'; END IF;
  -- DUP-NAME cert: desambiguou p/ Google/2021 (o 2º), não Amazon/2020
  IF (SELECT issuer FROM public.profile_certifications WHERE user_id=u AND name='AWS') <> 'Google'
     OR (SELECT date FROM public.profile_certifications WHERE user_id=u AND name='AWS') <> '2021-01-01' THEN
    RAISE EXCEPTION 'FALHOU R5-G(reviewed): cert dup-name não desambiguou p/ o issuer proposto (issuer/date do payload)'; END IF;
  RAISE NOTICE 'R5-G OK: fidelidade completa initial×reviewed (sentinelas); category/issuer/proficiency do payload; cert dup-name desambiguada';
END $t$;

-- R5-C — contato profissional: relay/sintético não protege nem entra; profissional vence.
DO $t$
DECLARE u uuid := '77777777-7777-7777-7777-777777777774';
  att uuid := '000000f6-0000-0000-0000-0000000000f6'; cand uuid; agg jsonb; got text;
BEGIN
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', '{"sub":"77777777-7777-7777-7777-777777777774"}', false);
  PERFORM public._t_reset(u);

  -- (a) predicado protegido: só relay/sintético → NÃO protegido; profissional → protegido.
  INSERT INTO public.profile_personal(user_id, email) VALUES (u, 'x@privaterelay.appleid.com');
  IF public._profile_has_protected_data(u) THEN RAISE EXCEPTION 'FALHOU R5-C: relay isolado tratado como protegido'; END IF;
  UPDATE public.profile_personal SET email='phone_5511@stage.app' WHERE user_id=u;
  IF public._profile_has_protected_data(u) THEN RAISE EXCEPTION 'FALHOU R5-C: sintético isolado tratado como protegido'; END IF;
  UPDATE public.profile_personal SET email='ana@corp.com' WHERE user_id=u;
  IF NOT public._profile_has_protected_data(u) THEN RAISE EXCEPTION 'FALHOU R5-C: email profissional não protege'; END IF;

  -- (b) fill-empty: relay existente → SUBSTITUÍDO por profissional do CV; profissional → preservado.
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, email) VALUES (u, 'y@privaterelay.appleid.com');
  PERFORM public.save_profile_fill_empty(u, '{"personal":{"email":"real@corp.com"}}'::jsonb);
  IF (SELECT email FROM public.profile_personal WHERE user_id=u) <> 'real@corp.com' THEN
    RAISE EXCEPTION 'FALHOU R5-C: fill-empty não substituiu relay por profissional'; END IF;
  UPDATE public.profile_personal SET email='keep@corp.com' WHERE user_id=u;
  PERFORM public.save_profile_fill_empty(u, '{"personal":{"email":"other@corp.com"}}'::jsonb);
  IF (SELECT email FROM public.profile_personal WHERE user_id=u) <> 'keep@corp.com' THEN
    RAISE EXCEPTION 'FALHOU R5-C: fill-empty sobrescreveu email profissional existente'; END IF;

  -- (c) reviewed email CAS: applied (relay vivo → profissional); stale (mudou depois do diff); rejected (não-vinculado).
  att := '000000f7-0000-0000-0000-0000000000f7';
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, first_name, email) VALUES (u, 'Pré', 'z@privaterelay.appleid.com');
  cand := public._t_seed_ready(u, 'Ce', '{"personal":{"first_name":"Pré","email":"boa@corp.com"}}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  agg := public.apply_reviewed_conflicts_and_promote(cand, att, jsonb_build_array(
    jsonb_build_object('kind','personal','field','email','expected','z@privaterelay.appleid.com','value','boa@corp.com')));
  RESET ROLE;
  IF NOT (agg->'applied' @> '["email"]'::jsonb) THEN RAISE EXCEPTION 'FALHOU R5-C: email revisado não aplicou (%)', agg; END IF;
  IF (SELECT email FROM public.profile_personal WHERE user_id=u) <> 'boa@corp.com' THEN RAISE EXCEPTION 'FALHOU R5-C: email profissional não gravado'; END IF;
  -- stale: nova candidata, edição manual concorrente muda o email vivo depois do diff.
  att := '000000f8-0000-0000-0000-0000000000f8';
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, first_name, email) VALUES (u, 'Pré', 'z@privaterelay.appleid.com');
  cand := public._t_seed_ready(u, 'Cs', '{"personal":{"first_name":"Pré","email":"boa@corp.com"}}'::jsonb, att);
  UPDATE public.profile_personal SET email='manual@corp.com' WHERE user_id=u;  -- manual vence
  SET LOCAL ROLE authenticated;
  agg := public.apply_reviewed_conflicts_and_promote(cand, att, jsonb_build_array(
    jsonb_build_object('kind','personal','field','email','expected','z@privaterelay.appleid.com','value','boa@corp.com')));
  RESET ROLE;
  IF NOT (agg->'stale' @> '["email"]'::jsonb) THEN RAISE EXCEPTION 'FALHOU R5-C: email não virou stale sob edição concorrente (%)', agg; END IF;
  IF (SELECT email FROM public.profile_personal WHERE user_id=u) <> 'manual@corp.com' THEN RAISE EXCEPTION 'FALHOU R5-C: stale sobrescreveu o manual'; END IF;
  RAISE NOTICE 'R5-C OK: relay/sintético não protege nem entra; fill-empty substitui relay/preserva profissional; email revisado CAS manual-vence';
END $t$;

-- R5-I — complete_import_extraction: p_meta={} REJEITADO (fail-closed); populado → ready.
DO $t$
DECLARE u uuid := '77777777-7777-7777-7777-777777777775';
  lc jsonb; cand uuid; att uuid; n int; tok uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', '{"sub":"77777777-7777-7777-7777-777777777775"}', false);
  PERFORM public._t_reset(u);
  SET LOCAL ROLE authenticated;
  lc := public.begin_import_source('C',public._t_import_path(u,tok),'x.pdf',tok);
  cand := (lc->>'candidate_id')::uuid; att := (lc->>'attempt_id')::uuid;
  RESET ROLE;
  SET LOCAL ROLE service_role;
  n := 0;
  BEGIN PERFORM public.complete_import_extraction(cand, att, '{"skills":[{"name":"Go"}]}'::jsonb, 'RAW', '{"parsed":true}'::jsonb, '{}'::jsonb);
  EXCEPTION WHEN SQLSTATE '22023' THEN n := 1; END;
  RESET ROLE;  -- verificações de status como postgres (service_role não tem SELECT no harness)
  IF n <> 1 THEN RAISE EXCEPTION 'FALHOU R5-I: p_meta={} aceito (deveria ser missing_meta)'; END IF;
  IF (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) = 'ready' THEN
    RAISE EXCEPTION 'FALHOU R5-I: candidata virou ready com meta vazio'; END IF;
  -- (Round 6 adj6) ESTRUTURA MÍNIMA: meta NÃO-VAZIO mas sem parser_version/parsed_at
  -- (blob acidental) TAMBÉM é rejeitado — não basta "objeto não-vazio".
  SET LOCAL ROLE service_role;
  n := 0;
  BEGIN PERFORM public.complete_import_extraction(cand, att, '{"skills":[{"name":"Go"}]}'::jsonb, 'RAW', '{"parsed":true}'::jsonb, '{"parser_source":"v1"}'::jsonb);
  EXCEPTION WHEN SQLSTATE '22023' THEN n := 1; END;
  RESET ROLE;
  IF n <> 1 THEN RAISE EXCEPTION 'FALHOU adj6: meta {parser_source} (sem parser_version/parsed_at) aceito'; END IF;
  IF (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) = 'ready' THEN
    RAISE EXCEPTION 'FALHOU adj6: candidata virou ready com meta estruturalmente inválido'; END IF;
  -- `->>` coage número/objeto para texto; por isso o SQL precisa exigir o tipo
  -- JSON string explicitamente, igual aos validadores TypeScript/Dart.
  SET LOCAL ROLE service_role;
  n := 0;
  BEGIN PERFORM public.complete_import_extraction(cand, att, '{"skills":[{"name":"Go"}]}'::jsonb, 'RAW', '{"parsed":true}'::jsonb,
    '{"parser_version":1,"parsed_at":2}'::jsonb);
  EXCEPTION WHEN SQLSTATE '22023' THEN n := 1; END;
  RESET ROLE;
  IF n <> 1 OR (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) = 'ready' THEN
    RAISE EXCEPTION 'FALHOU R7-meta: parser_version/parsed_at numéricos foram aceitos'; END IF;
  -- meta populado (estrutura mínima válida) → ready.
  SET LOCAL ROLE service_role;
  PERFORM public.complete_import_extraction(cand, att, '{"skills":[{"name":"Go"}]}'::jsonb, 'RAW', '{"parsed":true}'::jsonb, '{"parser_version":"v1","parsed_at":"2026-01-01T00:00:00Z"}'::jsonb);
  RESET ROLE;
  IF (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) <> 'ready' THEN
    RAISE EXCEPTION 'FALHOU R5-I: meta populado não concluiu ready'; END IF;
  RAISE NOTICE 'R7-META OK: vazio/chaves ausentes/tipos não-string rejeitados; strings → ready';
END $t$;

-- ════════════════════════════════════════════════════════════════════════════
-- R5-REV — regressões dos 5 achados CONFIRMADOS pela revisão adversarial da Round 5
-- ════════════════════════════════════════════════════════════════════════════

-- R5-REV1 — bullet vazio NÃO derruba a experiência nem promove perfil vazio: o bullet
-- é PULADO, o pai é gravado, promove com conteúdo (era: sub-savepoint revertia o pai
-- e has_content promovia perfil vazio como sucesso).
DO $t$
DECLARE u uuid := '77777777-7777-7777-7777-777777777776';
  att uuid := '000000fa-0000-0000-0000-0000000000fa'; cand uuid; res jsonb; eid uuid;
BEGIN
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', '{"sub":"77777777-7777-7777-7777-777777777776"}', false);
  PERFORM public._t_reset(u);
  cand := public._t_seed_ready(u, 'BB', jsonb_build_object('experiences', jsonb_build_array(jsonb_build_object(
    'title','Dev','company','ACME','start_date','2020-01-01','end_date','2021-01-01',
    'bullets', jsonb_build_array(jsonb_build_object('text','   '), jsonb_build_object('text','Fez X'))))), att);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(cand, att);
  RESET ROLE;
  IF (res#>>'{apply,status}') <> 'success' OR (res->>'promoted') <> 'true' THEN
    RAISE EXCEPTION 'FALHOU R5-REV1: bullet vazio derrubou o apply (%)', res; END IF;
  SELECT id INTO eid FROM public.profile_experiences WHERE user_id=u AND title='Dev';
  IF eid IS NULL THEN RAISE EXCEPTION 'FALHOU R5-REV1: experiência não gravada (pai revertido)'; END IF;
  IF (SELECT count(*) FROM public.profile_bullets WHERE experience_id=eid) <> 1 THEN
    RAISE EXCEPTION 'FALHOU R5-REV1: bullet vazio não foi pulado (esperado 1 bullet válido)'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_bullets WHERE experience_id=eid AND text='Fez X') THEN
    RAISE EXCEPTION 'FALHOU R5-REV1: bullet VÁLIDO perdido'; END IF;
  RAISE NOTICE 'R5-REV1 OK: bullet vazio pulado, pai gravado, promove com conteúdo';
END $t$;

-- R5-REV2 — _profile_has_protected_data alinhado ao Dart: um perfil protegido SÓ por
-- phone_country_code / date_of_birth / CEP / endereço / availability é PROTEGIDO, e a
-- revisão NÃO é rejeitada com profile_empty_use_initial.
DO $t$
DECLARE u uuid := '77777777-7777-7777-7777-777777777777';
  att uuid := '000000fb-0000-0000-0000-0000000000fb'; cand uuid; agg jsonb;
BEGIN
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', '{"sub":"77777777-7777-7777-7777-777777777777"}', false);
  PERFORM public._t_reset(u);
  -- cada um dos 5 campos, isolado, deve proteger:
  INSERT INTO public.profile_personal(user_id, availability) VALUES (u, 'immediate');
  IF NOT public._profile_has_protected_data(u) THEN RAISE EXCEPTION 'FALHOU R5-REV2: availability não protege'; END IF;
  UPDATE public.profile_personal SET availability=NULL, phone_country_code='+55' WHERE user_id=u;
  IF NOT public._profile_has_protected_data(u) THEN RAISE EXCEPTION 'FALHOU R5-REV2: phone_country_code não protege'; END IF;
  UPDATE public.profile_personal SET phone_country_code=NULL, date_of_birth='2000-01-01' WHERE user_id=u;
  IF NOT public._profile_has_protected_data(u) THEN RAISE EXCEPTION 'FALHOU R5-REV2: date_of_birth não protege'; END IF;
  UPDATE public.profile_personal SET date_of_birth=NULL, location_street_address='Rua X, 1' WHERE user_id=u;
  IF NOT public._profile_has_protected_data(u) THEN RAISE EXCEPTION 'FALHOU R5-REV2: location_street_address não protege'; END IF;
  -- e a revisão sobre esse perfil "só availability" NÃO é rejeitada:
  UPDATE public.profile_personal SET location_street_address=NULL, availability='immediate' WHERE user_id=u;
  cand := public._t_seed_ready(u, 'PR', '{"skills":[{"name":"Go"}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  agg := public.apply_reviewed_conflicts_and_promote(cand, att,
    jsonb_build_array(jsonb_build_object('kind','add','section','skill','source','Go','value','Go')));
  RESET ROLE;
  IF (agg->>'promoted') <> 'true' THEN RAISE EXCEPTION 'FALHOU R5-REV2: revisão rejeitada num perfil protegido só por availability (%)', agg; END IF;
  RAISE NOTICE 'R5-REV2 OK: predicado protegido alinhado ao Dart (5 campos); revisão não rejeitada';
END $t$;

-- R5-REV3 — cas_write_profile_scalar (single-row apply) também blinda o email: relay
-- rejeitado (non_public_email); profissional aplicado.
DO $t$
DECLARE u uuid := '77777777-7777-7777-7777-777777777778'; denied boolean; r text;
BEGIN
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', '{"sub":"77777777-7777-7777-7777-777777777778"}', false);
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id) VALUES (u);
  SET LOCAL ROLE authenticated;
  denied := false;
  BEGIN PERFORM public.cas_write_profile_scalar(u, 'email', '', 'x@privaterelay.appleid.com', NULL, NULL);
  EXCEPTION WHEN SQLSTATE '22023' THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'FALHOU R5-REV3: cas_write_profile_scalar aceitou relay como email'; END IF;
  r := public.cas_write_profile_scalar(u, 'email', '', 'ana@corp.com', NULL, NULL);
  RESET ROLE;
  IF r <> 'applied' THEN RAISE EXCEPTION 'FALHOU R5-REV3: email profissional não aplicou (%)', r; END IF;
  IF (SELECT email FROM public.profile_personal WHERE user_id=u) <> 'ana@corp.com' THEN
    RAISE EXCEPTION 'FALHOU R5-REV3: email profissional não gravado'; END IF;
  RAISE NOTICE 'R5-REV3 OK: cas_write_profile_scalar rejeita relay, aplica profissional';
END $t$;

-- ════════════════════════════════════════════════════════════════════════════
-- ROUND 6 — bloqueadores da revisão independente da Round 5
-- ════════════════════════════════════════════════════════════════════════════

-- R6-B1 — Apple Private Relay / sintético NUNCA vira contato profissional, INCLUSIVE
-- no PRIMEIRO insert (profile_personal ainda não existe). Relay-só = sem conteúdo.
DO $t$
DECLARE u uuid := '77777777-7777-7777-7777-777777777781';
  att uuid := '00000601-0000-0000-0000-000000000601'; cand uuid; res jsonb; n int;
BEGIN
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', '{"sub":"77777777-7777-7777-7777-777777777781"}', false);

  -- (a) has_content: relay/sintético isolado NÃO é conteúdo.
  IF public._profile_payload_has_content('{"personal":{"email":"abc@privaterelay.appleid.com"}}'::jsonb) THEN
    RAISE EXCEPTION 'FALHOU R6-B1a: relay isolado contou como conteúdo'; END IF;
  IF public._profile_payload_has_content('{"personal":{"email":"phone_5511@stage.app"}}'::jsonb) THEN
    RAISE EXCEPTION 'FALHOU R6-B1a: sintético isolado contou como conteúdo'; END IF;
  IF public._profile_payload_has_content('{"personal":{"email":"x@private.icloud.com"}}'::jsonb) THEN
    RAISE EXCEPTION 'FALHOU R6-B1a: icloud relay isolado contou como conteúdo'; END IF;
  IF NOT public._profile_payload_has_content('{"personal":{"email":"ana@corp.com"}}'::jsonb) THEN
    RAISE EXCEPTION 'FALHOU R6-B1a: email profissional não contou'; END IF;

  -- (b) apply inicial com payload SÓ relay → empty_payload, sem row/receipt/current.
  PERFORM public._t_reset(u);
  cand := public._t_seed_ready(u, 'Relay', '{"personal":{"email":"abc@privaterelay.appleid.com"}}'::jsonb, att);
  SET LOCAL ROLE authenticated; n := 0;
  BEGIN PERFORM public.apply_and_promote_imported_source(cand, att);
  EXCEPTION WHEN SQLSTATE '22023' THEN n := 1; END;  -- empty_payload
  RESET ROLE;
  IF n <> 1 THEN RAISE EXCEPTION 'FALHOU R6-B1b: payload só-relay não rejeitado'; END IF;
  IF EXISTS (SELECT 1 FROM public.profile_personal WHERE user_id=u) THEN
    RAISE EXCEPTION 'FALHOU R6-B1b: deixou linha profile_personal vazia'; END IF;
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=cand) THEN
    RAISE EXCEPTION 'FALHOU R6-B1b: promoveu fonte com payload só-relay'; END IF;
  IF EXISTS (SELECT 1 FROM public.import_apply_receipts WHERE candidate_id=cand) THEN
    RAISE EXCEPTION 'FALHOU R6-B1b: criou recibo terminal com payload só-relay'; END IF;

  -- (c) PRIMEIRO insert (sem profile_personal): fill-empty com relay+skill → skill aplica,
  -- email NÃO persiste (relay descartado); depois um email profissional preenche.
  att := '00000602-0000-0000-0000-000000000602';
  PERFORM public._t_reset(u);
  cand := public._t_seed_ready(u, 'Mix', '{"personal":{"email":"y@privaterelay.appleid.com"},"skills":[{"name":"Go"}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(cand, att);
  RESET ROLE;
  IF (res->>'promoted') <> 'true' THEN RAISE EXCEPTION 'FALHOU R6-B1c: skill válido não promoveu (%)', res; END IF;
  IF (SELECT email FROM public.profile_personal WHERE user_id=u) IS NOT NULL THEN
    RAISE EXCEPTION 'FALHOU R6-B1c: relay persistido no PRIMEIRO insert'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=u AND name='Go') THEN
    RAISE EXCEPTION 'FALHOU R6-B1c: skill válido não aplicado (relay derrubou tudo)'; END IF;
  -- profissional preenche o email vazio via fill-empty:
  PERFORM public.save_profile_fill_empty(u, '{"personal":{"email":"real@corp.com"}}'::jsonb);
  IF (SELECT email FROM public.profile_personal WHERE user_id=u) <> 'real@corp.com' THEN
    RAISE EXCEPTION 'FALHOU R6-B1c: profissional não preencheu email vazio'; END IF;
  RAISE NOTICE 'R6-B1 OK: relay/sintético fora do PRIMEIRO insert e do has_content; relay-só=sem conteúdo; profissional vence';
END $t$;

-- R7-B2 — seções compostas são atômicas: qualquer item significativo inválido
-- desfaz todos os irmãos, falha o apply global e nunca promove/recibo/cache.
-- Falha rebaixa a MESMA candidata para failed; reextração no MESMO attempt pode
-- concluir payload corrigido e então aplicar/promover.
DO $t$
DECLARE u uuid := '77777777-7777-7777-7777-777777777782';
  att uuid; cand uuid; res jsonb; n int;
  v_case text; v_sec text; v_payload jsonb;
BEGIN
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', '{"sub":"77777777-7777-7777-7777-777777777782"}', false);

  -- Probe 1: education com institution_id inválido → seção falha → NÃO promove.
  att := '00000611-0000-0000-0000-000000000611';
  PERFORM public._t_reset(u);
  cand := public._t_seed_ready(u, 'E1', '{"education":[{"institution":"Universidade X","institution_id":"bad-uuid"}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(cand, att);
  RESET ROLE;
  IF (res->>'promoted') = 'true' THEN RAISE EXCEPTION 'FALHOU R6-B2p1: promoveu com institution_id inválido (%)', res; END IF;
  IF (SELECT count(*) FROM public.profile_education WHERE user_id=u) <> 0 THEN RAISE EXCEPTION 'FALHOU R6-B2p1: education gravada apesar do erro'; END IF;
  IF (SELECT is_current_source FROM public.saved_resumes WHERE id=cand) THEN RAISE EXCEPTION 'FALHOU R6-B2p1: current no 1º erro'; END IF;
  IF EXISTS (SELECT 1 FROM public.import_apply_receipts WHERE candidate_id=cand) THEN RAISE EXCEPTION 'FALHOU R6-B2p1: recibo no 1º erro'; END IF;
  IF (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) <> 'failed'
     OR (res->>'retryable') <> 'true' THEN
    RAISE EXCEPTION 'FALHOU R7-B2retry: falha não declarou/reificou retry (%)', res; END IF;
  IF (SELECT gamification_data->'imported_resume' FROM public.user_profiles WHERE id=u) IS NOT NULL THEN
    RAISE EXCEPTION 'FALHOU R7-B2p1: cache ativado na falha'; END IF;

  -- MESMA candidate+attempt: Edge retoma failed→extracting, reextrai e complete
  -- substitui o payload antigo de forma vinculada; novo apply promove.
  UPDATE public.saved_resumes SET extraction_status='extracting',
    extraction_started_at=now(), extraction_completed_at=NULL,
    extraction_error_code=NULL, is_current_source=false WHERE id=cand;
  SET LOCAL ROLE service_role;
  PERFORM public.complete_import_extraction(cand, att,
    jsonb_build_object('education',jsonb_build_array(jsonb_build_object(
      'institution','Universidade X','institution_id','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'))),
    'RAW-CORRIGIDO', '{"parsed":true}'::jsonb,
    '{"parser_version":"v2","parsed_at":"2026-07-16T00:00:00Z"}'::jsonb);
  RESET ROLE;
  IF (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) <> 'ready'
     OR (SELECT extraction_attempt_id FROM public.saved_resumes WHERE id=cand) <> att THEN
    RAISE EXCEPTION 'FALHOU R7-B2retry: complete corrigido não preservou attempt/ready'; END IF;
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(cand, att);
  RESET ROLE;
  IF (res->>'promoted') <> 'true'
     OR (SELECT count(*) FROM public.profile_education WHERE user_id=u) <> 1
     OR NOT EXISTS (SELECT 1 FROM public.import_apply_receipts WHERE candidate_id=cand AND attempt_id=att) THEN
    RAISE EXCEPTION 'FALHOU R7-B2retry: mesma candidata corrigida não concluiu (%)', res; END IF;

  -- Probe 2: experiência válida com bullet de id inválido → seção falha → NÃO promove.
  att := '00000612-0000-0000-0000-000000000612';
  PERFORM public._t_reset(u);
  cand := public._t_seed_ready(u, 'E2', '{"experiences":[{"title":"Dev","company":"C","start_date":"2020-01-01","end_date":"2021-01-01","bullets":[{"id":"bad-uuid","text":"Resultado"}]}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(cand, att);
  RESET ROLE;
  IF (res->>'promoted') = 'true' THEN RAISE EXCEPTION 'FALHOU R6-B2p2: promoveu com bullet id inválido (%)', res; END IF;
  IF (SELECT count(*) FROM public.profile_experiences WHERE user_id=u) <> 0 THEN RAISE EXCEPTION 'FALHOU R6-B2p2: experiência gravada apesar do erro'; END IF;
  IF EXISTS (SELECT 1 FROM public.import_apply_receipts WHERE candidate_id=cand) THEN RAISE EXCEPTION 'FALHOU R6-B2p2: recibo no 1º erro'; END IF;
  IF (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) <> 'failed' THEN
    RAISE EXCEPTION 'FALHOU R7-B2p2: candidata não failed'; END IF;

  -- Probe 3: projeto com bullet id inválido → seção falha → NÃO promove.
  att := '00000613-0000-0000-0000-000000000613';
  PERFORM public._t_reset(u);
  cand := public._t_seed_ready(u, 'E3', '{"projects":[{"name":"Projeto X","start_date":"2024-01-01","bullets":[{"id":"bad-uuid","text":"X"}]}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(cand, att);
  RESET ROLE;
  IF (res->>'promoted') = 'true' THEN RAISE EXCEPTION 'FALHOU R6-B2p3: promoveu projeto com bullet id inválido (%)', res; END IF;
  IF (SELECT count(*) FROM public.profile_projects WHERE user_id=u) <> 0 THEN RAISE EXCEPTION 'FALHOU R6-B2p3: projeto gravado apesar do erro'; END IF;
  IF (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) <> 'failed' THEN
    RAISE EXCEPTION 'FALHOU R7-B2p3: candidata não failed'; END IF;

  -- Corrigido: institution_id válido → promove e grava.
  att := '00000614-0000-0000-0000-000000000614';
  PERFORM public._t_reset(u);
  cand := public._t_seed_ready(u, 'E4', jsonb_build_object('education', jsonb_build_array(jsonb_build_object(
    'institution','Universidade X','institution_id','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'))), att);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(cand, att);
  RESET ROLE;
  IF (res->>'promoted') <> 'true' THEN RAISE EXCEPTION 'FALHOU R6-B2corr: payload corrigido não promoveu (%)', res; END IF;
  IF (SELECT count(*) FROM public.profile_education WHERE user_id=u) <> 1 THEN RAISE EXCEPTION 'FALHOU R6-B2corr: education corrigida não gravada'; END IF;

  -- Mistura experience válida+inválida: seção INTEIRA desfaz; nada terminal.
  att := '00000615-0000-0000-0000-000000000615';
  PERFORM public._t_reset(u);
  cand := public._t_seed_ready(u, 'E5', '{"experiences":[
    {"title":"Good","company":"C","start_date":"2020-01-01","end_date":"2021-01-01","bullets":[{"text":"ok"}]},
    {"title":"Bad","company":"D","start_date":"2022-01-01","end_date":"2023-01-01","bullets":[{"id":"bad-uuid","text":"y"}]}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(cand, att);
  RESET ROLE;
  IF (res->>'promoted') <> 'false'
     OR (res#>>'{apply,status}') <> 'failure'
     OR (res->>'retryable') <> 'true'
     OR NOT (res#>'{apply,failed}' @> '["experiences"]'::jsonb)
     OR EXISTS (SELECT 1 FROM public.profile_experiences WHERE user_id=u)
     OR EXISTS (SELECT 1 FROM public.profile_bullets b JOIN public.profile_experiences e ON e.id=b.experience_id WHERE e.user_id=u)
     OR EXISTS (SELECT 1 FROM public.import_apply_receipts WHERE candidate_id=cand)
     OR (SELECT is_current_source FROM public.saved_resumes WHERE id=cand)
     OR (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) <> 'failed' THEN
    RAISE EXCEPTION 'FALHOU R7-B2mix-exp: descarte parcial/terminal (%)', res; END IF;
  IF (SELECT gamification_data->'imported_resume' FROM public.user_profiles WHERE id=u) IS NOT NULL THEN
    RAISE EXCEPTION 'FALHOU R7-B2mix-exp: cache ativado'; END IF;

  -- Mistura education válida + institution_id inválido: zero pais/filhas.
  att := '00000616-0000-0000-0000-000000000616';
  PERFORM public._t_reset(u);
  cand := public._t_seed_ready(u, 'E6', '{"education":[
    {"institution":"Boa","majors":["Computação"]},
    {"institution":"Ruim","institution_id":"bad-uuid","majors":["Dados"]}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(cand, att);
  RESET ROLE;
  IF (res->>'promoted') <> 'false'
     OR (res->>'retryable') <> 'true'
     OR NOT (res#>'{apply,failed}' @> '["education"]'::jsonb)
     OR EXISTS (SELECT 1 FROM public.profile_education WHERE user_id=u)
     OR EXISTS (SELECT 1 FROM public.profile_education_majors m JOIN public.profile_education e ON e.id=m.education_id WHERE e.user_id=u)
     OR EXISTS (SELECT 1 FROM public.import_apply_receipts WHERE candidate_id=cand)
     OR (SELECT is_current_source FROM public.saved_resumes WHERE id=cand)
     OR (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) <> 'failed' THEN
    RAISE EXCEPTION 'FALHOU R7-B2mix-edu: seção/terminal sobreviveu (%)', res; END IF;

  -- Mistura project válido + bullet-id inválido: zero pais/filhas.
  att := '00000617-0000-0000-0000-000000000617';
  PERFORM public._t_reset(u);
  cand := public._t_seed_ready(u, 'E7', '{"projects":[
    {"name":"Bom","bullets":[{"text":"ok"}]},
    {"name":"Ruim","bullets":[{"id":"bad-uuid","text":"x"}]}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(cand, att);
  RESET ROLE;
  IF (res->>'promoted') <> 'false'
     OR (res->>'retryable') <> 'true'
     OR NOT (res#>'{apply,failed}' @> '["projects"]'::jsonb)
     OR EXISTS (SELECT 1 FROM public.profile_projects WHERE user_id=u)
     OR EXISTS (SELECT 1 FROM public.profile_project_bullets b JOIN public.profile_projects p ON p.id=b.project_id WHERE p.user_id=u)
     OR EXISTS (SELECT 1 FROM public.import_apply_receipts WHERE candidate_id=cand)
     OR (SELECT is_current_source FROM public.saved_resumes WHERE id=cand)
     OR (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) <> 'failed' THEN
    RAISE EXCEPTION 'FALHOU R7-B2mix-proj: seção/terminal sobreviveu (%)', res; END IF;

  -- Revisão adversarial final: os classificadores de "ruído" precisam olhar
  -- TODOS os campos semânticos. Antes, estes três irmãos parciais eram pulados;
  -- o item bom persistia e a candidata recebia promoção+receipt terminal.
  -- is_current=false/default é scaffold; true é uma afirmação real.
  att := '00000618-0000-0000-0000-000000000618';
  PERFORM public._t_reset(u);
  cand := public._t_seed_ready(u, 'E8', '{"experiences":[
    {"title":"Boa","company":"C","start_date":"2020-01-01","end_date":"2021-01-01"},
    {"is_current":true}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(cand, att);
  RESET ROLE;
  IF (res->>'promoted') <> 'false'
     OR NOT (res#>'{apply,failed}' @> '["experiences"]'::jsonb)
     OR EXISTS (SELECT 1 FROM public.profile_experiences WHERE user_id=u)
     OR EXISTS (SELECT 1 FROM public.import_apply_receipts WHERE candidate_id=cand)
     OR (SELECT is_current_source FROM public.saved_resumes WHERE id=cand)
     OR (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) <> 'failed' THEN
    RAISE EXCEPTION 'FALHOU R7-B2semantic-exp: is_current=true foi descartado/terminal (%)', res; END IF;

  -- location/GPA/semestre/ano são dados acadêmicos reais, não metadata. Sem
  -- institution, qualquer um deles torna o item inválido e derruba a seção.
  att := '00000619-0000-0000-0000-000000000619';
  PERFORM public._t_reset(u);
  cand := public._t_seed_ready(u, 'E9', '{"education":[
    {"institution":"Boa"},
    {"location":"SP","gpa":9.5,"current_semester":5,"current_school_year":2}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(cand, att);
  RESET ROLE;
  IF (res->>'promoted') <> 'false'
     OR NOT (res#>'{apply,failed}' @> '["education"]'::jsonb)
     OR EXISTS (SELECT 1 FROM public.profile_education WHERE user_id=u)
     OR EXISTS (SELECT 1 FROM public.import_apply_receipts WHERE candidate_id=cand)
     OR (SELECT is_current_source FROM public.saved_resumes WHERE id=cand)
     OR (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) <> 'failed' THEN
    RAISE EXCEPTION 'FALHOU R7-B2semantic-edu: dado acadêmico foi descartado/terminal (%)', res; END IF;

  att := '0000061a-0000-0000-0000-00000000061a';
  PERFORM public._t_reset(u);
  cand := public._t_seed_ready(u, 'E10', '{"projects":[
    {"name":"Bom"},
    {"is_current":true}]}'::jsonb, att);
  SET LOCAL ROLE authenticated;
  res := public.apply_and_promote_imported_source(cand, att);
  RESET ROLE;
  IF (res->>'promoted') <> 'false'
     OR NOT (res#>'{apply,failed}' @> '["projects"]'::jsonb)
     OR EXISTS (SELECT 1 FROM public.profile_projects WHERE user_id=u)
     OR EXISTS (SELECT 1 FROM public.import_apply_receipts WHERE candidate_id=cand)
     OR (SELECT is_current_source FROM public.saved_resumes WHERE id=cand)
     OR (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) <> 'failed' THEN
    RAISE EXCEPTION 'FALHOU R7-B2semantic-proj: is_current=true foi descartado/terminal (%)', res; END IF;

  -- Datas opcionais continuam opcionais quando null/vazias. Se vieram NÃO-VAZIAS,
  -- porém não parseáveis, são uma tentativa real. O mesmo vale para
  -- semestre/ano fracionários: JSON number, mas não inteiro persistível. Cada
  -- caso abaixo derruba a seção inteira, sem conversão silenciosa para NULL.
  FOR v_case, v_sec, v_payload IN
    SELECT * FROM (VALUES
      ('exp.end_date','experiences','{"experiences":[
        {"title":"Boa","company":"C","start_date":"2020-01-01","end_date":"2021-01-01"},
        {"title":"Ruim","company":"D","start_date":"2022-01-01","end_date":"2024"}]}'::jsonb),
      ('edu.start_date','education','{"education":[
        {"institution":"Boa"},{"institution":"Ruim","start_date":"2020"}]}'::jsonb),
      ('edu.end_date','education','{"education":[
        {"institution":"Boa"},{"institution":"Ruim","end_date":"2024"}]}'::jsonb),
      ('edu.current_semester','education','{"education":[
        {"institution":"Boa"},{"institution":"Ruim","current_semester":1.5}]}'::jsonb),
      ('edu.current_school_year','education','{"education":[
        {"institution":"Boa"},{"institution":"Ruim","current_school_year":2.5}]}'::jsonb),
      ('project.start_date','projects','{"projects":[
        {"name":"Bom"},{"name":"Ruim","start_date":"2020"}]}'::jsonb),
      ('project.end_date','projects','{"projects":[
        {"name":"Bom"},{"name":"Ruim","end_date":"2024"}]}'::jsonb)
    ) AS cases(case_name, section_name, payload)
  LOOP
    att := gen_random_uuid();
    PERFORM public._t_reset(u);
    cand := public._t_seed_ready(u, 'DATE-'||v_case, v_payload, att);
    SET LOCAL ROLE authenticated;
    res := public.apply_and_promote_imported_source(cand, att);
    RESET ROLE;
    IF (res->>'promoted') <> 'false'
       OR NOT (res#>'{apply,failed}' @> jsonb_build_array(v_sec))
       OR EXISTS (SELECT 1 FROM public.profile_experiences WHERE user_id=u)
       OR EXISTS (SELECT 1 FROM public.profile_education WHERE user_id=u)
       OR EXISTS (SELECT 1 FROM public.profile_projects WHERE user_id=u)
       OR EXISTS (SELECT 1 FROM public.import_apply_receipts WHERE candidate_id=cand)
       OR (SELECT is_current_source FROM public.saved_resumes WHERE id=cand)
       OR (SELECT extraction_status FROM public.saved_resumes WHERE id=cand) <> 'failed' THEN
      RAISE EXCEPTION 'FALHOU R7-B2coercion %: valor inválido foi anulado/terminal (%)', v_case, res;
    END IF;
  END LOOP;

  RAISE NOTICE 'R7-B2 OK: mixed exp/edu/project (campos semânticos + datas/inteiros inválidos) atômicos; zero terminal/cache; mesma candidate+attempt reextrai e conclui';
END $t$;

-- REAPPLY real das duas migrations sobre estado populado: precisa ser idempotente
-- (DDL, backfills, triggers, grants e policies) e manter os invariantes cruzados.
\ir ../migrations/20260714120000_saved_resumes_import_metadata.sql
\ir ../migrations/20260714130000_save_profile_fill_empty.sql
DO $t$
BEGIN
  IF EXISTS (
    SELECT user_id FROM public.saved_resumes
     WHERE is_latest_legacy_source GROUP BY user_id HAVING count(*) > 1
  ) THEN RAISE EXCEPTION 'FALHOU REAPPLY: mais de um marker por user'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.saved_resumes legacy
     WHERE legacy.is_latest_legacy_source
       AND EXISTS (SELECT 1 FROM public.saved_resumes canonical
                    WHERE canonical.user_id=legacy.user_id
                      AND canonical.is_current_source
                      AND canonical.source='imported'
                      AND canonical.extraction_status='ready')
  ) THEN RAISE EXCEPTION 'FALHOU REAPPLY: marker coexistiu com current'; END IF;
  IF has_function_privilege('public','public._guard_user_profile_import_cache()','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.delete_user()','EXECUTE')
     OR NOT has_table_privilege('authenticated','public.saved_resumes','DELETE')
     OR has_table_privilege('service_role','public.saved_resumes','DELETE')
     OR has_table_privilege('anon','public.saved_resumes','DELETE') THEN
    RAISE EXCEPTION 'FALHOU REAPPLY: grants finais divergiram'; END IF;
  RAISE NOTICE 'T-REAPPLY OK: migrations idempotentes sobre estado populado; marker/current/grants íntegros';
END $t$;

SELECT 'ALL_SQL_TESTS_OK' AS result;
