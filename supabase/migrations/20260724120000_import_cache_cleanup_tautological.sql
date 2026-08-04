-- Fase 5 (IA/Perfil) — conserto do predicado de limpeza do cache legado de import.
--
-- PROBLEMA MEDIDO EM PROD (24/07): a limpeza do cache
-- `user_profiles.gamification_data->'imported_resume'` NUNCA roda. As três
-- condições existentes (trigger `_cleanup_import_cache_after_saved_resume_delete`,
-- RPC `remove_imported_source`, RPC `delete_saved_resume`) usam a MESMA regra:
--     OLD.is_current_source  OR  cache->>'source_resume_id' = OLD.id
-- e as duas cláusulas são INALCANÇÁVEIS na base atual:
--   • 0 de 738 rows `source='imported'` têm `is_current_source` (todas legadas,
--     `extraction_status IS NULL` — nenhuma fonte canônica/ready existe);
--   • 0 de 1.091 caches têm `source_resume_id` (o link só nasce em
--     `_canonical_import_cache`, que exige ready+current; e o backfill de
--     20260714130000:413-423 removeu qualquer link de quem não tem current).
-- Resultado: remover a fonte importada deixa o texto do CV vivo — e ele É lido
-- (analyze-match: chave do cache + prompt + bypass do Cenário C;
-- extract-job-skills; extract-profile cache-hit; getter `hasResume` do app).
--
-- CONSERTO: acrescenta uma terceira cláusula TAUTOLÓGICA — limpa também quando
-- NÃO SOBROU nenhuma row `source='imported'` do usuário. Se não existe mais
-- nenhuma fonte importada, um cache de import não pode pertencer a nada. Zero
-- inferência, zero heurística de "qual fonte era".
--
-- POR QUE NÃO "LIMPAR SEMPRE": quebraria a invariante EXECUTÁVEL de
-- `supabase/tests/perfil_central_fase3_promote_test.sql` (R5-E, ~:2740-2746):
-- apagar uma importada HISTÓRICA não pode matar o cache de outra ainda viva.
-- Com o predicado tautológico esse caso segue protegido (ainda sobra uma row),
-- e o teste continua passando. Em prod isso preserva os 37 usuários com mais de
-- uma importada e conserta os 633 que têm exatamente uma.
--
-- LIMITE CONHECIDO E DELIBERADO (não é bug desta migration):
--   1. NÃO alcança os 421 usuários que JÁ estão com o cache órfão (têm cache e
--      ZERO row importada) — para eles nenhum evento de DELETE vai existir. Isso
--      exige um backfill, que é decisão separada.
--   2. O backfill não é trivial: o guard `_guard_user_profile_import_cache`
--      (20260714130000:290-316) só HONRA a remoção da chave quando
--      `auth.uid() = NEW.id` e o UPDATE é exatamente "OLD menos a chave";
--      fora disso ele RESTAURA o cache. Numa migration `auth.uid()` é NULL, logo
--      um backfill service_role seria silenciosamente revertido. O harness prova
--      esse limite (bloco F5-CACHE-GUARD).
--   3. NÃO para a ESCRITA do cache (`extract-profile` e `cv_import_service`
--      seguem gravando). Aposentar a gaveta exige antes migrar o `analyze-match`
--      para ler `profile_*` — projeto próprio.
--
-- Nada aqui toca `profile_*` (invariante 10: o dado já incorporado ao perfil
-- PERMANECE) nem o pipeline de adapt/match (nenhuma mudança sob R5). Idempotente:
-- só CREATE OR REPLACE das 3 funções; o trigger existente segue apontando para a
-- função pelo nome (sem DROP/CREATE de trigger).

