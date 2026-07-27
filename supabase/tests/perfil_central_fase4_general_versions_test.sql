-- Fase 4 — F4.1: versões do Currículo geral (saved_resumes source='general').
-- Roda depois do combined (schema mock + migrations 14/07→21/07). Chamado como
-- superuser com request.jwt.claims setando auth.uid(); ACL/grants usam
-- SET LOCAL ROLE (padrão do harness de 14/07).

-- F4-SAVE — applied v1/v2, título default, noop honesto, template gera versão.
DO $f4$
DECLARE
  u uuid := '000000f4-0000-0000-0000-0000000000a1';
  fp_a text := repeat('a', 64);
  fp_b text := repeat('b', 64);
  path1 text; path2 text; path3 text;
  r jsonb; v2_id uuid; total integer;
BEGIN
  PERFORM set_config('request.jwt.claims', ('{"sub":"' || u || '"}')::text, false);
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  path1 := u::text || '/general/11111111-1111-1111-1111-111111111111.pdf';
  path2 := u::text || '/general/22222222-2222-2222-2222-222222222222.pdf';
  path3 := u::text || '/general/33333333-3333-3333-3333-333333333333.pdf';

  -- v1: applied; título vazio cai no default do servidor.
  r := public.save_general_resume_version_v1('  ', path1, '{"name":"Ana"}'::jsonb, 'harvard_ats', fp_a);
  IF r->>'status' <> 'applied' OR (r->>'version')::int <> 1 THEN
    RAISE EXCEPTION 'F4-SAVE: v1 applied falhou (%)', r; END IF;
  IF (SELECT title FROM public.saved_resumes WHERE id = (r->>'id')::uuid) <> 'Currículo geral' THEN
    RAISE EXCEPTION 'F4-SAVE: título default não aplicado'; END IF;
  IF (SELECT is_current_source OR is_latest_legacy_source
        FROM public.saved_resumes WHERE id = (r->>'id')::uuid) THEN
    RAISE EXCEPTION 'F4-SAVE: flags de import vazaram pra linha general'; END IF;

  -- v2: fingerprint diferente → applied 2.
  r := public.save_general_resume_version_v1('Currículo geral', path2, '{"name":"Ana","skills":["X"]}'::jsonb, 'harvard_ats', fp_b);
  IF r->>'status' <> 'applied' OR (r->>'version')::int <> 2 THEN
    RAISE EXCEPTION 'F4-SAVE: v2 applied falhou (%)', r; END IF;
  v2_id := (r->>'id')::uuid;

  -- noop: mesmo fingerprint E mesmo template da última → nada criado, recibo
  -- devolve a versão vigente (id/version/file_path da v2).
  r := public.save_general_resume_version_v1('Currículo geral', path3, '{"name":"Ana","skills":["X"]}'::jsonb, 'harvard_ats', fp_b);
  IF r->>'status' <> 'noop' OR (r->>'id')::uuid <> v2_id
     OR (r->>'version')::int <> 2 OR r->>'file_path' <> path2 THEN
    RAISE EXCEPTION 'F4-SAVE: noop falhou (%)', r; END IF;
  SELECT count(*) INTO total FROM public.saved_resumes WHERE user_id = u AND source = 'general';
  IF total <> 2 THEN RAISE EXCEPTION 'F4-SAVE: noop criou linha (%)', total; END IF;

  -- mesmo fingerprint mas TEMPLATE diferente → nova versão (decisão 3).
  r := public.save_general_resume_version_v1('Currículo geral', path3, '{"name":"Ana","skills":["X"]}'::jsonb, 'cobalt_modern', fp_b);
  IF r->>'status' <> 'applied' OR (r->>'version')::int <> 3 THEN
    RAISE EXCEPTION 'F4-SAVE: template novo não versionou (%)', r; END IF;

  -- delete da última + save → reusa o número liberado (max vivo + 1), sem furo
  -- no índice único.
  DELETE FROM public.saved_resumes WHERE user_id = u AND source = 'general' AND version = 3;
  r := public.save_general_resume_version_v1('Currículo geral', path3, '{"name":"Bia"}'::jsonb, 'harvard_ats', repeat('c', 64));
  IF r->>'status' <> 'applied' OR (r->>'version')::int <> 3 THEN
    RAISE EXCEPTION 'F4-SAVE: pós-delete não retomou max+1 (%)', r; END IF;

  RAISE NOTICE 'F4-SAVE OK: applied v1..v3, título default, noop honesto, template versiona, pós-delete';
