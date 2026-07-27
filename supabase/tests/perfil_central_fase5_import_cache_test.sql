-- Fase 5 — predicado TAUTOLÓGICO de limpeza do cache legado de import
-- (migration 20260724120000). Roda depois do combined (schema mock + migrations).
-- Chamado como superuser com request.jwt.claims definindo auth.uid.
--
-- O que estes blocos provam:
--   F5-CACHE-TAUT      remover a ÚNICA fonte importada limpa o cache (o conserto);
--   F5-CACHE-INVARIANT remover uma HISTÓRICA com outra viva NÃO limpa (invariante
--                      R5-E do promote_test preservada) e, ao remover a última,
--                      limpa (tautológico);
--   F5-CACHE-RPC       o mesmo pelo RPC remove_imported_source, com recibo;
--   F5-CACHE-SCOPE     apagar manual/adapted NÃO limpa o cache de import;
--   F5-CACHE-PROFILE   a limpeza NUNCA toca profile_* (invariante 10);
--   F5-CACHE-GUARD     LIMITE conhecido: sem sessão de usuário (auth.uid NULL) o
--                      guard RESTAURA o cache → um backfill service_role seria
--                      revertido em silêncio. Documentado, não "consertado".

-- F5-CACHE-TAUT — única fonte importada removida ⇒ cache limpo.
DO $f5$
DECLARE u uuid := '000000f5-0000-0000-0000-0000000000a1'; c uuid;
BEGIN
  PERFORM set_config('request.jwt.claims', ('{"sub":"' || u || '"}')::text, false);
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.saved_resumes(user_id,title,file_path,source)
    VALUES (u,'Meu Currículo',u::text||'/1.pdf','imported') RETURNING id INTO c;
  UPDATE public.user_profiles
     SET gamification_data = '{"imported_resume":{"raw_text":"TEXTO DO CV"}}'::jsonb
   WHERE id = u;
  IF NOT (SELECT gamification_data ? 'imported_resume'
            FROM public.user_profiles WHERE id=u) THEN
    RAISE EXCEPTION 'F5-CACHE-TAUT: seed do cache não pegou'; END IF;

  DELETE FROM public.saved_resumes WHERE id = c;

  IF (SELECT gamification_data ? 'imported_resume'
        FROM public.user_profiles WHERE id=u) THEN
    RAISE EXCEPTION 'F5-CACHE-TAUT: cache sobreviveu à remoção da única fonte';
  END IF;
  RAISE NOTICE 'F5-CACHE-TAUT OK: última fonte importada removida ⇒ cache limpo';
END $f5$;

-- F5-CACHE-INVARIANT — histórica com outra viva NÃO limpa; a última limpa.
DO $f5$
DECLARE u uuid := '000000f5-0000-0000-0000-0000000000a2'; c1 uuid; c2 uuid;
BEGIN
  PERFORM set_config('request.jwt.claims', ('{"sub":"' || u || '"}')::text, false);
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.saved_resumes(user_id,title,file_path,source)
    VALUES (u,'CV antigo',u::text||'/a.pdf','imported') RETURNING id INTO c1;
  INSERT INTO public.saved_resumes(user_id,title,file_path,source)
    VALUES (u,'CV novo',u::text||'/b.pdf','imported') RETURNING id INTO c2;
  UPDATE public.user_profiles
     SET gamification_data = '{"imported_resume":{"raw_text":"R2"}}'::jsonb
   WHERE id = u;

  -- Remove a HISTÓRICA: ainda sobra fonte ⇒ cache PRESERVADO (invariante R5-E).
  DELETE FROM public.saved_resumes WHERE id = c1;
  IF NOT (SELECT gamification_data ? 'imported_resume'
            FROM public.user_profiles WHERE id=u) THEN
    RAISE EXCEPTION 'F5-CACHE-INVARIANT: histórica limpou cache indevidamente';
  END IF;

  -- Remove a ÚLTIMA: não sobra nenhuma ⇒ tautológico ⇒ cache limpo.
  DELETE FROM public.saved_resumes WHERE id = c2;
  IF (SELECT gamification_data ? 'imported_resume'
        FROM public.user_profiles WHERE id=u) THEN
    RAISE EXCEPTION 'F5-CACHE-INVARIANT: cache sobreviveu à remoção da última';
  END IF;
  RAISE NOTICE 'F5-CACHE-INVARIANT OK: histórica preserva; última limpa';
END $f5$;

-- F5-CACHE-RPC — mesmo comportamento via remove_imported_source + recibo.
DO $f5$
DECLARE u uuid := '000000f5-0000-0000-0000-0000000000a3'; c uuid; r jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', ('{"sub":"' || u || '"}')::text, false);
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.saved_resumes(user_id,title,file_path,source)
    VALUES (u,'Meu Currículo',u::text||'/r.pdf','imported') RETURNING id INTO c;
  UPDATE public.user_profiles
     SET gamification_data = '{"imported_resume":{"raw_text":"RPC"}}'::jsonb
   WHERE id = u;

  r := public.remove_imported_source(c);
  IF (r->>'removed') <> 'true' OR (r->>'was_current') <> 'false' THEN
    RAISE EXCEPTION 'F5-CACHE-RPC: recibo inesperado (%)', r; END IF;
  IF (SELECT gamification_data ? 'imported_resume'
        FROM public.user_profiles WHERE id=u) THEN
    RAISE EXCEPTION 'F5-CACHE-RPC: cache sobreviveu ao RPC';
  END IF;
  IF EXISTS (SELECT 1 FROM public.saved_resumes WHERE id=c) THEN
    RAISE EXCEPTION 'F5-CACHE-RPC: row não foi removida'; END IF;
  RAISE NOTICE 'F5-CACHE-RPC OK: remove_imported_source limpa o cache (was_current=false)';
