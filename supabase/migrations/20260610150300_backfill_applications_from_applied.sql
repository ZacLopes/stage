-- Fase 1 T1.3 (D3) — backfill dos applied históricos para applications.
-- IDEMPOTENTE: re-execução = 0 rows (ON CONFLICT no índice parcial).
-- Estado medido em plan mode (2026-06-10): 493 applied=true, 0 com
-- applied_at null, 343 apontando pra jobs inativos (badge Expirada no
-- client 2.3.0), 0 jobs deletados.
-- Eventos iniciais saem do trigger de INSERT com actor 'system' (migration
-- roda sem JWT).

INSERT INTO public.applications
  (user_id, job_id, type, status, application_method, created_at)
SELECT sa.user_id, sa.job_id, 'external_confirmed', 'submitted',
       COALESCE(j.application_method, 'url'),
       COALESCE(sa.applied_at, sa.created_at)
FROM public.swipe_actions sa
JOIN public.jobs j ON j.id = sa.job_id
WHERE sa.applied = true
ON CONFLICT (user_id, job_id) WHERE job_id IS NOT NULL DO NOTHING;