END $f4$;

-- F4-VALID — validação fail-closed: nada inválido cria linha.
DO $f4$
DECLARE
  u uuid := '000000f4-0000-0000-0000-0000000000a2';
  other uuid := '000000f4-0000-0000-0000-0000000000a3';
  good_fp text := repeat('d', 64);
  good_path text;
  before_count integer; after_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims', ('{"sub":"' || u || '"}')::text, false);
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  good_path := u::text || '/general/44444444-4444-4444-4444-444444444444.pdf';
  SELECT count(*) INTO before_count FROM public.saved_resumes WHERE user_id = u;

  -- fingerprint: vazio / não-hex / MAIÚSCULO / curto → 22023.
  BEGIN
    PERFORM public.save_general_resume_version_v1('t', good_path, '{}'::jsonb, 'harvard_ats', '');
    RAISE EXCEPTION 'F4-VALID: fingerprint vazio passou';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;
  BEGIN
    PERFORM public.save_general_resume_version_v1('t', good_path, '{}'::jsonb, 'harvard_ats', repeat('Z', 64));
    RAISE EXCEPTION 'F4-VALID: fingerprint não-hex passou';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;
  BEGIN
    PERFORM public.save_general_resume_version_v1('t', good_path, '{}'::jsonb, 'harvard_ats', repeat('A', 64));
    RAISE EXCEPTION 'F4-VALID: fingerprint maiúsculo passou';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;
  BEGIN
    PERFORM public.save_general_resume_version_v1('t', good_path, '{}'::jsonb, 'harvard_ats', repeat('d', 63));
    RAISE EXCEPTION 'F4-VALID: fingerprint curto passou';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;

  -- template vazio / longo demais → 22023.
  BEGIN
    PERFORM public.save_general_resume_version_v1('t', good_path, '{}'::jsonb, '   ', good_fp);
    RAISE EXCEPTION 'F4-VALID: template vazio passou';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;
  BEGIN
    PERFORM public.save_general_resume_version_v1('t', good_path, '{}'::jsonb, repeat('x', 65), good_fp);
    RAISE EXCEPTION 'F4-VALID: template longo passou';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;

  -- resume_data: NULL / array / acima do teto de 256 KiB → 22023.
  BEGIN
    PERFORM public.save_general_resume_version_v1('t', good_path, NULL, 'harvard_ats', good_fp);
    RAISE EXCEPTION 'F4-VALID: resume_data NULL passou';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;
  BEGIN
    PERFORM public.save_general_resume_version_v1('t', good_path, '[]'::jsonb, 'harvard_ats', good_fp);
    RAISE EXCEPTION 'F4-VALID: resume_data array passou';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;
  BEGIN
    PERFORM public.save_general_resume_version_v1('t', good_path,
      jsonb_build_object('blob', repeat('a', 300000)), 'harvard_ats', good_fp);
    RAISE EXCEPTION 'F4-VALID: resume_data acima do teto passou';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;

  -- file_path: namespace de OUTRO usuário / pasta errada / sem uuid / traversal
  -- / uuid maiúsculo → 22023.
  BEGIN
    PERFORM public.save_general_resume_version_v1('t',
      other::text || '/general/44444444-4444-4444-4444-444444444444.pdf',
      '{}'::jsonb, 'harvard_ats', good_fp);
    RAISE EXCEPTION 'F4-VALID: path de outro usuário passou';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;
  BEGIN
    PERFORM public.save_general_resume_version_v1('t',
      u::text || '/imports/44444444-4444-4444-4444-444444444444.pdf',
      '{}'::jsonb, 'harvard_ats', good_fp);
    RAISE EXCEPTION 'F4-VALID: pasta errada passou';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;
  BEGIN
    PERFORM public.save_general_resume_version_v1('t',
      u::text || '/general/qualquer.pdf', '{}'::jsonb, 'harvard_ats', good_fp);
    RAISE EXCEPTION 'F4-VALID: filename não-uuid passou';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;
  BEGIN
    PERFORM public.save_general_resume_version_v1('t',
      u::text || '/general/../44444444-4444-4444-4444-444444444444.pdf',
      '{}'::jsonb, 'harvard_ats', good_fp);
    RAISE EXCEPTION 'F4-VALID: traversal passou';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;
  BEGIN
    PERFORM public.save_general_resume_version_v1('t',
      u::text || '/general/44444444-4444-4444-4444-44444444444A.pdf',
      '{}'::jsonb, 'harvard_ats', good_fp);
    RAISE EXCEPTION 'F4-VALID: uuid maiúsculo passou';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;

  -- sem sessão → 28000.
  PERFORM set_config('request.jwt.claims', '', false);
  BEGIN
    PERFORM public.save_general_resume_version_v1('t', good_path, '{}'::jsonb, 'harvard_ats', good_fp);
    RAISE EXCEPTION 'F4-VALID: sem auth passou';
  EXCEPTION WHEN sqlstate '28000' THEN NULL; END;
  PERFORM set_config('request.jwt.claims', ('{"sub":"' || u || '"}')::text, false);

  SELECT count(*) INTO after_count FROM public.saved_resumes WHERE user_id = u;
  IF after_count <> before_count THEN
    RAISE EXCEPTION 'F4-VALID: entrada inválida criou linha (% → %)', before_count, after_count; END IF;
  RAISE NOTICE 'F4-VALID OK: fingerprint/template/resume_data/path/auth fail-closed, zero linha criada';
