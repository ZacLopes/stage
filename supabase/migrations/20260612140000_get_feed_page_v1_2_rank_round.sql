-- FASE 2 (T2.2) — get_feed_page v1.2: rank_score quantizado em 6 casas.
--
-- Fecha o risco "cursor com numeric float" do §9 do PLANO-FASE-2: a
-- mitigação planejada ("client repassa rank_score como string exata") não
-- sobrevive ao caminho real — PostgREST serializa numeric como JSON number
-- e o jsonDecode do Dart entrega double. exp() produz numeric com 16+
-- dígitos; em EMPATES de rank (batches do sync compartilham published_at),
-- um cursor double≠numeric flipava o tie-break de id pra comparação de
-- rank e podia pular/duplicar o resto do empate na página seguinte.
--
-- round(rank, 6) → ≤9 dígitos significativos (rank < 104) → o double
-- roundtrip (shortest-repr do Dart) devolve a MESMA string decimal e o
-- cast numeric do PostgREST reconstrói o valor EXATO. Empates continuam
-- resolvidos por id DESC (rounding pode criar empates novos — coberto).
-- Muda só a expressão escalar do rank: conjunto e semântica de filtros
-- intactos (paridade não afetada); FASE2_TESTS_OK re-rodado pós-apply.
--
-- (Diff vs 20260612130000: apenas o round(...) em `ranked`.)

create or replace function public.get_feed_page(
  p_limit              int          default 20,
  p_cursor_rank        numeric      default null,
  p_cursor_id          uuid         default null,
  p_filter_areas       text[]       default null,
  p_filter_locations   text[]       default null,
  p_filter_work_models text[]       default null,
  p_filter_job_types   text[]       default null,
  p_min_salary         int          default null,
  p_frozen_at          timestamptz  default now()
) returns table (
  job_id uuid, score int, rank_score numeric,
  reason_area boolean, reason_location boolean, reason_work_model boolean,
  reason_job_type boolean, reason_salary boolean,
  total_after_filters bigint,
  total_available bigint
)
language plpgsql stable security invoker
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_limit int := greatest(1, least(coalesce(p_limit, 20), 50));
  v_first_page boolean := (p_cursor_id is null or p_cursor_rank is null);
  v_f_areas text[]; v_f_locations text[]; v_f_work_models text[]; v_f_job_types text[];
  r_areas text[]; r_locations text[]; r_work_models text[]; r_job_types text[];
