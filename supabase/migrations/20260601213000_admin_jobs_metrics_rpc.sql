-- Fast metrics for the admin jobs table.
-- Avoids transferring large swipe/match datasets to the Edge Function.

CREATE INDEX IF NOT EXISTS idx_swipe_actions_job_id
  ON public.swipe_actions (job_id);

CREATE INDEX IF NOT EXISTS idx_match_analyses_job_id
  ON public.match_analyses (job_id);

CREATE INDEX IF NOT EXISTS idx_jobs_active_published_at
  ON public.jobs (is_active, published_at DESC);

CREATE OR REPLACE FUNCTION public.admin_job_metrics(p_job_ids UUID[])
RETURNS TABLE (
  job_id UUID,
  likes INTEGER,
  applies INTEGER,
  avg_score NUMERIC
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH input_jobs AS (
    SELECT unnest(p_job_ids) AS job_id
  ),
  swipe_metrics AS (
    SELECT
      s.job_id,
      count(*) FILTER (WHERE s.action = 'liked')::INTEGER AS likes,
      count(*) FILTER (WHERE s.applied IS TRUE)::INTEGER AS applies
    FROM public.swipe_actions s
    JOIN input_jobs i ON i.job_id = s.job_id
    GROUP BY s.job_id
  ),
  match_metrics AS (
    SELECT
      m.job_id,
      avg(m.score)::NUMERIC AS avg_score
    FROM public.match_analyses m
    JOIN input_jobs i ON i.job_id = m.job_id
    GROUP BY m.job_id
  )
  SELECT
    i.job_id,
    COALESCE(s.likes, 0) AS likes,
    COALESCE(s.applies, 0) AS applies,
    COALESCE(m.avg_score, 0) AS avg_score
  FROM input_jobs i
  LEFT JOIN swipe_metrics s ON s.job_id = i.job_id
  LEFT JOIN match_metrics m ON m.job_id = i.job_id;
$$;

REVOKE ALL ON FUNCTION public.admin_job_metrics(UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_job_metrics(UUID[]) TO service_role;
