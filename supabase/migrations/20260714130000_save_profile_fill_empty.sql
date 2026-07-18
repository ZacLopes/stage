-- Fase 3 (Perfil Central) / Gate 2.3 — persistência COMPLETA segura + fencing de
-- TODOS os writers + operação única aplicar+promover.
--
-- CONTRATOS (integridade):
--  1) FILL-EMPTY sem sucesso parcial: cada seção-filha é ATÔMICA — só preenche se
--     estiver VAZIA (IF NOT EXISTS); QUALQUER item inválido que impeça a
--     persistência (ex.: start_date ausente) RAISE dentro da seção → rollback da
--     seção INTEIRA (savepoint) → registrada em `failed_sections`. Nunca fica
--     parcialmente aplicada (o que impediria retry). O outcome distingue:
--     applied (estava vazia e foi preenchida), preserved (já tinha dado manual →
--     intacta), failed (inválida/erro → desfeita). status='success' só sem
--     failed. `last_extracted_at` só em success. Retry re-tenta as vazias.
--  2) FENCING de TODOS os writers: triggers em cada profile_* adquirem
--     `profile_write_lock_key(user_id)` no início de QUALQUER INSERT/UPDATE/
--     DELETE — client (PostgREST), Edge Functions e RPCs serializam na mesma
--     ordem. Escritas unitárias participam via trigger; a importação segura o
--     lock pela transação inteira.
--  3) APLICAR+PROMOVER numa transação/lock ÚNICOS: `apply_and_promote_imported_source`
--     aplica o fill-empty E promove a candidata atomicamente. NUNCA promove se a
--     aplicação for partial/failed. Duas candidatas concorrentes serializam no
--     lock → impossível dados de A com B marcada atual.
--  4) FIDELIDADE: order_index vem de WITH ORDINALITY (o schema não fornece).
--     Projetos preservam o is_current extraído (não têm o CHECK das
--     experiências). Descartes de safe_date/safe_numeric/ON CONFLICT são
--     normalizações DOCUMENTADAS (ver comentários) — não descarte silencioso de
--     item inteiro.
--
-- MATRIZ PROFILE_JSON_SCHEMA → colunas: personal(todos os campos), experiences
--   (+bullets +confidence +needs_review), education(+majors/minors/activities
--   +confidence), languages, skills, certifications, projects, interests,
--   awards, coursework. NÃO produzidos pelo extrator: bullets.angle/strength/
--   verb, projects.role/context/bullets, order_index (derivado por ordinality),
--   job_preferences (fora do escopo).
--
-- SECURITY DEFINER endurecida (search_path='' + qualificado). Só a própria linha.
-- NÃO aplicar remotamente aqui.

BEGIN;

CREATE OR REPLACE FUNCTION public._fill_empty_text(existing text, incoming text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT CASE WHEN existing IS NOT NULL AND btrim(existing) <> '' THEN existing ELSE incoming END
$$;

-- ── CONTATO PROFISSIONAL (Round 5 blocker C) — espelho SQL de _shared/contact_email.ts
-- e lib/core/utils/contact_email.dart (não havia cópia SQL). Um e-mail Apple Private
-- Relay (privaterelay.appleid.com / private.icloud.com) ou sintético de login
-- (phone_*@stage.app) é IDENTIDADE de autenticação — nunca um contato profissional;
-- o CV jamais pode introduzi-lo, e um perfil que só tem relay/sintético NÃO conta
-- como "contato manual protegido". Fonte SQL única para: _profile_has_protected_data,
-- o fill-empty do email, e o CAS de email revisado.
CREATE OR REPLACE FUNCTION public._is_public_contact_email(p text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT p IS NOT NULL
    AND lower(btrim(p)) ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
    AND split_part(lower(btrim(p)), '@', 2) <> 'privaterelay.appleid.com'
    AND split_part(lower(btrim(p)), '@', 2) <> 'private.icloud.com'
    AND NOT (split_part(lower(btrim(p)), '@', 2) = 'stage.app'
             AND split_part(lower(btrim(p)), '@', 1) ~ '^phone_.+$')
$$;
-- Resolve o email a GRAVAR: um contato profissional existente SEMPRE vence; senão,
-- um email profissional novo pode preencher/substituir relay/sintético/vazio; senão
-- mantém o que estava (relay/sintético/NULL). Espelha resolveImportedContactEmail.
CREATE OR REPLACE FUNCTION public._resolve_contact_email(p_existing text, p_incoming text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT CASE
    WHEN public._is_public_contact_email(p_existing) THEN p_existing
    WHEN public._is_public_contact_email(p_incoming) THEN lower(btrim(p_incoming))
    ELSE p_existing
  END
$$;

CREATE OR REPLACE FUNCTION public.profile_write_lock_key(p_user_id uuid)
RETURNS bigint LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT hashtextextended('profile_write:' || p_user_id::text, 0)
$$;
REVOKE ALL ON FUNCTION public.profile_write_lock_key(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

-- ── FENCING (ORDEM ÚNICA DE LOCKS: advisory por-usuário SEMPRE antes de tuple) ─
-- O fencing por BEFORE ROW era INSEGURO: em UPDATE/DELETE a tupla-alvo já está
-- travada quando o trigger dispara → adquiria advisory DEPOIS do tuple lock,
-- enquanto a importação adquire advisory ANTES de tocar linhas → inversão
-- advisory↔tuple → DEADLOCK. Além disso resolvia o user_id da filha com um
-- SELECT por-linha.
--
-- Solução: fence em BEFORE STATEMENT, que dispara ANTES de qualquer tupla ser
-- travada. Como o writer autenticado (PostgREST) só escreve as PRÓPRIAS linhas
-- (RLS user_id=auth.uid()), `auth.uid()` é a chave correta para TODAS as tabelas
-- (pais E filhas) — sem resolver parent por linha. Ordem garantida em TODO
-- caminho: advisory(user) → tuple locks. Sem inversão ⇒ sem deadlock.
--
-- Writers service_role/Edge (auth.uid() NULL) NÃO são travados aqui — precisam
-- das RPCs transacionais (save_profile_from_json, save_profile_fill_empty, …),
-- que pegam o lock explicitamente por p_user_id, mantendo a MESMA ordem.
CREATE OR REPLACE FUNCTION public._fence_profile_writes()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  -- BEFORE STATEMENT: dispara antes de travar qualquer linha do statement.
  -- Cascatas disparam dentro de outro trigger (depth>1), portanto o statement
  -- pai já tocou/adquiriu seus locks; tentar advisory aqui reabriria uma ordem
  -- tuple→advisory. Escritas diretas/RPCs chegam com depth=1.
  IF pg_trigger_depth() = 1 AND auth.uid() IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(auth.uid()));
  END IF;
  RETURN NULL;  -- statement-level: valor ignorado
END $$;

DO $mk$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'profile_personal','profile_experiences','profile_bullets','profile_education',
    'profile_education_majors','profile_education_minors','profile_education_activities',
    'profile_languages','profile_skills','profile_certifications','profile_projects',
    'profile_project_bullets','profile_interests','profile_awards','profile_coursework']
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t) THEN
      -- remove o fencing BEFORE ROW antigo (inseguro) e o statement, se existirem
      EXECUTE format('DROP TRIGGER IF EXISTS zzz_fence ON public.%I', t);
      EXECUTE format('DROP TRIGGER IF EXISTS zzz_fence_stmt ON public.%I', t);
      EXECUTE format('CREATE TRIGGER zzz_fence_stmt BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION public._fence_profile_writes()', t);
    END IF;
  END LOOP;
END $mk$;

-- saved_resumes participa do MESMO protocolo de locks. Isto é necessário para
-- a ponte backward-compatible do build anterior: ele faz INSERT direto (com
-- user_id) e DELETE direto depois de remover o blob. O fence é STATEMENT-level,
-- portanto pega advisory(auth.uid()) ANTES de qualquer tuple lock.
DROP TRIGGER IF EXISTS zzz_fence_stmt ON public.saved_resumes;
CREATE TRIGGER zzz_fence_stmt
  BEFORE INSERT OR UPDATE OR DELETE ON public.saved_resumes
  FOR EACH STATEMENT EXECUTE FUNCTION public._fence_profile_writes();

-- O protocolo antigo não carregava candidate_id entre INSERT do arquivo e write
-- do cache. O BEFORE INSERT abaixo marca explicitamente a row legacy mais recente.
-- Para authenticated, o statement fence JÁ possui o advisory; antes de tocar
-- outras rows validamos que NEW.user_id é o uid da sessão. Para um writer owner/
-- service_role sem uid, BEFORE INSERT ainda ocorre antes da inserção da tupla e
-- pode adquirir advisory(NEW.user_id) sem inverter advisory↔tuple.
CREATE OR REPLACE FUNCTION public._mark_latest_legacy_source_on_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_auth_uid uuid := auth.uid();
BEGIN
  IF NEW.source = 'imported'
     AND NEW.extraction_status IS NULL
     AND NEW.extraction_attempt_id IS NULL
     AND NEW.client_import_id IS NULL
     AND COALESCE(NEW.is_current_source, false) = false THEN
    IF v_auth_uid IS NOT NULL AND v_auth_uid <> NEW.user_id THEN
      RAISE EXCEPTION 'saved_resume_owner_mismatch' USING ERRCODE='28000';
    END IF;
    IF v_auth_uid IS NULL THEN
      PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(NEW.user_id));
    END IF;

    -- Um app antigo não tem protocolo apply/promote. Aceitar a row como histórico
    -- e retornar sucesso seria desonesto: o client concluiria que substituiu a
    -- fonte, mas a current canônica continuaria ativa. Falhamos ANTES de tocar
    -- marker/cache. O HEAD^ conserva o PDF no retry local; o blob já enviado pode
    -- ficar órfão porque Storage↔Postgres não compartilham transação.
    IF EXISTS (
      SELECT 1 FROM public.saved_resumes
       WHERE user_id = NEW.user_id AND source = 'imported'
         AND extraction_status = 'ready' AND is_current_source
    ) THEN
      RAISE EXCEPTION 'legacy_import_blocked_by_canonical_source'
        USING ERRCODE='55000';
    END IF;

    UPDATE public.saved_resumes
       SET is_latest_legacy_source = false
     WHERE user_id = NEW.user_id AND is_latest_legacy_source;

    -- Mover o marker NÃO toca o cache. No protocolo HEAD^ uma row B pode ser
    -- salva e sua extração falhar, deixando o cache de A. Sem candidate_id não
    -- há prova de vínculo: o cache permanece UNBOUND (sem source_resume_id), em
    -- vez de ser apagado ou falsamente rotulado como B.
    NEW.is_latest_legacy_source := true;
  ELSE
    -- Nem service_role pode forjar o marker numa candidata canônica.
    NEW.is_latest_legacy_source := false;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public._mark_latest_legacy_source_on_insert() FROM PUBLIC;
DROP TRIGGER IF EXISTS zzz_mark_latest_legacy_source ON public.saved_resumes;
CREATE TRIGGER zzz_mark_latest_legacy_source
  BEFORE INSERT ON public.saved_resumes
  FOR EACH ROW EXECUTE FUNCTION public._mark_latest_legacy_source_on_insert();

-- Fecha também a janela operacional ENTRE as duas migrations: um HEAD^ podia
-- inserir depois do backfill de 120000 e antes deste trigger existir. Recalcular
-- aqui é idempotente; o trigger já instalado cuida de qualquer INSERT posterior.
UPDATE public.saved_resumes
   SET is_latest_legacy_source = false
 WHERE is_latest_legacy_source;
WITH ranked AS (
  SELECT legacy.id,
         row_number() OVER (
           PARTITION BY legacy.user_id ORDER BY legacy.created_at DESC, legacy.id DESC
         ) AS rn
    FROM public.saved_resumes AS legacy
   WHERE legacy.source = 'imported'
     AND legacy.extraction_status IS NULL
     AND legacy.extraction_attempt_id IS NULL
     AND legacy.client_import_id IS NULL
     AND legacy.is_current_source = false
     AND NOT EXISTS (
       SELECT 1 FROM public.saved_resumes AS canonical
        WHERE canonical.user_id = legacy.user_id
          AND canonical.source = 'imported'
          AND canonical.extraction_status = 'ready'
          AND canonical.is_current_source
     )
)
UPDATE public.saved_resumes AS s
   SET is_latest_legacy_source = true
  FROM ranked
 WHERE s.id = ranked.id AND ranked.rn = 1;

