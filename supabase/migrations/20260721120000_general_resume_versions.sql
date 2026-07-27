-- Fase 4 (IA/Perfil) — F4.1: contrato de dados das VERSÕES do Currículo geral.
--
-- Decisões do fundador (21/07): o Currículo geral (hoje projeção virtual de
-- profile_*) passa a ser persistido em saved_resumes com source='general',
-- salvo automaticamente no export, com re-export idêntico (fingerprint +
-- template iguais à última versão) devolvendo NOOP honesto — nunca versão
-- duplicada. Esta migration é SÓ o contrato server-side; nenhum caller existe
-- até a fatia F4.3 (co-deploy: migration ANTES do app que chama a RPC).
--
-- O que entra aqui:
--   1. CHECK de source ganha 'general' (versões do Currículo geral) e 'trail'
--      (reservado à F4.5: backfill tipado dos "Currículo Stage" legados —
--      NENHUMA linha muda nesta migration; evita segundo ALTER do CHECK).
--   2. Colunas version + profile_fingerprint, obrigatórias e válidas SOMENTE
--      em linhas general (CHECK); demais sources ficam NULL.
--   3. Índice único parcial (user_id, version) das linhas general.
--   4. RPC save_general_resume_version_v1: advisory lock → validação
--      fail-closed → noop/insert → recibo JSONB estrito.
--   5. Trigger de imutabilidade do CONTEÚDO das versões general (flags e
--      title continuam livres — o restore do import, 20260719120000, faz
--      UPDATE amplo de flags em todas as linhas do usuário e não pode quebrar).
--
-- Segurança (padrão dos Gates 3.0): SECURITY DEFINER com search_path='';
-- REVOKE explícito; grants por coluna NÃO ganham as colunas novas (cliente só
-- escreve version/fingerprint via RPC; INSERT direto de source='general' morre
-- no CHECK porque version não é grantável). Rollback operacional = flag
-- trilha_assist_v1 OFF (nenhum caller); schema aditivo permanece (sem down
-- destrutivo). Reapply é idempotente e não apaga dado.

-- ── 1. source: entra 'general' (F4.1) e 'trail' (reservado F4.5) ─────────────
ALTER TABLE public.saved_resumes
  DROP CONSTRAINT IF EXISTS saved_resumes_source_check;
ALTER TABLE public.saved_resumes
  ADD CONSTRAINT saved_resumes_source_check
  CHECK (source = ANY (ARRAY['manual', 'imported', 'adapted', 'general', 'trail']));

-- ── 2. Colunas de versão (NULL em todo source ≠ general) ─────────────────────
ALTER TABLE public.saved_resumes
  ADD COLUMN IF NOT EXISTS version integer,
  ADD COLUMN IF NOT EXISTS profile_fingerprint text;

-- Linha general: versão ≥ 1, fingerprint sha256-hex, template e conteúdo
-- presentes (sem eles a versão não re-renderiza) e ZERO maquinário de import
-- (general nunca é candidata/fonte). Linha não-general: colunas novas NULL —
-- inclui os futuros 'trail' (backfill F4.5) e todo o legado atual.
ALTER TABLE public.saved_resumes
  DROP CONSTRAINT IF EXISTS saved_resumes_general_version_check;
ALTER TABLE public.saved_resumes
  ADD CONSTRAINT saved_resumes_general_version_check
  CHECK (
    (source = 'general'
       AND version IS NOT NULL AND version >= 1
       AND profile_fingerprint IS NOT NULL
       AND profile_fingerprint ~ '^[0-9a-f]{64}$'
       AND template_id IS NOT NULL AND btrim(template_id) <> ''
       AND resume_data IS NOT NULL
       AND extraction_status IS NULL
       AND client_import_id IS NULL
       AND is_current_source = false)
    OR (source <> 'general' AND version IS NULL AND profile_fingerprint IS NULL)
  );

-- ── 3. Unicidade/ordenação das versões por usuário ───────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS saved_resumes_general_version_per_user
  ON public.saved_resumes (user_id, version)
  WHERE source = 'general';

