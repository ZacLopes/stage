-- Desativa vagas "banco de talentos" já existentes no Greenhouse. A partir
-- daqui o filtro isTalentPoolTitle() no _shared/jobs.ts impede que elas voltem
-- a ser inseridas — mas as 4 que já estavam ativas precisam ser zeradas
-- manualmente.

UPDATE public.jobs
SET is_active = false
WHERE is_active = true
  AND source = 'greenhouse'
  AND (
    title ILIKE 'banco de talentos%' OR
    title ILIKE '[banco de talentos]%' OR
    title ILIKE 'banco de talentos -%' OR
    title ILIKE 'banco de talentos |%'
  );
