-- ============================================================
-- FIX: user_answers RLS allowed SELECT/INSERT/UPDATE but NOT DELETE.
-- This caused `deleteExperienceUserAnswers` to silently no-op:
-- the API returned 200 OK but RLS filtered out every row before
-- the DELETE could touch them. Symptom: deleted experiences kept
-- coming back after AI regeneration.
--
-- Adding the missing DELETE policy + a defensive UNIQUE constraint
-- on (user_id, question_id) so the legacy `saveAnswer` upsert bug
-- can never again insert duplicate rows for the same question.
-- ============================================================

-- 1. Add the missing DELETE policy on user_answers
DROP POLICY IF EXISTS "Users can delete own answers" ON user_answers;
CREATE POLICY "Users can delete own answers" ON user_answers
  FOR DELETE USING (auth.uid() = user_id);

-- 2. (Defensive) Same fix for user_profiles and user_progress in case
--    some flow ever needs to delete from those.
--    NOTE: user_profiles.id IS the auth user UUID (no user_id column).
DROP POLICY IF EXISTS "Users can delete own profile" ON user_profiles;
CREATE POLICY "Users can delete own profile" ON user_profiles
  FOR DELETE USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can delete own progress" ON user_progress;
CREATE POLICY "Users can delete own progress" ON user_progress
  FOR DELETE USING (auth.uid() = user_id);

-- 3. CLEANUP: dedupe legacy duplicate rows (from the saveAnswer-without-
--    onConflict bug) — keep only the most recent row per (user_id, qid).
DELETE FROM user_answers a
USING user_answers b
WHERE a.user_id = b.user_id
  AND a.question_id = b.question_id
  AND a.answered_at < b.answered_at;

-- 4. Add UNIQUE constraint to prevent future duplicates. The upsert in
--    saveAnswer now has a real conflict target.
ALTER TABLE user_answers
  DROP CONSTRAINT IF EXISTS user_answers_user_question_uniq;
ALTER TABLE user_answers
  ADD CONSTRAINT user_answers_user_question_uniq
  UNIQUE (user_id, question_id);
