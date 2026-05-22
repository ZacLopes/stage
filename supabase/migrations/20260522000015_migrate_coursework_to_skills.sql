-- Migra profile_coursework -> profile_skills com dedupe por nome.
--
-- Estratégia:
-- - Case-insensitive trim no match
-- - Coursework duplicado (mesmo nome já em skills do user) é IGNORADO
-- - order_index novo = max do user + posição relativa do coursework
-- - category = NULL (não categorizamos no momento — templates não usam)
--
-- Tabela profile_coursework NÃO é dropada — fica dormida pra rollback fácil.
-- Após validação em prod, considerar drop em migration futura.

BEGIN;

WITH max_per_user AS (
  SELECT user_id, COALESCE(MAX(order_index), -1) AS max_idx
  FROM public.profile_skills
  GROUP BY user_id
),
ranked_coursework AS (
  SELECT
    cw.user_id,
    cw.name,
    ROW_NUMBER() OVER (PARTITION BY cw.user_id ORDER BY cw.order_index, cw.name) AS rn
  FROM public.profile_coursework cw
  WHERE NOT EXISTS (
    SELECT 1 FROM public.profile_skills s
    WHERE s.user_id = cw.user_id
      AND LOWER(TRIM(s.name)) = LOWER(TRIM(cw.name))
  )
)
INSERT INTO public.profile_skills (user_id, name, order_index, category)
SELECT
  rc.user_id,
  rc.name,
  COALESCE(mpu.max_idx, -1) + rc.rn,
  NULL
FROM ranked_coursework rc
LEFT JOIN max_per_user mpu ON mpu.user_id = rc.user_id;

COMMIT;
