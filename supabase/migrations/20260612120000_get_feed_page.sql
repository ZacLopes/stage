-- FASE 2 (T2.1, PLANO-FASE-2 §3.1): feed server-side com ranking determinístico v1.
-- ESPELHO de lib/features/jobs/utils/filter_helpers.dart e dos pesos de
-- match_score.dart (30/20/15/15/10; skills fora — decisão D-2 do PLANO-FASE-2).
-- Mudou lá → muda aqui → roda tools/feed_parity/ antes do merge.
--
-- Desvios do SQL literal do plano ("o fato vence" — detalhe no FASE-2-RELATORIO.md):
--  1. unaccent vive no schema `extensions` (não em public) — chamadas
--     qualificadas `extensions.unaccent`; search_path segue pinado em public.
--  2. m_loc GATEADO por `r_locations is not null`: no SQL do plano o atalho
--     do remoto ficava FORA do gate → numerador ganhava +15 sem os 15 no
--     denominador → score >100 pra user sem cidade declarada (divergia do
--     client, que só pontua dimensão declarada). Testado no test_fase2.
--  3. Linha-sentinela na 1ª página vazia: o desenho do plano devolvia os
--     counts em colunas das rows — com 0 rows (exatamente o estado B da
--     exaustão) o client ficava cego. 1ª página sem resultado → 1 row com
--     job_id NULL carregando total_after_filters/total_available.
--  4. Guards defensivos: hashtext::bigint antes do abs (abs(INT_MIN) estoura),
--     idade de publicação clampada ≥0 (published_at futuro não infla rank),
--     coalesce(p_limit,20), cursor incompleto (rank OU id null) = 1ª página,
--     args '{}' tratados como null (espelha isEmpty do client), ul <> '' no
--     match de localização (espelha o `continue` do client em string vazia).

create or replace function public.get_feed_page(
  p_limit              int          default 20,
  p_cursor_rank        numeric      default null,
  p_cursor_id          uuid         default null,
  p_filter_areas       text[]       default null,  -- null/vazio = sem filtro
  p_filter_locations   text[]       default null,
  p_filter_work_models text[]       default null,  -- vocabulário PT do client
  p_filter_job_types   text[]       default null,
  p_min_salary         int          default null,  -- centavos; só de filtro local
  p_frozen_at          timestamptz  default now()  -- D-7: cursor estável na sessão
) returns table (
  job_id uuid, score int, rank_score numeric,
  reason_area boolean, reason_location boolean, reason_work_model boolean,
  reason_job_type boolean, reason_salary boolean,
  total_after_filters bigint, -- só na 1ª página; senão null
  total_available bigint      -- idem: pós exclusões básicas, PRÉ filtros de args
)
language plpgsql stable security invoker
set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_limit int := greatest(1, least(coalesce(p_limit, 20), 50));
  v_first_page boolean := (p_cursor_id is null or p_cursor_rank is null);
  -- filtros efetivos (args do client) normalizados UMA vez
  v_f_areas text[]; v_f_locations text[]; v_f_work_models text[]; v_f_job_types text[];
  -- prefs de RANKING (identidade relacional — espelho de _loadProfilePrefs)
  r_areas text[]; r_locations text[]; r_work_models text[]; r_job_types text[];