-- Fonte ÚNICA do cache canônico. extraction_meta não pode injetar/sobrescrever
-- as chaves de integridade: removemos qualquer colisão antes de anexar parsed,
-- raw_text, imported_at e source_resume_id derivados da row READY/current.
CREATE OR REPLACE FUNCTION public._canonical_import_cache(p_resume_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT
    (COALESCE(extraction_meta, '{}'::jsonb)
       - 'parsed' - 'raw_text' - 'imported_at' - 'source_resume_id')
    || jsonb_build_object(
         'parsed', COALESCE(extraction_legacy_parsed, '{}'::jsonb),
         'imported_at', to_char(
           COALESCE(extraction_completed_at, created_at) AT TIME ZONE 'UTC',
           'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
         'source_resume_id', id::text)
    || CASE
         WHEN extraction_raw_text IS NOT NULL AND btrim(extraction_raw_text) <> ''
           THEN jsonb_build_object('raw_text', extraction_raw_text)
         ELSE '{}'::jsonb
       END
    FROM public.saved_resumes
   WHERE id = p_resume_id
     AND source = 'imported'
     AND extraction_status = 'ready'
     AND is_current_source
$$;
REVOKE ALL ON FUNCTION public._canonical_import_cache(uuid) FROM PUBLIC;

-- Toda escrita de gamification_data passa por este guard. NEW nunca é fonte de
-- verdade para uma current canônica: se existe READY/current, reconstruímos o
-- objeto da row. Sem current, cache HEAD^ sem candidate_id fica explicitamente
-- UNBOUND: é preservado, mas NUNCA recebe source_resume_id inferido por ordem ou
-- timestamp. Um id explícito só é aceito se for exatamente a marker legacy viva;
-- divergências preservam o OLD honesto (unbound ou ligado à marker), sem rebind.
CREATE OR REPLACE FUNCTION public._guard_user_profile_import_cache()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_current_id uuid; v_legacy_id uuid; v_cache jsonb;
  v_incoming jsonb; v_old jsonb; v_incoming_source text; v_old_source text;
BEGIN
  NEW.gamification_data := COALESCE(NEW.gamification_data, '{}'::jsonb);

  SELECT id INTO v_current_id
    FROM public.saved_resumes
   WHERE user_id = NEW.id AND source = 'imported'
     AND extraction_status = 'ready' AND is_current_source
   LIMIT 1;

  IF v_current_id IS NOT NULL THEN
    v_cache := public._canonical_import_cache(v_current_id);
    IF v_cache IS NULL THEN
      RAISE EXCEPTION 'current_import_cache_unbuildable' USING ERRCODE='23514';
    END IF;
    NEW.gamification_data := jsonb_set(
      NEW.gamification_data, '{imported_resume}', v_cache, true);
    RETURN NEW;
  END IF;

  SELECT id INTO v_legacy_id
    FROM public.saved_resumes
   WHERE user_id = NEW.id AND is_latest_legacy_source
   LIMIT 1;

  v_incoming := NEW.gamification_data->'imported_resume';

  -- UPDATEs parciais/antigos podem reenviar gamification_data sem a chave. Cache
  -- UNBOUND precisa sobreviver também: ausência da chave não prova que o caller
  -- quis/foi capaz de identificar qual fonte apagar.
  IF jsonb_typeof(v_incoming) IS DISTINCT FROM 'object' THEN
    IF TG_OP = 'UPDATE' THEN
      v_old := COALESCE(OLD.gamification_data, '{}'::jsonb)->'imported_resume';
      v_old_source := NULLIF(btrim(v_old->>'source_resume_id'), '');
      -- O HEAD^ `_clearLegacyImportedResume()` faz read-modify-write do objeto
      -- inteiro e envia EXATAMENTE OLD menos imported_resume. Esta forma é
      -- distinguível de update parcial/stale e só é honrada para o próprio uid.
      -- Limitação inevitável do protocolo sem token: se este clear atrasar e
      -- chegar depois da Edge, ele ainda pode limpar o cache recém-extraído.
      IF auth.uid() = NEW.id
         AND jsonb_typeof(v_old) = 'object'
         AND NEW.gamification_data IS NOT DISTINCT FROM
             (COALESCE(OLD.gamification_data, '{}'::jsonb) - 'imported_resume') THEN
        RETURN NEW;
      END IF;
      IF v_old_source IS NULL AND jsonb_typeof(v_old) = 'object' THEN
        v_old := v_old - 'source_resume_id';
      END IF;
    END IF;
    IF jsonb_typeof(v_old) = 'object'
       AND (v_old_source IS NULL OR v_old_source = v_legacy_id::text) THEN
      NEW.gamification_data := jsonb_set(
        NEW.gamification_data, '{imported_resume}', v_old, true);
    ELSE
      NEW.gamification_data := NEW.gamification_data - 'imported_resume';
    END IF;
    RETURN NEW;
  END IF;

  v_incoming_source := NULLIF(btrim(v_incoming->>'source_resume_id'), '');
  IF v_incoming_source IS NULL THEN
    -- Compatibilidade honesta: mantém o objeto sem vínculo e remove até a chave
    -- null/whitespace, para o estado UNBOUND ser materialmente inequívoco.
    NEW.gamification_data := jsonb_set(
      NEW.gamification_data, '{imported_resume}',
      v_incoming - 'source_resume_id', true);
    RETURN NEW;
  END IF;
  IF v_legacy_id IS NOT NULL AND v_incoming_source = v_legacy_id::text THEN
    NEW.gamification_data := jsonb_set(
      NEW.gamification_data, '{imported_resume}', v_incoming, true);
    RETURN NEW;
  END IF;

  -- Id explícito divergente = resposta tardia/forjada de outra fonte. Se OLD é
  -- unbound ou representa a marker viva, preservamo-lo; caso contrário removemos.
  IF TG_OP = 'UPDATE' THEN
    v_old := COALESCE(OLD.gamification_data, '{}'::jsonb)->'imported_resume';
    v_old_source := NULLIF(btrim(v_old->>'source_resume_id'), '');
    IF v_old_source IS NULL AND jsonb_typeof(v_old) = 'object' THEN
      v_old := v_old - 'source_resume_id';
    END IF;
  END IF;
  IF jsonb_typeof(v_old) = 'object'
     AND (v_old_source IS NULL OR v_old_source = v_legacy_id::text) THEN
    NEW.gamification_data := jsonb_set(
      NEW.gamification_data, '{imported_resume}', v_old, true);
  ELSE
    NEW.gamification_data := NEW.gamification_data - 'imported_resume';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public._guard_user_profile_import_cache() FROM PUBLIC;

-- Authenticated pega advisory ANTES do tuple de user_profiles. Edge legacy usa
-- service_role (auth.uid NULL): não pega advisory, mas o row guard + o próprio
-- tuple lock de user_profiles serializam o estado final com promoção/remoção;
-- ele apenas LÊ saved_resumes e portanto não cria ciclo de locks.
DROP TRIGGER IF EXISTS zzz_fence_gamification_stmt ON public.user_profiles;
CREATE TRIGGER zzz_fence_gamification_stmt
  BEFORE UPDATE OF gamification_data ON public.user_profiles
  FOR EACH STATEMENT EXECUTE FUNCTION public._fence_profile_writes();
DROP TRIGGER IF EXISTS zzz_fence_user_profile_delete_stmt ON public.user_profiles;
CREATE TRIGGER zzz_fence_user_profile_delete_stmt
  BEFORE DELETE ON public.user_profiles
  FOR EACH STATEMENT EXECUTE FUNCTION public._fence_profile_writes();
DROP TRIGGER IF EXISTS zzz_guard_import_cache_insert ON public.user_profiles;
CREATE TRIGGER zzz_guard_import_cache_insert
  BEFORE INSERT ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public._guard_user_profile_import_cache();
DROP TRIGGER IF EXISTS zzz_guard_import_cache_update ON public.user_profiles;
CREATE TRIGGER zzz_guard_import_cache_update
  BEFORE UPDATE OF gamification_data ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public._guard_user_profile_import_cache();

-- Compatibilidade de DELETE do HEAD^ sem cache órfão. O trigger ROW NÃO pega
-- advisory: statement/RPC já o fizeram. Cascata da exclusão do user_profiles é
-- ignorada (o pai está sendo removido; tentar atualizá-lo seria desnecessário).
-- Cache UNBOUND não pode ser atribuído à row apagada, nem mesmo se ela era a
-- marker mais recente; por isso só limpamos current canônica ou id EXATO.
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

  IF COALESCE(OLD.is_current_source, false)
     OR v_cache_source = OLD.id::text THEN
    UPDATE public.user_profiles
       SET gamification_data = COALESCE(gamification_data, '{}'::jsonb) - 'imported_resume'
     WHERE id = OLD.user_id;
  END IF;
  RETURN OLD;
END $$;
REVOKE ALL ON FUNCTION public._cleanup_import_cache_after_saved_resume_delete() FROM PUBLIC;
DROP TRIGGER IF EXISTS zzz_cleanup_import_cache ON public.saved_resumes;
CREATE TRIGGER zzz_cleanup_import_cache
  AFTER DELETE ON public.saved_resumes
  FOR EACH ROW EXECUTE FUNCTION public._cleanup_import_cache_after_saved_resume_delete();

-- Qualquer source_resume_id legacy encontrado no deploy/reapply veio da ponte
-- heurística anterior (o HEAD^ nunca enviava candidate_id). Removemos só essa
-- chave, preservando o cache; depois normalizamos apenas currents canônicas que
-- divergem. Não há UPDATE no-op em massa nem vínculo A→B inventado.
UPDATE public.user_profiles AS up
   SET gamification_data = jsonb_set(
         COALESCE(up.gamification_data, '{}'::jsonb), '{imported_resume}',
         (COALESCE(up.gamification_data, '{}'::jsonb)->'imported_resume')
           - 'source_resume_id', true)
 WHERE jsonb_typeof(COALESCE(up.gamification_data, '{}'::jsonb)->'imported_resume')='object'
   AND (COALESCE(up.gamification_data, '{}'::jsonb)->'imported_resume') ? 'source_resume_id'
   AND NOT EXISTS (
     SELECT 1 FROM public.saved_resumes sr
      WHERE sr.user_id=up.id AND sr.source='imported'
        AND sr.extraction_status='ready' AND sr.is_current_source);

WITH expected AS (
  SELECT up.id, public._canonical_import_cache(sr.id) AS cache
    FROM public.user_profiles up
    JOIN public.saved_resumes sr ON sr.user_id=up.id
   WHERE sr.source='imported' AND sr.extraction_status='ready'
     AND sr.is_current_source
)
UPDATE public.user_profiles AS up
   SET gamification_data = jsonb_set(
         COALESCE(up.gamification_data, '{}'::jsonb),
         '{imported_resume}', expected.cache, true)
  FROM expected
 WHERE expected.id=up.id
   AND expected.cache IS NOT NULL
   AND COALESCE(up.gamification_data, '{}'::jsonb)->'imported_resume'
       IS DISTINCT FROM expected.cache;

-- A migration 120000 manteve a ponte DELETE própria ativa para não quebrar o
-- HEAD^ entre commits de migration. Agora a recriamos DEPOIS de instalar
-- fence+cleanup, na mesma transação. O cliente novo segue usando
-- delete_saved_resume (DB→blob), caminho canônico e mais recuperável.
-- service_role NÃO recebe esta ponte: não existe caller Edge de DELETE direto e,
-- sem auth.uid(), o fence statement não teria uma chave. RPCs DEFINER e cascatas
-- do owner continuam funcionando sem privilégio de tabela do invocador.
DROP POLICY IF EXISTS "Users can delete their own resumes" ON public.saved_resumes;
CREATE POLICY "Users can delete their own resumes"
  ON public.saved_resumes FOR DELETE TO authenticated
  USING (
    (SELECT auth.uid()) = user_id
    AND split_part(file_path, '/', 1) = (SELECT auth.uid())::text
    AND cardinality(string_to_array(file_path, '/')) >= 2
    AND array_position(string_to_array(file_path, '/'), '') IS NULL
    AND NOT (string_to_array(file_path, '/') && ARRAY['.','..']::text[])
    AND strpos(file_path, E'\\') = 0
  );
GRANT DELETE ON public.saved_resumes TO authenticated;
REVOKE DELETE ON public.saved_resumes FROM anon, service_role;

-- Exclusão CANÔNICA da conta. O caminho real começa em auth.users e cascata
-- para user_profiles → saved_resumes. Sem este lock no TOPO, a cascata já teria
-- tuple de user_profiles quando chegasse à filha, enquanto uma importação faz
-- advisory → saved_resumes → user_profiles: ciclo/deadlock. Aqui a ordem vira
-- advisory(user) → auth tuple → todas as cascatas. Triggers aninhados podem (e
-- devem) continuar pulando uma segunda aquisição.
CREATE OR REPLACE FUNCTION public.delete_user()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE='28000';
  END IF;
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(v_uid));
  DELETE FROM auth.users WHERE id = v_uid;
END $$;
REVOKE ALL ON FUNCTION public.delete_user() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_user() TO authenticated;

-- Aposenta as funções BEFORE ROW antigas (nenhum trigger as referencia mais).
DROP FUNCTION IF EXISTS public._lock_profile_by_user() CASCADE;
DROP FUNCTION IF EXISTS public._lock_profile_by_experience() CASCADE;
DROP FUNCTION IF EXISTS public._lock_profile_by_education() CASCADE;
DROP FUNCTION IF EXISTS public._lock_profile_by_project() CASCADE;

-- ── APPLY (fill-empty) — CORE sem checagem de auth (as wrappers autorizam) ───
-- Retorna {status,applied,preserved,failed}. NÃO chamar direto do client — use
-- save_profile_fill_empty (authenticated) ou save_profile_fill_empty_service
-- (service_role/Edge). A ordem de lock (advisory→tuple) fica aqui.
DROP FUNCTION IF EXISTS public._save_profile_fill_empty_core(uuid, jsonb);
CREATE FUNCTION public._save_profile_fill_empty_core(p_user_id uuid, p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_exp jsonb; v_edu jsonb; v_lang jsonb; v_skill jsonb; v_cert jsonb; v_proj jsonb; v_item jsonb; v_bullet jsonb;
  v_text text; v_exp_id uuid; v_edu_id uuid; v_start date; v_end date; v_raw_cur boolean; v_ord bigint; v_bord bigint;
  v_applied text[] := '{}'; v_preserved text[] := '{}'; v_failed text[] := '{}'; v_status text;
  -- Contadores por seção. Em seções compostas, qualquer item significativo
  -- inválido PROPAGA até o savepoint da seção: todos os irmãos são desfeitos e
  -- a seção entra em failed. Em listas simples, v_secn impede declarar applied
  -- quando nenhum item renderizável foi realmente inserido.
  v_att int; v_secn int;
BEGIN
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'p_user_id null' USING ERRCODE='22004'; END IF;
  IF p_data IS NULL THEN RAISE EXCEPTION 'p_data null' USING ERRCODE='22004'; END IF;
  -- Validação ESTRUTURAL fail-closed ANTES de qualquer escrita (blocker 6). Vale
  -- para os DOIS wrappers (authenticated + service_role) pois ambos passam por
  -- aqui. Malformado (ex.: first_name objeto) → RAISE, zero escrita.
  PERFORM public._validate_profile_payload(p_data);
  -- (Round 7/hardening) a RPC-base também é fail-closed para payload sem dado
  -- persistível. Antes `{}` criava profile_personal vazia, marcava seis seções
  -- ausentes como applied e avançava last_extracted_at. Retorno tipado, zero write.
  IF NOT public._profile_payload_has_content(p_data) THEN
    RETURN jsonb_build_object('status','failure','applied','[]'::jsonb,
      'preserved','[]'::jsonb,'failed',jsonb_build_array('empty_payload'));
  END IF;
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(p_user_id));

  -- profile_personal (fill-empty; erro PROPAGA)
  INSERT INTO public.profile_personal (
    user_id, first_name, last_name, email, phone_country_code, phone_number, headline, summary,
    gender, age_range, location_country, location_state, location_city, location_postal_code,
    location_street_address, attribution_source, profile_source, completeness_score, linkedin_url, website)
  VALUES (
    -- (Round 6 blocker 1) o PRIMEIRO insert (profile_personal ainda não existe) também
    -- precisa sanitizar o email: _resolve_contact_email(NULL, incoming) grava só se for
    -- profissional (relay Apple / private.icloud / phone_*@stage.app viram NULL). Antes
    -- só o ON CONFLICT DO UPDATE sanitizava → um perfil novo persistia o relay cru.
    p_user_id, p_data->'personal'->>'first_name', p_data->'personal'->>'last_name',
    public._resolve_contact_email(NULL, p_data->'personal'->>'email'),
    p_data->'personal'->>'phone_country_code', p_data->'personal'->>'phone_number', p_data->'personal'->>'headline',
    p_data->'personal'->>'summary', p_data->'personal'->>'gender', p_data->'personal'->>'age_range',
    p_data->'personal'->>'location_country', p_data->'personal'->>'location_state', p_data->'personal'->>'location_city',
    p_data->'personal'->>'location_postal_code', p_data->'personal'->>'location_street_address',
    p_data->'personal'->>'attribution_source', COALESCE(p_data->'personal'->>'profile_source','imported'),
    COALESCE(public.safe_integer(p_data->'personal'->>'completeness_score'),0),
    p_data->'personal'->>'linkedin', p_data->'personal'->>'website')
  ON CONFLICT (user_id) DO UPDATE SET
    first_name=public._fill_empty_text(public.profile_personal.first_name,EXCLUDED.first_name),
    last_name=public._fill_empty_text(public.profile_personal.last_name,EXCLUDED.last_name),
    -- (blocker C) email NÃO é _fill_empty_text cego: um relay/sintético existente é
    -- SUBSTITUÍVEL por um email profissional do CV; um profissional existente é
    -- preservado; o CV nunca introduz relay/sintético.
    email=public._resolve_contact_email(public.profile_personal.email,EXCLUDED.email),
    phone_country_code=public._fill_empty_text(public.profile_personal.phone_country_code,EXCLUDED.phone_country_code),
    phone_number=public._fill_empty_text(public.profile_personal.phone_number,EXCLUDED.phone_number),
    headline=public._fill_empty_text(public.profile_personal.headline,EXCLUDED.headline),
    summary=public._fill_empty_text(public.profile_personal.summary,EXCLUDED.summary),
    gender=public._fill_empty_text(public.profile_personal.gender,EXCLUDED.gender),
    age_range=public._fill_empty_text(public.profile_personal.age_range,EXCLUDED.age_range),
    location_country=public._fill_empty_text(public.profile_personal.location_country,EXCLUDED.location_country),
    location_state=public._fill_empty_text(public.profile_personal.location_state,EXCLUDED.location_state),
    location_city=public._fill_empty_text(public.profile_personal.location_city,EXCLUDED.location_city),
    location_postal_code=public._fill_empty_text(public.profile_personal.location_postal_code,EXCLUDED.location_postal_code),
    location_street_address=public._fill_empty_text(public.profile_personal.location_street_address,EXCLUDED.location_street_address),
    attribution_source=public._fill_empty_text(public.profile_personal.attribution_source,EXCLUDED.attribution_source),
    profile_source=public._fill_empty_text(public.profile_personal.profile_source,EXCLUDED.profile_source),
    linkedin_url=public._fill_empty_text(public.profile_personal.linkedin_url,EXCLUDED.linkedin_url),
    website=public._fill_empty_text(public.profile_personal.website,EXCLUDED.website),
    updated_at=now();

  -- experiences + bullets: FIDELIDADE COMPLETA via o CORE composto (blocker G) — o
  -- MESMO writer da revisão (kind, confidence, bullets angle/verb/strength/order). Injeta
  -- order_index (ordinality) e o needs_review DERIVADO da importação inicial (a derivação
  -- vence o default do core). Ruído totalmente vazio é ignorado; item SIGNIFICATIVO
  -- sem mínimo persistível ou com filho inválido falha o savepoint da SEÇÃO INTEIRA.
  -- Nunca persiste um irmão e descarta outro enquanto retorna success terminal.
  IF EXISTS (SELECT 1 FROM public.profile_experiences WHERE user_id=p_user_id LIMIT 1) THEN
    v_preserved := array_append(v_preserved,'experiences');
  ELSE BEGIN
    v_att := 0; v_secn := 0;
    FOR v_exp, v_ord IN SELECT value, ordinality FROM jsonb_array_elements(COALESCE(p_data->'experiences','[]'::jsonb)) WITH ORDINALITY
    LOOP
      -- `{}`/strings vazias sem filhos = ruído. Metadados/scaffold isolados
      -- (kind/confidence/needs_review e is_current=false/default) também não
      -- descrevem uma experiência. Já is_current=true é uma afirmação real:
      -- sem identidade/data mínima, falha a seção em vez de sumir silenciosamente.
      IF btrim(COALESCE(v_exp->>'title','')) = ''
         AND btrim(COALESCE(v_exp->>'company','')) = ''
         AND btrim(COALESCE(v_exp->>'start_date','')) = ''
         AND btrim(COALESCE(v_exp->>'end_date','')) = ''
         AND btrim(COALESCE(v_exp->>'location','')) = ''
         AND COALESCE((v_exp->>'is_current')::boolean, false) = false
         AND COALESCE(jsonb_array_length(v_exp->'bullets'),0) = 0 THEN
        CONTINUE;
      END IF;
      v_att := v_att + 1;
      v_start := public.safe_date(v_exp->>'start_date'); v_end := public.safe_date(v_exp->>'end_date');
      IF v_start IS NULL
         OR (btrim(COALESCE(v_exp->>'end_date','')) <> '' AND v_end IS NULL)
         OR (btrim(COALESCE(v_exp->>'title','')) = '' AND btrim(COALESCE(v_exp->>'company','')) = '') THEN
        RAISE EXCEPTION 'invalid_experience_minimum' USING ERRCODE='23514';
      END IF;
      v_raw_cur := COALESCE((v_exp->>'is_current')::boolean, FALSE);
      PERFORM public._save_experience_with_bullets_core(p_user_id,
        (v_exp - 'id') || jsonb_build_object(
          'order_index', (v_ord-1),
          'needs_review', (COALESCE(public.safe_numeric(v_exp->>'confidence'),1) < 0.5
                           OR (v_end IS NULL AND v_raw_cur=FALSE))));
      v_secn := v_secn + 1;
    END LOOP;
    IF v_secn > 0 THEN v_applied := array_append(v_applied,'experiences');
    ELSIF v_att > 0 THEN v_failed := array_append(v_failed,'experiences');  -- tentou, nada persistiu
    END IF;
  EXCEPTION WHEN OTHERS THEN v_failed := array_append(v_failed,'experiences'); END; END IF;

  -- education + filhas: FIDELIDADE COMPLETA via o CORE composto (blocker G) —
  -- institution_id, education_level, education_status, current_semester/school_year,
  -- gpa/max_gpa, majors/minors/activities. order_index por ordinality; qualquer
  -- item significativo inválido desfaz a seção inteira.
  IF EXISTS (SELECT 1 FROM public.profile_education WHERE user_id=p_user_id LIMIT 1) THEN
    v_preserved := array_append(v_preserved,'education');
  ELSE BEGIN
    v_att := 0; v_secn := 0;
    FOR v_edu, v_ord IN SELECT value, ordinality FROM jsonb_array_elements(COALESCE(p_data->'education','[]'::jsonb)) WITH ORDINALITY
    LOOP
      IF btrim(COALESCE(v_edu->>'institution','')) = ''
         AND btrim(COALESCE(v_edu->>'institution_id','')) = ''
         AND btrim(COALESCE(v_edu->>'degree','')) = ''
         AND btrim(COALESCE(v_edu->>'education_level','')) = ''
         AND btrim(COALESCE(v_edu->>'education_status','')) = ''
         AND btrim(COALESCE(v_edu->>'location','')) = ''
         AND btrim(COALESCE(v_edu->>'start_date','')) = ''
         AND btrim(COALESCE(v_edu->>'end_date','')) = ''
         -- Números não-null são dado acadêmico real (inclusive 0, que o
         -- schema real pode rejeitar); nunca classificá-los como ruído. Apenas
         -- confidence isolada segue sendo metadata de extração/scaffold.
         AND jsonb_typeof(v_edu->'current_semester') IS DISTINCT FROM 'number'
         AND jsonb_typeof(v_edu->'current_school_year') IS DISTINCT FROM 'number'
         AND jsonb_typeof(v_edu->'gpa') IS DISTINCT FROM 'number'
         AND jsonb_typeof(v_edu->'max_gpa') IS DISTINCT FROM 'number'
         AND COALESCE(jsonb_array_length(v_edu->'majors'),0) = 0
         AND COALESCE(jsonb_array_length(v_edu->'minors'),0) = 0
         AND COALESCE(jsonb_array_length(v_edu->'activities'),0) = 0 THEN
        CONTINUE;
      END IF;
      v_att := v_att + 1;
      v_start := public.safe_date(v_edu->>'start_date'); v_end := public.safe_date(v_edu->>'end_date');
      IF (btrim(COALESCE(v_edu->>'start_date','')) <> '' AND v_start IS NULL)
         OR (btrim(COALESCE(v_edu->>'end_date','')) <> '' AND v_end IS NULL) THEN
        RAISE EXCEPTION 'invalid_education_date' USING ERRCODE='23514';
      END IF;
      -- O validator estrutural aceita JSON number, mas semestre/ano são
      -- inteiros. Uma fração não pode virar NULL via safe_integer e ainda
      -- permitir promoção; limites de domínio continuam nos CHECKs reais.
      IF (jsonb_typeof(v_edu->'current_semester') = 'number'
            AND public.safe_integer(v_edu->>'current_semester') IS NULL)
         OR (jsonb_typeof(v_edu->'current_school_year') = 'number'
            AND public.safe_integer(v_edu->>'current_school_year') IS NULL) THEN
        RAISE EXCEPTION 'invalid_education_integer' USING ERRCODE='23514';
      END IF;
      IF btrim(COALESCE(v_edu->>'institution','')) = '' THEN
        RAISE EXCEPTION 'invalid_education_minimum' USING ERRCODE='23514';
      END IF;
      PERFORM public._save_education_with_children_core(p_user_id, (v_edu - 'id') || jsonb_build_object('order_index',(v_ord-1)));
      v_secn := v_secn + 1;
    END LOOP;
    IF v_secn > 0 THEN v_applied := array_append(v_applied,'education');
    ELSIF v_att > 0 THEN v_failed := array_append(v_failed,'education');
    END IF;
  EXCEPTION WHEN OTHERS THEN v_failed := array_append(v_failed,'education'); END; END IF;

  -- languages
  IF EXISTS (SELECT 1 FROM public.profile_languages WHERE user_id=p_user_id LIMIT 1) THEN v_preserved := array_append(v_preserved,'languages');
  ELSE BEGIN
    v_secn := 0;
    FOR v_lang, v_ord IN SELECT value, ordinality FROM jsonb_array_elements(COALESCE(p_data->'languages','[]'::jsonb)) WITH ORDINALITY
    LOOP
      IF btrim(COALESCE(v_lang->>'name','')) = '' THEN CONTINUE; END IF;  -- G/inv.7
      INSERT INTO public.profile_languages (user_id,name,proficiency,order_index) VALUES (p_user_id, v_lang->>'name', v_lang->>'proficiency', (v_ord-1)::int);
      v_secn := v_secn + 1;
    END LOOP; IF v_secn > 0 THEN v_applied := array_append(v_applied,'languages'); END IF;
  EXCEPTION WHEN OTHERS THEN v_failed := array_append(v_failed,'languages'); END; END IF;

  -- skills (ON CONFLICT DO NOTHING = dedup case-insensitive DOCUMENTADO)
  IF EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=p_user_id LIMIT 1) THEN v_preserved := array_append(v_preserved,'skills');
  ELSE BEGIN
    v_secn := 0;
    FOR v_skill, v_ord IN SELECT value, ordinality FROM jsonb_array_elements(COALESCE(p_data->'skills','[]'::jsonb)) WITH ORDINALITY
    LOOP
      IF btrim(COALESCE(v_skill->>'name','')) = '' THEN CONTINUE; END IF;  -- G/inv.7
      INSERT INTO public.profile_skills (user_id,name,category,order_index) VALUES (p_user_id, v_skill->>'name', v_skill->>'category', (v_ord-1)::int)
      ON CONFLICT (user_id, LOWER(name)) DO NOTHING;
      GET DIAGNOSTICS v_att = ROW_COUNT; v_secn := v_secn + v_att;
    END LOOP; IF v_secn > 0 THEN v_applied := array_append(v_applied,'skills'); END IF;
  EXCEPTION WHEN OTHERS THEN v_failed := array_append(v_failed,'skills'); END; END IF;

  -- certifications
  IF EXISTS (SELECT 1 FROM public.profile_certifications WHERE user_id=p_user_id LIMIT 1) THEN v_preserved := array_append(v_preserved,'certifications');
  ELSE BEGIN
    v_secn := 0;
    FOR v_cert, v_ord IN SELECT value, ordinality FROM jsonb_array_elements(COALESCE(p_data->'certifications','[]'::jsonb)) WITH ORDINALITY
    LOOP
      IF btrim(COALESCE(v_cert->>'name','')) = '' THEN CONTINUE; END IF;  -- G/inv.7
      INSERT INTO public.profile_certifications (user_id,name,issuer,date,order_index) VALUES (p_user_id, v_cert->>'name', v_cert->>'issuer', public.safe_date(v_cert->>'date'), (v_ord-1)::int);
      v_secn := v_secn + 1;
    END LOOP; IF v_secn > 0 THEN v_applied := array_append(v_applied,'certifications'); END IF;
  EXCEPTION WHEN OTHERS THEN v_failed := array_append(v_failed,'certifications'); END; END IF;

  -- projects + project_bullets: FIDELIDADE COMPLETA via o CORE composto (blocker G) —
  -- role, context, website, descrição, datas, is_current, E os project_bullets (que o
  -- fill-empty inline NÃO gravava). order_index por ordinality; qualquer item
  -- significativo inválido desfaz a seção inteira.
  IF EXISTS (SELECT 1 FROM public.profile_projects WHERE user_id=p_user_id LIMIT 1) THEN v_preserved := array_append(v_preserved,'projects');
  ELSE BEGIN
    v_att := 0; v_secn := 0;
    FOR v_proj, v_ord IN SELECT value, ordinality FROM jsonb_array_elements(COALESCE(p_data->'projects','[]'::jsonb)) WITH ORDINALITY
    LOOP
      IF btrim(COALESCE(v_proj->>'name','')) = ''
         AND btrim(COALESCE(v_proj->>'role','')) = ''
         AND btrim(COALESCE(v_proj->>'context','')) = ''
         AND btrim(COALESCE(v_proj->>'description','')) = ''
         AND btrim(COALESCE(v_proj->>'website','')) = ''
         AND btrim(COALESCE(v_proj->>'start_date','')) = ''
         AND btrim(COALESCE(v_proj->>'end_date','')) = ''
         -- false/default sozinho é scaffold; true afirma projeto em andamento
         -- e, sem nome, precisa falhar a seção em vez de ser descartado.
         AND COALESCE((v_proj->>'is_current')::boolean, false) = false
         AND COALESCE(jsonb_array_length(v_proj->'bullets'),0) = 0 THEN
        CONTINUE;
      END IF;
      v_att := v_att + 1;
      v_start := public.safe_date(v_proj->>'start_date'); v_end := public.safe_date(v_proj->>'end_date');
      IF (btrim(COALESCE(v_proj->>'start_date','')) <> '' AND v_start IS NULL)
         OR (btrim(COALESCE(v_proj->>'end_date','')) <> '' AND v_end IS NULL) THEN
        RAISE EXCEPTION 'invalid_project_date' USING ERRCODE='23514';
      END IF;
      IF btrim(COALESCE(v_proj->>'name','')) = '' THEN
        RAISE EXCEPTION 'invalid_project_minimum' USING ERRCODE='23514';
      END IF;
      PERFORM public._save_project_with_bullets_core(p_user_id, (v_proj - 'id') || jsonb_build_object('order_index',(v_ord-1)));
      v_secn := v_secn + 1;
    END LOOP;
    IF v_secn > 0 THEN v_applied := array_append(v_applied,'projects');
    ELSIF v_att > 0 THEN v_failed := array_append(v_failed,'projects');
    END IF;
  EXCEPTION WHEN OTHERS THEN v_failed := array_append(v_failed,'projects'); END; END IF;

  -- interests
  IF EXISTS (SELECT 1 FROM public.profile_interests WHERE user_id=p_user_id LIMIT 1) THEN v_preserved := array_append(v_preserved,'interests');
  ELSE BEGIN
    v_secn := 0;
    FOR v_item, v_ord IN SELECT value, ordinality FROM jsonb_array_elements(COALESCE(p_data->'interests','[]'::jsonb)) WITH ORDINALITY
    LOOP
      IF btrim(COALESCE(v_item->>'name','')) = '' THEN CONTINUE; END IF;  -- G/inv.7
      INSERT INTO public.profile_interests (user_id,name,order_index) VALUES (p_user_id, v_item->>'name', (v_ord-1)::int) ON CONFLICT (user_id, LOWER(name)) DO NOTHING;
      GET DIAGNOSTICS v_att = ROW_COUNT; v_secn := v_secn + v_att;
    END LOOP; IF v_secn > 0 THEN v_applied := array_append(v_applied,'interests'); END IF;
  EXCEPTION WHEN OTHERS THEN v_failed := array_append(v_failed,'interests'); END; END IF;

  -- awards
  IF EXISTS (SELECT 1 FROM public.profile_awards WHERE user_id=p_user_id LIMIT 1) THEN v_preserved := array_append(v_preserved,'awards');
  ELSE BEGIN
    v_secn := 0;
    FOR v_item, v_ord IN SELECT value, ordinality FROM jsonb_array_elements(COALESCE(p_data->'awards','[]'::jsonb)) WITH ORDINALITY
    LOOP
      IF btrim(COALESCE(v_item->>'name','')) = '' THEN CONTINUE; END IF;  -- G/inv.7
      INSERT INTO public.profile_awards (user_id,name,date,order_index) VALUES (p_user_id, v_item->>'name', public.safe_date(v_item->>'date'), (v_ord-1)::int);
      v_secn := v_secn + 1;
    END LOOP; IF v_secn > 0 THEN v_applied := array_append(v_applied,'awards'); END IF;
  EXCEPTION WHEN OTHERS THEN v_failed := array_append(v_failed,'awards'); END; END IF;

  -- coursework
  IF EXISTS (SELECT 1 FROM public.profile_coursework WHERE user_id=p_user_id LIMIT 1) THEN v_preserved := array_append(v_preserved,'coursework');
  ELSE BEGIN
    v_secn := 0;
    FOR v_item, v_ord IN SELECT value, ordinality FROM jsonb_array_elements(COALESCE(p_data->'coursework','[]'::jsonb)) WITH ORDINALITY
    LOOP
      IF btrim(COALESCE(v_item->>'name','')) = '' THEN CONTINUE; END IF;  -- G/inv.7
      INSERT INTO public.profile_coursework (user_id,name,order_index) VALUES (p_user_id, v_item->>'name', (v_ord-1)::int);
      v_secn := v_secn + 1;
    END LOOP; IF v_secn > 0 THEN v_applied := array_append(v_applied,'coursework'); END IF;
  EXCEPTION WHEN OTHERS THEN v_failed := array_append(v_failed,'coursework'); END; END IF;

  v_status := CASE WHEN array_length(v_failed,1) IS NULL THEN 'success' ELSE 'partial' END;
  IF v_status = 'success' THEN
    UPDATE public.profile_personal SET last_extracted_at = now() WHERE user_id = p_user_id;
  END IF;
  RETURN jsonb_build_object('status',v_status,'applied',to_jsonb(v_applied),'preserved',to_jsonb(v_preserved),'failed',to_jsonb(v_failed));
