-- Fase 3 "Perfil Central": metadados persistentes da FONTE IMPORTADA.
--
-- Hoje o nome real do PDF vive só transitoriamente em CvImportResult.fileName e
-- o status da extração só existe em memória (ExtractionStatusViewModel) — nada
-- sobrevive ao restart. Esta migration estende `saved_resumes` de forma ADITIVA
-- pra que a seção "Fonte importada" (Perfil → Dados) tenha nome + status
-- confiáveis e pra suportar substituição ATÔMICA da fonte atual.
--
-- Backward-compatible: TODAS as colunas novas são nullable ou têm default, então
-- registros legados ficam com NULL/false e a UI os trata como "status
-- indisponível" (legado) — NUNCA inventa nome ou resultado de extração. NÃO
-- destrutiva. Não aplicar remotamente aqui (R2: só via CLI no release).

BEGIN;

ALTER TABLE public.saved_resumes
  ADD COLUMN IF NOT EXISTS original_filename text NULL,
  ADD COLUMN IF NOT EXISTS extraction_status text NULL,
  ADD COLUMN IF NOT EXISTS extraction_started_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS extraction_completed_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS extraction_error_code text NULL,
  ADD COLUMN IF NOT EXISTS is_current_source boolean NOT NULL DEFAULT false,
  -- Ponte TEMPORÁRIA para localizar a row legacy mais recente nos fluxos de
  -- biblioteca/remoção. O protocolo antigo criava a row e gravava
  -- gamification_data.imported_resume em requests concorrentes, SEM candidate_id;
  -- portanto o marker NÃO prova que o cache veio desta row e jamais autoriza
  -- inventar source_resume_id. Cache sem id permanece explicitamente UNBOUND.
  -- Nunca é gravável pelo client.
  ADD COLUMN IF NOT EXISTS is_latest_legacy_source boolean NOT NULL DEFAULT false,
  -- Payload extraído VINCULADO à candidata (Gate 2.3 blocker 3): a aplicação lê
  -- o JSON DAQUI (não de um arg independente) e valida o attempt_id, tornando
  -- impossível aplicar o payload de A na candidata B. Preenchidos pela Edge de
  -- extração ao concluir; nunca alterável direto pelo authenticated (grants
  -- abaixo).
  ADD COLUMN IF NOT EXISTS extraction_payload jsonb NULL,
  ADD COLUMN IF NOT EXISTS extraction_attempt_id uuid NULL,
  -- raw_text VINCULADO à candidata (blocker 3): não vai para o cache legacy ativo
  -- (gamification_data.imported_resume) até a PROMOÇÃO. Match/adaptação só passam
  -- a usá-lo depois de promovido.
  ADD COLUMN IF NOT EXISTS extraction_raw_text text NULL,
  -- Representação LEGACY (blocker 9) da extração VINCULADA à candidata: o formato
  -- `imported_resume.parsed` (toLegacyResume) + os metadados (confidence/parser)
  -- que a Edge já calcula. A PROMOÇÃO reescreve o cache legacy INTEIRO a partir
  -- DESSES campos + do raw_text da candidata — cache coerente com a fonte atual,
  -- sem sobras (parsed/raw_text) de uma importação anterior. Nunca alterável direto
  -- pelo authenticated (grants por-coluna abaixo); preenchidos por
  -- complete_import_extraction (service_role) junto com payload/raw/ready.
  ADD COLUMN IF NOT EXISTS extraction_legacy_parsed jsonb NULL,
  ADD COLUMN IF NOT EXISTS extraction_meta jsonb NULL,
  -- (Round 7/B3) token gerado e persistido NO CLIENTE antes de upload/begin. Um
  -- replay após crash usa o mesmo token e recupera a MESMA candidata+attempt, em
  -- vez de criar uma segunda row para o mesmo arquivo. Coluna de integridade:
  -- authenticated não recebe grant direto de INSERT/UPDATE nela.
  ADD COLUMN IF NOT EXISTS client_import_id uuid NULL;

