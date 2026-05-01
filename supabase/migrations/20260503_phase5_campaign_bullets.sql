-- Phase 5: Campaign-scoped bullet generation
-- Adds campaign_id FK to bullet_versions, approved_bullets, section_versions.
-- Existing experience_id columns are kept nullable (backward compat with old schema).
-- Also adds experience_phase_id (string key like 'm3.stage.0') to approved_bullets.

-- bullet_versions: add campaign_id + raw_response_ids
ALTER TABLE bullet_versions
  ADD COLUMN IF NOT EXISTS campaign_id UUID REFERENCES campaigns(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS experience_phase_id TEXT,
  ADD COLUMN IF NOT EXISTS raw_response_ids UUID[];

-- Make old experience_id nullable (was NOT NULL in old schema)
ALTER TABLE bullet_versions
  ALTER COLUMN experience_id DROP NOT NULL;

-- approved_bullets: add campaign_id + experience_phase_id
ALTER TABLE approved_bullets
  ADD COLUMN IF NOT EXISTS campaign_id UUID REFERENCES campaigns(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS experience_phase_id TEXT,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE approved_bullets
  ALTER COLUMN experience_id DROP NOT NULL,
  ALTER COLUMN user_id DROP NOT NULL;

-- section_versions: add campaign_id
ALTER TABLE section_versions
  ADD COLUMN IF NOT EXISTS campaign_id UUID REFERENCES campaigns(id) ON DELETE CASCADE;

ALTER TABLE section_versions
  ALTER COLUMN user_id DROP NOT NULL;

-- bullet_generation_logs: add campaign_id, make experience_id nullable
ALTER TABLE bullet_generation_logs
  ADD COLUMN IF NOT EXISTS campaign_id UUID REFERENCES campaigns(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS experience_phase_id TEXT;

ALTER TABLE bullet_generation_logs
  ALTER COLUMN experience_id DROP NOT NULL;

-- Indexes for new columns
CREATE INDEX IF NOT EXISTS idx_bullet_versions_campaign ON bullet_versions(campaign_id);
CREATE INDEX IF NOT EXISTS idx_bullet_versions_exp_phase ON bullet_versions(experience_phase_id);
CREATE INDEX IF NOT EXISTS idx_approved_campaign ON approved_bullets(campaign_id);
CREATE INDEX IF NOT EXISTS idx_approved_exp_phase ON approved_bullets(experience_phase_id);
CREATE INDEX IF NOT EXISTS idx_section_campaign ON section_versions(campaign_id);
