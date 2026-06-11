-- Testes da Fase 1 (V11 do PLANO-FASE-1): máquina de estados, imutabilidade,
-- bridges e idempotência — SEM Docker/shadow DB (não instalado), rodando
-- contra prod com ROLLBACK GARANTIDO: tudo vive num único DO block que
-- termina em RAISE EXCEPTION 'FASE1_TESTS_OK' — o erro final desfaz a
-- transação inteira. Ver erro com essa mensagem = TODOS os testes passaram.
--
-- Disciplina (decisão da revisão): transação curta; NUNCA tocar user_profiles
-- (trigger http notify_new_signup dispararia webhook real). profile_personal,
-- campaigns, target_jobs, swipe_actions e applications são seguros (triggers
-- locais). Sequences avançadas são inofensivas.
--
-- Usuário sintético: conta interna internal-fase0-test@stage.app
-- (3eaf8faa-a905-4d80-aced-40be7781f623) — sem swipes/campaigns/profile.

DO $$
DECLARE
  v_user constant uuid := '3eaf8faa-a905-4d80-aced-40be7781f623';
  v_job uuid;
  v_app uuid;
  v_stage_app uuid;
  v_tj uuid;
  v_count int;
  v_status text;
  v_ok boolean;
BEGIN
  SELECT id INTO v_job FROM jobs WHERE is_active LIMIT 1;
  IF v_job IS NULL THEN RAISE EXCEPTION 'pré-condição: nenhuma vaga ativa'; END IF;

  ------------------------------------------------------------------
  -- T1: criação manual + evento inicial (actor system — sem JWT aqui)
  ------------------------------------------------------------------
  INSERT INTO applications (user_id, type, external_company, external_title)
  VALUES (v_user, 'manual', 'Empresa Teste', 'Cargo Teste')
  RETURNING id INTO v_app;
  SELECT count(*) INTO v_count FROM application_events
   WHERE application_id = v_app AND from_status IS NULL
     AND to_status = 'submitted' AND actor = 'system';
  IF v_count <> 1 THEN RAISE EXCEPTION 'T1 FALHOU: evento inicial ausente/errado'; END IF;
  RAISE NOTICE 'T1 ok: criação manual + evento inicial (system)';

  ------------------------------------------------------------------
  -- T2: como USER (simula JWT) — pipeline + RETROCESSO POR DESIGN
  ------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text, true);

  UPDATE applications SET status = 'in_review' WHERE id = v_app;
  UPDATE applications SET status = 'offer'     WHERE id = v_app;
  UPDATE applications SET status = 'in_review' WHERE id = v_app;  -- retrocesso: por design
  UPDATE applications SET status = 'hired'     WHERE id = v_app;
  SELECT count(*) INTO v_count FROM application_events
   WHERE application_id = v_app AND actor = 'user';
  IF v_count <> 4 THEN RAISE EXCEPTION 'T2 FALHOU: esperava 4 eventos user, achei %', v_count; END IF;
  RAISE NOTICE 'T2 ok: pipeline user + retrocesso offer→in_review (por design) + 4 eventos';

  -- hired é terminal — nem user nem admin movem.
  v_ok := false;
  BEGIN
    UPDATE applications SET status = 'in_review' WHERE id = v_app;
  EXCEPTION WHEN check_violation THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'T2b FALHOU: hired deveria ser terminal'; END IF;
  RAISE NOTICE 'T2b ok: hired é terminal';

  ------------------------------------------------------------------
  -- T3: imutabilidade para actor user (lupa #2)
  ------------------------------------------------------------------
  v_ok := false;
  BEGIN
    UPDATE applications SET type = 'external_confirmed' WHERE id = v_app;
  EXCEPTION WHEN check_violation THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'T3 FALHOU: user conseguiu flipar type'; END IF;

  v_ok := false;
  BEGIN
    UPDATE applications SET sla_deadline = now() WHERE id = v_app;
  EXCEPTION WHEN check_violation THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'T3b FALHOU: user setou sla_deadline'; END IF;
  RAISE NOTICE 'T3 ok: imutabilidade (type, sla_deadline) para user';

  ------------------------------------------------------------------
  -- T4: type=stage — user só pode withdrawn; admin move; reabertura
  ------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', '', true);   -- volta a system p/ inserir stage
  INSERT INTO applications (user_id, job_id, type, status)
  VALUES (v_user, v_job, 'stage', 'submitted') RETURNING id INTO v_stage_app;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  v_ok := false;
  BEGIN
    UPDATE applications SET status = 'in_review' WHERE id = v_stage_app;
  EXCEPTION WHEN check_violation THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'T4 FALHOU: user moveu stage→in_review'; END IF;

  UPDATE applications SET status = 'withdrawn' WHERE id = v_stage_app;  -- permitido

  PERFORM set_config('app.actor', 'admin', true);
  UPDATE applications SET status = 'submitted' WHERE id = v_stage_app;  -- reabertura admin (stage)
  UPDATE applications SET status = 'in_review', sla_deadline = now() + interval '7 days'
   WHERE id = v_stage_app;                                              -- admin move + seta SLA
  PERFORM set_config('app.actor', '', true);
  RAISE NOTICE 'T4 ok: stage (user só withdrawn; admin reabre, move e seta SLA)';

  ------------------------------------------------------------------
  -- T5: BRIDGE 1 — caminho user-JWT (swipe applied=true → application)
  ------------------------------------------------------------------
  INSERT INTO swipe_actions (user_id, job_id, action, applied, applied_at)
  VALUES (v_user, v_job, 'liked', true, now());
  -- o job v_job já tem a application stage (T4) deste user → ON CONFLICT DO
  -- NOTHING: não duplica. Usa um SEGUNDO job pra testar a criação real.
  SELECT count(*) INTO v_count FROM applications WHERE user_id = v_user AND job_id = v_job;
  IF v_count <> 1 THEN RAISE EXCEPTION 'T5 FALHOU: unicidade (user,job) violada (%)', v_count; END IF;

  SELECT id INTO v_job FROM jobs WHERE is_active AND id <> v_job LIMIT 1;
  INSERT INTO swipe_actions (user_id, job_id, action, applied, applied_at)
  VALUES (v_user, v_job, 'liked', true, now());
  SELECT status INTO v_status FROM applications WHERE user_id = v_user AND job_id = v_job;
  IF v_status IS DISTINCT FROM 'submitted' THEN
    RAISE EXCEPTION 'T5b FALHOU: bridge não criou application (status=%)', v_status; END IF;
  SELECT count(*) INTO v_count FROM bridge_activity WHERE bridge = 'swipe_applied';
  IF v_count < 2 THEN RAISE EXCEPTION 'T5c FALHOU: bridge_activity não registrou'; END IF;
  RAISE NOTICE 'T5 ok: Bridge 1 cria application + unicidade + bridge_activity';

  ------------------------------------------------------------------
  -- T6: BRIDGE 1 — caminho SERVICE-ROLE/Studio (sem JWT → actor system)
  ------------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', '', true);
  UPDATE swipe_actions SET applied = false WHERE user_id = v_user AND job_id = v_job;
  SELECT status INTO v_status FROM applications WHERE user_id = v_user AND job_id = v_job;
  IF v_status IS DISTINCT FROM 'withdrawn' THEN
    RAISE EXCEPTION 'T6 FALHOU: undo via system não virou withdrawn (status=%)', v_status; END IF;
  RAISE NOTICE 'T6 ok: Bridge 1 undo via service-role (system→withdrawn)';

  ------------------------------------------------------------------
  -- T7: idempotência do backfill (sintético): re-INSERT = 0 rows
  ------------------------------------------------------------------
  INSERT INTO applications (user_id, job_id, type, status, application_method, created_at)
  SELECT sa.user_id, sa.job_id, 'external_confirmed', 'submitted',
         COALESCE(j.application_method, 'url'), COALESCE(sa.applied_at, sa.created_at)
  FROM swipe_actions sa JOIN jobs j ON j.id = sa.job_id
  WHERE sa.applied = true AND sa.user_id = v_user
  ON CONFLICT (user_id, job_id) WHERE job_id IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 0 THEN RAISE EXCEPTION 'T7 FALHOU: backfill re-executado inseriu % rows', v_count; END IF;
  RAISE NOTICE 'T7 ok: backfill idempotente (re-execução = 0 rows)';

  ------------------------------------------------------------------
  -- T8: BRIDGE 2 — campaign → onboarding_completed_at (INSERT mínimo)
  ------------------------------------------------------------------
  INSERT INTO target_jobs (user_id, is_skipped) VALUES (v_user, true) RETURNING id INTO v_tj;
  INSERT INTO campaigns (user_id, target_job_id, name, status)
  VALUES (v_user, v_tj, 'Campanha Teste F1', 'draft');
  SELECT count(*) INTO v_count FROM profile_personal
   WHERE user_id = v_user AND onboarding_completed_at IS NOT NULL;
  IF v_count <> 1 THEN RAISE EXCEPTION 'T8 FALHOU: onboarding_completed_at não setado'; END IF;
  RAISE NOTICE 'T8 ok: Bridge 2 com INSERT mínimo em profile_personal';

  ------------------------------------------------------------------
  -- T9: ON DELETE RESTRICT — vaga com candidatura não se deleta
  ------------------------------------------------------------------
  v_ok := false;
  BEGIN
    DELETE FROM jobs WHERE id = v_job;
  EXCEPTION WHEN foreign_key_violation THEN v_ok := true; END;
  IF NOT v_ok THEN RAISE EXCEPTION 'T9 FALHOU: delete de job com candidatura passou'; END IF;
  RAISE NOTICE 'T9 ok: ON DELETE RESTRICT protege a trilha de auditoria';

  ------------------------------------------------------------------
  RAISE NOTICE '═══ TODOS OS TESTES PASSARAM — rollback intencional a seguir ═══';
  RAISE EXCEPTION 'FASE1_TESTS_OK';
END $$;