END $f4$;

-- F4-ACL — grants/RLS/imutabilidade: cliente não força general por fora; anon e
-- service_role não executam a RPC; conteúdo da versão é imutável (title/flags livres).
DO $f4$
DECLARE
  u uuid := '000000f4-0000-0000-0000-0000000000a4';
  gen_id uuid; gen_path text; r jsonb; affected integer;
BEGIN
  PERFORM set_config('request.jwt.claims', ('{"sub":"' || u || '"}')::text, false);
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  gen_path := u::text || '/general/55555555-5555-5555-5555-555555555555.pdf';
  r := public.save_general_resume_version_v1('Currículo geral', gen_path, '{"name":"Ana"}'::jsonb, 'harvard_ats', repeat('e', 64));
  gen_id := (r->>'id')::uuid;

  -- INSERT direto de general como authenticated: version não é grantável →
  -- ou 42501 (coluna fora do grant) ou 23514 (CHECK sem version). Fail-closed
  -- dos dois jeitos; nunca linha criada.
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO public.saved_resumes (title, file_path, source, resume_data, template_id)
    VALUES ('forjado', gen_path, 'general', '{}'::jsonb, 'harvard_ats');
    RESET ROLE;
    RAISE EXCEPTION 'F4-ACL: INSERT direto de general passou';
  EXCEPTION WHEN sqlstate '42501' OR sqlstate '23514' THEN RESET ROLE; END;

  -- UPDATE da coluna version (fora do grant) → 42501.
  SET LOCAL ROLE authenticated;
  BEGIN
    UPDATE public.saved_resumes SET version = 99 WHERE id = gen_id;
    RESET ROLE;
    RAISE EXCEPTION 'F4-ACL: UPDATE de version passou';
  EXCEPTION WHEN sqlstate '42501' THEN RESET ROLE; END;

  -- UPDATE de resume_data (coluna GRANTada) numa linha general → trigger de
  -- imutabilidade 55000; conteúdo preservado.
  SET LOCAL ROLE authenticated;
  BEGIN
    UPDATE public.saved_resumes SET resume_data = '{"name":"Hack"}'::jsonb WHERE id = gen_id;
    RESET ROLE;
    RAISE EXCEPTION 'F4-ACL: mutação de resume_data em general passou';
  EXCEPTION WHEN sqlstate '55000' THEN RESET ROLE; END;
  IF (SELECT resume_data->>'name' FROM public.saved_resumes WHERE id = gen_id) <> 'Ana' THEN
    RAISE EXCEPTION 'F4-ACL: conteúdo da versão foi alterado'; END IF;

  -- Rename de title numa general: permitido (WHEN escopado não bloqueia).
  SET LOCAL ROLE authenticated;
  UPDATE public.saved_resumes SET title = 'Renomeado' WHERE id = gen_id;
  RESET ROLE;
  IF (SELECT title FROM public.saved_resumes WHERE id = gen_id) <> 'Renomeado' THEN
    RAISE EXCEPTION 'F4-ACL: rename de title bloqueado indevidamente'; END IF;

  -- UPDATE amplo de flags (o statement do restore do import, 20260719120000)
  -- passa com linhas general presentes — o WHEN não dispara em flags.
  UPDATE public.saved_resumes
     SET is_current_source = false, is_latest_legacy_source = false
   WHERE user_id = u;

  -- anon e service_role: EXECUTE revogado → 42501.
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM public.save_general_resume_version_v1('t', gen_path, '{}'::jsonb, 'harvard_ats', repeat('e', 64));
    RESET ROLE;
    RAISE EXCEPTION 'F4-ACL: anon executou a RPC';
  EXCEPTION WHEN sqlstate '42501' THEN RESET ROLE; END;
  SET LOCAL ROLE service_role;
  BEGIN
    PERFORM public.save_general_resume_version_v1('t', gen_path, '{}'::jsonb, 'harvard_ats', repeat('e', 64));
    RESET ROLE;
    RAISE EXCEPTION 'F4-ACL: service_role executou a RPC';
  EXCEPTION WHEN sqlstate '42501' THEN RESET ROLE; END;

  -- RLS: usuário B não lê nem deleta a versão de A.
  PERFORM set_config('request.jwt.claims',
    '{"sub":"000000f4-0000-0000-0000-0000000000a5"}', false);
  INSERT INTO auth.users(id) VALUES ('000000f4-0000-0000-0000-0000000000a5') ON CONFLICT DO NOTHING;
  SET LOCAL ROLE authenticated;
  IF EXISTS (SELECT 1 FROM public.saved_resumes WHERE id = gen_id) THEN
    RESET ROLE;
    RAISE EXCEPTION 'F4-ACL: B leu a versão de A'; END IF;
  DELETE FROM public.saved_resumes WHERE id = gen_id;
  GET DIAGNOSTICS affected = ROW_COUNT;
  RESET ROLE;
  IF affected <> 0 THEN RAISE EXCEPTION 'F4-ACL: B deletou a versão de A'; END IF;

  RAISE NOTICE 'F4-ACL OK: forge bloqueado, conteúdo imutável, title/flags livres, anon/service sem RPC, RLS cross-user';