-- ── 4. RPC do save (único caminho de escrita de linha general) ───────────────
-- Recibo: {status:'applied'|'noop', id, version, created_at, file_path}.
-- noop = última versão tem o MESMO fingerprint E MESMO template (decisão 3 do
-- fundador). Fingerprint diferente OU template diferente ⇒ nova versão
-- (max+1). O advisory lock por usuário serializa SELECT→INSERT (duas sessões
-- não duplicam versão); o índice único é a última barreira. O path é validado
-- no formato canônico {uid}/general/{uuid}.pdf (uuid minúsculo, como o client
-- gera) — nada fora do namespace do dono passa (espelha a policy de INSERT).
DROP FUNCTION IF EXISTS public.save_general_resume_version_v1(text, text, jsonb, text, text);
CREATE OR REPLACE FUNCTION public.save_general_resume_version_v1(
  p_title text,
  p_file_path text,
  p_resume_data jsonb,
  p_template_id text,
  p_fingerprint text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_template text := btrim(COALESCE(p_template_id, ''));
  v_title text;
  v_latest record;
  v_id uuid;
  v_version integer;
  v_created timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
  END IF;
  IF p_fingerprint IS NULL OR p_fingerprint !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid_fingerprint' USING ERRCODE = '22023';
  END IF;
  IF v_template = '' OR length(v_template) > 64 THEN
    RAISE EXCEPTION 'invalid_template' USING ERRCODE = '22023';
  END IF;
  IF p_resume_data IS NULL OR jsonb_typeof(p_resume_data) <> 'object' THEN
    RAISE EXCEPTION 'invalid_resume_data' USING ERRCODE = '22023';
  END IF;
  -- Teto de payload (fail-closed): versão não é depósito de blob arbitrário.
  IF pg_column_size(p_resume_data) > 262144 THEN
    RAISE EXCEPTION 'resume_data_too_large' USING ERRCODE = '22023';
  END IF;
  IF p_file_path IS NULL
     OR p_file_path !~ ('^' || v_uid::text || '/general/[0-9a-f-]{36}\.pdf$') THEN
    RAISE EXCEPTION 'invalid_file_path' USING ERRCODE = '22023';
  END IF;
  v_title := COALESCE(NULLIF(btrim(p_title), ''), 'Currículo geral');

  -- Ordem universal do protocolo: advisory(user) ANTES de qualquer tuple lock.
  PERFORM pg_advisory_xact_lock(public.profile_write_lock_key(v_uid));

  SELECT sr.id, sr.version, sr.profile_fingerprint, sr.template_id,
         sr.created_at, sr.file_path
    INTO v_latest
    FROM public.saved_resumes sr
   WHERE sr.user_id = v_uid AND sr.source = 'general'
   ORDER BY sr.version DESC
   LIMIT 1
   FOR UPDATE;

  IF FOUND
     AND v_latest.profile_fingerprint = p_fingerprint
     AND v_latest.template_id = v_template THEN
    RETURN jsonb_build_object(
      'status', 'noop',
      'id', v_latest.id,
      'version', v_latest.version,
      'created_at', v_latest.created_at,
      'file_path', v_latest.file_path);
  END IF;

  INSERT INTO public.saved_resumes
    (user_id, title, file_path, source, resume_data, template_id,
     version, profile_fingerprint)
  VALUES
    (v_uid, v_title, p_file_path, 'general', p_resume_data, v_template,
     COALESCE(v_latest.version, 0) + 1, p_fingerprint)
  RETURNING id, version, created_at INTO v_id, v_version, v_created;

  RETURN jsonb_build_object(
    'status', 'applied',
    'id', v_id,
    'version', v_version,
    'created_at', v_created,
    'file_path', p_file_path);
END $$;
REVOKE ALL ON FUNCTION public.save_general_resume_version_v1(text, text, jsonb, text, text)
  FROM PUBLIC;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.save_general_resume_version_v1(text, text, jsonb, text, text) FROM anon';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.save_general_resume_version_v1(text, text, jsonb, text, text) FROM service_role';
  END IF;
END $$;
GRANT EXECUTE ON FUNCTION public.save_general_resume_version_v1(text, text, jsonb, text, text)
  TO authenticated;

-- ── 5. Conteúdo de versão general é IMUTÁVEL pós-insert ──────────────────────
-- Trocar template NÃO muta versão (gera-se outra pela RPC); o grant por coluna
-- de UPDATE (title, template_id, resume_data) permitiria a um client mutar o
-- conteúdo — este trigger fecha isso no servidor. O WHEN é escopado às colunas
-- de conteúdo/identidade: UPDATEs de flags (restore do import 20260719120000
-- zera is_current_source/is_latest_legacy_source em TODAS as linhas do usuário)
-- e rename de title seguem passando. DELETE continua permitido (decisão 1:
-- apagar uma versão não afeta o perfil).
CREATE OR REPLACE FUNCTION public._general_resume_version_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'general_resume_version_immutable' USING ERRCODE = '55000';
END $$;
REVOKE ALL ON FUNCTION public._general_resume_version_immutable() FROM PUBLIC;
DROP TRIGGER IF EXISTS zzz_general_resume_immutable ON public.saved_resumes;
CREATE TRIGGER zzz_general_resume_immutable
  BEFORE UPDATE ON public.saved_resumes
  FOR EACH ROW
  WHEN (OLD.source = 'general' AND (
    OLD.resume_data IS DISTINCT FROM NEW.resume_data
    OR OLD.template_id IS DISTINCT FROM NEW.template_id
    OR OLD.version IS DISTINCT FROM NEW.version
    OR OLD.profile_fingerprint IS DISTINCT FROM NEW.profile_fingerprint
    OR OLD.file_path IS DISTINCT FROM NEW.file_path
    OR OLD.source IS DISTINCT FROM NEW.source
    OR OLD.user_id IS DISTINCT FROM NEW.user_id
  ))
  EXECUTE FUNCTION public._general_resume_version_immutable();
