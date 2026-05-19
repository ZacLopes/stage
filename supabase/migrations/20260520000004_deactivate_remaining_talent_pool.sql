-- Catch-all pras vagas "banco de talentos" que escaparam do
-- 20260520000003_deactivate_talent_pool_greenhouse.sql (padrões com prefixo
-- [, |, etc). A partir daqui o filtro isTalentPoolTitle() expandido bloqueia
-- futuras reinserções.

UPDATE public.jobs
SET is_active = false
WHERE is_active = true
  AND source = 'greenhouse'
  AND title ILIKE '%banco de talentos%';