-- Status válidos. NULL = legado (status indisponível) — o CHECK tolera NULL.
-- Nunca gravar stack trace / mensagem sensível: extraction_error_code é um
-- código curto e seguro (ex.: 'timeout', 'parse_failed', 'network').
ALTER TABLE public.saved_resumes
  DROP CONSTRAINT IF EXISTS saved_resumes_extraction_status_check;
ALTER TABLE public.saved_resumes
  ADD CONSTRAINT saved_resumes_extraction_status_check
  CHECK (
    extraction_status IS NULL
    OR extraction_status = ANY (ARRAY['pending', 'extracting', 'ready', 'failed'])
  );

-- A "fonte atual" só pode ser uma IMPORTADA e READY. O CHECK vale para TODAS as
-- linhas (não só as do índice) — impede is_current_source=true em manual/adapted
-- E em importadas ainda pending/extracting/failed. Assim é impossível existir
-- linha current fora do índice parcial. Legados (false por default) passam
-- trivialmente. NÃO pomos `ready` só no predicado do índice (isso deixaria
-- currents inválidos fora do índice, driblando a unicidade).
ALTER TABLE public.saved_resumes
  DROP CONSTRAINT IF EXISTS saved_resumes_current_only_imported_check;
ALTER TABLE public.saved_resumes
  ADD CONSTRAINT saved_resumes_current_only_imported_check
  CHECK (
    is_current_source = false
    OR (source = 'imported' AND extraction_status = 'ready')
  );

-- Um marker legacy jamais pode se passar pela fonte canônica. Ele só existe
-- em imports do protocolo antigo: status/attempt/client token ausentes e
-- is_current_source=false. Primeiro normalizamos (idempotência de reapply),
-- depois validamos o CHECK.
-- Zera antes de recalcular: além de remover qualquer marker inválido, evita
-- unique_violation por ordem de linhas num reapply quando uma row mais nova
-- precisa assumir o marker que ainda estava na antiga.
UPDATE public.saved_resumes
   SET is_latest_legacy_source = false
 WHERE is_latest_legacy_source;

ALTER TABLE public.saved_resumes
  DROP CONSTRAINT IF EXISTS saved_resumes_latest_legacy_only_check;
ALTER TABLE public.saved_resumes
  ADD CONSTRAINT saved_resumes_latest_legacy_only_check
  CHECK (
    is_latest_legacy_source = false
    OR (
      source = 'imported'
      AND extraction_status IS NULL
      AND extraction_attempt_id IS NULL
      AND client_import_id IS NULL
      AND is_current_source = false
    )
  );

-- Backfill determinístico do marker de BIBLIOTECA: para cada usuário, aponta o
-- PDF legacy mais recente (empate por id). Isto NÃO associa o cache legacy à
-- row: uma segunda importação podia salvar B e falhar antes de atualizar o cache
-- de A. Sem candidate_id/hash não existe correlação demonstrável; o cache segue
-- sem source_resume_id. Reapply recalcula só o marker, nunca o vínculo.
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
   SET is_latest_legacy_source = (ranked.rn = 1)
  FROM ranked
 WHERE s.id = ranked.id
   AND s.is_latest_legacy_source IS DISTINCT FROM (ranked.rn = 1);

-- No máximo UMA fonte importada "atual" por usuário (substituição atômica). O
-- índice parcial só cobre linhas de IMPORTADO com a flag true, então os legados
-- (false por default) e as saídas nunca conflitam. A promoção zera a antiga e
-- só depois marca a nova, na MESMA transação (ver promote_imported_source).
DROP INDEX IF EXISTS public.saved_resumes_one_current_source_per_user;
CREATE UNIQUE INDEX IF NOT EXISTS saved_resumes_one_current_source_per_user
  ON public.saved_resumes (user_id)
  WHERE is_current_source AND source = 'imported';

