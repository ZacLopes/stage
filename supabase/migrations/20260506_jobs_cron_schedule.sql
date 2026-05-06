-- Cron schedules pra rodar as Edge Functions de sync diariamente.
--
-- PRÉ-REQUISITOS (rodar UMA VEZ no SQL Editor antes de aplicar este arquivo):
--
-- 1. Habilitar extensões necessárias (pg_cron já vem habilitado em Supabase
--    Pro+; pg_net vem por padrão na maioria dos planos)
--
--      CREATE EXTENSION IF NOT EXISTS pg_cron;
--      CREATE EXTENSION IF NOT EXISTS pg_net;
--
-- 2. Salvar o CRON_SECRET no Vault do Supabase (para o pg_cron ler ao chamar
--    a Edge Function). Ajuste a string aleatória conforme você gerou e
--    salvou em `supabase secrets set CRON_SECRET=<mesmo-valor>`:
--
--      SELECT vault.create_secret(
--        '<COLE_AQUI_O_MESMO_CRON_SECRET>',
--        'cron_secret_jobs_sync',
--        'Shared secret for pg_cron → Edge Functions auth'
--      );
--
-- 3. Substituir a constante PROJECT_REF abaixo se for diferente.

DO $$
DECLARE
  project_ref CONSTANT TEXT := 'gaxfmniffjvwrwyunorl';
  fn_apify_url TEXT;
  fn_ats_url   TEXT;
  cron_secret  TEXT;
BEGIN
  fn_apify_url := format('https://%s.supabase.co/functions/v1/sync-jobs-apify', project_ref);
  fn_ats_url   := format('https://%s.supabase.co/functions/v1/sync-jobs-ats',   project_ref);

  -- Lê o secret do Vault (criado no passo 2 acima)
  SELECT decrypted_secret INTO cron_secret
  FROM vault.decrypted_secrets
  WHERE name = 'cron_secret_jobs_sync'
  LIMIT 1;

  IF cron_secret IS NULL THEN
    RAISE EXCEPTION 'Secret cron_secret_jobs_sync não encontrado. Crie via vault.create_secret antes.';
  END IF;

  -- Remove jobs antigos com mesmo nome se existirem (idempotente)
  PERFORM cron.unschedule('sync-jobs-apify-daily') WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'sync-jobs-apify-daily'
  );
  PERFORM cron.unschedule('sync-jobs-ats-daily') WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'sync-jobs-ats-daily'
  );

  -- Apify (Gupy) — 7h UTC = 4h BRT, 1x/dia
  -- maxResults=50 mantém o consumo dentro do plano FREE ($5/mês de crédito):
  --   50 jobs × 30 dias × $0.00299 ≈ $4.49/mês → cabe nos $5 grátis
  -- Pra ampliar, mude o `maxResults` aqui (ou mude o plano Apify pra Bronze/Silver).
  PERFORM cron.schedule(
    'sync-jobs-apify-daily',
    '0 7 * * *',
    format($cmd$
      SELECT net.http_post(
        url := %L,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cron-secret', %L
        ),
        body := jsonb_build_object('maxResults', 50)
      );
    $cmd$, fn_apify_url, cron_secret)
  );

  -- ATS (Greenhouse + Lever) — 7:30 UTC = 4:30 BRT, 1x/dia
  PERFORM cron.schedule(
    'sync-jobs-ats-daily',
    '30 7 * * *',
    format($cmd$
      SELECT net.http_post(
        url := %L,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cron-secret', %L
        )
      );
    $cmd$, fn_ats_url, cron_secret)
  );
END $$;

-- Verificar:
-- SELECT jobname, schedule, command FROM cron.job WHERE jobname LIKE 'sync-jobs-%';
