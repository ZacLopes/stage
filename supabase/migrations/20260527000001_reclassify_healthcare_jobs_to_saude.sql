-- Reclassifica vagas de saúde que foram mal classificadas pelo inferArea
-- antigo (sem regra de Saúde). 22 vagas observadas em 2026-05-27 caíram
-- em Produto/Operações/RH/Tecnologia — match score nunca casava área pra
-- users que marcassem "Saúde" como interesse (que agora existe na taxonomia).
--
-- Match conservador: precisa do título conter termo inequívoco de saúde.
-- Pra novas vagas, inferArea atualizada em supabase/functions/_shared/jobs.ts
-- já classifica em Saúde direto.

UPDATE public.jobs
SET area = 'Saúde'
WHERE is_active = true
  AND area != 'Saúde'
  AND (
    title ILIKE '%enferma%'
    OR title ILIKE '%medic%'
    OR title ILIKE '%farmácia%' OR title ILIKE '%farmacia%' OR title ILIKE '%farmac%'
    OR title ILIKE '%fisioterap%'
    OR title ILIKE '%nutricion%'
    OR title ILIKE '%psicólog%' OR title ILIKE '%psicolog%'
    OR title ILIKE '%biomédic%' OR title ILIKE '%biomedic%'
    OR title ILIKE '%odontológ%' OR title ILIKE '%odontolog%'
    OR title ILIKE '%veterin%'
    OR title ILIKE '%hospital%'
    OR title ILIKE '%clínica%' OR title ILIKE '%clinica%'
    OR title ILIKE '%radiolo%'
    OR title ILIKE '%fonoaudi%'
  );
