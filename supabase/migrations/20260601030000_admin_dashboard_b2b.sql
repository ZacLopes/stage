-- Admin Dashboard B2B
--
-- Internal tables for the Stage admin dashboard. All tables are RLS-protected
-- and are intended to be accessed only through admin Edge Functions using the
-- service role key after validating the caller against public.admin_users.

BEGIN;

CREATE TABLE IF NOT EXISTS public.admin_users (
  email      TEXT PRIMARY KEY,
  role       TEXT NOT NULL CHECK (role IN ('owner', 'analyst')),
  is_active  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "No direct client access to admin_users" ON public.admin_users;
CREATE POLICY "No direct client access to admin_users"
  ON public.admin_users FOR ALL
  USING (false)
  WITH CHECK (false);

CREATE TABLE IF NOT EXISTS public.employer_clients (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  website       TEXT,
  contact_name  TEXT,
  contact_email TEXT,
  status        TEXT NOT NULL DEFAULT 'prospect'
    CHECK (status IN ('prospect', 'active', 'paused', 'archived')),
  notes         TEXT,
  created_by    TEXT REFERENCES public.admin_users(email) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_employer_clients_status
  ON public.employer_clients (status, created_at DESC);

ALTER TABLE public.employer_clients ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "No direct client access to employer_clients" ON public.employer_clients;
CREATE POLICY "No direct client access to employer_clients"
  ON public.employer_clients FOR ALL
  USING (false)
  WITH CHECK (false);

CREATE TABLE IF NOT EXISTS public.candidate_list_requests (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       UUID REFERENCES public.employer_clients(id) ON DELETE SET NULL,
  source_job_id   UUID REFERENCES public.jobs(id) ON DELETE SET NULL,
  title           TEXT NOT NULL,
  area            TEXT,
  description     TEXT,
  requirements    TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  location_city   TEXT,
  location_state  TEXT,
  work_model      TEXT CHECK (work_model IS NULL OR work_model IN ('presencial', 'hibrido', 'remoto')),
  job_type        TEXT CHECK (job_type IS NULL OR job_type IN ('estagio', 'trainee', 'clt_junior', 'temporario', 'full_time', 'internship', 'contract', 'part_time')),
  min_score       INTEGER NOT NULL DEFAULT 60 CHECK (min_score BETWEEN 0 AND 100),
  status          TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'ranking', 'review', 'exported', 'archived')),
  created_by      TEXT REFERENCES public.admin_users(email) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_candidate_list_requests_client
  ON public.candidate_list_requests (client_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_candidate_list_requests_status
  ON public.candidate_list_requests (status, created_at DESC);

ALTER TABLE public.candidate_list_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "No direct client access to candidate_list_requests" ON public.candidate_list_requests;
CREATE POLICY "No direct client access to candidate_list_requests"
  ON public.candidate_list_requests FOR ALL
  USING (false)
  WITH CHECK (false);

CREATE TABLE IF NOT EXISTS public.candidate_data_sharing_consents (
  user_id          UUID PRIMARY KEY REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  status           TEXT NOT NULL DEFAULT 'not_asked'
    CHECK (status IN ('not_asked', 'granted', 'denied', 'revoked')),
  status_reason    TEXT,
  granted_at       TIMESTAMPTZ,
  revoked_at       TIMESTAMPTZ,
  updated_by_admin TEXT REFERENCES public.admin_users(email) ON DELETE SET NULL,
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_candidate_data_sharing_consents_status
  ON public.candidate_data_sharing_consents (status, updated_at DESC);

ALTER TABLE public.candidate_data_sharing_consents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "No direct client access to candidate_data_sharing_consents" ON public.candidate_data_sharing_consents;
CREATE POLICY "No direct client access to candidate_data_sharing_consents"
  ON public.candidate_data_sharing_consents FOR ALL
  USING (false)
  WITH CHECK (false);

CREATE TABLE IF NOT EXISTS public.candidate_list_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id      UUID NOT NULL REFERENCES public.candidate_list_requests(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  score           INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100),
  rank            INTEGER NOT NULL,
  score_breakdown JSONB NOT NULL DEFAULT '[]'::jsonb,
  status          TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'exported')),
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (request_id, user_id),
  UNIQUE (request_id, rank)
);

CREATE INDEX IF NOT EXISTS idx_candidate_list_items_request_rank
  ON public.candidate_list_items (request_id, rank);

CREATE INDEX IF NOT EXISTS idx_candidate_list_items_user
  ON public.candidate_list_items (user_id);

ALTER TABLE public.candidate_list_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "No direct client access to candidate_list_items" ON public.candidate_list_items;
CREATE POLICY "No direct client access to candidate_list_items"
  ON public.candidate_list_items FOR ALL
  USING (false)
  WITH CHECK (false);

CREATE TABLE IF NOT EXISTS public.candidate_list_exports (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id      UUID NOT NULL REFERENCES public.candidate_list_requests(id) ON DELETE CASCADE,
  exported_by     TEXT REFERENCES public.admin_users(email) ON DELETE SET NULL,
  format          TEXT NOT NULL DEFAULT 'csv' CHECK (format IN ('csv')),
  exported_fields TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  candidate_count INTEGER NOT NULL DEFAULT 0 CHECK (candidate_count >= 0),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_candidate_list_exports_request
  ON public.candidate_list_exports (request_id, created_at DESC);

ALTER TABLE public.candidate_list_exports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "No direct client access to candidate_list_exports" ON public.candidate_list_exports;
CREATE POLICY "No direct client access to candidate_list_exports"
  ON public.candidate_list_exports FOR ALL
  USING (false)
  WITH CHECK (false);

CREATE TABLE IF NOT EXISTS public.admin_audit_log (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_email TEXT REFERENCES public.admin_users(email) ON DELETE SET NULL,
  action      TEXT NOT NULL,
  entity_type TEXT,
  entity_id   TEXT,
  metadata    JSONB NOT NULL DEFAULT '{}'::jsonb,
  ip_address  TEXT,
  user_agent  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_admin
  ON public.admin_audit_log (admin_email, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_action
  ON public.admin_audit_log (action, created_at DESC);

ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "No direct client access to admin_audit_log" ON public.admin_audit_log;
CREATE POLICY "No direct client access to admin_audit_log"
  ON public.admin_audit_log FOR ALL
  USING (false)
  WITH CHECK (false);

DROP TRIGGER IF EXISTS trg_employer_clients_updated_at ON public.employer_clients;
CREATE TRIGGER trg_employer_clients_updated_at
  BEFORE UPDATE ON public.employer_clients
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_candidate_list_requests_updated_at ON public.candidate_list_requests;
CREATE TRIGGER trg_candidate_list_requests_updated_at
  BEFORE UPDATE ON public.candidate_list_requests
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_candidate_data_sharing_consents_updated_at ON public.candidate_data_sharing_consents;
CREATE TRIGGER trg_candidate_data_sharing_consents_updated_at
  BEFORE UPDATE ON public.candidate_data_sharing_consents
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_candidate_list_items_updated_at ON public.candidate_list_items;
CREATE TRIGGER trg_candidate_list_items_updated_at
  BEFORE UPDATE ON public.candidate_list_items
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

COMMIT;