END;
$$;
REVOKE ALL ON FUNCTION public._save_profile_fill_empty_core(uuid, jsonb) FROM PUBLIC;

-- Wrapper AUTHENTICATED: exige auth.uid() = p_user_id (só o próprio perfil).
DROP FUNCTION IF EXISTS public.save_profile_fill_empty(uuid, jsonb);
CREATE FUNCTION public.save_profile_fill_empty(p_user_id uuid, p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN RAISE EXCEPTION 'not_authorized' USING ERRCODE='28000'; END IF;
  RETURN public._save_profile_fill_empty_core(p_user_id, p_data);
END $$;
REVOKE ALL ON FUNCTION public.save_profile_fill_empty(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_profile_fill_empty(uuid, jsonb) TO authenticated;

-- Wrapper SERVICE_ROLE (blocker 7): a Edge de extração NÃO tem JWT (auth.uid()
-- NULL) → não pode usar o wrapper authenticated. Este é o caminho EXPLÍCITO para
-- service_role: o próprio GRANT (só service_role) é a autorização; o lock por
-- p_user_id mantém a ordem advisory→tuple, fencing a extração como todo o resto.
-- extract-profile passa a chamar ESTE em vez do legado save_profile_from_json.
DROP FUNCTION IF EXISTS public.save_profile_fill_empty_service(uuid, jsonb);
CREATE FUNCTION public.save_profile_fill_empty_service(p_user_id uuid, p_data jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT public._save_profile_fill_empty_core(p_user_id, p_data)
$$;
REVOKE ALL ON FUNCTION public.save_profile_fill_empty_service(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_profile_fill_empty_service(uuid, jsonb) TO service_role;

-- ── SHIM DE DEPLOY PARA A EDGE LEGACY ───────────────────────────────────────────────
-- Migrations entram antes do deploy da Edge nova. Durante essa janela, a versão
-- HEAD^ de extract-profile ainda chama save_profile_from_json como service_role.
-- Preservamos assinatura + shape de sucesso, mas delegamos ao core fenced e
-- fill-empty. Qualquer `partial`, outcome malformado ou exceção vira erro
-- GENÉRICO: o RAISE desfaz globalmente tudo que o core pudesse ter escrito e
-- nunca vaza SQLERRM/dados do perfil pela resposta do PostgREST.
--
-- PROFILE_JSON_SCHEMA (HEAD^ e atual) não contém job_preferences; o shim não
-- lê nem toca Objetivos ao importar um CV.
CREATE OR REPLACE FUNCTION public.save_profile_from_json(p_user_id uuid, p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_apply jsonb;
BEGIN
  v_apply := public._save_profile_fill_empty_core(p_user_id, p_data);
  IF v_apply IS NULL
     OR v_apply->>'status' IS DISTINCT FROM 'success'
     OR jsonb_typeof(v_apply->'failed') IS DISTINCT FROM 'array'
     OR jsonb_array_length(v_apply->'failed') <> 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'profile_import_apply_failed';
  END IF;
  RETURN jsonb_build_object('status','success','user_id',p_user_id,'skipped_rows',0);
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'profile_import_apply_failed';
END
$$;
REVOKE ALL ON FUNCTION public.save_profile_from_json(uuid, jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.save_profile_from_json(uuid, jsonb) TO service_role;

-- ── VALIDAÇÃO DE SCHEMA (fail-closed ESTRUTURAL, ANTES de qualquer escrita) ──
-- Rejeita: não-objeto; chave de topo desconhecida; escalar com tipo errado
-- (ex.: first_name como objeto/array — NUNCA coage objeto/array→texto); seção
-- não-array; item não-objeto; campos de item/filhas com tipo errado; datas não
-- string, números não number, booleanos não boolean. O extrator real é o
-- contrato (as filhas majors/minors/activities são listas de STRING).
CREATE OR REPLACE FUNCTION public._assert_jtype(v jsonb, key text, allowed text[], ctx text)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
BEGIN
  IF v ? key AND NOT (jsonb_typeof(v->key) = ANY(allowed)) THEN
    RAISE EXCEPTION 'malformed_payload: %.% tipo % (esperava %)', ctx, key, jsonb_typeof(v->key), allowed
      USING ERRCODE='22023';
  END IF;
END $$;

-- Lista aninhada deve ser array de STRINGS (majors/minors/activities).
CREATE OR REPLACE FUNCTION public._assert_string_list(v jsonb, key text, ctx text)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
DECLARE el jsonb;
BEGIN
  IF NOT (v ? key) THEN RETURN; END IF;
  IF jsonb_typeof(v->key) NOT IN ('array','null') THEN
    RAISE EXCEPTION 'malformed_payload: %.% não é array', ctx, key USING ERRCODE='22023'; END IF;
  IF jsonb_typeof(v->key) = 'array' THEN
    FOR el IN SELECT value FROM jsonb_array_elements(v->key) LOOP
      IF jsonb_typeof(el) <> 'string' THEN
        RAISE EXCEPTION 'malformed_payload: %.% item não-string (%)', ctx, key, jsonb_typeof(el) USING ERRCODE='22023';
      END IF;
    END LOOP;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public._validate_profile_payload(p_data jsonb)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
DECLARE v_sec text; v_el jsonb; v_p jsonb; v_key text; v_b jsonb;
  c_str constant text[] := ARRAY['string','null'];
  c_num constant text[] := ARRAY['number','null'];
  c_bool constant text[] := ARRAY['boolean','null'];
  c_allowed_top constant text[] := ARRAY['personal','experiences','education','languages','skills',
    'certifications','projects','interests','awards','coursework',
    -- chaves históricas ignoradas pelo fill-empty; PROFILE_JSON_SCHEMA atual
    -- não as produz e importar CV nunca altera os Objetivos do usuário.
    'job_preferences','desired_titles','desired_position','other_locations','application_countries'];
BEGIN
  IF p_data IS NULL OR jsonb_typeof(p_data) <> 'object' THEN
    RAISE EXCEPTION 'malformed_payload: not_object' USING ERRCODE='22023';
  END IF;
  -- chave de topo desconhecida → falha.
  FOR v_key IN SELECT jsonb_object_keys(p_data) LOOP
    IF NOT (v_key = ANY(c_allowed_top)) THEN
      RAISE EXCEPTION 'malformed_payload: chave de topo desconhecida "%"', v_key USING ERRCODE='22023';
    END IF;
  END LOOP;

  -- personal: objeto; cada escalar conhecido com tipo correto (sem coerção).
  IF p_data ? 'personal' THEN
    IF jsonb_typeof(p_data->'personal') NOT IN ('object','null') THEN
      RAISE EXCEPTION 'malformed_payload: personal não é objeto' USING ERRCODE='22023'; END IF;
    IF jsonb_typeof(p_data->'personal') = 'object' THEN
      v_p := p_data->'personal';
      FOREACH v_key IN ARRAY ARRAY['first_name','last_name','email','phone_country_code','phone_number',
        'headline','summary','gender','age_range','location_country','location_state','location_city',
        'location_postal_code','location_street_address','attribution_source','profile_source','linkedin','website']
      LOOP PERFORM public._assert_jtype(v_p, v_key, c_str, 'personal'); END LOOP;
      PERFORM public._assert_jtype(v_p, 'completeness_score', ARRAY['number','string','null'], 'personal');
    END IF;
  END IF;

  -- seções: array; item objeto; campos de item tipados.
  FOREACH v_sec IN ARRAY ARRAY['experiences','education','languages','skills',
    'certifications','projects','interests','awards','coursework']
  LOOP
    IF NOT (p_data ? v_sec) THEN CONTINUE; END IF;
    IF jsonb_typeof(p_data->v_sec) NOT IN ('array','null') THEN
      RAISE EXCEPTION 'malformed_payload: % não é array', v_sec USING ERRCODE='22023'; END IF;
    IF jsonb_typeof(p_data->v_sec) <> 'array' THEN CONTINUE; END IF;
    FOR v_el IN SELECT value FROM jsonb_array_elements(p_data->v_sec) LOOP
      IF jsonb_typeof(v_el) <> 'object' THEN
        RAISE EXCEPTION 'malformed_payload: item de % não é objeto', v_sec USING ERRCODE='22023'; END IF;
      IF v_sec = 'experiences' THEN
        PERFORM public._assert_jtype(v_el,'title',c_str,'experiences');
        PERFORM public._assert_jtype(v_el,'company',c_str,'experiences');
        PERFORM public._assert_jtype(v_el,'location',c_str,'experiences');
        PERFORM public._assert_jtype(v_el,'start_date',c_str,'experiences');
        PERFORM public._assert_jtype(v_el,'end_date',c_str,'experiences');
        PERFORM public._assert_jtype(v_el,'is_current',c_bool,'experiences');
        PERFORM public._assert_jtype(v_el,'needs_review',c_bool,'experiences');
        PERFORM public._assert_jtype(v_el,'confidence',c_num,'experiences');
        PERFORM public._assert_jtype(v_el,'kind',c_str,'experiences');
        PERFORM public._assert_jtype(v_el,'bullets',ARRAY['array','null'],'experiences');
        IF jsonb_typeof(v_el->'bullets')='array' THEN
          FOR v_b IN SELECT value FROM jsonb_array_elements(v_el->'bullets') LOOP
            IF jsonb_typeof(v_b) <> 'object' THEN RAISE EXCEPTION 'malformed_payload: bullet não é objeto' USING ERRCODE='22023'; END IF;
            PERFORM public._assert_jtype(v_b,'text',c_str,'bullet');
            PERFORM public._assert_jtype(v_b,'angle',c_str,'bullet');
            PERFORM public._assert_jtype(v_b,'verb',c_str,'bullet');
            PERFORM public._assert_jtype(v_b,'strength_score',c_num,'bullet');
          END LOOP;
        END IF;
      ELSIF v_sec = 'education' THEN
        PERFORM public._assert_jtype(v_el,'institution',c_str,'education');
        PERFORM public._assert_jtype(v_el,'institution_id',c_str,'education');
        PERFORM public._assert_jtype(v_el,'education_level',c_str,'education');
        PERFORM public._assert_jtype(v_el,'education_status',c_str,'education');
        PERFORM public._assert_jtype(v_el,'location',c_str,'education');
        PERFORM public._assert_jtype(v_el,'degree',c_str,'education');
        PERFORM public._assert_jtype(v_el,'start_date',c_str,'education');
        PERFORM public._assert_jtype(v_el,'end_date',c_str,'education');
        PERFORM public._assert_jtype(v_el,'current_semester',c_num,'education');
        PERFORM public._assert_jtype(v_el,'current_school_year',c_num,'education');
        PERFORM public._assert_jtype(v_el,'gpa',c_num,'education');
        PERFORM public._assert_jtype(v_el,'max_gpa',c_num,'education');
        PERFORM public._assert_jtype(v_el,'confidence',c_num,'education');
        PERFORM public._assert_string_list(v_el,'majors','education');
        PERFORM public._assert_string_list(v_el,'minors','education');
        PERFORM public._assert_string_list(v_el,'activities','education');
      ELSIF v_sec = 'languages' THEN
        PERFORM public._assert_jtype(v_el,'name',c_str,'languages');
        PERFORM public._assert_jtype(v_el,'proficiency',c_str,'languages');
      ELSIF v_sec = 'certifications' THEN
        PERFORM public._assert_jtype(v_el,'name',c_str,'certifications');
        PERFORM public._assert_jtype(v_el,'issuer',c_str,'certifications');
        PERFORM public._assert_jtype(v_el,'date',c_str,'certifications');
      ELSIF v_sec = 'projects' THEN
        PERFORM public._assert_jtype(v_el,'name',c_str,'projects');
        PERFORM public._assert_jtype(v_el,'role',c_str,'projects');
        PERFORM public._assert_jtype(v_el,'context',c_str,'projects');
        PERFORM public._assert_jtype(v_el,'website',c_str,'projects');
        PERFORM public._assert_jtype(v_el,'description',c_str,'projects');
        PERFORM public._assert_jtype(v_el,'is_current',c_bool,'projects');
        -- (blocker H) fidelidade completa do projeto: datas + bullets tipados.
        PERFORM public._assert_jtype(v_el,'start_date',c_str,'projects');
        PERFORM public._assert_jtype(v_el,'end_date',c_str,'projects');
        PERFORM public._assert_jtype(v_el,'bullets',ARRAY['array','null'],'projects');
        IF jsonb_typeof(v_el->'bullets')='array' THEN
          FOR v_b IN SELECT value FROM jsonb_array_elements(v_el->'bullets') LOOP
            IF jsonb_typeof(v_b) <> 'object' THEN RAISE EXCEPTION 'malformed_payload: project bullet não é objeto' USING ERRCODE='22023'; END IF;
            PERFORM public._assert_jtype(v_b,'text',c_str,'project_bullet');
          END LOOP;
        END IF;
      ELSIF v_sec = 'awards' THEN
        PERFORM public._assert_jtype(v_el,'name',c_str,'awards');
        PERFORM public._assert_jtype(v_el,'date',c_str,'awards');
      ELSIF v_sec = 'skills' THEN
        PERFORM public._assert_jtype(v_el,'name',c_str,'skills');
        -- category é persistida pelo fill-empty; sem esta validação, `->>`
        -- coagia objeto/array para texto e promovia um valor estruturalmente inválido.
        PERFORM public._assert_jtype(v_el,'category',c_str,'skills');
      ELSE  -- interests, coursework: name string
        PERFORM public._assert_jtype(v_el,'name',c_str,v_sec);
      END IF;
    END LOOP;
  END LOOP;
END $$;

-- Conteúdo real e RENDERIZÁVEL? (blocker G) — um array não-vazio por si só NÃO é
-- conteúdo: itens sem os campos mínimos renderizáveis (só {}, whitespace, ruído)
-- não contam. Exige ao menos UM campo pessoal útil OU UM item profissional com o
-- campo mínimo renderável preenchido (EXISTS por seção). Assim `{"skills":[{}]}`,
-- `{"skills":[{"name":"  "}]}`, `{"experiences":[{}]}` etc. NUNCA viram ready/current.
CREATE OR REPLACE FUNCTION public._profile_payload_has_content(p_data jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT
    -- pessoais úteis
    btrim(COALESCE(p_data->'personal'->>'first_name','')) <> '' OR
    btrim(COALESCE(p_data->'personal'->>'last_name','')) <> '' OR
    -- (Round 6 blocker 1) só um email PROFISSIONAL conta como conteúdo: um payload que
    -- só tem relay/sintético NÃO é conteúdo → não vira ready/current nem deixa linha
    -- pessoal vazia (has_content=false ⇒ apply_and_promote levanta empty_payload antes
    -- de qualquer escrita/recibo).
    public._is_public_contact_email(p_data->'personal'->>'email') OR
    btrim(COALESCE(p_data->'personal'->>'phone_number','')) <> '' OR
    btrim(COALESCE(p_data->'personal'->>'headline','')) <> '' OR
    btrim(COALESCE(p_data->'personal'->>'summary','')) <> '' OR
    -- Demais campos pessoais que o core realmente persiste também são conteúdo.
    -- Não contam isoladamente: profile_source/completeness/attribution e DDI sem
    -- número (metadados, não perfil renderizável).
    btrim(COALESCE(p_data->'personal'->>'gender','')) <> '' OR
    btrim(COALESCE(p_data->'personal'->>'age_range','')) <> '' OR
    btrim(COALESCE(p_data->'personal'->>'location_country','')) <> '' OR
    btrim(COALESCE(p_data->'personal'->>'location_state','')) <> '' OR
    btrim(COALESCE(p_data->'personal'->>'location_city','')) <> '' OR
    btrim(COALESCE(p_data->'personal'->>'location_postal_code','')) <> '' OR
    btrim(COALESCE(p_data->'personal'->>'location_street_address','')) <> '' OR
    btrim(COALESCE(p_data->'personal'->>'linkedin','')) <> '' OR
    btrim(COALESCE(p_data->'personal'->>'website','')) <> '' OR
    -- listas simples renderizáveis: precisa de name não-vazio
    EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_data->'skills')='array' THEN p_data->'skills' ELSE '[]'::jsonb END) e
      WHERE jsonb_typeof(e)='object' AND btrim(COALESCE(e->>'name','')) <> '') OR
    EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_data->'interests')='array' THEN p_data->'interests' ELSE '[]'::jsonb END) e
      WHERE jsonb_typeof(e)='object' AND btrim(COALESCE(e->>'name','')) <> '') OR
    EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_data->'coursework')='array' THEN p_data->'coursework' ELSE '[]'::jsonb END) e
      WHERE jsonb_typeof(e)='object' AND btrim(COALESCE(e->>'name','')) <> '') OR
    EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_data->'awards')='array' THEN p_data->'awards' ELSE '[]'::jsonb END) e
      WHERE jsonb_typeof(e)='object' AND btrim(COALESCE(e->>'name','')) <> '') OR
    EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_data->'projects')='array' THEN p_data->'projects' ELSE '[]'::jsonb END) e
      WHERE jsonb_typeof(e)='object' AND btrim(COALESCE(e->>'name','')) <> '') OR
    EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_data->'certifications')='array' THEN p_data->'certifications' ELSE '[]'::jsonb END) e
      WHERE jsonb_typeof(e)='object' AND btrim(COALESCE(e->>'name','')) <> '') OR
    EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_data->'languages')='array' THEN p_data->'languages' ELSE '[]'::jsonb END) e
      WHERE jsonb_typeof(e)='object' AND btrim(COALESCE(e->>'name','')) <> '') OR
    -- experiências: title OU company preenchidos E start_date PERSISTÍVEL. O writer
    -- (fill-empty e save_experience_with_bullets) EXIGE safe_date(start_date) não-nula
    -- e PULA a experiência caso contrário. Sem casar o has_content com isso, um payload
    -- só-experiência com data não-ISO (ex.: LLM desobedeceu o prompt "sempre YYYY-MM-DD"
    -- e mandou "2020") passava no has_content por title/company mas o writer gravava 0
    -- linhas → status='success' promovendo a fonte com perfil relacional VAZIO (só o
    -- cache legacy tinha o dado). Alinhado ⇒ ou a experiência é persistível e conta como
    -- conteúdo, ou o payload é honestamente rejeitado como vazio (nunca vira ready/current).
    EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_data->'experiences')='array' THEN p_data->'experiences' ELSE '[]'::jsonb END) e
      WHERE jsonb_typeof(e)='object'
        AND (btrim(COALESCE(e->>'title','')) <> '' OR btrim(COALESCE(e->>'company','')) <> '')
        AND public.safe_date(e->>'start_date') IS NOT NULL) OR
    -- formação: institution preenchida
    EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_data->'education')='array' THEN p_data->'education' ELSE '[]'::jsonb END) e
      WHERE jsonb_typeof(e)='object' AND btrim(COALESCE(e->>'institution','')) <> '')