END $f4$;

-- F4-LEGACY — convivência com o marker legacy de import: general nunca rouba
-- nem zera o marker; o trigger de INSERT força false na linha general.
DO $f4$
DECLARE
  u uuid := '000000f4-0000-0000-0000-0000000000a6';
  legacy_id uuid; r jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', ('{"sub":"' || u || '"}')::text, false);
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;

  -- import shape-legacy → vira o marker do usuário.
  INSERT INTO public.saved_resumes (user_id, title, file_path, source)
  VALUES (u, 'Meu Currículo', u::text || '/123.pdf', 'imported')
  RETURNING id INTO legacy_id;
  IF NOT (SELECT is_latest_legacy_source FROM public.saved_resumes WHERE id = legacy_id) THEN
    RAISE EXCEPTION 'F4-LEGACY: seed não marcou o legacy'; END IF;

  r := public.save_general_resume_version_v1('Currículo geral',
    u::text || '/general/66666666-6666-6666-6666-666666666666.pdf',
    '{"name":"Ana"}'::jsonb, 'harvard_ats', repeat('f', 64));
  IF (SELECT is_latest_legacy_source FROM public.saved_resumes WHERE id = (r->>'id')::uuid) THEN
    RAISE EXCEPTION 'F4-LEGACY: linha general recebeu o marker'; END IF;
  IF NOT (SELECT is_latest_legacy_source FROM public.saved_resumes WHERE id = legacy_id) THEN
    RAISE EXCEPTION 'F4-LEGACY: save do general zerou o marker do import'; END IF;
  RAISE NOTICE 'F4-LEGACY OK: marker de import intacto; general sempre false';
END $f4$;

-- F4-REAPPLY — reaplicar a migration é idempotente e NÃO apaga dado.
\ir ../migrations/20260721120000_general_resume_versions.sql

DO $f4$
DECLARE
  u uuid := '000000f4-0000-0000-0000-0000000000a1';
  r jsonb; total integer;
BEGIN
  PERFORM set_config('request.jwt.claims', ('{"sub":"' || u || '"}')::text, false);
  SELECT count(*) INTO total FROM public.saved_resumes WHERE user_id = u AND source = 'general';
  IF total <> 3 THEN
    RAISE EXCEPTION 'F4-REAPPLY: versões sumiram no reapply (%)', total; END IF;
  -- noop continua noop após reapply (última = v3 fp 'c'/harvard_ats).
  r := public.save_general_resume_version_v1('Currículo geral',
    u::text || '/general/77777777-7777-7777-7777-777777777777.pdf',
    '{"name":"Bia"}'::jsonb, 'harvard_ats', repeat('c', 64));
  IF r->>'status' <> 'noop' OR (r->>'version')::int <> 3 THEN
    RAISE EXCEPTION 'F4-REAPPLY: noop pós-reapply falhou (%)', r; END IF;
  RAISE NOTICE 'F4-REAPPLY OK: idempotente, dados e contrato preservados';
