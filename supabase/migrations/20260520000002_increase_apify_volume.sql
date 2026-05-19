-- Aumenta o volume dos crons Apify (decisão 2026-05-20).
--
-- Volumes anteriores (do 20260519124045_balance_apify_budget):
--   • sync-jobs-apify-internship-am: maxResults=100
--   • sync-jobs-apify-trainee-pm:    maxResults=70
--   • sync-jobs-brazil-daily:        maxListings=25
--   → Total: ~195 vagas brutas/dia, ~$30/mês
--
-- Novos volumes:
--   • internship-am: 100 → 150 (+50, custo +$4.50/mês)
--   • trainee-pm:    70 → 100  (+30, custo +$2.70/mês)
--   • brazil-daily:  25 → 40   (+15, custo +$9.00/mês — Brazil é $0.02/vaga vs Gupy $0.003)
--   → Total novo: ~290 vagas brutas/dia, ~$46/mês
--
-- Cron schedules e segredos inalterados. Só body.maxResults / body.maxListings muda.

-- ─── Gupy internship: maxResults 100 → 150 ───────────────────────────────────
SELECT cron.unschedule('sync-jobs-apify-internship-am');

SELECT cron.schedule(
  'sync-jobs-apify-internship-am',
  '0 7 * * *',  -- 07:00 UTC = 04:00 BRT
  $$
    SELECT net.http_post(
      url := 'https://gaxfmniffjvwrwyunorl.supabase.co/functions/v1/sync-jobs-apify',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdheGZtbmlmZmp2d3J3eXVub3JsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM5NDY3NjYsImV4cCI6MjA3OTUyMjc2Nn0.sghxL3I5OpYs53z_dmPTZZg2dOFod7zYbI6uqWNNjsQ',
        'x-cron-secret', 'fbd43b64f6b24be962bc81f5b04642f0ee9bda8572a0cf2d230d6cfe83b703fc'
      ),
      body := jsonb_build_object(
        'maxResults', 150,
        'jobTypes', jsonb_build_array('vacancy_type_internship')
      )
    );
  $$
);

-- ─── Gupy trainee: maxResults 70 → 100 ───────────────────────────────────────
SELECT cron.unschedule('sync-jobs-apify-trainee-pm');

SELECT cron.schedule(
  'sync-jobs-apify-trainee-pm',
  '0 19 * * *',  -- 19:00 UTC = 16:00 BRT
  $$
    SELECT net.http_post(
      url := 'https://gaxfmniffjvwrwyunorl.supabase.co/functions/v1/sync-jobs-apify',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdheGZtbmlmZmp2d3J3eXVub3JsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM5NDY3NjYsImV4cCI6MjA3OTUyMjc2Nn0.sghxL3I5OpYs53z_dmPTZZg2dOFod7zYbI6uqWNNjsQ',
        'x-cron-secret', 'fbd43b64f6b24be962bc81f5b04642f0ee9bda8572a0cf2d230d6cfe83b703fc'
      ),
      body := jsonb_build_object(
        'maxResults', 100,
        'jobTypes', jsonb_build_array('vacancy_type_trainee')
      )
    );
  $$
);

-- ─── Brazil scraper: maxListings 25 → 40 ─────────────────────────────────────
SELECT cron.unschedule('sync-jobs-brazil-daily');

SELECT cron.schedule(
  'sync-jobs-brazil-daily',
  '0 8 * * *',  -- 08:00 UTC = 05:00 BRT (inalterado)
  $$
    SELECT net.http_post(
      url := 'https://gaxfmniffjvwrwyunorl.supabase.co/functions/v1/sync-jobs-brazil',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdheGZtbmlmZmp2d3J3eXVub3JsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM5NDY3NjYsImV4cCI6MjA3OTUyMjc2Nn0.sghxL3I5OpYs53z_dmPTZZg2dOFod7zYbI6uqWNNjsQ',
        'x-cron-secret', 'fbd43b64f6b24be962bc81f5b04642f0ee9bda8572a0cf2d230d6cfe83b703fc'
      ),
      body := jsonb_build_object(
        'maxListings', 40,
        'keyword', 'estagio',
        'sources', 'all',
        'includeDescription', true
      )
    );
  $$
);