$$;

-- Perfil TEM dado protegido? (espelha snapshotHasProtectedProfileData no Dart —
-- decide importação inicial [vazio] × substituição [existente]).
CREATE OR REPLACE FUNCTION public._profile_has_protected_data(p_uid uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path = '' AS $$
DECLARE v boolean;
BEGIN
  SELECT EXISTS (SELECT 1 FROM public.profile_personal WHERE user_id=p_uid AND (
      btrim(COALESCE(first_name,'')) <> '' OR btrim(COALESCE(last_name,'')) <> '' OR
      -- (blocker C) só um email PROFISSIONAL protege; relay/sintético isolado NÃO
      -- se comporta como contato manual (senão travaria a substituição pelo CV).
      public._is_public_contact_email(email) OR btrim(COALESCE(phone_number,'')) <> '' OR
      btrim(COALESCE(phone_country_code,'')) <> '' OR
      btrim(COALESCE(headline,'')) <> '' OR btrim(COALESCE(summary,'')) <> '' OR
      gender IS NOT NULL OR age_range IS NOT NULL OR date_of_birth IS NOT NULL OR
      btrim(COALESCE(location_city,'')) <> '' OR btrim(COALESCE(location_state,'')) <> '' OR
      btrim(COALESCE(location_country,'')) <> '' OR btrim(COALESCE(location_postal_code,'')) <> '' OR
      btrim(COALESCE(location_street_address,'')) <> '' OR
      btrim(COALESCE(linkedin_url,'')) <> '' OR btrim(COALESCE(website,'')) <> '' OR
      -- (Round 5 review) alinha com o Dart snapshotHasProtectedProfileData: sem estes 5
      -- campos, um perfil protegido só por phone_country_code/date_of_birth/CEP/endereço/
      -- availability caía em reviewConflicts no cliente mas o guard reviewed rejeitava.
      btrim(COALESCE(availability,'')) <> ''))
    OR EXISTS (SELECT 1 FROM public.profile_experiences WHERE user_id=p_uid)
    OR EXISTS (SELECT 1 FROM public.profile_education WHERE user_id=p_uid)
    OR EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id=p_uid)
    OR EXISTS (SELECT 1 FROM public.profile_languages WHERE user_id=p_uid)
    OR EXISTS (SELECT 1 FROM public.profile_certifications WHERE user_id=p_uid)
    OR EXISTS (SELECT 1 FROM public.profile_projects WHERE user_id=p_uid)
    OR EXISTS (SELECT 1 FROM public.profile_interests WHERE user_id=p_uid)
    OR EXISTS (SELECT 1 FROM public.profile_awards WHERE user_id=p_uid)
    OR EXISTS (SELECT 1 FROM public.profile_coursework WHERE user_id=p_uid)
    INTO v;
  RETURN v;
END $$;