begin
  if v_uid is null then
    raise exception 'get_feed_page requer usuário autenticado';
  end if;
  p_frozen_at := least(coalesce(p_frozen_at, now()), now());

  v_f_areas := (select array_agg(lower(btrim(extensions.unaccent(a)))) from unnest(p_filter_areas) a);
  v_f_locations := (select array_agg(lower(btrim(extensions.unaccent(l)))) from unnest(p_filter_locations) l);
  v_f_work_models := case when p_filter_work_models is null
                            or array_length(p_filter_work_models, 1) is null
                          then null else p_filter_work_models end;
  v_f_job_types := case when p_filter_job_types is null
                          or array_length(p_filter_job_types, 1) is null
                        then null else p_filter_job_types end;

  select array_agg(lower(btrim(extensions.unaccent(title))))
    into r_areas
    from profile_desired_titles
   where user_id = v_uid and coalesce(title, '') <> '';

  select nullif(array_remove(array[
           (select lower(btrim(extensions.unaccent(primary_location_city)))
              from profile_job_preferences
             where user_id = v_uid
               and coalesce(primary_location_city, '') <> '')
         ] || coalesce((select array_agg(lower(btrim(extensions.unaccent(city))))
                          from profile_other_locations
                         where user_id = v_uid
                           and coalesce(city, '') <> ''), '{}'::text[]),
         null), '{}'::text[])
    into r_locations;

  select array_agg(case wm when 'remote'    then 'remoto'
                           when 'hybrid'    then 'hibrido'
                           when 'in_person' then 'presencial' else wm end)
    into r_work_models
    from profile_job_preferences jp
   cross join lateral unnest(coalesce(jp.work_mode, '{}'::text[])) wm
   where jp.user_id = v_uid;

  select case when jp.job_types is null or array_length(jp.job_types, 1) is null
              then null else jp.job_types end
    into r_job_types
    from profile_job_preferences jp
   where jp.user_id = v_uid;

  return query
  with syn(canonical, synonym) as (values
    -- ESPELHO LITERAL de FilterHelpers._areaSynonyms (13 chaves, 58 pares)
    ('rh','rh'),('rh','recursos humanos'),('rh','gente'),('rh','gente e gestao'),('rh','people'),
    ('recursos humanos','rh'),('recursos humanos','recursos humanos'),('recursos humanos','gente'),
    ('recursos humanos','gente e gestao'),('recursos humanos','people'),
    ('tecnologia','tecnologia'),('tecnologia','ti'),('tecnologia','tech'),
    ('tecnologia','engenharia de software'),('tecnologia','desenvolvimento'),('tecnologia','software'),
    ('engenharia','engenharia'),('engenharia','engenharia de software'),('engenharia','engineering'),
    ('design','design'),('design','produto'),('design','ux'),('design','ui'),
    ('design','product design'),('design','experiencia do usuario'),
    ('produto','produto'),('produto','design'),('produto','product'),('produto','ux'),('produto','ui'),
    ('marketing','marketing'),('marketing','growth'),('marketing','comunicacao'),
    ('marketing','crm'),('marketing','brand'),
    ('vendas','vendas'),('vendas','comercial'),('vendas','sales'),('vendas','business development'),
    ('financas','financas'),('financas','finance'),('financas','controladoria'),('financas','contabilidade'),
    ('operacoes','operacoes'),('operacoes','operations'),('operacoes','logistica'),
    ('operacoes','supply chain'),('operacoes','cs'),('operacoes','customer success'),
    ('operacoes','atendimento'),('operacoes','suporte'),
    ('juridico','juridico'),('juridico','legal'),('juridico','compliance'),
    ('administrativo','administrativo'),('administrativo','admin'),
    ('geral','geral'),('geral','general')
  ),
  city_state(city, uf) as (values
    -- ESPELHO LITERAL de FilterHelpers._cityToState (28 entradas)
    ('sao paulo','sp'),('campinas','sp'),('santos','sp'),('sao bernardo do campo','sp'),
    ('guarulhos','sp'),('osasco','sp'),('sao jose dos campos','sp'),('ribeirao preto','sp'),('sorocaba','sp'),
    ('rio de janeiro','rj'),('niteroi','rj'),
    ('belo horizonte','mg'),('uberlandia','mg'),('contagem','mg'),
    ('curitiba','pr'),('londrina','pr'),('porto alegre','rs'),('caxias do sul','rs'),
    ('brasilia','df'),('salvador','ba'),('recife','pe'),('fortaleza','ce'),('manaus','am'),
    ('florianopolis','sc'),('joinville','sc'),('goiania','go'),('vitoria','es'),('belem','pa')
  ),
  base as (
    select j.id, j.published_at, j.work_model, j.job_type, j.salary_min, j.area,
           coalesce(j.location_city, '')  as city_raw,
           coalesce(j.location_state, '') as state_raw
    from jobs j
    where j.is_active = true
      and (j.deadline is null or j.deadline >= now())
      and not exists (select 1 from swipe_actions sa
                      where sa.user_id = v_uid and sa.job_id = j.id)
  ),
  areas_d as (select distinct b.area from base b),
  area_f as (
    select a.area from areas_d a
    where exists (
      select 1 from unnest(v_f_areas) ua
      where ua = lower(btrim(extensions.unaccent(a.area)))
         or exists (select 1 from syn s
                    where s.canonical = lower(btrim(extensions.unaccent(a.area)))
                      and s.synonym = ua)
         or exists (select 1 from syn s
                    where s.canonical = ua
                      and s.synonym = lower(btrim(extensions.unaccent(a.area)))))
  ),
  area_r as (
    select a.area from areas_d a
    where exists (
      select 1 from unnest(r_areas) ua
      where ua = lower(btrim(extensions.unaccent(a.area)))
         or exists (select 1 from syn s
                    where s.canonical = lower(btrim(extensions.unaccent(a.area)))
                      and s.synonym = ua)
         or exists (select 1 from syn s
                    where s.canonical = ua
                      and s.synonym = lower(btrim(extensions.unaccent(a.area)))))
  ),
  locs_d as (select distinct b.city_raw, b.state_raw from base b),
  loc_f as (
    select l.city_raw, l.state_raw from locs_d l
    where (btrim(l.city_raw) <> '' or btrim(l.state_raw) <> '')
      and exists (
        select 1 from unnest(v_f_locations) ul
        left join city_state cs_u on cs_u.city = ul
        left join city_state cs_j on cs_j.city = lower(btrim(extensions.unaccent(l.city_raw)))
        where ul <> ''
          and ((btrim(l.city_raw) <> ''
                and (lower(btrim(extensions.unaccent(l.city_raw))) like '%' || ul || '%'
                     or ul like '%' || lower(btrim(extensions.unaccent(l.city_raw))) || '%'))
            or (cs_u.uf is not null
                and lower(btrim(extensions.unaccent(l.state_raw))) = cs_u.uf)
            or (cs_j.uf is not null and cs_u.uf is not null and cs_j.uf = cs_u.uf)
            or (ul = lower(btrim(extensions.unaccent(l.state_raw)))))
      )
  ),
  loc_r as (
    select l.city_raw, l.state_raw from locs_d l
    where (btrim(l.city_raw) <> '' or btrim(l.state_raw) <> '')
      and exists (
        select 1 from unnest(r_locations) ul
        left join city_state cs_u on cs_u.city = ul
        left join city_state cs_j on cs_j.city = lower(btrim(extensions.unaccent(l.city_raw)))
        where ul <> ''
          and ((btrim(l.city_raw) <> ''
                and (lower(btrim(extensions.unaccent(l.city_raw))) like '%' || ul || '%'
                     or ul like '%' || lower(btrim(extensions.unaccent(l.city_raw))) || '%'))
            or (cs_u.uf is not null
                and lower(btrim(extensions.unaccent(l.state_raw))) = cs_u.uf)
            or (cs_j.uf is not null and cs_u.uf is not null and cs_j.uf = cs_u.uf)
            or (ul = lower(btrim(extensions.unaccent(l.state_raw)))))
      )
  ),
  scored as (
    select b.id, b.published_at,
      (v_f_areas is null or b.area in (select af.area from area_f af)) as pass_area,
      (v_f_work_models is null or b.work_model = any(v_f_work_models)) as pass_model,
      (v_f_job_types is null or b.job_type = any(v_f_job_types)) as pass_type,
      (v_f_locations is null or b.work_model = 'remoto'
        or (b.city_raw, b.state_raw) in (select lf.city_raw, lf.state_raw from loc_f lf)) as pass_loc,
      (p_min_salary is null or p_min_salary <= 0
        or b.salary_min is null or b.salary_min >= p_min_salary) as pass_salary,
      (r_areas is not null and b.area in (select ar.area from area_r ar)) as m_area,
      (r_job_types is not null and b.job_type = any(r_job_types)) as m_type,
      (r_locations is not null and (b.work_model = 'remoto'
        or (b.city_raw, b.state_raw) in (select lr.city_raw, lr.state_raw from loc_r lr))) as m_loc,
      (r_work_models is not null and b.work_model = any(r_work_models)) as m_model,
      (p_min_salary is not null and p_min_salary > 0
       and b.salary_min is not null and b.salary_min >= p_min_salary) as m_salary
    from base b
  ),
  calc as (
    select s.id, s.published_at,
      case when w.total > 0 then round(
        (30 * s.m_area::int + 20 * s.m_type::int + 15 * s.m_loc::int
         + 15 * s.m_model::int + 10 * s.m_salary::int)::numeric / w.total * 100)
      else 0 end as score_calc,
      s.m_area, s.m_loc, s.m_model, s.m_type, s.m_salary
    from scored s
    cross join lateral (select
        (case when r_areas       is not null then 30 else 0 end)
      + (case when r_job_types   is not null then 20 else 0 end)
      + (case when r_locations   is not null then 15 else 0 end)
      + (case when r_work_models is not null then 15 else 0 end)
      + (case when p_min_salary is not null and p_min_salary > 0 then 10 else 0 end)
      as total) w
    where s.pass_area and s.pass_model and s.pass_type and s.pass_loc and s.pass_salary
  ),
  -- (REV-1) rank = score × (0.6 + 0.4·exp(−dias/14)) + jitter(user, vaga, dia)
  -- (v1.2) round 6 casas: cursor sobrevive ao roundtrip JSON→double→numeric
  ranked as (
    select c.id, c.score_calc,
      round(
        (c.score_calc * (0.6 + 0.4 * exp(-greatest(extract(epoch from (p_frozen_at - c.published_at)), 0) / 86400.0 / 14.0))
         + (abs(hashtext(v_uid::text || c.id::text || date_trunc('day', p_frozen_at)::text)::bigint) % 1000) / 250.0
        )::numeric, 6) as rank_calc,
      c.m_area, c.m_loc, c.m_model, c.m_type, c.m_salary
    from calc c
  )
  (select rc.id, rc.score_calc::int, rc.rank_calc,
          rc.m_area, rc.m_loc, rc.m_model, rc.m_type, rc.m_salary,
          case when v_first_page then (select count(*) from calc) else null end,
          case when v_first_page then (select count(*) from scored) else null end
     from ranked rc
    where v_first_page
       or row(rc.rank_calc, rc.id) < row(p_cursor_rank, p_cursor_id)
    -- (REV-1) id DESC alinhado ao predicado ROW(…) < ROW(…)
    order by rc.rank_calc desc, rc.id desc
    limit v_limit)
  union all
  -- sentinela do estado B: 1ª página vazia → 1 row só-totais (job_id null)
  select null::uuid, null::int, null::numeric,
         null::boolean, null::boolean, null::boolean, null::boolean, null::boolean,
         0::bigint, (select count(*) from scored)
   where v_first_page and not exists (select 1 from calc);
end $fn$;

comment on function public.get_feed_page is
  'Fase 2 v1.2: feed paginado por keyset (rank_score DESC, id DESC), rank quantizado 6dp (cursor float-safe), matching por valor distinto. Espelho de filter_helpers.dart — mudou lá, roda tools/feed_parity/.';

revoke all on function public.get_feed_page(int, numeric, uuid, text[], text[], text[], text[], int, timestamptz) from public, anon;
grant execute on function public.get_feed_page(int, numeric, uuid, text[], text[], text[], text[], int, timestamptz) to authenticated;
