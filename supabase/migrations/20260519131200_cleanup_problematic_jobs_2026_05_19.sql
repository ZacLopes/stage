-- Auditoria 2026-05-19: marca 32 vagas problemáticas como is_active=false.
-- Operação reversível (não DELETE). Padrões:
--   • Op 1: 5 mocks (source NULL — vagas falsas de Nubank/Ambev/iFood/Itaú/MercadoLivre)
--   • Op 2: 7 empresas com nome "spammy" (Vagas, Recrutamento, Consultoria, etc)
--   • Op 3: 17 vagas do agregador "Estagiando Centro de Estágio"
--   • Op 4: 3 vagas com descrição curta começando em "Banco de talentos"

-- Op 1: mocks
UPDATE jobs SET is_active = false WHERE source IS NULL;

-- Op 2: empresas agregadoras
UPDATE jobs j SET is_active = false
WHERE j.is_active AND j.company_id IN (
  SELECT id FROM companies c WHERE
    c.name ILIKE '%vagas%' OR
    c.name ILIKE '%recrutament%' OR
    c.name ILIKE '%consultoria%' OR
    c.name ILIKE '%confidencia%' OR
    c.name ILIKE '%feira recrut%'
);

-- Op 3: agregador "Estagiando"
UPDATE jobs j SET is_active = false
WHERE j.is_active AND j.company_id IN (
  SELECT id FROM companies WHERE name ILIKE '%estagiando%'
);

-- Op 4: METTA "banco de talentos" na descrição curta
UPDATE jobs SET is_active = false
WHERE is_active
  AND source = 'brz_infojobs'
  AND description ILIKE '%banco de talentos%'
  AND LENGTH(description) < 500;
