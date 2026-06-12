-- Testes da Fase 2 (T2.1 do PLANO-FASE-2): RPC get_feed_page — filtros,
-- score, keyset all-ties, jitter determinístico, salário e sentinela do
-- estado B. SEM Docker/shadow DB, rodando contra prod com ROLLBACK
-- GARANTIDO: tudo num único DO block que termina em
-- RAISE EXCEPTION 'FASE2_TESTS_OK' — o erro final desfaz a transação
-- inteira. Ver erro com essa mensagem = TODOS os testes passaram.
--
-- Disciplina (herdada da F1): transação curta; NUNCA tocar user_profiles
-- (trigger http notify_new_signup dispara webhook REAL). jobs,
-- profile_desired_titles, profile_job_preferences, profile_other_locations
-- e swipe_actions são seguros (triggers locais; bridge de swipe só age em
-- applied=true — aqui usamos disliked/applied=false).
--
-- Sandbox: vagas sintéticas com area 'ZZTest Área F2' — filtrar por essa
-- área isola os asserts do catálogo real (que muda todo dia).
--
-- Usuário: conta interna 3eaf8faa-… As prefs dela são DELETADAS dentro da
-- transação (rollback restaura) pra construir cada cenário do zero.

DO $$
DECLARE
  v_user constant uuid := '3eaf8faa-a905-4d80-aced-40be7781f623';
  v_sandbox constant text := 'ZZTest Área F2';
  v_company uuid;
  j_swiped uuid; j_match uuid; j_remote uuid; j_inactive uuid; j_expired uuid;
  j_sal_low uuid; j_sal_high uuid;
  v_count int; v_total bigint; v_avail bigint; v_total2 bigint;
  v_score int; v_ok boolean;
  v_frozen timestamptz := now();
  v_ids uuid[]; v_ids2 uuid[]; v_all uuid[]; v_page uuid[];
  v_cursor_rank numeric; v_cursor_id uuid;
  v_pages int;
  r record;
