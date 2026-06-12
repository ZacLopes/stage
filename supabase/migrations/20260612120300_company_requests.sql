-- FASE 2 (T2.3, PLANO-FASE-2 §6/PR1): pedidos de empresa no estado de
-- exaustão honesta do feed ("Pedir uma empresa"). B1/D2 do plano provaram
-- que feeds-zero EXISTEM hoje (2 dos 7 perfis de paridade) — esses estados
-- são produto, não edge case. Client (PR3) faz own-insert; admin dashboard
-- lê via service role.
create table public.company_requests (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  company_name text not null,
  note         text,
  created_at   timestamptz not null default now()
);

alter table public.company_requests enable row level security;

create policy company_requests_own_insert on public.company_requests
  for insert to authenticated
  with check (auth.uid() = user_id);

create policy company_requests_own_select on public.company_requests
  for select to authenticated
  using (auth.uid() = user_id);

-- anon não tem nada a fazer aqui; service_role (admin dashboard) bypassa RLS.
revoke all on public.company_requests from anon;
grant select, insert on public.company_requests to authenticated;
grant select on public.company_requests to service_role;
