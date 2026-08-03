-- Fecha 7 funções SECURITY DEFINER que qualquer anônimo podia executar.
--
-- ⚠️ INDEPENDENTE DA RELEASE. Isto conserta produção HOJE, com a 2.4.0 no ar.
-- Não espera build, não espera Apple, não espera adoção.
--
-- COMO FOI ACHADO: `get_advisors(security)` acusa 21 ocorrências de
-- `anon_security_definer_function_executable`. A maioria é trigger function sem
-- argumento (não invocável por PostgREST) ou da família `cas_write_*` /
-- `apply_reviewed_*`, que já guarda por `auth.uid()`. Sobraram estas 7, todas
-- com `has_function_privilege('anon', oid, 'EXECUTE') = true` e SEM guard.
--
-- CAUSA-RAIZ (para não repetir): `20260719120000_import_revert_snapshot.sql`
-- linhas 95 e 197 fazem apenas `REVOKE ALL … FROM PUBLIC`. Isso NÃO remove
-- grant explícito a `anon`/`authenticated` — e o Supabase concede esses grants
-- por default em objetos novos do schema `public`. O padrão correto já existia
-- no repo, em `20260721120000` (bloco DO com REVOKE nominal por role); é ele
-- que este arquivo aplica.
--
-- O QUE CADA UMA EXPUNHA:
--
--   _snapshot_profile_content(uuid)          PII completa + texto integral do
--                                            CV de QUALQUER uuid
--   _restore_profile_snapshot(uuid, jsonb)   10 DELETE FROM profile_* sem
--                                            condição = wipe de perfil alheio
--   get_saved_jobs_expiring(int)             enumera user_id reais, sem sequer
--                                            precisar de argumento
--   cleanup_old_logs()                       DELETE em ai_generation_logs (>90d)
--                                            e security_audit_log (>180d) —
--                                            primitivo anti-forense anônimo
--   admin_job_metrics(uuid[])                métricas de swipe/apply por vaga
--   compute_profile_completeness(uuid,…)     oráculo do score de perfil alheio
--   check_rate_limit(uuid, text, int)        oráculo de quota de IA alheia
--
-- POR QUE REVOGAR DE `authenticated` TAMBÉM NÃO QUEBRA NADA — verificado
-- caller a caller, não presumido:
--
--   - cliente Dart: `grep -rl` das 7 em `lib/` → ZERO ocorrências. Nenhuma é
--     chamada por `.rpc()`;
--   - `get_saved_jobs_expiring` → único caller é `notifications-daily-digest`,
--     que usa SUPABASE_SERVICE_ROLE_KEY (index.ts:42,127);
--   - `admin_job_metrics` → único caller é `admin-jobs`, via `requireAdmin` de
--     `_shared/admin.ts`, que monta serviceClient com SERVICE_ROLE (linha 82);
--   - `_snapshot_profile_content` / `_restore_profile_snapshot` → chamadas só
--     de DENTRO de `apply_reviewed_with_snapshot` e `revert_reviewed_apply`
--     (20260719120000:215,223,261,267,271), ambas SECURITY DEFINER: rodam como
--     o owner, que mantém EXECUTE. A cadeia interna sobrevive;
--   - `compute_profile_completeness` → chamada por `set_profile_completeness` e
--     `touch_profile_completeness`. Consultei `pg_proc` em produção: as duas são
--     `prosecdef = true`, owner `postgres`. Rodam como owner. Os triggers de
--     completeness continuam funcionando para escrita de cliente;
--   - `cleanup_old_logs` → agendada no pg_cron, que executa como `postgres`;
--   - `check_rate_limit` → nenhum caller em `lib/`, `supabase/functions/`,
--     `admin_dashboard/src/` nem no SQL do repo. Efetivamente morta.
--
-- `service_role` é intencionalmente PRESERVADO: é por ele que as edge functions
-- legítimas chegam.
--
-- IDEMPOTENTE: REVOKE em quem já não tem é no-op. Reaplicável.
-- ROLLBACK: `GRANT EXECUTE ON FUNCTION … TO anon, authenticated` — mas a única
-- razão para fazer isso seria descobrir um caller não mapeado; nesse caso o
-- certo é dar o grant só ao role que precisa, não desfazer o bloco.

DO $$
DECLARE
  fn text;
  alvos text[] := ARRAY[
    'public._snapshot_profile_content(uuid)',
    'public._restore_profile_snapshot(uuid, jsonb)',
    'public.get_saved_jobs_expiring(integer)',
    'public.cleanup_old_logs()',
    'public.admin_job_metrics(uuid[])',
    'public.compute_profile_completeness(uuid, text, text, text)',
    'public.check_rate_limit(uuid, text, integer)'
  ];
BEGIN
  FOREACH fn IN ARRAY alvos LOOP
    -- to_regprocedure devolve NULL se a assinatura não existir: assim a
    -- migration não explode se alguma função for renomeada/removida depois.
    IF to_regprocedure(fn) IS NULL THEN
      RAISE NOTICE 'pulando (não existe nesta base): %', fn;
      CONTINUE;
    END IF;

    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', fn);

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', fn);
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM authenticated', fn);
    END IF;

    RAISE NOTICE 'revogado de PUBLIC/anon/authenticated: %', fn;
  END LOOP;
END $$;

-- Verificação embutida: falha a migration se sobrou alguma acessível ao `anon`.
-- "Verificado, não declarado" — a migration prova o próprio efeito.
DO $$
DECLARE
  restante text;
BEGIN
  SELECT string_agg(fn, ', ')
    INTO restante
  FROM (
    SELECT unnest(ARRAY[
      'public._snapshot_profile_content(uuid)',
      'public._restore_profile_snapshot(uuid, jsonb)',
      'public.get_saved_jobs_expiring(integer)',
      'public.cleanup_old_logs()',
      'public.admin_job_metrics(uuid[])',
      'public.compute_profile_completeness(uuid, text, text, text)',
      'public.check_rate_limit(uuid, text, integer)'
    ]) AS fn
  ) t
  WHERE to_regprocedure(t.fn) IS NOT NULL
    AND has_function_privilege('anon', to_regprocedure(t.fn), 'EXECUTE');

  IF restante IS NOT NULL THEN
    RAISE EXCEPTION 'REVOKE não pegou em: %', restante;
  END IF;

  RAISE NOTICE 'REVOKE_ANON_SECDEF_OK — nenhuma das 7 é executável por anon';
END $$;