-- Idempotência de begin por usuário. NULL preserva registros legados; imports
-- novos exigem token não-nulo na RPC begin_import_source de 4 argumentos.
CREATE UNIQUE INDEX IF NOT EXISTS saved_resumes_client_import_id_per_user
  ON public.saved_resumes (user_id, client_import_id)
  WHERE client_import_id IS NOT NULL;

DROP INDEX IF EXISTS public.saved_resumes_one_latest_legacy_source_per_user;
CREATE UNIQUE INDEX saved_resumes_one_latest_legacy_source_per_user
  ON public.saved_resumes (user_id)
  WHERE is_latest_legacy_source;

-- Chave do advisory lock por-usuário (ordem ÚNICA de locks). Definida aqui pois
-- as RPCs desta migration já a usam; 20260714130000 a redefine (idêntica,
-- idempotente) junto do fencing por statement.
CREATE OR REPLACE FUNCTION public.profile_write_lock_key(p_user_id uuid)
RETURNS bigint LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT hashtextextended('profile_write:' || p_user_id::text, 0)
$$;
-- Helper interno: expô-lo permitiria a uma sessão segurar o lock de outro UUID.
-- Triggers e RPCs SECURITY DEFINER o executam como owner; nenhum papel de API
-- precisa chamá-lo diretamente, inclusive na janela antes da próxima migration.
REVOKE ALL ON FUNCTION public.profile_write_lock_key(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

-- ── PROTEÇÃO DAS COLUNAS DE INTEGRIDADE (Gate 2.3 blocker 4) ─────────────────
-- authenticated NÃO pode ALTERAR diretamente colunas de integridade
-- (extraction_status/started_at/completed_at/error_code, is_current_source,
-- extraction_payload/attempt_id). Só as RPCs SECURITY DEFINER validadas mudam
-- status/promoção. Grant por-COLUNA restringe tanto UPDATE quanto INSERT às
-- colunas legítimas da biblioteca — assim um INSERT direto também não pode
-- forjar uma fonte 'ready'/'current' sem passar pela extração.
REVOKE UPDATE, INSERT ON public.saved_resumes FROM authenticated;
-- UPDATE só nas colunas de biblioteca (renomear, trocar template, salvar conteúdo).
GRANT UPDATE (title, template_id, resume_data) ON public.saved_resumes TO authenticated;
-- INSERT só nas colunas não-integridade; as de integridade caem no DEFAULT
-- (extraction_status=NULL, is_current_source=false, payload/attempt=NULL).
-- `user_id` precisa permanecer no grant por compatibilidade com o build anterior
-- (saveResume enviava explicitamente o uid da sessão). Isso NÃO reabre forge de
-- dono: a policy INSERT existente exige user_id=auth.uid(); outro uid falha em
-- RLS. O build novo pode continuar omitindo a coluna e usando DEFAULT auth.uid().
GRANT INSERT (user_id, title, file_path, source, resume_data, template_id, original_filename)
  ON public.saved_resumes TO authenticated;

-- O user_id explícito do HEAD^ é aceito, mas dono E namespace do blob precisam
-- ser os da sessão. Sem o prefixo, um cliente poderia registrar no próprio row
-- um path pertencente a outro usuário e induzir deletes/downloads indevidos.
DROP POLICY IF EXISTS "Users can insert their own resumes" ON public.saved_resumes;
CREATE POLICY "Users can insert their own resumes"
  ON public.saved_resumes FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT auth.uid()) = user_id
    AND split_part(file_path, '/', 1) = (SELECT auth.uid())::text
    AND cardinality(string_to_array(file_path, '/')) >= 2
    AND array_position(string_to_array(file_path, '/'), '') IS NULL
    AND NOT (string_to_array(file_path, '/') && ARRAY['.','..']::text[])
    AND strpos(file_path, E'\\') = 0
  );
-- Compatibilidade precisa existir AO FINAL DE CADA migration: o CLI commita os
-- arquivos separadamente e o HEAD^ remove o blob antes do DELETE da row. Manter
-- DELETE authenticated nesta migration evita uma janela 120000→130000 em que o
-- build antigo deixaria blob já removido + row órfã por 42501. A policy exige
-- dono E namespace seguro do arquivo. A 130000 instala fence+cleanup e recria o
-- mesmo contrato na própria transação.
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

