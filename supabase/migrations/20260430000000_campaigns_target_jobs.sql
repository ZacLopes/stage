-- Fase 1: Vaga-alvo e Campanhas
-- Cria as tabelas target_jobs e campaigns, com RLS e migração de usuários existentes.

-- Step 1: target_jobs
CREATE TABLE IF NOT EXISTS target_jobs (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID        NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  title                TEXT,
  description_text     TEXT,
  source_url           TEXT,
  parsed_requirements  JSONB,
  is_skipped           BOOLEAN     NOT NULL DEFAULT false,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE target_jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own target_jobs"
  ON target_jobs FOR ALL
  USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_target_jobs_user_id ON target_jobs(user_id);

-- Step 2: campaigns
CREATE TABLE IF NOT EXISTS campaigns (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID        NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  target_job_id  UUID        REFERENCES target_jobs(id) ON DELETE SET NULL,
  name           TEXT        NOT NULL DEFAULT 'Campanha 1',
  status         TEXT        NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'completed')),
  template_id    TEXT        NOT NULL DEFAULT 'harvard_ats',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_edited_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE campaigns ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own campaigns"
  ON campaigns FOR ALL
  USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_campaigns_user_id      ON campaigns(user_id);
CREATE INDEX IF NOT EXISTS idx_campaigns_target_job_id ON campaigns(target_job_id);

-- Step 3: Migrar usuários existentes sem campanha
-- Cria um target_job com is_skipped=true + uma campaign apontando para ele.
WITH new_jobs AS (
  INSERT INTO target_jobs (user_id, is_skipped)
  SELECT up.id, true
  FROM user_profiles up
  WHERE NOT EXISTS (
    SELECT 1 FROM campaigns c WHERE c.user_id = up.id
  )
  RETURNING id, user_id
)
INSERT INTO campaigns (user_id, target_job_id, name, status)
SELECT nj.user_id, nj.id, 'Campanha 1', 'draft'
FROM new_jobs nj;
