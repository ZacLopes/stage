-- Agenda diária do `sync-jobs-brazil` Edge Function via pg_cron.
--
-- PRÉ-REQUISITOS (mesmos do sync-jobs-apify, já existentes no projeto):
-- 1. pg_cron + pg_net habilitados
-- 2. Secret `cron_secret_jobs_sync` no Vault
-- 3. Secret `supabase_anon_key` no Vault
-- 4. Edge Function `sync-jobs-brazil` deployada
-- 5. Env var `APIFY_API_TOKEN` setada via `supabase secrets set`

DO $$
DECLARE
  project_ref CONSTANT TEXT := 'gaxfmniffjvwrwyunorl';
  fn_brazil_url TEXT;
  cron_secret  TEXT;
  anon_key     TEXT;
BEGIN
  fn_brazil_url := format(
    'https://%s.supabase.co/functions/v1/sync-jobs-brazil',
    project_ref
  );

  SELECT decrypted_secret INTO cron_secret
  FROM vault.decrypted_secrets
  WHERE name = 'cron_secret_jobs_sync'
  LIMIT 1;

  IF cron_secret IS NULL THEN
    RAISE EXCEPTION 'Secret cron_secret_jobs_sync não encontrado. Crie via vault.create_secret antes.';
  END IF;

  SELECT decrypted_secret INTO anon_key
  FROM vault.decrypted_secrets
  WHERE name = 'supabase_anon_key'
  LIMIT 1;

  IF anon_key IS NULL THEN
    RAISE EXCEPTION 'Secret supabase_anon_key não encontrado.';
  END IF;

  -- Idempotente: remove agendamento anterior se existir
  PERFORM cron.unschedule('sync-jobs-brazil-daily') WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'sync-jobs-brazil-daily'
  );

  -- 8h UTC = 5h BRT (1h depois do sync-jobs-apify, evita disputa de recursos)
  -- maxListings=50 inicial → $1/dia = $30/mês.
  -- Pra escalar: edita esse cron via SQL e bumpa maxListings (50 → 100 → 200).
  -- Hard cap absoluto no código da função: 200 vagas/run.
  PERFORM cron.schedule(
    'sync-jobs-brazil-daily',
    '0 8 * * *',
    format($cmd$
      SELECT net.http_post(
        url := %L,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', %L,
          'x-cron-secret', %L
        ),
        body := jsonb_build_object(
          'maxListings', 50,
          'keyword', 'estagio',
          'sources', 'all',  -- actor só aceita 1 enum por chamada; código filtra Gupy
          'includeDescription', true
        )
      );
    $cmd$, fn_brazil_url, 'Bearer ' || anon_key, cron_secret)
  );
END $$;

-- Verificação após aplicar:
--   SELECT jobname, schedule, command FROM cron.job WHERE jobname = 'sync-jobs-brazil-daily';