END $f5$;

-- F5-CACHE-SCOPE — apagar manual/adapted NÃO limpa o cache de import.
DO $f5$
DECLARE u uuid := '000000f5-0000-0000-0000-0000000000a4'; cm uuid;
BEGIN
  PERFORM set_config('request.jwt.claims', ('{"sub":"' || u || '"}')::text, false);
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  -- Nenhuma importada existe; só um manual. O cache (órfão histórico) fica.
  INSERT INTO public.saved_resumes(user_id,title,file_path,source)
    VALUES (u,'Currículo Stage',u::text||'/m.pdf','manual') RETURNING id INTO cm;
  UPDATE public.user_profiles
     SET gamification_data = '{"imported_resume":{"raw_text":"ORFAO"}}'::jsonb
   WHERE id = u;

  DELETE FROM public.saved_resumes WHERE id = cm;
  IF NOT (SELECT gamification_data ? 'imported_resume'
            FROM public.user_profiles WHERE id=u) THEN
    RAISE EXCEPTION 'F5-CACHE-SCOPE: apagar manual limpou o cache de import';
  END IF;
  RAISE NOTICE 'F5-CACHE-SCOPE OK: delete de manual/adapted não toca o cache de import';
END $f5$;

-- F5-CACHE-PROFILE — a limpeza NUNCA toca profile_* (invariante 10).
DO $f5$
DECLARE u uuid := '000000f5-0000-0000-0000-0000000000a5'; c uuid;
BEGIN
  PERFORM set_config('request.jwt.claims', ('{"sub":"' || u || '"}')::text, false);
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  PERFORM public._t_reset(u);
  INSERT INTO public.profile_personal(user_id, first_name) VALUES (u,'Ana');
  INSERT INTO public.profile_skills(user_id, name) VALUES (u,'Dart');
  INSERT INTO public.saved_resumes(user_id,title,file_path,source)
    VALUES (u,'Meu Currículo',u::text||'/p.pdf','imported') RETURNING id INTO c;
  UPDATE public.user_profiles
     SET gamification_data = '{"imported_resume":{"raw_text":"X"}}'::jsonb
   WHERE id = u;

  PERFORM public.remove_imported_source(c);

  IF (SELECT count(*) FROM public.profile_skills WHERE user_id=u) <> 1
     OR (SELECT first_name FROM public.profile_personal WHERE user_id=u) <> 'Ana' THEN
    RAISE EXCEPTION 'F5-CACHE-PROFILE: a remoção tocou profile_*';
  END IF;
  RAISE NOTICE 'F5-CACHE-PROFILE OK: fatos do perfil preservados (invariante 10)';
END $f5$;

-- F5-CACHE-GUARD — LIMITE CONHECIDO: sem auth.uid() o guard RESTAURA o cache.
-- Prova que um backfill service_role/migration dos 421 já-órfãos seria revertido
-- em silêncio. Não é regressão: é a fronteira desta migration, documentada.
DO $f5$
DECLARE u uuid := '000000f5-0000-0000-0000-0000000000a6';
BEGIN
  -- Cria o cache COM sessão (para o guard aceitar a escrita inicial).
  PERFORM set_config('request.jwt.claims', ('{"sub":"' || u || '"}')::text, false);
  INSERT INTO auth.users(id) VALUES (u) ON CONFLICT DO NOTHING;
  INSERT INTO public.user_profiles(id) VALUES (u) ON CONFLICT DO NOTHING;
  UPDATE public.user_profiles
     SET gamification_data = '{"imported_resume":{"raw_text":"BACKFILL"}}'::jsonb
   WHERE id = u;

  -- Agora tenta remover SEM sessão (como faria uma migration/service_role).
  PERFORM set_config('request.jwt.claims', '', false);
  UPDATE public.user_profiles
     SET gamification_data = COALESCE(gamification_data,'{}'::jsonb) - 'imported_resume'
   WHERE id = u;

  IF NOT (SELECT gamification_data ? 'imported_resume'
            FROM public.user_profiles WHERE id=u) THEN
    RAISE EXCEPTION
      'F5-CACHE-GUARD: o guard DEIXOU remover sem auth.uid() — a premissa da '
      'nota de limite mudou; revisar antes de planejar backfill';
  END IF;
  RAISE NOTICE 'F5-CACHE-GUARD OK (limite): sem auth.uid() o guard restaura o cache — backfill exigiria outro caminho';
END $f5$;

SELECT 'FASE5_IMPORT_CACHE_SQL_TESTS_OK' AS result;
