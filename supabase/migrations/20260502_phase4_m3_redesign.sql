-- Phase 4: M3 "Minhas Experiências" Redesign
-- Removes old single experienceForm question, adds inventory → quantity → D1-D5 flow
-- t3_p2 "Atividades" phase is removed (activities absorbed into inventory as 'lead')

-- 1. Drop old M3_1_1_Q1 (type=experienceForm, will be replaced by experienceInventory)
DELETE FROM questions WHERE id = 'M3_1_1_Q1';

-- 2. Drop old M3_1_1_Q2_* dynamic entries (experienceForm instances, if any were persisted)
DELETE FROM questions WHERE id LIKE 'M3_1_1_Q2%';

-- 3. Remove t3_p2 phase "Atividades" (M2_3_1_Q2 activities are now absorbed into inventory)
DELETE FROM questions WHERE phase_id = 't3_p2';
DELETE FROM phases WHERE id = 't3_p2';

-- 4. Clean up raw_responses for removed questions (MVP: users are wiped anyway, but for safety)
DELETE FROM raw_responses WHERE question LIKE 'M3_1_1_Q2%';
DELETE FROM raw_responses WHERE question = 'M3_1_1_Q1';
DELETE FROM raw_responses WHERE phase_id LIKE 'm3.%';

-- 6. Update question type for the new inventory question (will be upserted by seed_data.dart)
-- Types: 39=experienceInventory, 40=experienceQuantity, 41=experienceDetailForm
-- seed_data.dart handles upsert on app startup; this migration only cleans legacy data.