BEGIN
  SELECT id INTO v_company FROM companies LIMIT 1;
  IF v_company IS NULL THEN RAISE EXCEPTION 'pré-condição: nenhuma company'; END IF;

  ------------------------------------------------------------------
  -- Setup: zera prefs da conta interna (dentro da tx) + vagas sandbox
  ------------------------------------------------------------------
  DELETE FROM profile_desired_titles  WHERE user_id = v_user;
  DELETE FROM profile_other_locations WHERE user_id = v_user;
  DELETE FROM profile_job_preferences WHERE user_id = v_user;

  INSERT INTO jobs (company_id, title, description, work_model, job_type, area,
                    location_city, location_state, published_at)
  VALUES (v_company, '[TEST-F2] swiped', 'x', 'presencial', 'estagio', v_sandbox,
          'São Paulo', 'SP', now())
  RETURNING id INTO j_swiped;

  INSERT INTO jobs (company_id, title, description, work_model, job_type, area,
                    location_city, location_state, published_at)
  VALUES (v_company, '[TEST-F2] match 63', 'x', 'presencial', 'estagio', v_sandbox,
          'Curitiba', 'PR', now())
  RETURNING id INTO j_match;

  INSERT INTO jobs (company_id, title, description, work_model, job_type, area,
                    published_at)
  VALUES (v_company, '[TEST-F2] remoto', 'x', 'remoto', 'trainee', v_sandbox, now())
  RETURNING id INTO j_remote;

  INSERT INTO jobs (company_id, title, description, work_model, job_type, area,
                    is_active, published_at)
  VALUES (v_company, '[TEST-F2] inativa', 'x', 'presencial', 'estagio', v_sandbox,
          false, now())
  RETURNING id INTO j_inactive;

  INSERT INTO jobs (company_id, title, description, work_model, job_type, area,
                    deadline, published_at)
  VALUES (v_company, '[TEST-F2] vencida', 'x', 'presencial', 'estagio', v_sandbox,
          now() - interval '1 day', now())
  RETURNING id INTO j_expired;

  INSERT INTO jobs (company_id, title, description, work_model, job_type, area,
                    location_city, location_state, salary_min, published_at)
  VALUES (v_company, '[TEST-F2] salário baixo', 'x', 'presencial', 'temporario',
          v_sandbox, 'Santos', 'SP', 100000, now())
  RETURNING id INTO j_sal_low;

  INSERT INTO jobs (company_id, title, description, work_model, job_type, area,
                    location_city, location_state, salary_min, published_at)
  VALUES (v_company, '[TEST-F2] salário alto', 'x', 'presencial', 'temporario',
          v_sandbox, 'Santos', 'SP', 300000, now())
  RETURNING id INTO j_sal_high;

  -- swipe na j_swiped (rejected/applied=false → bridge da F1 não age;
  -- vocabulário real do check: liked|rejected)
  INSERT INTO swipe_actions (user_id, job_id, action)
  VALUES (v_user, j_swiped, 'rejected');

  ------------------------------------------------------------------
  -- T0: sem autenticação → exceção; role anon → sem EXECUTE
  ------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', '', true);
  v_ok := false;
  BEGIN
    SELECT count(*) INTO v_count FROM get_feed_page();
  EXCEPTION WHEN OTHERS THEN
    v_ok := (SQLERRM LIKE '%autenticado%');
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'T0 FALHOU: sem auth deveria lançar exceção'; END IF;

  v_ok := false;
  BEGIN
    EXECUTE 'SET LOCAL ROLE anon';
    SELECT count(*) INTO v_count FROM get_feed_page();
    EXECUTE 'RESET ROLE';
  EXCEPTION WHEN insufficient_privilege THEN
    v_ok := true;
    EXECUTE 'RESET ROLE';
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'T0b FALHOU: anon não deveria ter EXECUTE'; END IF;
  RAISE NOTICE 'T0 ok: auth obrigatório + anon sem EXECUTE';

  -- autentica como a conta interna pro resto dos testes
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text, true);

  ------------------------------------------------------------------
  -- T1: exclusões — swipada, inativa e deadline vencida fora do feed
  ------------------------------------------------------------------
  SELECT count(*) FILTER (WHERE g.job_id = j_swiped),
         count(*) FILTER (WHERE g.job_id = j_inactive),
         count(*) FILTER (WHERE g.job_id = j_expired),
         count(*) FILTER (WHERE g.job_id = j_match),
         count(*)
    INTO v_count, v_total, v_avail, v_score, v_pages
    FROM get_feed_page(p_limit := 50, p_filter_areas := array[v_sandbox]) g;
  IF v_count <> 0 THEN RAISE EXCEPTION 'T1 FALHOU: vaga swipada apareceu'; END IF;
  IF v_total <> 0 THEN RAISE EXCEPTION 'T1 FALHOU: vaga inativa apareceu'; END IF;
  IF v_avail <> 0 THEN RAISE EXCEPTION 'T1 FALHOU: vaga vencida apareceu'; END IF;
  IF v_score <> 1 THEN RAISE EXCEPTION 'T1 FALHOU: j_match não apareceu'; END IF;
  IF v_pages <> 4 THEN RAISE EXCEPTION 'T1 FALHOU: sandbox esperava 4 vagas, achou %', v_pages; END IF;
  RAISE NOTICE 'T1 ok: exclusões (swipe, inativa, vencida) + 4 vagas sandbox';

  ------------------------------------------------------------------
  -- T2: null-permissividade — args null = sem filtro; '{}' = null
  ------------------------------------------------------------------
  SELECT g.total_after_filters, g.total_available INTO v_total, v_avail
    FROM get_feed_page(p_limit := 1) g LIMIT 1;
  IF v_total IS DISTINCT FROM v_avail OR v_total = 0 THEN
    RAISE EXCEPTION 'T2 FALHOU: sem args, after_filters (%) ≠ available (%)', v_total, v_avail;
  END IF;
  SELECT g.total_after_filters INTO v_total2
    FROM get_feed_page(p_limit := 1,
                       p_filter_areas := '{}'::text[],
                       p_filter_locations := '{}'::text[],
                       p_filter_work_models := '{}'::text[],
                       p_filter_job_types := '{}'::text[]) g LIMIT 1;
  IF v_total2 IS DISTINCT FROM v_total THEN
    RAISE EXCEPTION 'T2 FALHOU: args vazios (%) ≠ args null (%)', v_total2, v_total;
  END IF;
  RAISE NOTICE 'T2 ok: null-permissividade (% vagas; ''{}''=null)', v_total;

  ------------------------------------------------------------------
  -- T3: clamp do limit — 0→1, null→20, 200→50
  ------------------------------------------------------------------
  SELECT count(*) INTO v_count FROM get_feed_page(p_limit := 0, p_filter_areas := array[v_sandbox]);
  IF v_count <> 1 THEN RAISE EXCEPTION 'T3 FALHOU: limit 0 deveria clampar pra 1 (%)', v_count; END IF;
  SELECT count(*) INTO v_count FROM get_feed_page(p_limit := 200);
  IF v_count <> 50 THEN RAISE EXCEPTION 'T3 FALHOU: limit 200 deveria clampar pra 50 (%)', v_count; END IF;
  SELECT count(*) INTO v_count FROM get_feed_page(p_limit := null);
  IF v_count <> 20 THEN RAISE EXCEPTION 'T3 FALHOU: limit null deveria virar 20 (%)', v_count; END IF;
  RAISE NOTICE 'T3 ok: clamp do limit (0→1, null→20, 200→50)';

  ------------------------------------------------------------------
  -- T4: score exato — área+tipo casam, cidade+modelo não → 50/80 = 63
  ------------------------------------------------------------------
  INSERT INTO profile_desired_titles (user_id, title, order_index)
  VALUES (v_user, v_sandbox, 0);
  INSERT INTO profile_job_preferences (user_id, primary_location_city, work_mode, job_types)
  VALUES (v_user, 'Porto Alegre', array['remote'], array['estagio']);

  SELECT g.score INTO v_score
    FROM get_feed_page(p_limit := 50, p_filter_areas := array[v_sandbox]) g
   WHERE g.job_id = j_match;
  IF v_score <> 63 THEN RAISE EXCEPTION 'T4 FALHOU: esperava 63, veio %', v_score; END IF;
  SELECT (g.reason_area AND g.reason_job_type
          AND NOT g.reason_location AND NOT g.reason_work_model AND NOT g.reason_salary)
    INTO v_ok
    FROM get_feed_page(p_limit := 50, p_filter_areas := array[v_sandbox]) g
   WHERE g.job_id = j_match;
  IF NOT v_ok THEN RAISE EXCEPTION 'T4 FALHOU: reasons errados pro 63'; END IF;
  RAISE NOTICE 'T4 ok: score 63 (área+tipo / 80) + reasons coerentes';

  ------------------------------------------------------------------
  -- T5: guard anti-inflação — só área declarada + vaga remota →
  --     m_loc NÃO entra no numerador (score 100, nunca 150)
  ------------------------------------------------------------------
  DELETE FROM profile_job_preferences WHERE user_id = v_user;
  SELECT g.score, g.reason_location INTO v_score, v_ok
    FROM get_feed_page(p_limit := 50, p_filter_areas := array[v_sandbox]) g
   WHERE g.job_id = j_remote;
  IF v_score <> 100 THEN
    RAISE EXCEPTION 'T5 FALHOU: esperava 100 (30/30), veio % (inflação do m_loc?)', v_score;
  END IF;
  IF v_ok THEN RAISE EXCEPTION 'T5 FALHOU: reason_location deveria ser false (dim não declarada)'; END IF;
  SELECT max(g.score) INTO v_score FROM get_feed_page(p_limit := 50) g;
  IF v_score > 100 THEN RAISE EXCEPTION 'T5 FALHOU: score >100 no catálogo (%)', v_score; END IF;
  RAISE NOTICE 'T5 ok: dimensão não-declarada fora do numerador (100, nunca >100)';

  ------------------------------------------------------------------
  -- T6: salário (REV-1) — sem salário passa permissiva (não pontua),
  --     abaixo do mínimo cai, acima passa e pontua +10
  ------------------------------------------------------------------
  -- estado: só área declarada (30) + p_min_salary (10) → denominador 40
  SELECT count(*) INTO v_count
    FROM get_feed_page(p_limit := 50, p_filter_areas := array[v_sandbox],
                       p_min_salary := 200000) g
   WHERE g.job_id = j_sal_low;
  IF v_count <> 0 THEN RAISE EXCEPTION 'T6 FALHOU: vaga abaixo do mínimo passou'; END IF;
  SELECT g.score, g.reason_salary INTO v_score, v_ok
    FROM get_feed_page(p_limit := 50, p_filter_areas := array[v_sandbox],
                       p_min_salary := 200000) g
   WHERE g.job_id = j_sal_high;
  IF v_score <> 100 OR NOT v_ok THEN
    RAISE EXCEPTION 'T6 FALHOU: acima do mínimo esperava 100 + reason_salary, veio % / %', v_score, v_ok;
  END IF;
  SELECT g.score, g.reason_salary INTO v_score, v_ok
    FROM get_feed_page(p_limit := 50, p_filter_areas := array[v_sandbox],
                       p_min_salary := 200000) g
   WHERE g.job_id = j_match;
  IF v_score <> 75 OR v_ok THEN
    RAISE EXCEPTION 'T6 FALHOU: sem salário esperava 75 (30/40) sem reason, veio % / %', v_score, v_ok;
  END IF;
  RAISE NOTICE 'T6 ok: salário permissivo no null, excludente abaixo, +10 acima';

  ------------------------------------------------------------------
  -- T7: ALL-TIES (REV-1) — usuário sem NENHUMA pref (rank = só jitter),
  --     paginando o catálogo inteiro: zero overlap, zero gap
  ------------------------------------------------------------------
  DELETE FROM profile_desired_titles WHERE user_id = v_user;
  v_all := '{}'::uuid[]; v_cursor_rank := NULL; v_cursor_id := NULL;
  v_total := NULL; v_pages := 0;
  LOOP
    v_page := '{}'::uuid[];
    FOR r IN
      SELECT * FROM get_feed_page(p_limit := 50,
                                  p_cursor_rank := v_cursor_rank,
                                  p_cursor_id := v_cursor_id,
                                  p_frozen_at := v_frozen)
    LOOP
      IF r.job_id IS NULL THEN CONTINUE; END IF;  -- sentinela
      IF v_total IS NULL THEN v_total := r.total_after_filters; END IF;
      v_page := v_page || r.job_id;
      v_cursor_rank := r.rank_score; v_cursor_id := r.job_id;
    END LOOP;
    EXIT WHEN coalesce(array_length(v_page, 1), 0) = 0;
    IF EXISTS (SELECT 1 FROM unnest(v_page) p WHERE p = ANY(v_all)) THEN
      RAISE EXCEPTION 'T7 FALHOU: overlap entre páginas (keyset quebrado no all-ties)';
    END IF;
    v_all := v_all || v_page;
    v_pages := v_pages + 1;
    IF v_pages > 60 THEN RAISE EXCEPTION 'T7 FALHOU: paginação não converge'; END IF;
  END LOOP;
  IF coalesce(array_length(v_all, 1), 0) <> v_total THEN
    RAISE EXCEPTION 'T7 FALHOU: união das páginas (%) ≠ total_after_filters (%)',
      coalesce(array_length(v_all, 1), 0), v_total;
  END IF;
  RAISE NOTICE 'T7 ok: all-ties — % páginas, % vagas, zero overlap, zero gap', v_pages, v_total;

  ------------------------------------------------------------------
  -- T8: jitter — determinístico no mesmo p_frozen_at, rotaciona por dia,
  --     e clamp do futuro (frozen futuro = hoje)
  ------------------------------------------------------------------
  SELECT array_agg(g.job_id ORDER BY g.ord) INTO v_ids
    FROM get_feed_page(p_limit := 50, p_frozen_at := v_frozen)
         WITH ORDINALITY g(job_id, score, rank_score, ra, rl, rwm, rjt, rs, taf, tav, ord);
  SELECT array_agg(g.job_id ORDER BY g.ord) INTO v_ids2
    FROM get_feed_page(p_limit := 50, p_frozen_at := v_frozen)
         WITH ORDINALITY g(job_id, score, rank_score, ra, rl, rwm, rjt, rs, taf, tav, ord);
  IF v_ids IS DISTINCT FROM v_ids2 THEN
    RAISE EXCEPTION 'T8 FALHOU: mesmo p_frozen_at, ordens diferentes';
  END IF;
  SELECT array_agg(g.job_id ORDER BY g.ord) INTO v_ids2
    FROM get_feed_page(p_limit := 50, p_frozen_at := v_frozen - interval '1 day')
         WITH ORDINALITY g(job_id, score, rank_score, ra, rl, rwm, rjt, rs, taf, tav, ord);
  IF v_ids = v_ids2 THEN
    RAISE EXCEPTION 'T8 FALHOU: dias diferentes deveriam rotacionar a ordem';
  END IF;
  SELECT array_agg(g.job_id ORDER BY g.ord) INTO v_ids2
    FROM get_feed_page(p_limit := 50, p_frozen_at := v_frozen + interval '10 years')
         WITH ORDINALITY g(job_id, score, rank_score, ra, rl, rwm, rjt, rs, taf, tav, ord);
  IF v_ids IS DISTINCT FROM v_ids2 THEN
    RAISE EXCEPTION 'T8 FALHOU: frozen futuro deveria clampar pra now() (= mesma ordem)';
  END IF;
  RAISE NOTICE 'T8 ok: jitter determinístico na sessão, rotaciona por dia, clamp do futuro';

  ------------------------------------------------------------------
  -- T9: sentinela do estado B — filtros zeram tudo → 1 row só-totais
  ------------------------------------------------------------------
  v_count := 0;
  SELECT count(*), min(g.total_after_filters), min(g.total_available)
    INTO v_count, v_total, v_avail
    FROM get_feed_page(p_limit := 20,
                       p_filter_work_models := array['__inexistente__']) g;
  IF v_count <> 1 THEN RAISE EXCEPTION 'T9 FALHOU: esperava 1 row sentinela, veio %', v_count; END IF;
  SELECT (g.job_id IS NULL AND g.score IS NULL) INTO v_ok
    FROM get_feed_page(p_limit := 20,
                       p_filter_work_models := array['__inexistente__']) g;
  IF NOT v_ok THEN RAISE EXCEPTION 'T9 FALHOU: sentinela deveria ter job_id/score null'; END IF;
  IF v_total <> 0 OR v_avail = 0 THEN
    RAISE EXCEPTION 'T9 FALHOU: sentinela esperava after=0/available>0, veio %/%', v_total, v_avail;
  END IF;
  RAISE NOTICE 'T9 ok: sentinela do estado B (after=0, available=%)', v_avail;

  ------------------------------------------------------------------
  RAISE NOTICE '═══ TODOS OS TESTES PASSARAM — rollback intencional a seguir ═══';
  RAISE EXCEPTION 'FASE2_TESTS_OK';
END $$;
