-- feed_parity — lado RPC do harness (Fase 2, T2.1).
--
-- Pra cada um dos 7 perfis de referência: monta os ARGS como o client
-- montaria (prefs do Perfil viram filtros — caminho default do
-- _performFetch, D-8 do plano), simula o JWT via request.jwt.claims e
-- pagina o RPC real até esgotar. Saída: (user_id, n, ids_md5) — comparar
-- com a saída do parity_check.dart (mesma janela de minutos!).
--
-- Rodar como service role/postgres em prod, payload ÚNICO (temp table some
-- no commit). Não escreve em nada.

create temp table _feed_parity_results (
  user_id uuid,
  n int,
  ids_md5 text
) on commit drop;

do $$
declare
  v_prefixes constant text[] := array[
    'a91e0ed2','b7226e54','456ea636','1d052e97','16835f3d','d466f487','c5bdb3ac'];
  v_uid uuid;
  a_areas text[]; a_locs text[]; a_modes text[]; a_types text[];
  v_all uuid[]; v_page uuid[];
  v_cursor_rank numeric; v_cursor_id uuid;
  v_frozen timestamptz := now();
  v_pages int;
  r record;
begin
  for v_uid in
    select u.id from auth.users u
    where left(u.id::text, 8) = any(v_prefixes)
    order by array_position(v_prefixes, left(u.id::text, 8))
  loop
    -- ESPELHO da montagem do client (checks de vazio CRUS, sem btrim —
    -- ver parity_check.dart). Lista vazia → NULL (= sem filtro).
    select nullif(array_agg(t.title) filter (where coalesce(t.title, '') <> ''),
                  '{}'::text[])
      into a_areas
      from profile_desired_titles t where t.user_id = v_uid;

    select nullif(array_remove(array[
             (select jp.primary_location_city from profile_job_preferences jp
               where jp.user_id = v_uid
                 and coalesce(jp.primary_location_city, '') <> '')
           ] || coalesce((select array_agg(ol.city)
                            from profile_other_locations ol
                           where ol.user_id = v_uid
                             and coalesce(ol.city, '') <> ''), '{}'::text[]),
           null), '{}'::text[])
      into a_locs;

    select nullif(array_agg(case wm when 'remote'    then 'remoto'
                                    when 'hybrid'    then 'hibrido'
                                    when 'in_person' then 'presencial'
                                    else wm end), '{}'::text[])
      into a_modes
      from profile_job_preferences jp
     cross join lateral unnest(coalesce(jp.work_mode, '{}'::text[])) wm
     where jp.user_id = v_uid;

    select case when jp.job_types is null or array_length(jp.job_types, 1) is null
                then null else jp.job_types end
      into a_types
      from profile_job_preferences jp where jp.user_id = v_uid;

    -- client sem NENHUMA pref → preferences null → repo não filtra nada;
    -- equivalente no RPC: todos os args null (já é o caso aqui).

    perform set_config('request.jwt.claims',
      json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);

    v_all := '{}'::uuid[]; v_cursor_rank := null; v_cursor_id := null; v_pages := 0;
    loop
      v_page := '{}'::uuid[];
      for r in
        select * from get_feed_page(
          p_limit := 50,
          p_cursor_rank := v_cursor_rank,
          p_cursor_id := v_cursor_id,
          p_filter_areas := a_areas,
          p_filter_locations := a_locs,
          p_filter_work_models := a_modes,
          p_filter_job_types := a_types,
          p_frozen_at := v_frozen)
      loop
        if r.job_id is null then continue; end if;  -- sentinela (feed vazio)
        v_page := v_page || r.job_id;
        v_cursor_rank := r.rank_score; v_cursor_id := r.job_id;
      end loop;
      exit when coalesce(array_length(v_page, 1), 0) = 0;
      v_all := v_all || v_page;
      v_pages := v_pages + 1;
      if v_pages > 200 then raise exception 'paginação não converge pra %', v_uid; end if;
    end loop;

    insert into _feed_parity_results
    select v_uid, coalesce(array_length(v_all, 1), 0),
           md5(coalesce((select string_agg(x.id::text, ',' order by x.id)
                           from unnest(v_all) x(id)), ''));
  end loop;

  perform set_config('request.jwt.claims', '', true);
end $$;

select user_id, n, ids_md5 from _feed_parity_results;