-- Nenhuma Edge/admin apaga saved_resumes diretamente. service_role fica
-- fail-closed: DELETE deve passar por RPC SECURITY DEFINER (que toma advisory
-- por p_user_id) ou pela cascata do owner.
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    EXECUTE 'REVOKE DELETE ON public.saved_resumes FROM anon';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN
    EXECUTE 'REVOKE DELETE ON public.saved_resumes FROM service_role';
  END IF;
END $$;

-- ── Transição de status da extração (RPC validada; única via authenticated) ──
-- O client acompanha pending→extracting→ready/failed por AQUI, nunca por UPDATE
-- direto. SECURITY DEFINER: roda como owner (contorna o grant por-coluna) mas
-- valida posse via auth.uid(). NÃO promove nem toca is_current_source.
CREATE OR REPLACE FUNCTION public.set_import_extraction_status(
  p_candidate_id uuid, p_status text, p_error_code text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_uid uuid := auth.uid(); v_src text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='28000'; END IF;
  -- (blocker 2) authenticated NÃO pode marcar 'ready' — ready exige payload+attempt
  -- válidos e só vem via complete_import_extraction (service_role). Aqui só o
  -- ciclo do cliente: pending / extracting / failed.
  IF p_status IS NULL OR p_status <> ALL (ARRAY['pending','extracting','failed']) THEN
    RAISE EXCEPTION 'invalid_status' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(v_uid));
  SELECT source INTO v_src FROM public.saved_resumes
    WHERE id = p_candidate_id AND user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'candidate_not_found' USING ERRCODE='P0002'; END IF;
  IF v_src <> 'imported' THEN RAISE EXCEPTION 'candidate_not_imported' USING ERRCODE='22023'; END IF;
  UPDATE public.saved_resumes SET
    extraction_status = p_status,
    extraction_started_at = CASE WHEN p_status='extracting' THEN now() ELSE extraction_started_at END,
    extraction_completed_at = CASE WHEN p_status='failed' THEN now() ELSE extraction_completed_at END,
    extraction_error_code = CASE WHEN p_status='failed' THEN p_error_code ELSE NULL END,
    -- sair de 'ready' rebaixa (retry: ready→extracting→ready) para não ficar atual inválida.
    is_current_source = false
  WHERE id = p_candidate_id;
END $$;
-- (Round 5 blocker E) set_import_extraction_status NÃO recebe grant: não há caller
-- Dart/TS (grep repo-wide = zero) e este caminho podia rebaixar uma fonte ready/current
-- para extracting/failed zerando is_current_source SEM limpar o cache legacy → flag e
-- cache divergiam. Sem grant = owner-only (uncallable por cliente). A blindagem de
-- privilégios de …130000 também o mantém fora de v_client.
REVOKE ALL ON FUNCTION public.set_import_extraction_status(uuid, text, text) FROM PUBLIC;