END $f4$;

-- F4-BACKFILL — o UPDATE da migration 125 tipa SÓ os manuais 'Currículo Stage%'
-- como trail; não toca outros manuais, nem imported/adapted, nem general.
DO $f4$
DECLARE
  u uuid := '000000f4-0000-0000-0000-0000000000b1';
  id_stage_manual uuid;
  id_other_manual uuid;
  id_stage_adapted uuid;
  id_imported uuid;
BEGIN
  PERFORM set_config('request.jwt.claims', ('{"sub":"' || u || '"}')::text, false);
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;

  -- Legado da trilha (deve virar trail).
  INSERT INTO public.saved_resumes(user_id, title, file_path, source)
  VALUES (u, 'Currículo Stage', u::text || '/1.pdf', 'manual')
  RETURNING id INTO id_stage_manual;
  -- Legado com sufixo de desambiguação (LIKE 'Currículo Stage%' também pega).
  INSERT INTO public.saved_resumes(user_id, title, file_path, source)
  VALUES (u, 'Currículo Stage (2)', u::text || '/1b.pdf', 'manual');
  -- Manual de OUTRO título (NÃO deve mudar).
  INSERT INTO public.saved_resumes(user_id, title, file_path, source)
  VALUES (u, 'Meu Currículo', u::text || '/2.pdf', 'manual')
  RETURNING id INTO id_other_manual;
  -- Adaptado com título que COMEÇA igual (NÃO deve mudar — source ≠ manual).
  INSERT INTO public.saved_resumes(user_id, title, file_path, source)
  VALUES (u, 'Currículo Stage - Vaga X', u::text || '/3.pdf', 'adapted')
  RETURNING id INTO id_stage_adapted;
  -- Importado (NÃO deve mudar).
  INSERT INTO public.saved_resumes(user_id, title, file_path, source)
  VALUES (u, 'Currículo importado', u::text || '/4.pdf', 'imported')
  RETURNING id INTO id_imported;

  -- Espelha EXATAMENTE o UPDATE da migration 20260722120000.
  UPDATE public.saved_resumes
     SET source = 'trail'
   WHERE source = 'manual'
     AND title LIKE 'Currículo Stage%';

  IF (SELECT source FROM public.saved_resumes WHERE id = id_stage_manual) <> 'trail' THEN
    RAISE EXCEPTION 'F4-BACKFILL: Currículo Stage manual não virou trail'; END IF;
  IF (SELECT count(*) FROM public.saved_resumes
        WHERE user_id = u AND source = 'trail') <> 2 THEN
    RAISE EXCEPTION 'F4-BACKFILL: esperava 2 trail (Stage + Stage (2))'; END IF;
  IF (SELECT source FROM public.saved_resumes WHERE id = id_other_manual) <> 'manual' THEN
    RAISE EXCEPTION 'F4-BACKFILL: manual de outro título mudou'; END IF;
  IF (SELECT source FROM public.saved_resumes WHERE id = id_stage_adapted) <> 'adapted' THEN
    RAISE EXCEPTION 'F4-BACKFILL: adapted com prefixo Stage mudou'; END IF;
  IF (SELECT source FROM public.saved_resumes WHERE id = id_imported) <> 'imported' THEN
    RAISE EXCEPTION 'F4-BACKFILL: imported mudou'; END IF;

  -- Idempotência: reaplicar não muda nada (já são trail).
  UPDATE public.saved_resumes
     SET source = 'trail'
   WHERE source = 'manual'
     AND title LIKE 'Currículo Stage%';
  IF (SELECT count(*) FROM public.saved_resumes
        WHERE user_id = u AND source = 'trail') <> 2 THEN
    RAISE EXCEPTION 'F4-BACKFILL: reaplicar mudou a contagem'; END IF;

  RAISE NOTICE 'F4-BACKFILL OK: só manual+Stage%% → trail; outros intactos; idempotente';
END $f4$;

SELECT 'FASE4_GENERAL_VERSIONS_SQL_TESTS_OK' AS result;
