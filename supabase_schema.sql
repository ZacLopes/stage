-- ============================================
-- Career Gamification App - Supabase Schema
-- ============================================
-- Run this script in your Supabase SQL Editor
-- ============================================

-- Drop existing tables if they exist (for clean setup)
DROP TABLE IF EXISTS user_answers CASCADE;
DROP TABLE IF EXISTS user_progress CASCADE;
DROP TABLE IF EXISTS user_profiles CASCADE;
DROP TABLE IF EXISTS questions CASCADE;
DROP TABLE IF EXISTS phases CASCADE;
DROP TABLE IF EXISTS tracks CASCADE;

-- ============================================
-- CONTENT TABLES (Admin-managed)
-- ============================================

-- Tracks (Mundos)
CREATE TABLE tracks (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  color BIGINT NOT NULL,
  icon_asset TEXT NOT NULL,
  order_index INTEGER NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Phases (Etapas)
CREATE TABLE phases (
  id TEXT PRIMARY KEY,
  track_id TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  order_index INTEGER NOT NULL,
  xp_reward INTEGER NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Questions
CREATE TABLE questions (
  id TEXT PRIMARY KEY,
  phase_id TEXT NOT NULL REFERENCES phases(id) ON DELETE CASCADE,
  type INTEGER NOT NULL, -- 0=single, 1=multiple, 2=scale, 3=text
  content TEXT NOT NULL,
  options TEXT, -- JSON array as text
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- USER TABLES
-- ============================================

-- User Profiles (extends Supabase Auth)
CREATE TABLE user_profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  course TEXT,
  semester TEXT,
  xp INTEGER DEFAULT 0,
  level INTEGER DEFAULT 1,
  ai_consent BOOLEAN DEFAULT FALSE,
  ai_consent_timestamp TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- User Progress (Phase completion tracking)
CREATE TABLE user_progress (
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  phase_id TEXT NOT NULL REFERENCES phases(id) ON DELETE CASCADE,
  completed BOOLEAN DEFAULT FALSE,
  score INTEGER DEFAULT 0,
  completed_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, phase_id)
);

-- User Answers (for resume generation)
CREATE TABLE user_answers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  question_id TEXT NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
  answer TEXT NOT NULL, -- JSON for multiple answers
  answered_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- INDEXES FOR PERFORMANCE
-- ============================================

CREATE INDEX idx_phases_track ON phases(track_id);
CREATE INDEX idx_questions_phase ON questions(phase_id);
CREATE INDEX idx_progress_user ON user_progress(user_id);
CREATE INDEX idx_answers_user ON user_answers(user_id);
CREATE INDEX idx_answers_question ON user_answers(question_id);

-- ============================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================

-- Enable RLS on all tables
ALTER TABLE tracks ENABLE ROW LEVEL SECURITY;
ALTER TABLE phases ENABLE ROW LEVEL SECURITY;
ALTER TABLE questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_answers ENABLE ROW LEVEL SECURITY;

-- Content tables: Public read access, authenticated insert/update (for seeding)
CREATE POLICY "Anyone can view tracks" ON tracks
  FOR SELECT USING (true);

CREATE POLICY "Anyone can insert tracks" ON tracks
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Anyone can update tracks" ON tracks
  FOR UPDATE USING (true);

CREATE POLICY "Anyone can view phases" ON phases
  FOR SELECT USING (true);

CREATE POLICY "Anyone can insert phases" ON phases
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Anyone can update phases" ON phases
  FOR UPDATE USING (true);

CREATE POLICY "Anyone can view questions" ON questions
  FOR SELECT USING (true);

CREATE POLICY "Anyone can insert questions" ON questions
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Anyone can update questions" ON questions
  FOR UPDATE USING (true);

-- User Profiles: Users can read/update their own profile
CREATE POLICY "Users can view own profile" ON user_profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON user_profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON user_profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

-- User Progress: Users can manage their own progress
CREATE POLICY "Users can view own progress" ON user_progress
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own progress" ON user_progress
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own progress" ON user_progress
  FOR UPDATE USING (auth.uid() = user_id);

-- User Answers: Users can manage their own answers
CREATE POLICY "Users can view own answers" ON user_answers
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own answers" ON user_answers
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own answers" ON user_answers
  FOR UPDATE USING (auth.uid() = user_id);

-- ============================================
-- FUNCTIONS & TRIGGERS
-- ============================================

-- Function to automatically create user profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.user_profiles (id, email, name, course, semester)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'name', 'User'),
    COALESCE(NEW.raw_user_meta_data->>'course', ''),
    COALESCE(NEW.raw_user_meta_data->>'semester', '')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to create profile on user signup
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to allow users to delete their own account from auth.users
-- This requires SECURITY DEFINER to bypass the normal lack of permissions on auth.users
CREATE OR REPLACE FUNCTION public.delete_user()
RETURNS void AS $$
BEGIN
  DELETE FROM auth.users WHERE id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for user_profiles updated_at
CREATE TRIGGER update_user_profiles_updated_at
    BEFORE UPDATE ON user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- DONE!
-- ============================================
-- Next step: Upload your seed data using the Dart script
