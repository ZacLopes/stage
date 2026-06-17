-- P2: faceta de ÁREA da busca do admin (auditoria — dimensão central que não
-- era filtrável). Distinct de profile_desired_titles.title + nº de candidatos,
-- pro picker de área. Via RPC porque PostgREST não faz DISTINCT/agg e o select
-- cru de profile_desired_titles (~3,4k rows) estoura o db-max-rows (1000).
-- Chamada só pela edge admin-candidates-search (service_role).
create or replace function public.admin_area_facet()
returns table(title text, users bigint)
language sql stable security invoker
set search_path = public
as $function$
  select t.title, count(distinct t.user_id)::bigint as users
  from profile_desired_titles t
  where coalesce(btrim(t.title), '') <> ''
  group by t.title
  order by count(distinct t.user_id) desc, t.title;
$function$;

revoke all on function public.admin_area_facet() from public, anon;
grant execute on function public.admin_area_facet() to service_role;