-- ── APLICAR + PROMOVER (importação INICIAL) — all-or-nothing, VÍNCULO REAL ────
-- Diferente do anterior (candidate_id + json independentes): NÃO aceita payload
-- solto. Lê o payload VINCULADO à candidata (saved_resumes.extraction_payload) e
-- exige que p_attempt_id case com o extraction_attempt_id gravado — impossível
-- aplicar o payload de A na candidata B. É SÓ para importação inicial (perfil
-- COMPROVADAMENTE vazio); substituição usa apply_reviewed_conflicts_and_promote.
-- ALL-OR-NOTHING: se o apply não for 'success', um savepoint desfaz TUDO daquele
-- apply (personal + seções válidas), NÃO avança last_extracted_at, NÃO promove,
-- e a candidata muda para failed; o Edge reextrai no MESMO attempt antes do retry.
-- PROMOÇÃO COERENTE (blocker 3): trocar a fonte atual E atualizar o cache legacy
-- ATIVO (gamification_data.imported_resume.raw_text, usado por match/adaptação)
-- na MESMA transação. Antes da promoção o raw_text vive SÓ na candidata; só aqui
-- ele vira o dado ativo. Uma falha antes daqui preserva integralmente a anterior.
CREATE OR REPLACE FUNCTION public._promote_imported_and_activate(
  p_uid uuid, p_candidate_id uuid, p_raw_text text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_imported jsonb;
BEGIN
  -- Swap da fonte atual na MESMA transação (clear da antiga → set da nova).
  -- Qualquer marker do protocolo antigo é aposentado definitivamente: depois
  -- de uma promoção canônica, Edge/HEAD^ tardios nunca podem ressuscitá-lo.
  UPDATE public.saved_resumes SET is_latest_legacy_source = false
    WHERE user_id = p_uid AND is_latest_legacy_source;
  UPDATE public.saved_resumes SET is_current_source = false
    WHERE user_id = p_uid AND is_current_source AND id <> p_candidate_id;
  UPDATE public.saved_resumes SET is_current_source = true WHERE id = p_candidate_id;

  -- (blocker 9) Cache legacy COERENTE: reescrito INTEIRO a partir dos dados
  -- canônicos da candidata (parsed legacy + meta + raw_text). Substituição TOTAL
  -- (não jsonb-merge): nenhum sub-campo de uma importação anterior sobrevive —
  -- `raw_text`/`parsed` stale do source antigo somem. raw ausente ⇒ o objeto novo
  -- simplesmente NÃO tem `raw_text` (clears), então match/adaptação não reusam raw
  -- de outra fonte. Tudo na mesma transação da promoção; rollback preserva o cache.
  -- O argumento p_raw_text permanece na assinatura para compatibilidade entre
  -- migrations, mas a fonte de verdade é SEMPRE a row vinculada. O builder
  -- remove colisões do meta e inclui source_resume_id estável.
  v_imported := public._canonical_import_cache(p_candidate_id);
  IF v_imported IS NULL THEN
    RAISE EXCEPTION 'current_import_cache_unbuildable' USING ERRCODE='23514';
  END IF;

  UPDATE public.user_profiles SET gamification_data = jsonb_set(
    COALESCE(gamification_data, '{}'::jsonb), '{imported_resume}', v_imported)
    WHERE id = p_uid;
END $$;

DROP FUNCTION IF EXISTS public.apply_and_promote_imported_source(uuid, jsonb);
DROP FUNCTION IF EXISTS public.apply_and_promote_imported_source(uuid, uuid);
CREATE FUNCTION public.apply_and_promote_imported_source(p_candidate_id uuid, p_attempt_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_src text; v_st text; v_payload jsonb; v_attempt uuid; v_raw_text text; v_current boolean;
  v_apply jsonb; v_promoted boolean := false; v_receipt jsonb; v_recop text; v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='28000'; END IF;
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(v_uid));  -- advisory ANTES de qualquer tuple

  SELECT source, extraction_status, extraction_payload, extraction_attempt_id, extraction_raw_text, is_current_source
    INTO v_src, v_st, v_payload, v_attempt, v_raw_text, v_current
    FROM public.saved_resumes WHERE id = p_candidate_id AND user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'candidate_not_found' USING ERRCODE='P0002'; END IF;
  IF v_src <> 'imported' THEN RAISE EXCEPTION 'candidate_not_imported' USING ERRCODE='22023'; END IF;
  IF v_st IS DISTINCT FROM 'ready' THEN RAISE EXCEPTION 'candidate_not_ready' USING ERRCODE='22023'; END IF;

  -- VÍNCULO: o attempt do chamador precisa casar com o da candidata.
  IF p_attempt_id IS NULL OR v_attempt IS NULL OR v_attempt <> p_attempt_id THEN
    RAISE EXCEPTION 'attempt_mismatch' USING ERRCODE='22023';
  END IF;

  -- (blocker E2/F) IDEMPOTÊNCIA TERMINAL cross-op por (candidata, attempt). Um replay
  -- (resposta perdida) devolve o mesmo sucesso sem re-aplicar (o que dispararia
  -- profile_not_empty_use_review). Se a candidata JÁ concluiu por REVISÃO, ela já é a
  -- fonte atual → devolve um sucesso inicial shape-correto SEM 2ª promoção (mutuamente
  -- exclusivo: nunca dois terminais). Fica sob o advisory lock.
  SELECT operation, result INTO v_recop, v_receipt FROM public.import_apply_receipts
    WHERE candidate_id = p_candidate_id AND attempt_id = p_attempt_id;
  IF v_recop = 'apply_initial' THEN
    RETURN v_receipt;
  ELSIF v_recop = 'apply_reviewed' THEN
    RETURN jsonb_build_object('apply', jsonb_build_object('status','success',
      'applied','[]'::jsonb,'preserved','[]'::jsonb,'failed','[]'::jsonb), 'promoted', true);
  END IF;
  -- Sem recibo, uma fonte já atual não é candidata de import inicial. Rejeitar
  -- evita que uma falha subsequente a rebaixe e deixe cache ativo órfão.
  IF COALESCE(v_current,false) THEN
    RAISE EXCEPTION 'candidate_already_current' USING ERRCODE='22023';
  END IF;

  -- Schema fail-closed + conteúdo real (nada de promover extração vazia).
  PERFORM public._validate_profile_payload(v_payload);
  IF NOT public._profile_payload_has_content(v_payload) THEN
    RAISE EXCEPTION 'empty_payload' USING ERRCODE='22023';
  END IF;

  -- Importação INICIAL só: perfil precisa estar comprovadamente vazio. Perfil com
  -- dado ⇒ é substituição, que exige reviewConflicts (não fill-empty automático).
  IF public._profile_has_protected_data(v_uid) THEN
    RAISE EXCEPTION 'profile_not_empty_use_review' USING ERRCODE='22023';
  END IF;

  -- Savepoint: apply + promote atômicos; qualquer não-sucesso desfaz TUDO.
  BEGIN
    v_apply := public.save_profile_fill_empty(v_uid, v_payload);
    IF (v_apply->>'status') <> 'success' THEN
      RAISE EXCEPTION 'apply_not_success' USING ERRCODE='23514';
    END IF;
    -- (Round 6 blocker 2) DEFESA FINAL antes de promover: mesmo com status='success',
    -- exige que o fill-empty tenha PERSISTIDO conteúdo real (campo pessoal útil OU ≥1
    -- linha de seção) — nunca promover uma linha de profile_personal só com
    -- profile_source/completeness. Antes desta importação o perfil estava vazio
    -- (guarda profile_not_empty_use_review acima); se após o apply ainda NÃO há dado
    -- protegido, então nada persistiu de verdade → falha (retryável), sem promover.
    IF NOT public._profile_has_protected_data(v_uid) THEN
      RAISE EXCEPTION 'apply_persisted_nothing' USING ERRCODE='23514';
    END IF;
    -- promoção + ativação do cache legacy na MESMA transação (blocker 3).
    PERFORM public._promote_imported_and_activate(v_uid, p_candidate_id, v_raw_text);
    v_promoted := true;
  EXCEPTION WHEN OTHERS THEN
    -- O savepoint desfez TUDO (personal + seções + timestamp + promoção parcial).
    -- (blocker 6) A resposta precisa refletir o ESTADO PERSISTIDO: nada persistiu
    -- → apply=failure, NUNCA success/partial. Preserva as seções que falharam no
    -- diagnóstico (se houver) para o cliente saber o motivo.
    v_promoted := false;
    v_apply := jsonb_build_object('status','failure','applied','[]'::jsonb,'preserved','[]'::jsonb,
      'failed', COALESCE(v_apply->'failed','[]'::jsonb));
  END;

  -- (Round 7/retry honesto) Falha de apply não pode deixar a candidata READY
  -- presa ao payload inválido. Fora do savepoint (logo o status sobrevive ao
  -- rollback do perfil), rebaixa para failed sem receipt/current. O Edge já tem
  -- o caminho failed→extracting e complete_import_extraction aceita o MESMO
  -- attempt após reextração, podendo substituir o payload antes de novo apply.
  IF NOT v_promoted THEN
    UPDATE public.saved_resumes SET
      extraction_status = 'failed',
      extraction_completed_at = now(),
      extraction_error_code = 'apply_failed',
      is_current_source = false
    WHERE id = p_candidate_id AND user_id = v_uid
      AND extraction_attempt_id = p_attempt_id;
  END IF;

  v_result := jsonb_build_object(
    'apply', COALESCE(v_apply, jsonb_build_object('status','failure','applied','[]'::jsonb,'preserved','[]'::jsonb,'failed','[]'::jsonb)),
    'promoted', v_promoted,
    'retryable', NOT v_promoted,
    'extraction_status', CASE WHEN v_promoted THEN 'ready' ELSE 'failed' END);
  -- Grava o recibo SÓ no sucesso (falha é retryável); na MESMA transação da promoção.
  IF v_promoted THEN
    INSERT INTO public.import_apply_receipts(candidate_id, attempt_id, operation, result)
      VALUES (p_candidate_id, p_attempt_id, 'apply_initial', v_result);
  END IF;
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.apply_and_promote_imported_source(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_and_promote_imported_source(uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.save_profile_fill_empty(uuid, jsonb) IS
  'Fase 3: fill-empty completo, atômico por seção (invalid→seção desfeita), '
  'ordem por ordinality. Retorna {status,applied,preserved,failed}.';
COMMENT ON FUNCTION public.apply_and_promote_imported_source(uuid, uuid) IS
  'Fase 3: importação INICIAL (perfil vazio). Lê o payload VINCULADO à candidata '
  '+ valida attempt_id; all-or-nothing; só promove em success. Falha marca '
  'candidate failed para reextração; substituição usa apply_reviewed_conflicts_and_promote.';

-- ════════════════════════════════════════════════════════════════════════════
-- WRITERS COMPOSTOS TRANSACIONAIS (Gate 2.3 blocker 2)
-- Cada operação lógica que antes era multi-request (pai + filhas em chamadas
-- separadas) vira UMA transação server-side com a MESMA ordem de lock
-- (advisory ANTES de qualquer tupla). Falha no item N desfaz TUDO (a função é
-- uma transação; qualquer RAISE aborta o conjunto). O client passa a chamar
-- estas RPCs no lugar dos INSERT/DELETE encadeados.
-- ════════════════════════════════════════════════════════════════════════════

-- Experiência + bullets numa transação, FIDELIDADE COMPLETA (blocker 4): kind,
-- confidence, needs_review; bullets com id/angle/strength_score/verb/order_index.
-- Reconciliação de bullets PRESERVA IDs enviados (UPDATE), insere novas e remove
-- só as ausentes — tudo na mesma transação. NÃO é DELETE+INSERT cego.
-- CORE auth-less (Round 5 blocker G): a MESMA lógica de fidelidade completa reusada
-- pelo writer público (revisão) E pelo fill-empty inicial — os dois caminhos gravam o
-- MESMO payload canônico. Sem auth check (o chamador — wrapper público ou o fill-empty
-- core, ambos SECURITY DEFINER — já validou posse); mantém o advisory lock (reentrante).
-- Owner-only (sem grant; adicionado a v_all na blindagem).
CREATE OR REPLACE FUNCTION public._save_experience_with_bullets_core(p_user_id uuid, p_exp jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id uuid; v_start date; v_end date; v_bullet jsonb; v_ord bigint; v_keep uuid[]; v_bid uuid;
BEGIN
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(p_user_id));
  v_start := public.safe_date(p_exp->>'start_date'); v_end := public.safe_date(p_exp->>'end_date');
  IF v_start IS NULL THEN RAISE EXCEPTION 'invalid_experience: start_date' USING ERRCODE='23514'; END IF;
  IF NULLIF(p_exp->>'id','') IS NULL THEN
    INSERT INTO public.profile_experiences (user_id,title,company,location,start_date,end_date,is_current,order_index,confidence,needs_review,kind)
    VALUES (p_user_id, p_exp->>'title', p_exp->>'company', p_exp->>'location', v_start, v_end,
      CASE WHEN v_end IS NULL THEN TRUE ELSE COALESCE((p_exp->>'is_current')::boolean, FALSE) END,
      COALESCE(public.safe_integer(p_exp->>'order_index'),0), public.safe_numeric(p_exp->>'confidence'),
      COALESCE((p_exp->>'needs_review')::boolean, FALSE), NULLIF(p_exp->>'kind',''))
    RETURNING id INTO v_id;
  ELSE
    v_id := (p_exp->>'id')::uuid;
    UPDATE public.profile_experiences SET title=p_exp->>'title', company=p_exp->>'company', location=p_exp->>'location',
      start_date=v_start, end_date=v_end,
      is_current=CASE WHEN v_end IS NULL THEN TRUE ELSE COALESCE((p_exp->>'is_current')::boolean, FALSE) END,
      order_index=COALESCE(public.safe_integer(p_exp->>'order_index'), order_index),
      confidence=public.safe_numeric(p_exp->>'confidence'),
      needs_review=COALESCE((p_exp->>'needs_review')::boolean, needs_review),
      kind=CASE WHEN p_exp ? 'kind' THEN NULLIF(p_exp->>'kind','') ELSE kind END
    WHERE id=v_id AND user_id=p_user_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'experience_not_found' USING ERRCODE='P0002'; END IF;
  END IF;
  -- reconciliação: remove bullets AUSENTES do payload (ids não enviados).
  SELECT COALESCE(array_agg((b->>'id')::uuid), '{}') INTO v_keep
    FROM jsonb_array_elements(COALESCE(p_exp->'bullets','[]'::jsonb)) b WHERE NULLIF(b->>'id','') IS NOT NULL;
  DELETE FROM public.profile_bullets WHERE experience_id = v_id AND NOT (id = ANY(v_keep));
  FOR v_bullet, v_ord IN SELECT value, ordinality FROM jsonb_array_elements(COALESCE(p_exp->'bullets','[]'::jsonb)) WITH ORDINALITY LOOP
    -- (Round 5 review) bullet vazio/whitespace é RUÍDO da extração → PULA o bullet,
    -- NÃO derruba a experiência inteira. Antes RAISE 23514: no fill-empty, o sub-savepoint
    -- por-item revertia a experiência JÁ inserida e o has_content (que só olha title/
    -- company/start_date) ainda promovia → perfil relacional vazio marcado como sucesso.
    -- Pular o bullet mantém a fidelidade (o pai e os bullets VÁLIDOS ficam) nos DOIS caminhos.
    IF btrim(COALESCE(v_bullet->>'text','')) = '' THEN CONTINUE; END IF;
    v_bid := NULLIF(v_bullet->>'id','')::uuid;
    IF v_bid IS NOT NULL AND EXISTS (SELECT 1 FROM public.profile_bullets WHERE id=v_bid AND experience_id=v_id) THEN
      UPDATE public.profile_bullets SET text=v_bullet->>'text', angle=NULLIF(v_bullet->>'angle',''),
        strength_score=public.safe_integer(v_bullet->>'strength_score'), verb=NULLIF(v_bullet->>'verb',''),
        order_index=(v_ord-1)::int WHERE id=v_bid AND experience_id=v_id;
    ELSE
      INSERT INTO public.profile_bullets (experience_id,text,angle,strength_score,verb,order_index)
      VALUES (v_id, v_bullet->>'text', NULLIF(v_bullet->>'angle',''), public.safe_integer(v_bullet->>'strength_score'),
        NULLIF(v_bullet->>'verb',''), (v_ord-1)::int);
    END IF;
  END LOOP;
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public._save_experience_with_bullets_core(uuid, jsonb) FROM PUBLIC;
-- Wrapper público (revisão/cliente): valida posse e delega ao core.
CREATE OR REPLACE FUNCTION public.save_experience_with_bullets(p_user_id uuid, p_exp jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN RAISE EXCEPTION 'not_authorized' USING ERRCODE='28000'; END IF;
  RETURN public._save_experience_with_bullets_core(p_user_id, p_exp);
END $$;

-- Formação + majors/minors/activities numa transação, FIDELIDADE COMPLETA
-- (blocker 4): institution_id, education_level, education_status,
-- current_semester, current_school_year, location, degree, datas, gpa/max_gpa,
-- confidence, order. Filhas name-only são replace-all com ordinality.
CREATE OR REPLACE FUNCTION public._save_education_with_children_core(p_user_id uuid, p_edu jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id uuid; v_txt text; v_ord bigint;
BEGIN
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(p_user_id));
  IF btrim(COALESCE(p_edu->>'institution','')) = '' THEN RAISE EXCEPTION 'invalid_education: institution' USING ERRCODE='23514'; END IF;
  IF NULLIF(p_edu->>'id','') IS NULL THEN
    INSERT INTO public.profile_education (user_id,institution,institution_id,education_level,education_status,location,degree,
      current_semester,current_school_year,start_date,end_date,gpa,max_gpa,order_index,confidence)
    VALUES (p_user_id, p_edu->>'institution', NULLIF(p_edu->>'institution_id','')::uuid, NULLIF(p_edu->>'education_level',''),
      NULLIF(p_edu->>'education_status',''), p_edu->>'location', p_edu->>'degree',
      public.safe_integer(p_edu->>'current_semester'), public.safe_integer(p_edu->>'current_school_year'),
      public.safe_date(p_edu->>'start_date'), public.safe_date(p_edu->>'end_date'),
      public.safe_numeric(p_edu->>'gpa'), public.safe_numeric(p_edu->>'max_gpa'),
      COALESCE(public.safe_integer(p_edu->>'order_index'),0), public.safe_numeric(p_edu->>'confidence'))
    RETURNING id INTO v_id;
  ELSE
    v_id := (p_edu->>'id')::uuid;
    UPDATE public.profile_education SET institution=p_edu->>'institution', institution_id=NULLIF(p_edu->>'institution_id','')::uuid,
      education_level=NULLIF(p_edu->>'education_level',''), education_status=NULLIF(p_edu->>'education_status',''),
      location=p_edu->>'location', degree=p_edu->>'degree',
      current_semester=public.safe_integer(p_edu->>'current_semester'), current_school_year=public.safe_integer(p_edu->>'current_school_year'),
      start_date=public.safe_date(p_edu->>'start_date'), end_date=public.safe_date(p_edu->>'end_date'),
      gpa=public.safe_numeric(p_edu->>'gpa'), max_gpa=public.safe_numeric(p_edu->>'max_gpa'),
      order_index=COALESCE(public.safe_integer(p_edu->>'order_index'), order_index), confidence=public.safe_numeric(p_edu->>'confidence')
    WHERE id=v_id AND user_id=p_user_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'education_not_found' USING ERRCODE='P0002'; END IF;
  END IF;
  DELETE FROM public.profile_education_majors WHERE education_id=v_id;
  DELETE FROM public.profile_education_minors WHERE education_id=v_id;
  DELETE FROM public.profile_education_activities WHERE education_id=v_id;
  FOR v_txt, v_ord IN SELECT value, ordinality FROM jsonb_array_elements_text(COALESCE(p_edu->'majors','[]'::jsonb)) WITH ORDINALITY LOOP
    IF btrim(v_txt)='' THEN CONTINUE; END IF;
    INSERT INTO public.profile_education_majors (education_id,name,order_index) VALUES (v_id, v_txt, (v_ord-1)::int);
  END LOOP;
  FOR v_txt, v_ord IN SELECT value, ordinality FROM jsonb_array_elements_text(COALESCE(p_edu->'minors','[]'::jsonb)) WITH ORDINALITY LOOP
    IF btrim(v_txt)='' THEN CONTINUE; END IF;
    INSERT INTO public.profile_education_minors (education_id,name,order_index) VALUES (v_id, v_txt, (v_ord-1)::int);
  END LOOP;
  FOR v_txt, v_ord IN SELECT value, ordinality FROM jsonb_array_elements_text(COALESCE(p_edu->'activities','[]'::jsonb)) WITH ORDINALITY LOOP
    IF btrim(v_txt)='' THEN CONTINUE; END IF;
    INSERT INTO public.profile_education_activities (education_id,text,order_index) VALUES (v_id, v_txt, (v_ord-1)::int);
  END LOOP;
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public._save_education_with_children_core(uuid, jsonb) FROM PUBLIC;
CREATE OR REPLACE FUNCTION public.save_education_with_children(p_user_id uuid, p_edu jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN RAISE EXCEPTION 'not_authorized' USING ERRCODE='28000'; END IF;
  RETURN public._save_education_with_children_core(p_user_id, p_edu);
END $$;

-- Projeto + project_bullets numa transação, FIDELIDADE COMPLETA (blocker 4):
-- role, context, website, descrição, datas, is_current, order; bullets com IDs
-- preservados (reconciliação, não DELETE+INSERT cego).
CREATE OR REPLACE FUNCTION public._save_project_with_bullets_core(p_user_id uuid, p_proj jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id uuid; v_bullet jsonb; v_ord bigint; v_has_pb boolean; v_keep uuid[]; v_bid uuid;
BEGIN
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(p_user_id));
  IF btrim(COALESCE(p_proj->>'name','')) = '' THEN RAISE EXCEPTION 'invalid_project: name' USING ERRCODE='23514'; END IF;
  IF NULLIF(p_proj->>'id','') IS NULL THEN
    INSERT INTO public.profile_projects (user_id,name,role,context,website,description,start_date,end_date,is_current,order_index)
    VALUES (p_user_id, p_proj->>'name', p_proj->>'role', p_proj->>'context', p_proj->>'website', p_proj->>'description',
      public.safe_date(p_proj->>'start_date'), public.safe_date(p_proj->>'end_date'),
      COALESCE((p_proj->>'is_current')::boolean, FALSE), COALESCE(public.safe_integer(p_proj->>'order_index'),0))
    RETURNING id INTO v_id;
  ELSE
    v_id := (p_proj->>'id')::uuid;
    UPDATE public.profile_projects SET name=p_proj->>'name', role=p_proj->>'role', context=p_proj->>'context',
      website=p_proj->>'website', description=p_proj->>'description',
      start_date=public.safe_date(p_proj->>'start_date'), end_date=public.safe_date(p_proj->>'end_date'),
      is_current=COALESCE((p_proj->>'is_current')::boolean, FALSE),
      order_index=COALESCE(public.safe_integer(p_proj->>'order_index'), order_index)
    WHERE id=v_id AND user_id=p_user_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'project_not_found' USING ERRCODE='P0002'; END IF;
  END IF;
  SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='profile_project_bullets') INTO v_has_pb;
  IF v_has_pb THEN
    SELECT COALESCE(array_agg((b->>'id')::uuid), '{}') INTO v_keep
      FROM jsonb_array_elements(COALESCE(p_proj->'bullets','[]'::jsonb)) b WHERE NULLIF(b->>'id','') IS NOT NULL;
    DELETE FROM public.profile_project_bullets WHERE project_id = v_id AND NOT (id = ANY(v_keep));
    FOR v_bullet, v_ord IN SELECT value, ordinality FROM jsonb_array_elements(COALESCE(p_proj->'bullets','[]'::jsonb)) WITH ORDINALITY LOOP
      -- (Round 5 review) bullet vazio de projeto é PULADO, não derruba o projeto (idem exp).
      IF btrim(COALESCE(v_bullet->>'text','')) = '' THEN CONTINUE; END IF;
      v_bid := NULLIF(v_bullet->>'id','')::uuid;
      IF v_bid IS NOT NULL AND EXISTS (SELECT 1 FROM public.profile_project_bullets WHERE id=v_bid AND project_id=v_id) THEN
        UPDATE public.profile_project_bullets SET text=v_bullet->>'text', order_index=(v_ord-1)::int WHERE id=v_bid AND project_id=v_id;
      ELSE
        INSERT INTO public.profile_project_bullets (project_id,text,order_index) VALUES (v_id, v_bullet->>'text', (v_ord-1)::int);
      END IF;
    END LOOP;
  END IF;
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public._save_project_with_bullets_core(uuid, jsonb) FROM PUBLIC;
CREATE OR REPLACE FUNCTION public.save_project_with_bullets(p_user_id uuid, p_proj jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN RAISE EXCEPTION 'not_authorized' USING ERRCODE='28000'; END IF;
  RETURN public._save_project_with_bullets_core(p_user_id, p_proj);
END $$;

-- Replace-all de listas simples (skills/interests/coursework) — atômico, com
-- ordinality e dedup case-insensitive.
CREATE OR REPLACE FUNCTION public._replace_simple_list(p_user_id uuid, p_table text, p_names jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_name text; v_ord bigint; v_seen text[] := '{}';
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN RAISE EXCEPTION 'not_authorized' USING ERRCODE='28000'; END IF;
  IF p_table <> ALL (ARRAY['profile_skills','profile_interests','profile_coursework']) THEN
    RAISE EXCEPTION 'invalid_table' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(p_user_id));
  EXECUTE format('DELETE FROM public.%I WHERE user_id = $1', p_table) USING p_user_id;
  FOR v_name, v_ord IN SELECT value, ordinality FROM jsonb_array_elements_text(COALESCE(p_names,'[]'::jsonb)) WITH ORDINALITY LOOP
    IF btrim(COALESCE(v_name,'')) = '' OR lower(btrim(v_name)) = ANY(v_seen) THEN CONTINUE; END IF;
    v_seen := array_append(v_seen, lower(btrim(v_name)));
    EXECUTE format('INSERT INTO public.%I (user_id,name,order_index) VALUES ($1,$2,$3)', p_table)
      USING p_user_id, btrim(v_name), (v_ord-1)::int;
  END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.replace_profile_skills(p_user_id uuid, p_names jsonb)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT public._replace_simple_list(p_user_id, 'profile_skills', p_names) $$;
CREATE OR REPLACE FUNCTION public.replace_profile_interests(p_user_id uuid, p_names jsonb)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT public._replace_simple_list(p_user_id, 'profile_interests', p_names) $$;
CREATE OR REPLACE FUNCTION public.replace_profile_coursework(p_user_id uuid, p_names jsonb)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT public._replace_simple_list(p_user_id, 'profile_coursework', p_names) $$;

-- Reordenação atômica de uma seção (order_index = posição na lista de ids). Todos
-- os ids precisam ser do usuário; ausência de um id ⇒ RAISE ⇒ nada muda.
CREATE OR REPLACE FUNCTION public.reorder_profile_section(p_user_id uuid, p_table text, p_ids jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id uuid; v_ord bigint; v_n int;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN RAISE EXCEPTION 'not_authorized' USING ERRCODE='28000'; END IF;
  IF p_table <> ALL (ARRAY['profile_experiences','profile_education','profile_skills','profile_languages',
      'profile_certifications','profile_projects','profile_interests','profile_awards','profile_coursework']) THEN
    RAISE EXCEPTION 'invalid_table' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(p_user_id));
  FOR v_id, v_ord IN SELECT value::text::uuid, ordinality FROM jsonb_array_elements_text(COALESCE(p_ids,'[]'::jsonb)) WITH ORDINALITY LOOP
    EXECUTE format('UPDATE public.%I SET order_index = $1 WHERE id = $2 AND user_id = $3', p_table)
      USING (v_ord-1)::int, v_id, p_user_id;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 1 THEN RAISE EXCEPTION 'reorder_id_not_owned: %', v_id USING ERRCODE='P0002'; END IF;
  END LOOP;
END $$;

DO $g$
DECLARE fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'save_experience_with_bullets(uuid, jsonb)','save_education_with_children(uuid, jsonb)',
    'save_project_with_bullets(uuid, jsonb)','replace_profile_skills(uuid, jsonb)',
    'replace_profile_interests(uuid, jsonb)','replace_profile_coursework(uuid, jsonb)',
    'reorder_profile_section(uuid, text, jsonb)']
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated', fn);
  END LOOP;
END $g$;
-- helper interno: sem grant a authenticated (só as wrappers o chamam via DEFINER).
REVOKE ALL ON FUNCTION public._replace_simple_list(uuid, text, jsonb) FROM PUBLIC;

-- ════════════════════════════════════════════════════════════════════════════
-- COMPARE-AND-SET de campos escalares (Gate 2.3 blocker 6) — "manual vence" REAL.
-- O diff observou `p_expected`; no apply, se o valor VIVO não casa mais (edição
-- manual concorrente), NÃO sobrescreve e retorna 'stale'. Whitelist de campos →
-- coluna. Fenced pelo lock (advisory→tuple).
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._profile_scalar_column(p_field text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT CASE p_field
    WHEN 'summary' THEN 'summary' WHEN 'headline' THEN 'headline'
    WHEN 'linkedin' THEN 'linkedin_url' WHEN 'website' THEN 'website'
    WHEN 'phone' THEN 'phone_number' WHEN 'city' THEN 'location_city'
    WHEN 'email' THEN 'email'
    ELSE NULL END
$$;
DROP FUNCTION IF EXISTS public.cas_write_profile_scalar(uuid, text, text, text);
CREATE OR REPLACE FUNCTION public.cas_write_profile_scalar(
  p_user_id uuid, p_field text, p_expected text, p_new text,
  p_expected_country_code text, p_new_country_code text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_col text; v_live text; v_live_cc text;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN RAISE EXCEPTION 'not_authorized' USING ERRCODE='28000'; END IF;
  v_col := public._profile_scalar_column(p_field);
  IF v_col IS NULL THEN RAISE EXCEPTION 'invalid_field' USING ERRCODE='22023'; END IF;
  -- (Round 5 review) blocker C também no single-row apply: nunca gravar relay/sintético
  -- como contato profissional por este caminho (espelha _cas_write_personal_field).
  IF p_field = 'email' AND btrim(COALESCE(p_new,'')) <> '' AND NOT public._is_public_contact_email(p_new) THEN
    RAISE EXCEPTION 'non_public_email' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(p_user_id));
  IF p_field = 'phone' THEN
    -- Telefone é um valor COMPOSTO. Se número OU DDI mudou desde o diff,
    -- a edição manual vence; se ambos casam, os dois atualizam atomicamente.
    SELECT phone_number, phone_country_code INTO v_live, v_live_cc
      FROM public.profile_personal WHERE user_id=p_user_id;
    IF COALESCE(btrim(v_live),'') IS DISTINCT FROM COALESCE(btrim(p_expected),'')
       OR COALESCE(btrim(v_live_cc),'') IS DISTINCT FROM COALESCE(btrim(p_expected_country_code),'') THEN
      RETURN 'stale';
    END IF;
  ELSE
    EXECUTE format('SELECT %I FROM public.profile_personal WHERE user_id=$1', v_col) INTO v_live USING p_user_id;
    -- valor vivo mudou desde o diff → edição manual VENCE, não sobrescreve.
    IF COALESCE(btrim(v_live),'') IS DISTINCT FROM COALESCE(btrim(p_expected),'') THEN
      RETURN 'stale';
    END IF;
  END IF;
  INSERT INTO public.profile_personal(user_id) VALUES (p_user_id) ON CONFLICT (user_id) DO NOTHING;
  IF p_field = 'phone' THEN
    UPDATE public.profile_personal SET phone_number=p_new,
      phone_country_code=NULLIF(btrim(p_new_country_code),''), updated_at=now()
      WHERE user_id=p_user_id;
  ELSE
    EXECUTE format('UPDATE public.profile_personal SET %I=$1, updated_at=now() WHERE user_id=$2', v_col)
      USING p_new, p_user_id;
  END IF;
  RETURN 'applied';
END $$;
REVOKE ALL ON FUNCTION public.cas_write_profile_scalar(uuid, text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cas_write_profile_scalar(uuid, text, text, text, text, text) TO authenticated;

-- coluna do payload que ORIGINA um conflito escalar (para checar VÍNCULO).
CREATE OR REPLACE FUNCTION public._payload_scalar_source(p_field text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT CASE p_field
    WHEN 'summary' THEN 'summary' WHEN 'headline' THEN 'headline'
    WHEN 'linkedin' THEN 'linkedin' WHEN 'website' THEN 'website'
    WHEN 'phone' THEN 'phone_number' WHEN 'city' THEN 'location_city'
    WHEN 'email' THEN 'email'
    ELSE NULL END
$$;

-- CAS de campo PESSOAL para a substituição revisada (blocker 12). Uniformiza o
-- apply de TODOS os pessoais numa chamada: escalares 1:1 (summary/headline/
-- linkedin/website) e COMPOSTOS (phone→número+DDI; name→first+last;
-- city→cidade/UF + limpa o
-- CEP). CAS contra o valor VIVO composto: se mudou desde o diff (edição manual
-- concorrente), retorna 'stale' e NÃO grava nada. Espelha assistWriteFieldValue
-- (mesma partição de nome pela ÚLTIMA palavra e mesma semântica de cidade/UF).
-- Interno: só chamado pela RPC de revisão (via DEFINER) — sem grant a authenticated.
DROP FUNCTION IF EXISTS public._cas_write_personal_field(uuid, text, text, text);
CREATE OR REPLACE FUNCTION public._cas_write_personal_field(
  p_uid uuid, p_field text, p_expected text, p_value text,
  p_expected_country_code text, p_new_country_code text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_col text; v_live text; v_val text := btrim(COALESCE(p_value,''));
  v_live_cc text; v_first text; v_last text; v_city text; v_uf text; v_sep text;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_uid THEN RAISE EXCEPTION 'not_authorized' USING ERRCODE='28000'; END IF;
  INSERT INTO public.profile_personal(user_id) VALUES (p_uid) ON CONFLICT (user_id) DO NOTHING;

  IF p_field = 'name' THEN
    SELECT btrim(regexp_replace(COALESCE(first_name,'')||' '||COALESCE(last_name,''), '\s+', ' ', 'g'))
      INTO v_live FROM public.profile_personal WHERE user_id=p_uid;
    IF COALESCE(v_live,'') IS DISTINCT FROM COALESCE(btrim(p_expected),'') THEN RETURN 'stale'; END IF;
    IF v_val = '' THEN RAISE EXCEPTION 'empty_name' USING ERRCODE='22023'; END IF;
    IF position(' ' in v_val) = 0 THEN
      v_first := v_val; v_last := '';
    ELSE  -- sobrenome = ÚLTIMA palavra; nome = o resto (round-trip idempotente pt-BR).
      v_first := btrim(regexp_replace(v_val, '\s+\S+$', ''));
      v_last  := btrim(regexp_replace(v_val, '^.*\s+', ''));
    END IF;
    UPDATE public.profile_personal SET first_name=NULLIF(v_first,''), last_name=NULLIF(v_last,''), updated_at=now()
      WHERE user_id=p_uid;
    RETURN 'applied';

  ELSIF p_field = 'city' THEN
    SELECT btrim(COALESCE(location_city,'') ||
      CASE WHEN btrim(COALESCE(location_state,''))<>'' THEN ', '||location_state ELSE '' END)
      INTO v_live FROM public.profile_personal WHERE user_id=p_uid;
    IF COALESCE(v_live,'') IS DISTINCT FROM COALESCE(btrim(p_expected),'') THEN RETURN 'stale'; END IF;
    -- "Cidade|UF" (typeahead) | "Cidade, UF" | "Cidade". UF do value é autoritativa;
    -- sem UF ⇒ estado limpo. CEP SEMPRE limpo (era de outra cidade).
    v_sep := CASE WHEN position('|' in v_val)>0 THEN '|' WHEN position(',' in v_val)>0 THEN ',' ELSE '' END;
    IF v_sep = '' THEN v_city := v_val; v_uf := NULL;
    ELSE v_city := btrim(split_part(v_val, v_sep, 1)); v_uf := NULLIF(btrim(split_part(v_val, v_sep, 2)),''); END IF;
    IF v_city = '' THEN RAISE EXCEPTION 'empty_city' USING ERRCODE='22023'; END IF;
    UPDATE public.profile_personal SET location_city=v_city, location_state=v_uf,
      location_postal_code=NULL, location_country=COALESCE(location_country,'BR'), updated_at=now()
      WHERE user_id=p_uid;
    RETURN 'applied';

  ELSIF p_field = 'phone' THEN
    SELECT phone_number, phone_country_code INTO v_live, v_live_cc
      FROM public.profile_personal WHERE user_id=p_uid;
    IF COALESCE(btrim(v_live),'') IS DISTINCT FROM COALESCE(btrim(p_expected),'')
       OR COALESCE(btrim(v_live_cc),'') IS DISTINCT FROM COALESCE(btrim(p_expected_country_code),'') THEN
      RETURN 'stale';
    END IF;
    UPDATE public.profile_personal SET phone_number=v_val,
      phone_country_code=NULLIF(btrim(p_new_country_code),''), updated_at=now()
      WHERE user_id=p_uid;
    RETURN 'applied';

  ELSE  -- escalar 1:1
    v_col := public._profile_scalar_column(p_field);
    IF v_col IS NULL THEN RAISE EXCEPTION 'invalid_field: %', p_field USING ERRCODE='22023'; END IF;
    -- (blocker C) email: a revisão NUNCA grava relay/sintético, mesmo vinculado ao
    -- payload — rejeitado (o lote segue). O diff e a Edge já filtram; isto blinda.
    IF p_field = 'email' AND btrim(COALESCE(v_val,'')) <> '' AND NOT public._is_public_contact_email(v_val) THEN
      RAISE EXCEPTION 'non_public_email' USING ERRCODE='22023';
    END IF;
    EXECUTE format('SELECT %I FROM public.profile_personal WHERE user_id=$1', v_col) INTO v_live USING p_uid;
    IF COALESCE(btrim(v_live),'') IS DISTINCT FROM COALESCE(btrim(p_expected),'') THEN RETURN 'stale'; END IF;
    EXECUTE format('UPDATE public.profile_personal SET %I=$1, updated_at=now() WHERE user_id=$2', v_col)
      USING v_val, p_uid;
    RETURN 'applied';
  END IF;
END $$;
REVOKE ALL ON FUNCTION public._cas_write_personal_field(uuid, text, text, text, text, text) FROM PUBLIC;

-- Normalização de texto p/ VÍNCULO (espelha _norm no Dart: lower + strip de
-- acentos + trim). translate() char-a-char (from/to de comprimento igual).
CREATE OR REPLACE FUNCTION public._norm_txt(p text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT translate(lower(btrim(COALESCE(p,''))),
    'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc')
$$;

-- payload key de uma seção de lista (blocker 14: 'coursework' NÃO pluraliza).
CREATE OR REPLACE FUNCTION public._payload_list_key(p_section text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT CASE p_section
    WHEN 'skill' THEN 'skills' WHEN 'interest' THEN 'interests'
    WHEN 'coursework' THEN 'coursework' WHEN 'award' THEN 'awards'
    WHEN 'project' THEN 'projects' WHEN 'certification' THEN 'certifications'
    WHEN 'language' THEN 'languages' WHEN 'experience' THEN 'experiences'
    WHEN 'education' THEN 'education' ELSE NULL END
$$;

-- SUBSTITUIÇÃO (blocker 12): aplicar TODO o lote revisado E promover a candidata
-- numa ÚNICA transação, cobrindo TODOS os tipos de conflito (pessoais escalares e
-- COMPOSTOS name/city; listas skill/interest/coursework/award/project; cert;
-- idioma add/nível; experiência conflito-de-cargo + adição inteira c/ bullets;
-- formação conflito-de-curso + adição inteira c/ filhas). Contrato:
--   1. advisory lock ANTES de qualquer tuple; 2. candidata FOR UPDATE;
--   3. valida posse/imported/ready/ATTEMPT/payload/conteúdo; 4. cada escolha
--   precisa apontar para algo REALMENTE proposto pela extração daquela candidata
--   (VÍNCULO contra o payload; lote não-vazio 100% desvinculado → RAISE); 5. CAS
--   contra o valor VIVO nos campos escalares/de-item (manual venceu ⇒ stale);
--   6. adições inteiras aplicam os dados CANÔNICOS do payload (não o que o cliente
--   mandou) — o cliente só SELECIONA por chave; 7. lote atômico (erro inesperado ⇒
--   rollback + sem promoção; stale/rejected legítimos NÃO abortam); 8. só então
--   demova a anterior e promova a nova (+cache) na mesma tx; 9. agregado
--   {applied,stale,rejected,failed,promoted}; failed≠[] nunca coexiste com
--   promoted=true; SEM SQLERRM cru na resposta (só um código curto). Rejeitar tudo
--   (choices vazio) é válido: perfil igual, nova fonte ainda promove.
CREATE OR REPLACE FUNCTION public.apply_reviewed_conflicts_and_promote(
  p_candidate_id uuid, p_attempt_id uuid, p_choices jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_src text; v_st text; v_payload jsonb; v_attempt uuid; v_raw text;
  v_ch jsonb; v_kind text; v_field text; v_srccol text; v_sec text; v_val text;
  v_source text; v_name text; v_issuer text; v_prof text; v_refid uuid; v_expected text;
  v_bound boolean; v_res text; v_item jsonb; v_live text; v_paykey text; v_col text;
  v_keycompany text; v_keytitle text; v_keyinst text; v_keydeg text; v_ord int;
  v_applied jsonb := '[]'::jsonb; v_stale jsonb := '[]'::jsonb; v_rejected jsonb := '[]'::jsonb;
  v_any_bound boolean := false; v_label text;
  v_hash text; v_receipt jsonb; v_rhash text; v_recop text; v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='28000'; END IF;
  IF jsonb_typeof(COALESCE(p_choices,'null'::jsonb)) <> 'array' THEN RAISE EXCEPTION 'malformed_choices' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(v_uid));  -- advisory antes de tuple

  SELECT source, extraction_status, extraction_payload, extraction_attempt_id, extraction_raw_text
    INTO v_src, v_st, v_payload, v_attempt, v_raw
    FROM public.saved_resumes WHERE id=p_candidate_id AND user_id=v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'candidate_not_found' USING ERRCODE='P0002'; END IF;
  IF v_src <> 'imported' THEN RAISE EXCEPTION 'candidate_not_imported' USING ERRCODE='22023'; END IF;
  IF v_st IS DISTINCT FROM 'ready' THEN RAISE EXCEPTION 'candidate_not_ready' USING ERRCODE='22023'; END IF;
  IF p_attempt_id IS NULL OR v_attempt IS NULL OR v_attempt <> p_attempt_id THEN
    RAISE EXCEPTION 'attempt_mismatch' USING ERRCODE='22023'; END IF;
  PERFORM public._validate_profile_payload(v_payload);
  IF NOT public._profile_payload_has_content(v_payload) THEN  -- blocker 14: nada de promover {}
    RAISE EXCEPTION 'empty_payload' USING ERRCODE='22023'; END IF;

  -- (blocker E3/F) IDEMPOTÊNCIA TERMINAL cross-op por (candidata, attempt). Hash
  -- CANÔNICO por ORDEM: o MESMO conjunto de escolhas em ordem diferente idempotente
  -- (jsonb já normaliza a ordem das chaves de cada objeto; ordenamos os elementos por
  -- texto). Antes md5(array as-is) rejeitava um replay reordenado como
  -- already_applied_different.
  v_hash := md5(COALESCE((SELECT jsonb_agg(elem ORDER BY elem::text)
                          FROM jsonb_array_elements(COALESCE(p_choices,'[]'::jsonb)) AS elem),
                         '[]'::jsonb)::text);
  SELECT operation, choices_hash, result INTO v_recop, v_rhash, v_receipt FROM public.import_apply_receipts
    WHERE candidate_id=p_candidate_id AND attempt_id=p_attempt_id;
  IF v_recop = 'apply_reviewed' THEN
    IF v_rhash = v_hash THEN RETURN v_receipt; END IF;
    RAISE EXCEPTION 'already_applied_different' USING ERRCODE='22023';
  ELSIF v_recop = 'apply_initial' THEN
    -- já concluída por importação inicial: candidata é a atual; nada a reaplicar.
    RETURN jsonb_build_object('applied','[]'::jsonb,'stale','[]'::jsonb,'rejected','[]'::jsonb,
      'failed','[]'::jsonb,'promoted',true);
  END IF;

  -- (blocker F) a REVISÃO exige perfil PROTEGIDO/existente — nunca promove choices=[]
  -- (nem nada) num perfil comprovadamente vazio: isso é importação INICIAL. Fecha o
  -- buraco reviewed→initial (reviewed-vazio deixava o perfil vazio e o initial promovia
  -- de novo). Depois do curto-circuito do recibo (um replay legítimo ainda retorna).
  IF NOT public._profile_has_protected_data(v_uid) THEN
    RAISE EXCEPTION 'profile_empty_use_initial' USING ERRCODE='22023';
  END IF;

  -- Savepoint: aplica o lote; erro inesperado desfaz TUDO e NÃO promove.
  BEGIN
    FOR v_ch IN SELECT value FROM jsonb_array_elements(p_choices) LOOP
      v_bound := false; v_kind := v_ch->>'kind';

      -- Sub-savepoint POR ESCOLHA (review adversarial): um item ACEITO cujo dado
      -- CANÔNICO é inaplicável (ex.: adição de formação sem instituição, que a
      -- extração produz para bootcamps/cursos sem escola; experiência com
      -- start_date inválida; edição vazia; bullet vazio; kind inválido) é REJEITADO
      -- e o lote SEGUE — um item ruim da extração NÃO pode destruir todas as outras
      -- escolhas aceitas nem impedir a promoção. Atomicidade preservada onde
      -- importa: apply+promote+cache continuam numa transação; falha inesperada
      -- FORA do laço (promoção/tampering) ainda desfaz tudo (savepoint externo).
      BEGIN
      -- ── PESSOAIS (escalares + compostos name/city) ── CAS "manual vence" ──────
      IF v_kind = 'personal' THEN
        v_field := v_ch->>'field'; v_label := v_field;
        IF v_field = 'name' THEN
          v_bound := btrim(COALESCE(v_payload->'personal'->>'first_name',''))<>''
                  OR btrim(COALESCE(v_payload->'personal'->>'last_name',''))<>'';
        ELSE
          v_srccol := public._payload_scalar_source(v_field);
          IF v_srccol IS NULL THEN RAISE EXCEPTION 'invalid_scalar_field: %', v_field USING ERRCODE='22023'; END IF;
          v_bound := btrim(COALESCE(v_payload->'personal'->>v_srccol,'')) <> '';
        END IF;
        IF v_bound THEN
          v_any_bound := true;
          v_res := public._cas_write_personal_field(
            v_uid, v_field, v_ch->>'expected', v_ch->>'value',
            v_ch->>'expected_country_code', v_ch->>'country_code');
          IF v_res = 'applied' THEN
            -- Telefone+DDI já foram comparados e gravados atomicamente pelo
            -- helper; não existe segundo UPDATE que possa clobberar DDI manual.
            v_applied := v_applied || to_jsonb(v_label);
          ELSE v_stale := v_stale || to_jsonb(v_label); END IF;
        ELSE
          v_rejected := v_rejected || to_jsonb(v_label);
        END IF;

      -- ── ADIÇÕES de listas: skill/interest/coursework/award/project ────────────
      -- FIDELIDADE (blocker H): o item é LOCALIZADO no extraction_payload da própria
      -- candidata (por nome, o vínculo original) e os campos CANÔNICOS são
      -- preservados (award.date; projeto inteiro via writer composto). O cliente só
      -- SELECIONA por chave; nunca manda um objeto completo arbitrário. Editar só o
      -- nome preserva os demais campos canônicos.
      ELSIF v_kind = 'add' THEN
        v_sec := v_ch->>'section'; v_val := btrim(COALESCE(v_ch->>'value',''));
        v_source := COALESCE(v_ch->>'source', v_val);  -- VÍNCULO pelo valor ORIGINAL proposto
        IF v_sec <> ALL(ARRAY['skill','interest','coursework','award','project']) THEN
          RAISE EXCEPTION 'invalid_add_section: %', v_sec USING ERRCODE='22023'; END IF;
        v_paykey := public._payload_list_key(v_sec);
        v_item := NULL;
        IF v_val <> '' THEN
          SELECT value INTO v_item FROM jsonb_array_elements(COALESCE(v_payload->v_paykey,'[]'::jsonb)) e
            WHERE public._norm_txt(e->>'name') = public._norm_txt(v_source) LIMIT 1;
        END IF;
        IF v_val <> '' AND v_item IS NOT NULL THEN
          v_any_bound := true;
          IF v_sec = 'skill' THEN
            -- (blocker G) category NÃO-editável vem do payload VINCULADO (v_item), não
            -- do cliente — antes era DROPADA (divergência vs fill-empty inicial).
            INSERT INTO public.profile_skills(user_id,name,category)
              VALUES (v_uid, v_val, NULLIF(btrim(v_item->>'category'),'')) ON CONFLICT (user_id, lower(name)) DO NOTHING;
          ELSIF v_sec = 'interest' THEN
            INSERT INTO public.profile_interests(user_id,name) VALUES (v_uid, v_val) ON CONFLICT (user_id, lower(name)) DO NOTHING;
          ELSIF v_sec = 'coursework' THEN
            INSERT INTO public.profile_coursework(user_id,name,order_index)
              SELECT v_uid, v_val, COALESCE((SELECT max(order_index)+1 FROM public.profile_coursework WHERE user_id=v_uid),0)
              WHERE NOT EXISTS (SELECT 1 FROM public.profile_coursework WHERE user_id=v_uid AND public._norm_txt(name)=public._norm_txt(v_val));
          ELSIF v_sec = 'award' THEN
            -- FIDELIDADE: preserva a DATA canônica do prêmio (perdida antes).
            INSERT INTO public.profile_awards(user_id,name,date,order_index)
              SELECT v_uid, v_val, public.safe_date(v_item->>'date'),
                     COALESCE((SELECT max(order_index)+1 FROM public.profile_awards WHERE user_id=v_uid),0)
              WHERE NOT EXISTS (SELECT 1 FROM public.profile_awards WHERE user_id=v_uid AND public._norm_txt(name)=public._norm_txt(v_val));
          ELSE  -- project → writer COMPOSTO: role/context/website/description/datas/is_current/bullets.
            IF NOT EXISTS (SELECT 1 FROM public.profile_projects WHERE user_id=v_uid AND public._norm_txt(name)=public._norm_txt(v_val)) THEN
              PERFORM public.save_project_with_bullets(v_uid, (v_item - 'id') || jsonb_build_object('name', v_val));
            END IF;
          END IF;
          v_applied := v_applied || to_jsonb(v_sec||':'||v_val);
        ELSE
          v_rejected := v_rejected || to_jsonb(v_sec||':'||v_val);
        END IF;

      -- ── ADIÇÃO de certificação (nome + emissor + DATA canônica) ──────────────
      ELSIF v_kind = 'add_cert' THEN
        v_name := btrim(COALESCE(v_ch->>'name',''));
        v_source := COALESCE(v_ch->>'source', v_name);
        v_item := NULL;
        IF v_name <> '' THEN
          -- (blocker G) IDENTIDADE SUFICIENTE: quando há vários certs com o mesmo nome no
          -- payload, o issuer PROPOSTO pelo cliente desambigua QUAL selecionar; senão o 1º.
          IF NULLIF(btrim(v_ch->>'issuer'),'') IS NOT NULL THEN
            SELECT value INTO v_item FROM jsonb_array_elements(COALESCE(v_payload->'certifications','[]'::jsonb)) e
              WHERE public._norm_txt(e->>'name') = public._norm_txt(v_source)
                AND public._norm_txt(COALESCE(e->>'issuer','')) = public._norm_txt(v_ch->>'issuer') LIMIT 1;
          END IF;
          IF v_item IS NULL THEN
            SELECT value INTO v_item FROM jsonb_array_elements(COALESCE(v_payload->'certifications','[]'::jsonb)) e
              WHERE public._norm_txt(e->>'name') = public._norm_txt(v_source) LIMIT 1;
          END IF;
        END IF;
        IF v_name <> '' AND v_item IS NOT NULL THEN
          v_any_bound := true;
          -- (blocker G) issuer E date NÃO-editáveis vêm do payload VINCULADO (v_item),
          -- nunca do cliente (antes o issuer vinha do cliente = não-confiável).
          v_issuer := NULLIF(btrim(v_item->>'issuer'),'');
          INSERT INTO public.profile_certifications(user_id,name,issuer,date,order_index)
            SELECT v_uid, v_name, v_issuer, public.safe_date(v_item->>'date'),
                   COALESCE((SELECT max(order_index)+1 FROM public.profile_certifications WHERE user_id=v_uid),0)
            WHERE NOT EXISTS (SELECT 1 FROM public.profile_certifications WHERE user_id=v_uid
              AND public._norm_txt(name)=public._norm_txt(v_name) AND COALESCE(public._norm_txt(issuer),'')=COALESCE(public._norm_txt(v_issuer),''));
          v_applied := v_applied || to_jsonb('certification:'||v_name);
        ELSE
          v_rejected := v_rejected || to_jsonb('certification:'||v_name);
        END IF;

      -- ── ADIÇÃO de idioma (o diff viu AUSENTE) ────────────────────────────────
      -- (blocker F) "manual vence": se o idioma APARECEU manualmente entre o diff e
      -- o apply, NÃO sobrescreve — preserva o manual e devolve STALE. Só insere
      -- quando de fato ausente no momento do apply.
      ELSIF v_kind = 'add_lang' THEN
        v_name := btrim(COALESCE(v_ch->>'name',''));
        v_source := COALESCE(v_ch->>'source', v_name);
        -- (blocker G) proficiency NÃO-editável vem do payload VINCULADO, não do cliente.
        v_prof := NULL;
        SELECT NULLIF(btrim(e->>'proficiency'),'') INTO v_prof
          FROM jsonb_array_elements(COALESCE(v_payload->'languages','[]'::jsonb)) e
          WHERE public._norm_txt(e->>'name') = public._norm_txt(v_source) LIMIT 1;
        v_bound := EXISTS (
          SELECT 1 FROM jsonb_array_elements(COALESCE(v_payload->'languages','[]'::jsonb)) e
          WHERE public._norm_txt(e->>'name') = public._norm_txt(v_source));
        IF v_name <> '' AND v_bound THEN
          v_any_bound := true;
          IF EXISTS (SELECT 1 FROM public.profile_languages WHERE user_id=v_uid AND public._norm_txt(name)=public._norm_txt(v_name)) THEN
            v_stale := v_stale || to_jsonb('language:'||v_name);  -- apareceu manualmente → manual vence
          ELSE
            INSERT INTO public.profile_languages(user_id,name,proficiency,order_index)
              VALUES (v_uid, v_name, v_prof, COALESCE((SELECT max(order_index)+1 FROM public.profile_languages WHERE user_id=v_uid),0));
            v_applied := v_applied || to_jsonb('language:'||v_name);
          END IF;
        ELSE
          v_rejected := v_rejected || to_jsonb('language:'||v_name);
        END IF;

      -- ── CONFLITO de NÍVEL de idioma (idioma já existe) — CAS "manual vence" ───
      -- (blocker F) v_expected é a proficiência CANÔNICA (id, ex.: 'basic') que o
      -- diff observou. Se o nível VIVO mudou desde o diff (edição manual) ou o
      -- idioma sumiu, retorna STALE e NÃO grava. Só aplica quando o vivo == esperado.
      ELSIF v_kind = 'lang_level' THEN
        v_name := btrim(COALESCE(v_ch->>'name',''));
        v_expected := v_ch->>'expected';
        -- (blocker G) o NOVO nível NÃO-editável vem do payload VINCULADO, não do cliente;
        -- `expected` (token do CAS) SEGUE do cliente (é o valor observado no diff).
        v_prof := NULL;
        SELECT NULLIF(btrim(e->>'proficiency'),'') INTO v_prof
          FROM jsonb_array_elements(COALESCE(v_payload->'languages','[]'::jsonb)) e
          WHERE public._norm_txt(e->>'name') = public._norm_txt(v_name) LIMIT 1;
        v_bound := EXISTS (
          SELECT 1 FROM jsonb_array_elements(COALESCE(v_payload->'languages','[]'::jsonb)) e
          WHERE public._norm_txt(e->>'name') = public._norm_txt(v_name));
        IF v_name = '' OR NOT v_bound THEN
          v_rejected := v_rejected || to_jsonb('language:'||v_name);
        ELSE
          v_any_bound := true;
          v_live := NULL;
          SELECT proficiency INTO v_live FROM public.profile_languages
            WHERE user_id=v_uid AND public._norm_txt(name)=public._norm_txt(v_name) LIMIT 1;
          IF COALESCE(btrim(v_live),'') IS DISTINCT FROM COALESCE(btrim(v_expected),'') THEN
            v_stale := v_stale || to_jsonb('language:'||v_name);  -- manual mudou o nível → manual vence
          ELSE
            UPDATE public.profile_languages SET proficiency=v_prof WHERE user_id=v_uid AND public._norm_txt(name)=public._norm_txt(v_name);
            v_applied := v_applied || to_jsonb('language:'||v_name);
          END IF;
        END IF;

      -- ── CONFLITO de campo de ITEM: experiência (cargo) / formação (curso) ─────
      ELSIF v_kind = 'item_field' THEN
        v_sec := v_ch->>'section'; v_field := v_ch->>'field'; v_expected := v_ch->>'expected';
        v_val := btrim(COALESCE(v_ch->>'value',''));
        BEGIN v_refid := (v_ch->>'ref_id')::uuid; EXCEPTION WHEN OTHERS THEN
          RAISE EXCEPTION 'invalid_ref_id' USING ERRCODE='22023'; END;
        IF v_sec = 'experience' AND v_field = 'title' THEN
          SELECT company INTO v_keycompany FROM public.profile_experiences WHERE id=v_refid AND user_id=v_uid;
          v_bound := v_keycompany IS NOT NULL AND EXISTS (
            SELECT 1 FROM jsonb_array_elements(COALESCE(v_payload->'experiences','[]'::jsonb)) e
            WHERE public._norm_txt(e->>'company') = public._norm_txt(v_keycompany));
          IF v_bound THEN
            v_any_bound := true;
            SELECT title INTO v_live FROM public.profile_experiences WHERE id=v_refid AND user_id=v_uid;
            IF COALESCE(btrim(v_live),'') IS DISTINCT FROM COALESCE(btrim(v_expected),'') THEN
              v_stale := v_stale || to_jsonb('experience.title:'||v_refid::text);
            ELSE
              IF v_val = '' THEN RAISE EXCEPTION 'empty_title' USING ERRCODE='22023'; END IF;
              UPDATE public.profile_experiences SET title=v_val WHERE id=v_refid AND user_id=v_uid;
              v_applied := v_applied || to_jsonb('experience.title:'||v_refid::text);
            END IF;
          ELSE
            v_rejected := v_rejected || to_jsonb('experience.title:'||v_refid::text);
          END IF;
        ELSIF v_sec = 'education' AND v_field = 'degree' THEN
          SELECT institution INTO v_keyinst FROM public.profile_education WHERE id=v_refid AND user_id=v_uid;
          v_bound := v_keyinst IS NOT NULL AND EXISTS (
            SELECT 1 FROM jsonb_array_elements(COALESCE(v_payload->'education','[]'::jsonb)) e
            WHERE public._norm_txt(e->>'institution') = public._norm_txt(v_keyinst));
          IF v_bound THEN
            v_any_bound := true;
            SELECT degree INTO v_live FROM public.profile_education WHERE id=v_refid AND user_id=v_uid;
            IF COALESCE(btrim(v_live),'') IS DISTINCT FROM COALESCE(btrim(v_expected),'') THEN
              v_stale := v_stale || to_jsonb('education.degree:'||v_refid::text);
            ELSE
              UPDATE public.profile_education SET degree=NULLIF(v_val,'') WHERE id=v_refid AND user_id=v_uid;
              v_applied := v_applied || to_jsonb('education.degree:'||v_refid::text);
            END IF;
          ELSE
            v_rejected := v_rejected || to_jsonb('education.degree:'||v_refid::text);
          END IF;
        ELSE
          RAISE EXCEPTION 'invalid_item_field: %/%', v_sec, v_field USING ERRCODE='22023';
        END IF;

      -- ── ADIÇÃO INTEIRA de experiência (com bullets) — dados CANÔNICOS do payload ─
      ELSIF v_kind = 'add_experience' THEN
        v_keycompany := btrim(COALESCE(v_ch->>'company','')); v_keytitle := btrim(COALESCE(v_ch->>'title',''));
        SELECT value INTO v_item FROM jsonb_array_elements(COALESCE(v_payload->'experiences','[]'::jsonb))
          WHERE public._norm_txt(value->>'company') = public._norm_txt(v_keycompany)
            AND public._norm_txt(value->>'title') = public._norm_txt(v_keytitle) LIMIT 1;
        IF v_item IS NOT NULL THEN
          v_any_bound := true;
          PERFORM public.save_experience_with_bullets(v_uid, v_item - 'id');
          v_applied := v_applied || to_jsonb('experience+:'||v_keytitle);
        ELSE
          v_rejected := v_rejected || to_jsonb('experience+:'||v_keytitle);
        END IF;

      -- ── ADIÇÃO INTEIRA de formação (com filhas) — dados CANÔNICOS do payload ──
      ELSIF v_kind = 'add_education' THEN
        v_keyinst := btrim(COALESCE(v_ch->>'institution','')); v_keydeg := btrim(COALESCE(v_ch->>'degree',''));
        SELECT value INTO v_item FROM jsonb_array_elements(COALESCE(v_payload->'education','[]'::jsonb))
          WHERE public._norm_txt(value->>'institution') = public._norm_txt(v_keyinst)
            AND public._norm_txt(COALESCE(value->>'degree','')) = public._norm_txt(v_keydeg) LIMIT 1;
        IF v_item IS NOT NULL THEN
          v_any_bound := true;
          PERFORM public.save_education_with_children(v_uid, v_item - 'id');
          v_applied := v_applied || to_jsonb('education+:'||v_keyinst);
        ELSE
          v_rejected := v_rejected || to_jsonb('education+:'||v_keyinst);
        END IF;

      ELSE RAISE EXCEPTION 'invalid_choice_kind: %', v_kind USING ERRCODE='22023';
      END IF;
      EXCEPTION
        WHEN SQLSTATE '22023' OR SQLSTATE '23514' OR SQLSTATE '23502'
          OR SQLSTATE '22007' OR SQLSTATE '22008' OR SQLSTATE '22P02'
          OR SQLSTATE '23505' OR SQLSTATE 'P0002' THEN
          -- (blocker H) SÓ erros de VALIDAÇÃO/dado-ruim conhecidos (item aceito
          -- inaplicável: formação sem instituição, start_date inválida, edição vazia,
          -- bullet vazio, kind inválido) viram REJEITADO e o lote SEGUE — sem poison
          -- pill. v_any_bound já reflete o vínculo mesmo com o sub-savepoint revertido.
          v_rejected := v_rejected || to_jsonb('unapplicable:'||COALESCE(v_kind,'?'));
        -- WHEN OTHERS: erro INESPERADO (infra/schema/autorização/serialização/
        -- deadlock) NÃO é capturado aqui → PROPAGA ao savepoint externo → rollback
        -- TOTAL do lote + promoted:false (nunca "fingir" que aplicou).
      END;
    END LOOP;

    -- lote NÃO-vazio totalmente DESVINCULADO da revisão → recusa (tampering).
    IF jsonb_array_length(p_choices) > 0 AND NOT v_any_bound THEN
      RAISE EXCEPTION 'choices_unbound_from_revision' USING ERRCODE='22023';
    END IF;

    -- promove + ativa o cache na MESMA transação (sem falhas até aqui).
    PERFORM public._promote_imported_and_activate(v_uid, p_candidate_id, v_raw);
  EXCEPTION WHEN OTHERS THEN
    -- rollback do lote + promoção. Resposta reflete "nada persistiu"; NÃO vaza
    -- SQLERRM cru (blocker 14) — só um código curto e seguro (SQLSTATE).
    RETURN jsonb_build_object('applied','[]'::jsonb,'stale','[]'::jsonb,'rejected','[]'::jsonb,
      'failed', to_jsonb(ARRAY['apply_failed:'||SQLSTATE]), 'promoted', false);
  END;

  v_result := jsonb_build_object('applied', v_applied, 'stale', v_stale, 'rejected', v_rejected,
    'failed', '[]'::jsonb, 'promoted', true);
  -- (blocker E3) grava o recibo na MESMA transação da promoção (só no sucesso).
  INSERT INTO public.import_apply_receipts(candidate_id, attempt_id, operation, choices_hash, result)
    VALUES (p_candidate_id, p_attempt_id, 'apply_reviewed', v_hash, v_result);
  RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.apply_reviewed_conflicts_and_promote(uuid, uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_reviewed_conflicts_and_promote(uuid, uuid, jsonb) TO authenticated;

-- ABORT attempt-bound de candidata incompleta (Round 7/B3). Compensa
-- begin_import_source quando o cliente não conseguiu persistir o handle local.
-- Exige o attempt exato e só remove lifecycle não-terminal: pending/extracting/
-- failed, nunca ready/current nem candidata com recibo. Retorna o file_path
-- canônico; o cliente apaga o blob somente DEPOIS do commit desta RPC.
CREATE OR REPLACE FUNCTION public.abort_import_source(
  p_candidate_id uuid, p_attempt_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid(); v_src text; v_status text; v_attempt uuid;
  v_current boolean; v_path text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='28000'; END IF;
  IF p_attempt_id IS NULL THEN RAISE EXCEPTION 'attempt_required' USING ERRCODE='22004'; END IF;
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(v_uid));
  SELECT source, extraction_status, extraction_attempt_id, is_current_source, file_path
    INTO v_src, v_status, v_attempt, v_current, v_path
    FROM public.saved_resumes
   WHERE id=p_candidate_id AND user_id=v_uid
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'candidate_not_found' USING ERRCODE='P0002'; END IF;
  IF v_src <> 'imported' THEN RAISE EXCEPTION 'candidate_not_imported' USING ERRCODE='22023'; END IF;
  IF v_attempt IS NULL OR v_attempt <> p_attempt_id THEN
    RAISE EXCEPTION 'attempt_mismatch' USING ERRCODE='22023';
  END IF;
  IF COALESCE(v_current,false) OR v_status IS NULL
     OR v_status <> ALL (ARRAY['pending','extracting','failed']) THEN
    RAISE EXCEPTION 'candidate_not_abortable' USING ERRCODE='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.import_apply_receipts
             WHERE candidate_id=p_candidate_id AND attempt_id=p_attempt_id) THEN
    RAISE EXCEPTION 'candidate_has_terminal_receipt' USING ERRCODE='22023';
  END IF;
  DELETE FROM public.saved_resumes WHERE id=p_candidate_id AND user_id=v_uid;
  RETURN v_path;
END $$;
REVOKE ALL ON FUNCTION public.abort_import_source(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.abort_import_source(uuid, uuid) TO authenticated;

-- ── REMOÇÃO TRANSACIONAL de fonte importada (Round 4, blocker J) ─────────────
-- Excluir a fonte importada ATUAL pela row direta deixava o cache legacy
-- gamification_data.imported_resume órfão (match/adaptação continuavam lendo um
-- CV que não existe mais). Esta RPC faz tudo numa transação, sob o advisory lock:
--   • valida posse (auth.uid()); só atua sobre source='imported';
--   • sabe se era a fonte ATUAL (is_current_source);
--   • remove a row (o recibo de idempotência cai por CASCADE);
--   • se era a atual, LIMPA o cache imported_resume do gamification_data;
--   • NUNCA toca profile_* — o dado já INCORPORADO ao perfil permanece;
--   • não afeta documentos manual/adapted (o cliente roteia só imported por aqui).
-- Devolve {removed, was_current} para o cliente dar o feedback certo e remover o
-- blob do Storage DEPOIS do sucesso do banco (ordem que evita "sucesso" com estado
-- inconsistente; falha do blob físico é reportada à parte, sem perder consistência).
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
  IF COALESCE(v_current,false) THEN
    UPDATE public.user_profiles
      SET gamification_data = COALESCE(gamification_data,'{}'::jsonb) - 'imported_resume'
      WHERE id=v_uid;
  END IF;
  RETURN jsonb_build_object('removed', true, 'was_current', COALESCE(v_current,false));
END $$;
REVOKE ALL ON FUNCTION public.remove_imported_source(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.remove_imported_source(uuid) TO authenticated;

-- ── EXCLUSÃO CANÔNICA para TODO tipo de documento (Round 5 blocker E) ─────
-- O build novo passa por aqui (DB primeiro, blob depois). O DELETE direto existe
-- apenas como ponte do HEAD^ e é protegido por RLS + fence + cleanup trigger acima.
-- Esta RPC cobre os 4 casos numa transação, sob advisory, validando posse:
--   • imported ATUAL   → remove a row + LIMPA o cache imported_resume (mesma tx);
--   • imported histórica→ remove só a row (cache intacto);
--   • manual/adapted/output → remove só a row.
-- NUNCA toca profile_* (invariante 10): o dado já incorporado ao perfil permanece.
-- O recibo de idempotência da candidata cai por CASCADE. Devolve {removed, was_current}.
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
  -- SÓ a fonte importada ATUAL carrega cache legacy a limpar; nunca mexe em profile_*.
  IF v_src = 'imported' AND COALESCE(v_current,false) THEN
    UPDATE public.user_profiles
      SET gamification_data = COALESCE(gamification_data,'{}'::jsonb) - 'imported_resume'
      WHERE id=v_uid;
  END IF;
  RETURN jsonb_build_object('removed', true, 'was_current', COALESCE(v_current,false));
END $$;
REVOKE ALL ON FUNCTION public.delete_saved_resume(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_saved_resume(uuid) TO authenticated;

-- ── RECIBO TERMINAL (Round 5 blocker F) — leitura fail-closed para o coordenador ──
-- O coordenador Flutter escolhia inicial×revisão só pela vacuidade do perfil; depois
-- de uma aplicação já concluída (perfil agora cheio) ele reescolhia REVISÃO e drivava
-- um 2º terminal. Esta RPC read-only devolve o recibo terminal da candidata+attempt
-- (ou NULL) para o coordenador reconhecer "já concluído" e NÃO reaplicar. Valida posse.
CREATE OR REPLACE FUNCTION public.import_terminal_receipt(p_candidate_id uuid, p_attempt_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_uid uuid := auth.uid(); v_ok boolean; v_op text; v_res jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='28000'; END IF;
  SELECT EXISTS (SELECT 1 FROM public.saved_resumes WHERE id=p_candidate_id AND user_id=v_uid) INTO v_ok;
  IF NOT v_ok THEN RETURN NULL; END IF;  -- nunca vaza recibo de outro usuário
  SELECT operation, result INTO v_op, v_res FROM public.import_apply_receipts
    WHERE candidate_id=p_candidate_id AND attempt_id=p_attempt_id;
  IF v_op IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('operation', v_op, 'result', v_res);
END $$;
REVOKE ALL ON FUNCTION public.import_terminal_receipt(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.import_terminal_receipt(uuid, uuid) TO authenticated;

-- ── CAS do resumo (blocker 7 — generate-profile-summary não clobbera edição) ──
-- A IA lê summary+headline, gera por segundos, e gravava cegamente (lost update).
-- Agora: CAS nos DOIS — só grava se summary VIVO == p_expected_summary E headline
-- VIVO == p_expected_headline. Se QUALQUER um mudou (edição manual concorrente),
-- retorna 'stale' e NÃO sobrescreve NENHUM dos dois. Retorna 'applied' | 'stale'.
-- Nova assinatura (4→5 args); a antiga (4 args) é removida para não deixar um
-- caminho sem checagem de headline.
DROP FUNCTION IF EXISTS public.set_profile_summary_cas(uuid, text, text, text);
CREATE OR REPLACE FUNCTION public.set_profile_summary_cas(
  p_user_id uuid, p_summary text, p_headline text,
  p_expected_summary text, p_expected_headline text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_sum text; v_head text;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN RAISE EXCEPTION 'not_authorized' USING ERRCODE='28000'; END IF;
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(p_user_id));
  SELECT summary, headline INTO v_sum, v_head FROM public.profile_personal WHERE user_id = p_user_id;
  -- QUALQUER dos dois mudou desde a leitura da IA → não sobrescreve nenhum.
  IF COALESCE(btrim(v_sum),'') IS DISTINCT FROM COALESCE(btrim(p_expected_summary),'')
     OR COALESCE(btrim(v_head),'') IS DISTINCT FROM COALESCE(btrim(p_expected_headline),'') THEN
    RETURN 'stale';
  END IF;
  INSERT INTO public.profile_personal(user_id) VALUES (p_user_id) ON CONFLICT (user_id) DO NOTHING;
  UPDATE public.profile_personal SET summary = p_summary,
    headline = CASE WHEN btrim(COALESCE(p_headline,''))<>'' THEN p_headline ELSE headline END,
    updated_at = now() WHERE user_id = p_user_id;
  RETURN 'applied';
END $$;
REVOKE ALL ON FUNCTION public.set_profile_summary_cas(uuid, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_profile_summary_cas(uuid, text, text, text, text) TO authenticated;

-- ── Append fenced de bullets geradas (blocker 7 — generate-bullets) ──────────
-- Antes: INSERT direto append-only (fenced só via trigger), sem dedup → retries
-- duplicavam. Agora: RPC valida posse da experiência, fenced pelo lock, e DEDUP
-- por texto. Retorna quantas foram realmente inseridas.
CREATE OR REPLACE FUNCTION public.append_experience_bullets(
  p_user_id uuid, p_experience_id uuid, p_bullets jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_b jsonb; v_max int; v_n int := 0; v_txt text;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN RAISE EXCEPTION 'not_authorized' USING ERRCODE='28000'; END IF;
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(p_user_id));
  IF NOT EXISTS (SELECT 1 FROM public.profile_experiences WHERE id=p_experience_id AND user_id=p_user_id) THEN
    RAISE EXCEPTION 'experience_not_found' USING ERRCODE='P0002';
  END IF;
  SELECT COALESCE(max(order_index),-1) INTO v_max FROM public.profile_bullets WHERE experience_id=p_experience_id;
  FOR v_b IN SELECT value FROM jsonb_array_elements(COALESCE(p_bullets,'[]'::jsonb)) LOOP
    v_txt := btrim(COALESCE(v_b->>'text',''));
    IF v_txt = '' THEN CONTINUE; END IF;
    IF EXISTS (SELECT 1 FROM public.profile_bullets WHERE experience_id=p_experience_id AND lower(btrim(text))=lower(v_txt)) THEN CONTINUE; END IF;
    v_max := v_max + 1; v_n := v_n + 1;
    INSERT INTO public.profile_bullets(experience_id,text,angle,strength_score,order_index)
      VALUES (p_experience_id, v_b->>'text', v_b->>'angle', public.safe_integer(v_b->>'strength_score'), v_max);
  END LOOP;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.append_experience_bullets(uuid, uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.append_experience_bullets(uuid, uuid, jsonb) TO authenticated;

-- Reorder ATÔMICO de bullets de uma experiência/projeto (blocker 2). Era N
-- UPDATEs paralelos (Future.wait); agora uma transação sob o lock por-usuário,
-- validando posse do pai. Usa auth.uid() (o writer é sempre o dono).
CREATE OR REPLACE FUNCTION public.reorder_child_bullets(p_kind text, p_parent_id uuid, p_ids jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_uid uuid := auth.uid(); v_id uuid; v_ord bigint; v_n int; v_owner boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='28000'; END IF;
  IF p_kind <> ALL (ARRAY['experience','project']) THEN RAISE EXCEPTION 'invalid_kind' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(v_uid));
  IF p_kind = 'experience' THEN
    SELECT EXISTS(SELECT 1 FROM public.profile_experiences WHERE id=p_parent_id AND user_id=v_uid) INTO v_owner;
  ELSE
    SELECT EXISTS(SELECT 1 FROM public.profile_projects WHERE id=p_parent_id AND user_id=v_uid) INTO v_owner;
  END IF;
  IF NOT v_owner THEN RAISE EXCEPTION 'parent_not_owned' USING ERRCODE='P0002'; END IF;
  FOR v_id, v_ord IN SELECT value::text::uuid, ordinality FROM jsonb_array_elements_text(COALESCE(p_ids,'[]'::jsonb)) WITH ORDINALITY LOOP
    IF p_kind='experience' THEN
      UPDATE public.profile_bullets SET order_index=(v_ord-1)::int WHERE id=v_id AND experience_id=p_parent_id;
    ELSE
      UPDATE public.profile_project_bullets SET order_index=(v_ord-1)::int WHERE id=v_id AND project_id=p_parent_id;
    END IF;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 1 THEN RAISE EXCEPTION 'reorder_bullet_not_found: %', v_id USING ERRCODE='P0002'; END IF;
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.reorder_child_bullets(text, uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reorder_child_bullets(text, uuid, jsonb) TO authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- BLINDAGEM DE PRIVILÉGIOS (Gate 2.3 R3 blocker 1 + 2) — NENHUMA função nasce
-- executável por PUBLIC. Por padrão o Postgres concede EXECUTE a PUBLIC em toda
-- função nova; CREATE OR REPLACE em base limpa também. Aqui, DEPOIS de todas as
-- funções das DUAS migrations existirem, revogamos EXECUTE de PUBLIC/anon/
-- authenticated/service_role de TODAS e re-concedemos SÓ os contratos:
--   • helpers internas (inclusive as SECURITY DEFINER como _promote_imported_and_
--     activate) → NENHUM grant (só o owner as chama, de dentro de outras DEFINER);
--   • RPCs client-callable → authenticated;
--   • RPCs de Edge → service_role.
-- promote_imported_source: SEM grant — promoção direta (sem apply/revisão/attempt)
-- APOSENTADA (blocker 2). A promoção só existe dentro de apply_and_promote e
-- apply_reviewed_conflicts_and_promote.
DO $sec$
DECLARE
  fn text; role_name text;
  v_all text[] := ARRAY[
    'public._fill_empty_text(text, text)','public.profile_write_lock_key(uuid)',
    'public._fence_profile_writes()','public._mark_latest_legacy_source_on_insert()',
    'public._canonical_import_cache(uuid)','public._guard_user_profile_import_cache()',
    'public._cleanup_import_cache_after_saved_resume_delete()',
    'public._save_profile_fill_empty_core(uuid, jsonb)',
    'public._assert_jtype(jsonb, text, text[], text)','public._assert_string_list(jsonb, text, text)',
    'public._validate_profile_payload(jsonb)','public._profile_payload_has_content(jsonb)',
    'public._profile_has_protected_data(uuid)','public._promote_imported_and_activate(uuid, uuid, text)',
    'public._replace_simple_list(uuid, text, jsonb)','public._profile_scalar_column(text)',
    'public._payload_scalar_source(text)','public._norm_txt(text)',
    'public._payload_list_key(text)','public._cas_write_personal_field(uuid, text, text, text, text, text)',
    -- (Round 5) helpers internos novos: contato profissional (C) + cores de fidelidade (G).
    'public._is_public_contact_email(text)','public._resolve_contact_email(text, text)',
    'public._save_experience_with_bullets_core(uuid, jsonb)','public._save_education_with_children_core(uuid, jsonb)',
    'public._save_project_with_bullets_core(uuid, jsonb)',
    'public.promote_imported_source(uuid)',
    'public.set_import_extraction_status(uuid, text, text)','public.begin_import_source(text, text, text, uuid)',
    'public.save_profile_fill_empty(uuid, jsonb)','public.apply_and_promote_imported_source(uuid, uuid)',
    'public.save_experience_with_bullets(uuid, jsonb)','public.save_education_with_children(uuid, jsonb)',
    'public.save_project_with_bullets(uuid, jsonb)','public.replace_profile_skills(uuid, jsonb)',
    'public.replace_profile_interests(uuid, jsonb)','public.replace_profile_coursework(uuid, jsonb)',
    'public.reorder_profile_section(uuid, text, jsonb)','public.cas_write_profile_scalar(uuid, text, text, text, text, text)',
    'public.apply_reviewed_conflicts_and_promote(uuid, uuid, jsonb)','public.set_profile_summary_cas(uuid, text, text, text, text)',
    'public.append_experience_bullets(uuid, uuid, jsonb)','public.reorder_child_bullets(text, uuid, jsonb)',
    'public.abort_import_source(uuid, uuid)','public.remove_imported_source(uuid)',
    'public.delete_saved_resume(uuid)','public.delete_user()','public.import_terminal_receipt(uuid, uuid)',
    'public.complete_import_extraction(uuid, uuid, jsonb, text, jsonb, jsonb)','public.save_profile_fill_empty_service(uuid, jsonb)',
    'public.save_profile_from_json(uuid, jsonb)'];
  v_client text[] := ARRAY[
    -- (Round 5 blocker E) set_import_extraction_status REMOVIDO: sem caller, e podia
    -- rebaixar a fonte atual sem limpar o cache. Fica revogado (só em v_all).
    'public.begin_import_source(text, text, text, uuid)',
    'public.save_profile_fill_empty(uuid, jsonb)','public.apply_and_promote_imported_source(uuid, uuid)',
    'public.save_experience_with_bullets(uuid, jsonb)','public.save_education_with_children(uuid, jsonb)',
    'public.save_project_with_bullets(uuid, jsonb)','public.replace_profile_skills(uuid, jsonb)',
    'public.replace_profile_interests(uuid, jsonb)','public.replace_profile_coursework(uuid, jsonb)',
    'public.reorder_profile_section(uuid, text, jsonb)','public.cas_write_profile_scalar(uuid, text, text, text, text, text)',
    'public.apply_reviewed_conflicts_and_promote(uuid, uuid, jsonb)','public.set_profile_summary_cas(uuid, text, text, text, text)',
    'public.append_experience_bullets(uuid, uuid, jsonb)','public.reorder_child_bullets(text, uuid, jsonb)',
    'public.abort_import_source(uuid, uuid)','public.remove_imported_source(uuid)',
    'public.delete_saved_resume(uuid)','public.delete_user()','public.import_terminal_receipt(uuid, uuid)'];
  v_service text[] := ARRAY[
    'public.complete_import_extraction(uuid, uuid, jsonb, text, jsonb, jsonb)','public.save_profile_fill_empty_service(uuid, jsonb)',
    'public.save_profile_from_json(uuid, jsonb)'];
BEGIN
  FOREACH fn IN ARRAY v_all LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', fn);
    FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I', fn, role_name);
      END IF;
    END LOOP;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    FOREACH fn IN ARRAY v_client LOOP EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', fn); END LOOP;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN
    FOREACH fn IN ARRAY v_service LOOP EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn); END LOOP;
  END IF;
END $sec$;

COMMIT;