begin
  if v_uid is null then
    raise exception 'get_feed_page requer usuário autenticado';
  end if;
  -- clamp defensivo (REV-1): client bugado/malicioso não viaja no futuro
  p_frozen_at := least(coalesce(p_frozen_at, now()), now());

  -- args normalizados; array vazio → null (= sem filtro, espelho do isEmpty)
  v_f_areas := (select array_agg(lower(btrim(extensions.unaccent(a)))) from unnest(p_filter_areas) a);
  v_f_locations := (select array_agg(lower(btrim(extensions.unaccent(l)))) from unnest(p_filter_locations) l);
  v_f_work_models := case when p_filter_work_models is null
                            or array_length(p_filter_work_models, 1) is null
                          then null else p_filter_work_models end;
  v_f_job_types := case when p_filter_job_types is null
                          or array_length(p_filter_job_types, 1) is null
                        then null else p_filter_job_types end;

  -- prefs de ranking. Check de vazio é CRU (sem btrim) — espelho exato do
  -- client, que dropa '' via isNotEmpty ao montar as listas mas MANTÉM
  -- strings só-de-espaço (que depois normalizam pra '' e nunca casam,
  -- porém CONTAM como dimensão declarada no denominador).
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

  -- work_mode relacional é EN → PT (espelho do switch de _loadProfilePrefs)
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
  scored as (
    select j.id, j.published_at,
      -- pass_* = filtros dos ARGS (paridade com _applyPreferenceFilters)
      (v_f_areas is null or exists (
         select 1 from unnest(v_f_areas) ua
         where ua = lower(btrim(extensions.unaccent(j.area)))
            or exists (select 1 from syn s
                       where s.canonical = lower(btrim(extensions.unaccent(j.area)))
                         and s.synonym = ua)
            or exists (select 1 from syn s
                       where s.canonical = ua
                         and s.synonym = lower(btrim(extensions.unaccent(j.area))))
      )) as pass_area,
      (v_f_work_models is null or j.work_model = any(v_f_work_models)) as pass_model,
      (v_f_job_types is null or j.job_type = any(v_f_job_types)) as pass_type,
      (v_f_locations is null or j.work_model = 'remoto' or (
         (coalesce(btrim(j.location_city), '') <> '' or coalesce(btrim(j.location_state), '') <> '')
         and exists (
           select 1 from unnest(v_f_locations) ul
           left join city_state cs_u on cs_u.city = ul
           left join city_state cs_j on cs_j.city = lower(btrim(extensions.unaccent(coalesce(j.location_city, ''))))
           where ul <> ''
             and ((coalesce(btrim(j.location_city), '') <> ''
                   and (lower(btrim(extensions.unaccent(j.location_city))) like '%' || ul || '%'
                        or ul like '%' || lower(btrim(extensions.unaccent(j.location_city))) || '%'))
               or (cs_u.uf is not null
                   and lower(btrim(extensions.unaccent(coalesce(j.location_state, '')))) = cs_u.uf)
               or (cs_j.uf is not null and cs_u.uf is not null and cs_j.uf = cs_u.uf)
               or (ul = lower(btrim(extensions.unaccent(coalesce(j.location_state, ''))))))
         )
      )) as pass_loc,
      (p_min_salary is null or p_min_salary <= 0
        or j.salary_min is null or j.salary_min >= p_min_salary) as pass_salary,
      -- m_* = matched do RANKING (prefs relacionais r_*), mesmos predicados.
      -- TODOS gateados pela dimensão declarada (numerador ⊆ denominador).
      (r_areas is not null and exists (
         select 1 from unnest(r_areas) ua
         where ua = lower(btrim(extensions.unaccent(j.area)))
            or exists (select 1 from syn s
                       where s.canonical = lower(btrim(extensions.unaccent(j.area)))
                         and s.synonym = ua)
            or exists (select 1 from syn s
                       where s.canonical = ua
                         and s.synonym = lower(btrim(extensions.unaccent(j.area))))
      )) as m_area,
      (r_job_types is not null and j.job_type = any(r_job_types)) as m_type,
      (r_locations is not null and (j.work_model = 'remoto' or (
         (coalesce(btrim(j.location_city), '') <> '' or coalesce(btrim(j.location_state), '') <> '')
         and exists (
           select 1 from unnest(r_locations) ul
           left join city_state cs_u on cs_u.city = ul
           left join city_state cs_j on cs_j.city = lower(btrim(extensions.unaccent(coalesce(j.location_city, ''))))
           where ul <> ''
             and ((coalesce(btrim(j.location_city), '') <> ''
                   and (lower(btrim(extensions.unaccent(j.location_city))) like '%' || ul || '%'
                        or ul like '%' || lower(btrim(extensions.unaccent(j.location_city))) || '%'))
               or (cs_u.uf is not null
                   and lower(btrim(extensions.unaccent(coalesce(j.location_state, '')))) = cs_u.uf)
               or (cs_j.uf is not null and cs_u.uf is not null and cs_j.uf = cs_u.uf)
               or (ul = lower(btrim(extensions.unaccent(coalesce(j.location_state, ''))))))
         )
      ))) as m_loc,
      (r_work_models is not null and j.work_model = any(r_work_models)) as m_model,
      (p_min_salary is not null and p_min_salary > 0
       and j.salary_min is not null and j.salary_min >= p_min_salary) as m_salary
    from jobs j
    where j.is_active = true
      and (j.deadline is null or j.deadline >= now())
      and not exists (select 1 from swipe_actions sa
                      where sa.user_id = v_uid and sa.job_id = j.id)
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
  -- (REV-1) rank = score × (0.6 + 0.4·exp(−dias/14)) + jitter
  --   · piso 0.6: frescor custa NO MÁXIMO 40% do score — relevância domina.
  --   · jitter determinístico 0..~4 pontos, seed (user, vaga, dia da sessão):
  --     repõe a FUNÇÃO do shuffle pros 52% sem prefs (rank base 0 → feed
  --     rotaciona por dia, não por id fixo) e desempata scores quantizados.
  --     Determinístico dentro da sessão (p_frozen_at truncado) → keyset estável.
  ranked as (
    select c.id, c.score_calc,
      (c.score_calc * (0.6 + 0.4 * exp(-greatest(extract(epoch from (p_frozen_at - c.published_at)), 0) / 86400.0 / 14.0))
       + (abs(hashtext(v_uid::text || c.id::text || date_trunc('day', p_frozen_at)::text)::bigint) % 1000) / 250.0
      )::numeric as rank_calc,
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
    -- (REV-1) id DESC alinhado ao predicado ROW(…) < ROW(…) — com ASC, empates
    -- de rank (52% da base, tudo em rank≈jitter) loopavam duplicatas na pág. 2.
    order by rc.rank_calc desc, rc.id desc
    limit v_limit)
  union all
  -- sentinela do estado B: 1ª página sem NENHUMA vaga pós-filtros → 1 row
  -- só-totais (job_id null). total_after_filters=0 com total_available>0 =
  -- "filtros zeraram" (CTA limpar filtros); total_available=0 = catálogo
  -- esgotado de verdade (estado A).
  select null::uuid, null::int, null::numeric,
         null::boolean, null::boolean, null::boolean, null::boolean, null::boolean,
         0::bigint, (select count(*) from scored)
   where v_first_page and not exists (select 1 from calc);
end $fn$;

comment on function public.get_feed_page is
  'Fase 2: feed paginado por keyset (rank_score DESC, id DESC) com ranking determinístico v1. Espelho de filter_helpers.dart — mudou lá, roda tools/feed_parity/.';

revoke all on function public.get_feed_page(int, numeric, uuid, text[], text[], text[], text[], int, timestamptz) from public, anon;
grant execute on function public.get_feed_page(int, numeric, uuid, text[], text[], text[], text[], int, timestamptz) to authenticated;
