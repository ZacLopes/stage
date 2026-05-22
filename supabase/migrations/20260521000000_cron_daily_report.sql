-- Cron schedule pra rodar `daily-report` 1x/dia.
--
-- A Edge Function agrega:
--   - Usuários novos (faculdade, curso, semestre, AI consent, telefone)
--   - Engajamento (DAU, CV adapters, appliers)
--   - Vagas inseridas (por área, fonte, empresa, modelo, tipo, cidade)
--   - Estoque atual (vagas ativas, idade média, % com link)
--   - Match (curtidas, aplicações, top jobs/empresas, score médio)
--   - CV adaptado (total e por área)
--   - Gap oferta vs demanda
--   - Saúde IA (chamadas, tokens)
--
-- Aos domingos, inclui resumo dos últimos 7 dias com WoW (a Edge Function
-- auto-detecta `new Date().getUTCDay() === 0`).
--
-- Entrega: email rico via Resend + notificação curta via ntfy.sh.
--
-- PRÉ-REQUISITOS: já satisfeitos pelo `20260506000003_jobs_cron_schedule.sql`
--   (pg_cron, pg_net, vault.cron_secret_jobs_sync, vault.supabase_anon_key).
--
-- SECRETS NECESSÁRIOS NA EDGE FUNCTION (configurar com `supabase secrets set`):
--   RESEND_API_KEY        - https://resend.com/api-keys
--   REPORT_EMAIL_FROM     - ex.: "Stage <reports@stage-app.com.br>"
--                                  (ou "Stage <onboarding@resend.dev>" sem domínio próprio)
--   REPORT_EMAIL_TO       - ex.: "zackourilopes@outlook.com"
--   NTFY_TOPIC_REPORT     - topic ntfy.sh (pode ser o mesmo do notify-signup)
--
-- HORÁRIO: 10h UTC = 7h BRT — manhã cedo, sync de vagas Apify (7h UTC) e
-- ATS (7:30h UTC) já terminaram, dados frescos.

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
    RAISE EXCEPTION 'Secret cron_secret_jobs_sync não encontrado. Rode a migration 20260506000003 antes.';
  END IF;

  SELECT decrypted_secret INTO anon_key
  FROM vault.decrypted_secrets
  WHERE name = 'supabase_anon_key'
  LIMIT 1;

  IF anon_key IS NULL THEN
    RAISE EXCEPTION 'Secret supabase_anon_key não encontrado. Rode a migration 20260506000003 antes.';
  END IF;

  -- Idempotente: remove schedule antigo com mesmo nome se existir.
  PERFORM cron.unschedule('daily-report') WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'daily-report'
  );

  -- Diário às 10h UTC = 7h BRT.
  -- Body vazio = Edge Function auto-detecta domingo pra ativar modo semanal.
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
        body := '{}'::jsonb
      );
    $cmd$, fn_url, 'Bearer ' || anon_key, cron_secret)
  );
END $$;

-- Verificar:
-- SELECT jobname, schedule, command FROM cron.job WHERE jobname = 'daily-report';
--
-- Disparar manual:
-- SELECT net.http_post(
--   url := 'https://gaxfmniffjvwrwyunorl.supabase.co/functions/v1/daily-report',
--   headers := jsonb_build_object('Content-Type','application/json','x-cron-secret', '<secret>'),
--   body := '{"dryRun": true}'::jsonb
-- );
