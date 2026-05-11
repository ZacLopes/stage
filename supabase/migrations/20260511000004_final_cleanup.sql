-- Migration: cleanup final dos vazamentos pequenos identificados após
-- rodadas com search terms variados.

BEGIN;

-- 1. Desativa vagas problemáticas (não DELETE pra preservar FK
-- com swipe_actions — usuários podem ter swipado).
UPDATE public.jobs j
SET is_active = false
WHERE j.is_active = true
  AND EXISTS (
    SELECT 1 FROM public.companies c
    WHERE c.id = j.company_id
      AND (
        c.name ILIKE 'pib-teste%'
        OR c.name ILIKE '%greenlife%'
        OR c.name = 'Sunojobs'
        OR c.name ILIKE 'oval - vagas%'
        OR c.name ILIKE 'conexão talento'
        OR c.name ILIKE 'vagas instituto%'
        OR c.name ILIKE 'programa de estágio e aprendiz 2026'
        OR c.name ILIKE '%seja pasa!%'
        OR c.name ILIKE 'faça parte do time%'
        OR c.name ILIKE 'talentos barcelos%'
        OR c.name ILIKE 'janaina rodrigues%'
      )
  );

-- 2. Renomeia companies bloqueadas (em vez de deletar — FK também impede).
-- O prefixo `[blocked]` no slug faz o próximo sync identificar e pular esse
-- companySubdomain quando tentar upsert (mas como adicionei no
-- COMPANY_NAME_BLACKLIST_REGEXES, a vaga já é filtrada antes de chegar aqui).
UPDATE public.companies
SET slug = COALESCE(slug, name) || ':blocked',
    source = COALESCE(source, 'unknown') || ':blocked'
WHERE source NOT LIKE '%:blocked%'
  AND (
    name ILIKE 'pib-teste%'
    OR name ILIKE '%greenlife%'
    OR name = 'Sunojobs'
    OR name ILIKE 'oval - vagas%'
    OR name ILIKE 'conexão talento'
    OR name ILIKE 'vagas instituto%'
    OR name ILIKE 'programa de estágio e aprendiz 2026'
    OR name ILIKE '%seja pasa!%'
    OR name ILIKE 'faça parte do time%'
    OR name ILIKE 'talentos barcelos%'
    OR name ILIKE 'janaina rodrigues%'
  );

COMMIT;