-- ── LIFECYCLE da fonte importada (blocker 2) ─────────────────────────────────
-- begin_import_source: o app cria a CANDIDATA rastreável (source=imported,
-- status=pending, attempt_id gerado) e recebe candidate_id+attempt_id. O
-- client_import_id nasce e é persistido junto dos bytes ANTES desta chamada:
-- replay com o mesmo token+arquivo devolve a MESMA candidata/attempt; reutilizar
-- o token com outro arquivo é rejeitado fail-closed. Isso fecha a janela
-- begin-confirmado / handle-local-não-persistido sem permitir overwrite de ready.
DROP FUNCTION IF EXISTS public.begin_import_source(text, text, text);
CREATE OR REPLACE FUNCTION public.begin_import_source(
  p_title text, p_file_path text, p_original_filename text, p_client_import_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid(); v_id uuid; v_attempt uuid := gen_random_uuid();
  v_path text; v_original text; v_expected_path text; v_input_original text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='28000'; END IF;
  IF p_client_import_id IS NULL THEN RAISE EXCEPTION 'client_import_id_required' USING ERRCODE='22004'; END IF;
  -- O servidor, não o cliente, define o único path canônico deste token. Além
  -- de fechar referências arbitrárias para blobs de outro usuário, isso torna o
  -- replay determinístico: o mesmo uid+client_import_id sempre aponta aos mesmos bytes.
  v_expected_path := v_uid::text || '/imports/' || p_client_import_id::text || '.pdf';
  IF p_file_path IS DISTINCT FROM v_expected_path THEN
    RAISE EXCEPTION 'invalid_file_path' USING ERRCODE='22023';
  END IF;
  -- O bundle local persiste filename.trim(); normalize do mesmo modo no primeiro
  -- begin e no replay para um crash não transformar espaços periféricos em mismatch.
  v_input_original := NULLIF(btrim(COALESCE(p_original_filename,'')), '');
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(v_uid));

  -- O advisory por usuário serializa SELECT→INSERT; o índice único é a
  -- última barreira. O token vincula o arquivo: metadados divergentes indicam
  -- reuso acidental/malicioso e nunca reutilizam payload/attempt existente.
  SELECT id, extraction_attempt_id, file_path, original_filename
    INTO v_id, v_attempt, v_path, v_original
    FROM public.saved_resumes
   WHERE user_id = v_uid AND client_import_id = p_client_import_id
   FOR UPDATE;
  IF FOUND THEN
    IF v_path IS DISTINCT FROM v_expected_path
       OR v_original IS DISTINCT FROM v_input_original THEN
      RAISE EXCEPTION 'client_import_id_mismatch' USING ERRCODE='22023';
    END IF;
    IF v_attempt IS NULL THEN
      RAISE EXCEPTION 'client_import_missing_attempt' USING ERRCODE='23514';
    END IF;
    RETURN jsonb_build_object('candidate_id', v_id, 'attempt_id', v_attempt,
      'file_path', v_path, 'replayed', true);
  END IF;

  v_attempt := gen_random_uuid();
  INSERT INTO public.saved_resumes (user_id, title, file_path, source, original_filename,
    extraction_status, extraction_attempt_id, client_import_id)
  VALUES (v_uid, COALESCE(NULLIF(btrim(p_title),''), 'Currículo importado'), v_expected_path, 'imported',
    v_input_original, 'pending', v_attempt, p_client_import_id)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('candidate_id', v_id, 'attempt_id', v_attempt,
    'file_path', v_expected_path, 'replayed', false);
