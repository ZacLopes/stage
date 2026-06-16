-- FASE 3 (T3.5, PLANO-FASE-3 §5 + §6/PR2): suporte server pro digest com prazos.
-- O digest existente (notifications-daily-digest) mira só o cohort D+1; T3.5 o
-- estende com uma 2ª passada — usuários com vaga SALVA (swipe_actions liked) que
-- fecha em ≤48h e que ainda NÃO aplicaram. Zero novo tipo de push: mesma edge,
-- mesmo canal OneSignal, só uma intent nova.

-- Índice MEDIDO (correção 1 do fundador): EXPLAIN ANALYZE da query candidata em
-- prod (2026-06-16) mostrou varredura de `idx_jobs_active_published_at` filtrando
-- a janela de deadline sobre TODAS as ativas (Rows Removed by Filter: 427, 303ms).
-- Sem indexar a janela, na projeção de 5k ativas (F2) isso cresce ~10×. Este
-- índice parcial troca o filtro full-active por um range scan na janela.
create index jobs_deadline_active_idx on public.jobs (deadline)
  where is_active and deadline is not null;

-- A edge usa supabase-js (sem SQL cru); o anti-join + agregação vive aqui.
-- SECURITY DEFINER + search_path pinado: lê cross-user (é o cron quem chama via
-- service_role); execute SÓ pra service_role — usuário não enumera ninguém.
create or replace function public.get_saved_jobs_expiring(p_hours int default 48)
returns table(user_id uuid, n int)
language sql
stable
security definer
set search_path = public
as $$
  select sa.user_id, count(*)::int as n
  from swipe_actions sa
  join jobs j on j.id = sa.job_id
  where sa.action = 'liked'
    and j.is_active = true
    and j.deadline is not null
    and j.deadline >= now()
    and j.deadline <= now() + make_interval(hours => greatest(p_hours, 1))
    and not exists (
      select 1 from applications a
      where a.user_id = sa.user_id and a.job_id = sa.job_id
    )
  group by sa.user_id;
$$;

revoke all on function public.get_saved_jobs_expiring(int) from public;
grant execute on function public.get_saved_jobs_expiring(int) to service_role;
