-- FASE 3 (T3.4, PLANO-FASE-3 §4/D3 + §6/PR1): instrumentação da saída externa.
-- Hoje o clique de "aplicar no site" some no launchUrl cru — o registro de QUEM
-- clicou em QUAL vaga só vive no PostHog (auditoria H2). Esta tabela leve traz o
-- funil externo pro banco: client (PR3) faz own-insert no único call site de
-- apply (liked_jobs_screen::_openApplication, branch http(s); mailto NÃO grava).
-- Leitura cross-user pro relatório B2B ("X salvaram, Y clicaram") = service role
-- / console na F4; own-select basta agora.
create table public.outbound_clicks (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  job_id     uuid references public.jobs(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.outbound_clicks enable row level security;

create policy outbound_clicks_own_insert on public.outbound_clicks
  for insert to authenticated
  with check (auth.uid() = user_id);

create policy outbound_clicks_own_select on public.outbound_clicks
  for select to authenticated
  using (auth.uid() = user_id);

-- anon não tem nada a fazer aqui; service_role (console/admin) bypassa RLS.
revoke all on public.outbound_clicks from anon;
grant select, insert on public.outbound_clicks to authenticated;
grant select on public.outbound_clicks to service_role;

create index outbound_clicks_user_created_idx on public.outbound_clicks (user_id, created_at desc);
create index outbound_clicks_job_idx on public.outbound_clicks (job_id);

-- T3.3 (adição manual): link opcional da vaga adicionada à mão. Coluna aditiva,
-- paralela a external_company/external_title (já existem da F1). NULL pros types
-- stage/external_confirmed; o CHECK de type não muda.
alter table public.applications add column external_url text;
