-- Rebalanceia o budget de Apify ($30/mês recorrente):
--   • Gupy: 1 run/dia (maxResults=50, ~$4.50/mês)
--     → 2 runs/dia, split por jobType, maxResults=100 + 70 (~$15.30/mês)
--   • Brazil scraper: 1 run/dia (maxListings=50, ~$30/mês)
--     → 1 run/dia, maxListings=25 (~$15.00/mês)
--
-- Total: $30.30/mês. Volume estimado +80% (de ~100 → ~175 vagas/dia ativas).
-- Filtros de qualidade (TITLE_BLACKLIST, COMPANY_BLACKLIST, isOutsideBrazil)
-- permanecem intactos — só configuração de volume muda.

-- ─── Gupy: split por jobType ──────────────────────────────────────────────────
SELECT cron.unschedule('sync-jobs-apify-daily');

-- AM run: estágios (volume maior em geral)
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
        'maxResults', 100,
        'jobTypes', jsonb_build_array('vacancy_type_internship')
      )
    );
  $$
);

-- PM run: trainees (volume menor; rodar separado evita ser sufocado pelos estágios em sortBy=newest)
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
        'maxResults', 70,
        'jobTypes', jsonb_build_array('vacancy_type_trainee')
      )
    );
  $$
);

-- ─── Brazil scraper: reduzir maxListings de 50 → 25 ───────────────────────────
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
        'maxListings', 25,
        'keyword', 'estagio',
        'sources', 'all',
        'includeDescription', true
      )
    );
  $$
);
