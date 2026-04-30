-- Remove permanently the obsolete phases and questions that were being
-- filtered out in Dart code. After this migration, all runtime filters
-- and the _cleanupObsoleteData() workaround can be removed from the app.

-- Step 1: Remove user_answers for obsolete questions (safety first for FK)
DELETE FROM user_answers
WHERE question_id IN (
  SELECT id FROM questions
  WHERE content ILIKE '%qual era a sua função%'
     OR content ILIKE '%onde essa experiência aconteceu%'
);

-- Step 2: Remove user_answers for questions belonging to obsolete phases
DELETE FROM user_answers
WHERE question_id IN (
  SELECT id FROM questions
  WHERE phase_id = 't1_p4'
     OR phase_id IN (
       SELECT id FROM phases
       WHERE title IN ('Revisão', 'O Cronômetro da Jornada', 'O que você fez')
     )
);

-- Step 3: Remove user_progress for obsolete phases
DELETE FROM user_progress
WHERE phase_id = 't1_p4'
   OR phase_id IN (
     SELECT id FROM phases
     WHERE title IN ('Revisão', 'O Cronômetro da Jornada', 'O que você fez')
   );

-- Step 4: Remove the obsolete questions by content
DELETE FROM questions
WHERE content ILIKE '%qual era a sua função%'
   OR content ILIKE '%onde essa experiência aconteceu%';

-- Step 5: Remove questions belonging to obsolete phases
DELETE FROM questions
WHERE phase_id = 't1_p4'
   OR phase_id IN (
     SELECT id FROM phases
     WHERE title IN ('Revisão', 'O Cronômetro da Jornada', 'O que você fez')
   );

-- Step 6: Remove the obsolete phases
DELETE FROM phases
WHERE id = 't1_p4'
   OR title IN ('Revisão', 'O Cronômetro da Jornada', 'O que você fez', 'Minha cultura e trabalho');

-- Step 7: Remove question M1_3_1_Q1 ("Sucesso") — not in the database
DELETE FROM user_answers WHERE question_id = 'M1_3_1_Q1';
DELETE FROM questions WHERE id = 'M1_3_1_Q1';