-- ── 1. Trigger de limpeza (cobre TODOS os caminhos de DELETE) ────────────────
CREATE OR REPLACE FUNCTION public._cleanup_import_cache_after_saved_resume_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_cache jsonb; v_cache_source text;
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN OLD;
  END IF;
  IF OLD.source <> 'imported' THEN
    RETURN OLD;
  END IF;

  SELECT COALESCE(gamification_data, '{}'::jsonb)->'imported_resume'
    INTO v_cache FROM public.user_profiles WHERE id = OLD.user_id;
  v_cache_source := NULLIF(btrim(v_cache->>'source_resume_id'), '');

  -- 3ª cláusula (tautológica): o AFTER DELETE já removeu a row, então este
  -- NOT EXISTS significa "não sobrou NENHUMA fonte importada". Cache de import
  -- sem nenhuma fonte é órfão por definição — não há a quem pertencer.
  IF COALESCE(OLD.is_current_source, false)
     OR v_cache_source = OLD.id::text
     OR (jsonb_typeof(v_cache) = 'object'
         AND NOT EXISTS (
           SELECT 1 FROM public.saved_resumes
            WHERE user_id = OLD.user_id AND source = 'imported')) THEN
    UPDATE public.user_profiles
       SET gamification_data = COALESCE(gamification_data, '{}'::jsonb) - 'imported_resume'
     WHERE id = OLD.user_id;
  END IF;
  RETURN OLD;
END $$;
REVOKE ALL ON FUNCTION public._cleanup_import_cache_after_saved_resume_delete() FROM PUBLIC;

-- ── 2. RPC de remoção da fonte importada ────────────────────────────────────
-- O DELETE abaixo já dispara o trigger acima (que limpa pelo mesmo critério);
-- a limpeza local fica como defesa em profundidade e é idempotente.
CREATE OR REPLACE FUNCTION public.remove_imported_source(p_candidate_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_uid uuid := auth.uid(); v_src text; v_current boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='28000'; END IF;
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(v_uid));  -- advisory antes de tuple
  SELECT source, is_current_source INTO v_src, v_current
    FROM public.saved_resumes WHERE id=p_candidate_id AND user_id=v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'candidate_not_found' USING ERRCODE='P0002'; END IF;
  IF v_src <> 'imported' THEN RAISE EXCEPTION 'not_an_imported_source' USING ERRCODE='22023'; END IF;

  DELETE FROM public.saved_resumes WHERE id=p_candidate_id AND user_id=v_uid;
  IF COALESCE(v_current,false)
     OR NOT EXISTS (SELECT 1 FROM public.saved_resumes
                     WHERE user_id=v_uid AND source='imported') THEN
    UPDATE public.user_profiles
      SET gamification_data = COALESCE(gamification_data,'{}'::jsonb) - 'imported_resume'
      WHERE id=v_uid;
  END IF;
  RETURN jsonb_build_object('removed', true, 'was_current', COALESCE(v_current,false));
END $$;
REVOKE ALL ON FUNCTION public.remove_imported_source(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.remove_imported_source(uuid) TO authenticated;

-- ── 3. RPC de exclusão canônica (todos os tipos) ─────────────────────────────
-- Mantém o escopo: só a exclusão de uma IMPORTADA pode limpar o cache de import
-- (apagar manual/adapted/general/trail não tem relação com a fonte).
CREATE OR REPLACE FUNCTION public.delete_saved_resume(p_resume_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_uid uuid := auth.uid(); v_src text; v_current boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='28000'; END IF;
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(v_uid));  -- advisory antes de tuple
  SELECT source, is_current_source INTO v_src, v_current
    FROM public.saved_resumes WHERE id=p_resume_id AND user_id=v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'resume_not_found' USING ERRCODE='P0002'; END IF;
  DELETE FROM public.saved_resumes WHERE id=p_resume_id AND user_id=v_uid;
  IF v_src = 'imported'
     AND (COALESCE(v_current,false)
          OR NOT EXISTS (SELECT 1 FROM public.saved_resumes
                          WHERE user_id=v_uid AND source='imported')) THEN
    UPDATE public.user_profiles
      SET gamification_data = COALESCE(gamification_data,'{}'::jsonb) - 'imported_resume'
      WHERE id=v_uid;
  END IF;
  RETURN jsonb_build_object('removed', true, 'was_current', COALESCE(v_current,false));
END $$;
REVOKE ALL ON FUNCTION public.delete_saved_resume(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_saved_resume(uuid) TO authenticated;
