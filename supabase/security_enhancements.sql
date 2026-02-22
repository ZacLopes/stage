-- ============================================
-- SECURITY ENHANCEMENTS - Career Gamification App
-- ============================================
-- Run this script in your Supabase SQL Editor AFTER the main schema
-- ============================================

-- ============================================
-- 1. AI GENERATION LOGS (Rate Limiting)
-- ============================================

CREATE TABLE IF NOT EXISTS ai_generation_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  generation_type TEXT NOT NULL CHECK (generation_type IN ('profile', 'resume', 'interview')),
  tokens_used INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast rate limit queries
CREATE INDEX idx_ai_logs_user_type_date ON ai_generation_logs(user_id, generation_type, created_at);

-- RLS Policies
ALTER TABLE ai_generation_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own generation logs" ON ai_generation_logs
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Service can insert generation logs" ON ai_generation_logs
  FOR INSERT WITH CHECK (true); -- Edge Functions use service role

-- ============================================
-- 2. RESTRICT CONTENT TABLE POLICIES (Security Fix)
-- ============================================

-- Drop overly permissive policies
DROP POLICY IF EXISTS "Anyone can insert tracks" ON tracks;
DROP POLICY IF EXISTS "Anyone can update tracks" ON tracks;
DROP POLICY IF EXISTS "Anyone can insert phases" ON phases;
DROP POLICY IF EXISTS "Anyone can update phases" ON phases;
DROP POLICY IF EXISTS "Anyone can insert questions" ON questions;
DROP POLICY IF EXISTS "Anyone can update questions" ON questions;

-- Create restricted policies (read-only for public, write for service role only)
CREATE POLICY "Public can view tracks" ON tracks
  FOR SELECT USING (true);

CREATE POLICY "Public can view phases" ON phases
  FOR SELECT USING (true);

CREATE POLICY "Public can view questions" ON questions
  FOR SELECT USING (true);

-- Service role can manage content (via Dashboard or seeding scripts)
-- No need for explicit policy - service role bypasses RLS

-- ============================================
-- 3. SECURITY AUDIT LOG (Optional but Recommended)
-- ============================================

CREATE TABLE IF NOT EXISTS security_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  event_type TEXT NOT NULL, -- 'login', 'failed_login', 'account_delete', 'suspicious_activity'
  ip_address TEXT,
  user_agent TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_audit_user_date ON security_audit_log(user_id, created_at);
CREATE INDEX idx_audit_event_date ON security_audit_log(event_type, created_at);

ALTER TABLE security_audit_log ENABLE ROW LEVEL SECURITY;

-- Only admins can view audit logs (service role)
CREATE POLICY "Service role can view audit logs" ON security_audit_log
  FOR SELECT USING (false); -- No public access

-- ============================================
-- 4. RATE LIMITING HELPER FUNCTION
-- ============================================

CREATE OR REPLACE FUNCTION check_rate_limit(
  p_user_id UUID,
  p_generation_type TEXT,
  p_max_per_day INTEGER
) RETURNS BOOLEAN AS $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM ai_generation_logs
  WHERE user_id = p_user_id
    AND generation_type = p_generation_type
    AND created_at >= CURRENT_DATE;
  
  RETURN v_count < p_max_per_day;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 5. CLEANUP OLD LOGS (Performance)
-- ============================================

-- Function to clean up logs older than 90 days
CREATE OR REPLACE FUNCTION cleanup_old_logs() RETURNS void AS $$
BEGIN
  DELETE FROM ai_generation_logs WHERE created_at < NOW() - INTERVAL '90 days';
  DELETE FROM security_audit_log WHERE created_at < NOW() - INTERVAL '180 days';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Schedule cleanup (requires pg_cron extension - enable in Supabase Dashboard)
-- SELECT cron.schedule('cleanup-logs', '0 2 * * *', 'SELECT cleanup_old_logs()');

-- ============================================
-- 6. ADD MISSING AGE COLUMN TO USER_PROFILES (if not exists)
-- ============================================

DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'user_profiles' AND column_name = 'age'
  ) THEN
    ALTER TABLE user_profiles ADD COLUMN age INTEGER;
  END IF;
END $$;

-- ============================================
-- DONE! Security enhancements applied.
-- ============================================
-- Next steps:
-- 1. Deploy Edge Functions: supabase functions deploy
-- 2. Set OPENAI_API_KEY secret: supabase secrets set OPENAI_API_KEY=your_key
-- 3. Update Flutter app to use Edge Functions instead of direct OpenAI calls