END $$;
REVOKE ALL ON FUNCTION public.begin_import_source(text, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.begin_import_source(text, text, text, uuid) TO authenticated;

-- complete_import_extraction: a Edge de extração (service_role) conclui a
-- candidata como READY, gravando payload + raw_text ATOMICAMENTE. Autorização =
-- GRANT service_role + vínculo candidate+attempt. Valida posse/tipo/status/attempt
-- e o SCHEMA do payload (fail-closed) ANTES de marcar ready. O cliente NÃO
-- consegue chamar (sem grant) — não há bypass pending→ready. Serializa pela
-- própria candidata (FOR UPDATE); não toca profile_* (não precisa do advisory).
-- A assinatura ganhou p_legacy_parsed/p_meta (blocker 9) — precisa DROP do overload
-- antigo (4-arg) antes do CREATE, senão os dois coexistiriam.
DROP FUNCTION IF EXISTS public.complete_import_extraction(uuid, uuid, jsonb, text);
CREATE OR REPLACE FUNCTION public.complete_import_extraction(
  p_candidate_id uuid, p_attempt_id uuid, p_payload jsonb, p_raw_text text,
  p_legacy_parsed jsonb DEFAULT NULL, p_meta jsonb DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_src text; v_st text; v_attempt uuid; v_existing jsonb; v_eraw text; v_eparsed jsonb; v_emeta jsonb;
BEGIN
  SELECT source, extraction_status, extraction_attempt_id, extraction_payload,
         extraction_raw_text, extraction_legacy_parsed, extraction_meta
    INTO v_src, v_st, v_attempt, v_existing, v_eraw, v_eparsed, v_emeta
    FROM public.saved_resumes WHERE id = p_candidate_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'candidate_not_found' USING ERRCODE='P0002'; END IF;
  IF v_src <> 'imported' THEN RAISE EXCEPTION 'candidate_not_imported' USING ERRCODE='22023'; END IF;
  -- VÍNCULO attempt: exigido SEMPRE, inclusive no replay idempotente.
  IF p_attempt_id IS NULL OR v_attempt IS NULL OR v_attempt <> p_attempt_id THEN
    RAISE EXCEPTION 'attempt_mismatch' USING ERRCODE='22023'; END IF;
  -- fail-closed (blocker 14): schema + CONTEÚDO real. Nunca marcar ready uma
  -- extração vazia (payload {} / só ruído) — senão promoveria "nada" como sucesso.
  PERFORM public._validate_profile_payload(p_payload);
  IF NOT public._profile_payload_has_content(p_payload) THEN
    RAISE EXCEPTION 'empty_payload' USING ERRCODE='22023'; END IF;
  -- (blocker I) CONTRATO COMPLETO do cache: parsed-legacy e meta são OBRIGATÓRIOS
  -- e não-vazios — uma fonte NUNCA pode ser promovida com imported_resume.parsed:{}
  -- por omissão acidental da Edge. O cache legacy é reconstruído desses campos.
  IF p_legacy_parsed IS NULL OR jsonb_typeof(p_legacy_parsed) <> 'object' OR p_legacy_parsed = '{}'::jsonb THEN
    RAISE EXCEPTION 'missing_legacy_parsed' USING ERRCODE='22023'; END IF;
  -- (Round 6 adj6) ESTRUTURA MÍNIMA do meta — não basta "objeto não-vazio". Um blob
  -- acidental ({"x":1}) NÃO é meta de extração. Exige as chaves que TODA extração real
  -- grava: parser_version (texto não-vazio) + parsed_at (texto não-vazio). Assim uma
  -- candidata só fica 'ready' com um meta reconstruível, e o replay/cache é coerente.
  IF p_meta IS NULL OR jsonb_typeof(p_meta) <> 'object'
     OR jsonb_typeof(p_meta->'parser_version') IS DISTINCT FROM 'string'
     OR jsonb_typeof(p_meta->'parsed_at') IS DISTINCT FROM 'string'
     OR NULLIF(btrim(coalesce(p_meta->>'parser_version','')), '') IS NULL
     OR NULLIF(btrim(coalesce(p_meta->>'parsed_at','')), '') IS NULL THEN
    RAISE EXCEPTION 'missing_meta' USING ERRCODE='22023'; END IF;

  -- (blocker 8/I) IDEMPOTÊNCIA sobre o CONJUNTO CANÔNICO completo: já READY com o
  -- MESMO attempt E o MESMO payload+raw+parsed+meta ⇒ reentrega da mesma conclusão
  -- → no-op (sem 2ª escrita, sem mexer em completed_at). Qualquer divergência numa
  -- candidata já ready = tentativa de sobrescrever a conclusão → rejeita.
  IF v_st = 'ready' THEN
    IF v_existing IS NOT DISTINCT FROM p_payload
       AND v_eraw IS NOT DISTINCT FROM p_raw_text
       AND v_eparsed IS NOT DISTINCT FROM p_legacy_parsed
       AND v_emeta IS NOT DISTINCT FROM p_meta THEN
      RETURN;  -- replay idêntico → idempotente.
    END IF;
    RAISE EXCEPTION 'candidate_already_completed' USING ERRCODE='22023';
  END IF;
  IF v_st NOT IN ('pending','extracting') THEN
    RAISE EXCEPTION 'candidate_not_extracting' USING ERRCODE='22023'; END IF;

  UPDATE public.saved_resumes SET
    extraction_payload = p_payload, extraction_raw_text = p_raw_text,
    extraction_legacy_parsed = p_legacy_parsed, extraction_meta = p_meta,
    extraction_status = 'ready', extraction_completed_at = now(), extraction_error_code = NULL
  WHERE id = p_candidate_id;
END $$;
REVOKE ALL ON FUNCTION public.complete_import_extraction(uuid, uuid, jsonb, text, jsonb, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_import_extraction(uuid, uuid, jsonb, text, jsonb, jsonb) TO service_role;

COMMENT ON COLUMN public.saved_resumes.original_filename IS
  'Nome real do PDF enviado pelo usuário (Fase 3). Null em registros legados.';
COMMENT ON COLUMN public.saved_resumes.extraction_status IS
  'pending | extracting | ready | failed. Null = legado (status indisponível). '
  'Só relevante para source = imported.';
COMMENT ON COLUMN public.saved_resumes.extraction_error_code IS
  'Código curto e seguro do erro de extração (nunca stack trace/PII).';
COMMENT ON COLUMN public.saved_resumes.is_current_source IS
  'Fonte importada ATUAL do usuário (substituição atômica). Índice parcial '
  'único garante no máximo 1 por user; legados ficam false.';
COMMENT ON COLUMN public.saved_resumes.is_latest_legacy_source IS
  'Ponte temporária: row importada mais recente na biblioteca do protocolo antigo. '
  'NÃO prova nem cria vínculo com gamification_data sem candidate_id; não significa READY/current.';

-- ── Promoção ATÔMICA da fonte importada (substituição fail-safe, R5) ─────────
-- Transforma "zerar a antiga" + "marcar a nova" em UMA transação. O índice
-- parcial garante ≤1 flag, mas NÃO torna as duas operações do cliente
-- atômicas — por isso esta função. Valida, na mesma transação:
--   • usuário autenticado (auth.uid());
--   • candidato existe e é do usuário (FOR UPDATE serializa concorrência);
--   • source = 'imported';
--   • extração TERMINOU e está utilizável (extraction_status = 'ready').
-- Qualquer falha (RAISE) faz ROLLBACK → a fonte anterior é preservada
-- integralmente. SECURITY DEFINER (blocker 4): is_current_source é coluna de
-- integridade, sem grant de UPDATE p/ authenticated — então a promoção roda como
-- owner, mas valida posse por auth.uid(). Contrato UNIFICADO de lock: usa o mesmo
-- profile_write_lock_key de TODAS as escritas de perfil (antes era um advisory
-- key diferente, que não serializava contra apply/fill-empty).
-- Uso: PROMOÇÃO da fonte revisada (substituição) — a aplicação das escolhas
-- aceitas já aconteceu; aqui só se marca a atual.
CREATE OR REPLACE FUNCTION public.promote_imported_source(p_candidate_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_source text;
  v_status text;
  v_raw    text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'promote_imported_source: not_authenticated'
      USING ERRCODE = '28000';
  END IF;

  -- Contrato de lock UNIFICADO: mesma chave por-usuário de todo write de perfil,
  -- adquirida ANTES do FOR UPDATE (advisory→tuple). Serializa promoções de
  -- candidatas DIFERENTES do mesmo usuário (o FOR UPDATE sozinho não o faria).
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(v_uid));

  -- Trava a candidata e valida posse.
  SELECT source, extraction_status, extraction_raw_text
    INTO v_source, v_status, v_raw
    FROM public.saved_resumes
   WHERE id = p_candidate_id AND user_id = v_uid
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'promote_imported_source: candidate_not_found'
      USING ERRCODE = 'P0002';
  END IF;
  IF v_source <> 'imported' THEN
    RAISE EXCEPTION 'promote_imported_source: candidate_not_imported'
      USING ERRCODE = '22023';
  END IF;
  IF v_status IS DISTINCT FROM 'ready' THEN
    RAISE EXCEPTION 'promote_imported_source: candidate_not_ready'
      USING ERRCODE = '22023';
  END IF;

  -- Promoção + ativação do cache legacy na MESMA transação (blocker 3). O helper
  -- (definido em 20260714130000) faz clear→set + gamification_data.imported_resume.
  PERFORM public._promote_imported_and_activate(v_uid, p_candidate_id, v_raw);
END;
$$;

REVOKE ALL ON FUNCTION public.promote_imported_source(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.promote_imported_source(uuid)
  FROM anon, authenticated, service_role;

COMMENT ON FUNCTION public.promote_imported_source(uuid) IS
  'Fase 3: promove uma fonte importada READY como is_current_source do usuário, '
  'zerando a anterior na MESMA transação. Falha (posse/tipo/prontidão) → '
  'rollback, preservando a fonte anterior.';

-- ── RECIBO de IDEMPOTÊNCIA de aplicação (Round 4, blocker E) ─────────────────
-- Marker persistido por (candidate, attempt, operação) DENTRO da transação de
-- apply/promote. Torna as RPCs de aplicação idempotentes ponta a ponta:
--   • apply_initial: 1ª chamada promove e grava o recibo com o resultado; um
--     replay (resposta perdida) devolve EXATAMENTE o mesmo sucesso, sem re-aplicar
--     (não dispara profile_not_empty_use_review por o perfil já estar preenchido).
--   • apply_reviewed: replay com o MESMO conjunto de escolhas (choices_hash)
--     devolve o resultado original sem re-inserir; um conjunto DIFERENTE depois de
--     concluído é rejeitado explicitamente (already_applied_different).
-- Escrito/lido SÓ pelas RPCs SECURITY DEFINER (owner) — sem grant a authenticated.
-- ON DELETE CASCADE: se a candidata é removida, o recibo some junto.
-- (Round 5 blocker F) UM ÚNICO terminal de aplicação por candidate+attempt: a PK é
-- (candidate_id, attempt_id) — SEM `operation`. `operation` vira coluna informativa
-- (qual modo concluiu). Antes a PK incluía `operation`, então a MESMA candidata podia
-- receber apply_initial E DEPOIS apply_reviewed (promoção/ativação de cache em DOBRO).
-- Agora o 2º terminal (do outro modo) é impossível; cada RPC consulta o recibo por
-- (candidate,attempt) e ramifica pela operação gravada (ver …130000).
CREATE TABLE IF NOT EXISTS public.import_apply_receipts (
  candidate_id uuid NOT NULL REFERENCES public.saved_resumes(id) ON DELETE CASCADE,
  attempt_id   uuid NOT NULL,
  operation    text NOT NULL CHECK (operation IN ('apply_initial','apply_reviewed')),
  choices_hash text NOT NULL DEFAULT '',
  result       jsonb NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (candidate_id, attempt_id)
);
ALTER TABLE public.import_apply_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.import_apply_receipts FROM PUBLIC;
-- sem policy/grant a authenticated: só as RPCs DEFINER (owner) tocam a tabela.
COMMENT ON TABLE public.import_apply_receipts IS
  'Fase 3 Round 4 (blocker E): recibo idempotente por candidate+attempt+operação. '
  'Replay de apply devolve o resultado gravado sem re-aplicar/duplicar.';

-- ── BARREIRA DE DEPLOY ENTRE 120000 E 130000 ────────────────────────────────────
-- Cada migration commita separadamente. A Edge HEAD^ ainda chama esta assinatura,
-- mas a implementação legacy sobrescreve escalares manuais e não participa do
-- advisory lock sob service_role. Até 130000 instalar o shim fenced/fill-empty,
-- falhar explicitamente é mais seguro que aceitar uma escrita destrutiva. A
-- assinatura/RETURNS ficam estáveis para o PostgREST não perder o endpoint.
CREATE OR REPLACE FUNCTION public.save_profile_from_json(p_user_id uuid, p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'profile_import_temporarily_unavailable';
END
$$;
REVOKE ALL ON FUNCTION public.save_profile_from_json(uuid, jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.save_profile_from_json(uuid, jsonb) TO service_role;

COMMIT;
