-- Cron schedule pra rodar `notifications-daily-digest` 1x/dia.
--
-- A Edge Function escaneia users criados entre 22-26h atrás (janela D+1)
-- e dispara push contextual via OneSignal:
--   - Adaptou CV mas não exportou → "📄 Seu CV adaptado tá esperando"
--   - Completou alguma fase → "🚀 Sua trilha está esperando"
--   - Caso geral → "📬 Novas vagas com match alto chegaram"
--
-- Pré-fix (relatório PostHog): D1 retention 6-12%, 91% dos usuários D1-only.
-- Esse push é o trigger externo pra trazer o user de volta no dia seguinte.
--
-- PRÉ-REQUISITOS: já satisfeitos pelo `20260506000003_jobs_cron_schedule.sql`
--   (pg_cron, pg_net, vault.cron_secret_jobs_sync, vault.supabase_anon_key).
--
-- HORÁRIO: 13h UTC = 10h BRT — bom horário de push (gente acordada, fora
-- do pico de trabalho, antes do almoço). Ajustar aqui se quiser mudar.

DO $$
DECLARE
  project_ref CONSTANT TEXT := 'gaxfmniffjvwrwyunorl';
  fn_digest_url TEXT;
  cron_secret  TEXT;
  anon_key     TEXT;
BEGIN
  fn_digest_url := format('https://%s.supabase.co/functions/v1/notifications-daily-digest', project_ref);

  -- Lê o cron secret do Vault (já criado na migration 20260506000003)
  SELECT decrypted_secret INTO cron_secret
  FROM vault.decrypted_secrets
  WHERE name = 'cron_secret_jobs_sync'
  LIMIT 1;

  IF cron_secret IS NULL THEN
    RAISE EXCEPTION 'Secret cron_secret_jobs_sync não encontrado. Rode a migration 20260506000003 antes.';
  END IF;

  -- Lê o anon key do Vault (já criado na migration 20260506000003)
  SELECT decrypted_secret INTO anon_key
  FROM vault.decrypted_secrets
  WHERE name = 'supabase_anon_key'
  LIMIT 1;

  IF anon_key IS NULL THEN
    RAISE EXCEPTION 'Secret supabase_anon_key não encontrado. Rode a migration 20260506000003 antes.';
  END IF;

  -- Remove job antigo com mesmo nome se existir (idempotente — pode rodar a
  -- migration N vezes sem duplicar schedules)
  PERFORM cron.unschedule('notifications-daily-digest') WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'notifications-daily-digest'
  );

  -- Daily digest — 13h UTC = 10h BRT, 1x/dia
  -- Body vazio = usa defaults da function (windowHoursStart=22, windowHoursEnd=26).
  PERFORM cron.schedule(
    'notifications-daily-digest',
    '0 13 * * *',
    format($cmd$
      SELECT net.http_post(
        url := %L,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', %L,
          'x-cron-secret', %L
        ),
        body := '{}'::jsonb
      );
    $cmd$, fn_digest_url, 'Bearer ' || anon_key, cron_secret)
  );
END $$;

-- Verificar:
-- SELECT jobname, schedule, command FROM cron.job WHERE jobname = 'notifications-daily-digest';
