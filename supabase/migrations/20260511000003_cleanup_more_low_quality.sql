-- Migration: cleanup adicional pós-1ª rodada do sync
--
-- Remove vazamentos identificados após rodada manual: vagas Peru, agregadores
-- genéricos ("Programa de Estágio", "VAGAS DE ESTÁGIO? TEMOS"), academia.

BEGIN;

-- 1. Vagas fora do Brasil (proxy country BR não filtrava resultado).
-- Mantém só estados BR válidos + 'BR' genérico + remoto (sem state).
UPDATE public.jobs j
SET is_active = false
WHERE j.is_active = true
  AND j.work_model != 'remoto'
  AND j.location_state IS NOT NULL
  AND j.location_state NOT IN (
    'BR','AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG',
    'PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO'
  );

-- 2. Vagas de companies "spammy" (agregadores, academia, Peru).
UPDATE public.jobs j
SET is_active = false
WHERE j.is_active = true
  AND EXISTS (
    SELECT 1 FROM public.companies c
    WHERE c.id = j.company_id
      AND (
        c.name ILIKE 'programa de estágio'
        OR c.name ILIKE 'programa de estagio'
        OR c.name ILIKE '%vagas de estágio%temos%'
        OR c.name ILIKE '%vagas de estagio%temos%'
        OR c.name ILIKE '%academia%'
        OR c.name ILIKE '%greenlife%'
        OR c.name ILIKE '%nexa peru%'
        OR c.name ILIKE '%nexa perú%'
        OR c.name ILIKE '%carreras nexa%'
      )
  );

COMMIT;
