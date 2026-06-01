-- Reagenda o cron do daily-report com timeout maior no pg_net.
--
-- O pg_cron considera a chamada "succeeded" quando o request é enfileirado no
-- net.http_post. Sem timeout explícito, o pg_net usa 5s; o relatório atual pode
-- levar mais que isso agregando métricas + Resend/ntfy, gerando timeout mesmo
-- com o cron aparecendo como sucesso.

DO $$
DECLARE
  project_ref CONSTANT TEXT := 'gaxfmniffjvwrwyunorl';
  fn_url       TEXT;
  cron_secret  TEXT;
  anon_key     TEXT;
BEGIN
  fn_url := format('https://%s.supabase.co/functions/v1/daily-report', project_ref);

  SELECT decrypted_secret INTO cron_secret
  FROM vault.decrypted_secrets
  WHERE name = 'cron_secret_jobs_sync'
  LIMIT 1;

  IF cron_secret IS NULL THEN
    RAISE EXCEPTION 'Secret cron_secret_jobs_sync não encontrado.';
  END IF;

  SELECT decrypted_secret INTO anon_key
  FROM vault.decrypted_secrets
  WHERE name = 'supabase_anon_key'
  LIMIT 1;

  IF anon_key IS NULL THEN
    RAISE EXCEPTION 'Secret supabase_anon_key não encontrado.';
  END IF;

  PERFORM cron.unschedule('daily-report') WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'daily-report'
  );

  PERFORM cron.schedule(
    'daily-report',
    '0 10 * * *',
    format($cmd$
      SELECT net.http_post(
        url := %L,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', %L,
          'x-cron-secret', %L
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 30000
      );
    $cmd$, fn_url, 'Bearer ' || anon_key, cron_secret)
  );
END $$;

