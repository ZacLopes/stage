-- Testes da Fase 3 PR1 (T3.4 schema, PLANO-FASE-3 §4/D3 + §7): tabela
-- outbound_clicks (RLS own-insert/own-select + anon negado) e a coluna
-- applications.external_url + o CHECK manual_fields. SEM Docker, rodando
-- contra prod com ROLLBACK GARANTIDO: tudo num único DO block que termina em
-- RAISE EXCEPTION 'FASE3_PR1_TESTS_OK' — o erro final desfaz a transação.
-- Ver erro com essa mensagem = TODOS os testes passaram.
--
-- Disciplina (herdada da F1/F2): transação curta; NUNCA tocar user_profiles
-- (trigger http notify_new_signup dispara webhook REAL). applications,
-- application_events e outbound_clicks são seguros (triggers locais; tudo
-- some no rollback). RLS exercitada com SET LOCAL ROLE + request.jwt.claims.
--
-- Usuário: conta interna 3eaf8faa-… (real em auth.users).

DO $$
DECLARE
  v_user  constant uuid := '3eaf8faa-a905-4d80-aced-40be7781f623';
  v_other constant uuid := gen_random_uuid();           -- não existe em auth.users
  v_cnt   int;
  v_url   text;
  v_failed boolean;
BEGIN
  -- Contexto de usuário autenticado v_user (claims setadas como owner, antes do
  -- switch de role; são transação-local e sobrevivem ao SET ROLE).
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;

  -- T1 — own-insert em outbound_clicks (job_id null) passa e é visível.
  INSERT INTO public.outbound_clicks (user_id, job_id) VALUES (v_user, NULL);
  SELECT count(*) INTO v_cnt FROM public.outbound_clicks WHERE user_id = v_user;
  IF v_cnt < 1 THEN RAISE EXCEPTION 'T1 FAIL: own-insert não visível'; END IF;

  -- T2 — insert para OUTRO user_id é barrado pela RLS WITH CHECK (avaliada
  -- antes do FK; v_other nem existe em auth.users).
  v_failed := false;
  BEGIN
    INSERT INTO public.outbound_clicks (user_id, job_id) VALUES (v_other, NULL);
  EXCEPTION WHEN others THEN v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'T2 FAIL: RLS deixou inserir p/ outro user'; END IF;

  -- T3 — own-select isola: com claims de v_other, a row de v_user some.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
  SELECT count(*) INTO v_cnt FROM public.outbound_clicks;
  IF v_cnt <> 0 THEN RAISE EXCEPTION 'T3 FAIL: own-select vazou % rows de outro user', v_cnt; END IF;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text, true);

  -- T4 — applications.external_url persiste num manual (type=manual, job_id null,
  -- external_company/title presentes → passa applications_job_or_manual +
  -- applications_manual_fields; RLS applications_insert_own permite manual).
  INSERT INTO public.applications
    (user_id, job_id, type, status, external_company, external_title, external_url)
  VALUES (v_user, NULL, 'manual', 'submitted',
          'Empresa Teste F3', 'Analista Teste F3', 'https://exemplo.com/vaga?x=1');
  SELECT external_url INTO v_url FROM public.applications
    WHERE user_id = v_user AND type = 'manual' AND external_title = 'Analista Teste F3';
  IF v_url IS DISTINCT FROM 'https://exemplo.com/vaga?x=1'
    THEN RAISE EXCEPTION 'T4 FAIL: external_url não persistiu (%)', v_url; END IF;

  -- T5 — manual sem external_company viola applications_manual_fields.
  v_failed := false;
  BEGIN
    INSERT INTO public.applications (user_id, job_id, type, status, external_title)
    VALUES (v_user, NULL, 'manual', 'submitted', 'Sem Empresa');
  EXCEPTION WHEN others THEN v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'T5 FAIL: manual sem external_company passou'; END IF;

  RESET ROLE;

  -- T6 — anon não insere em outbound_clicks (revoke all from anon).
  SET LOCAL ROLE anon;
  v_failed := false;
  BEGIN
    INSERT INTO public.outbound_clicks (user_id, job_id) VALUES (v_user, NULL);
  EXCEPTION WHEN others THEN v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'T6 FAIL: anon conseguiu inserir em outbound_clicks'; END IF;
  RESET ROLE;

  RAISE EXCEPTION 'FASE3_PR1_TESTS_OK';
END $$;
