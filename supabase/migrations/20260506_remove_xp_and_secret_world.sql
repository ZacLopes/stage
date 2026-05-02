-- Migration: Remove XP/level system and the Secret World track.
-- Background: gamification was simplified to use phase-completion percentage
-- only. XP, levels, and the elite interview report are gone from the app.

BEGIN;

-- 1) Drop XP/level columns from user_profiles
ALTER TABLE user_profiles DROP COLUMN IF EXISTS xp;
ALTER TABLE user_profiles DROP COLUMN IF EXISTS level;

-- 2) Drop xp_reward column from phases
ALTER TABLE phases DROP COLUMN IF EXISTS xp_reward;

-- 3) Drop score column from user_progress (was XP earned per phase)
ALTER TABLE user_progress DROP COLUMN IF EXISTS score;

-- 4) Remove the Secret World track and any data referencing it
-- Order matters: questions → phases → tracks (FK chain).
DELETE FROM questions
  WHERE phase_id IN (SELECT id FROM phases WHERE track_id = 'track_secret');
DELETE FROM phases WHERE track_id = 'track_secret';
DELETE FROM tracks WHERE id = 'track_secret';

-- 5) Drop the AI generation log row type for interview reports.
-- This is a soft cleanup — leaves history rows but won't be referenced.
DELETE FROM ai_generation_logs WHERE generation_type = 'interview';

COMMIT;
