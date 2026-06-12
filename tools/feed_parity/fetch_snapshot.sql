-- feed_parity: snapshot de prod pro lado client do harness (rodar como
-- service role; salvar o JSON em tools/feed_parity/snapshot.json — NÃO commitar).
-- Os 8 prefixos = 7 perfis de referência do PLANO-FASE-2 §4 (D2).
with target_users(uid) as (
  select u.id from auth.users u
  where left(u.id::text, 8) = any(array[
    'a91e0ed2','b7226e54','456ea636','1d052e97','16835f3d','d466f487','c5bdb3ac'
  ])
)
select json_build_object(
  'fetched_at', now(),
  'jobs', (
    select coalesce(json_agg(json_build_object(
        'id', j.id,
        'area', j.area,
        'work_model', j.work_model,
        'job_type', j.job_type,
        'location_city', j.location_city,
        'location_state', j.location_state,
        'salary_min', j.salary_min,
        'deadline', j.deadline)), '[]'::json)
    from jobs j where j.is_active = true
  ),
  'users', (
    select json_agg(json_build_object(
        'user_id', tu.uid,
        'desired_titles', (select coalesce(json_agg(t.title), '[]'::json)
                             from profile_desired_titles t where t.user_id = tu.uid),
        'job_preferences', (select row_to_json(x) from (
                              select jp.primary_location_city, jp.work_mode, jp.job_types
                                from profile_job_preferences jp where jp.user_id = tu.uid) x),
        'other_locations', (select coalesce(json_agg(ol.city), '[]'::json)
                              from profile_other_locations ol where ol.user_id = tu.uid),
        'swiped_job_ids', (select coalesce(json_agg(sa.job_id), '[]'::json)
                             from swipe_actions sa where sa.user_id = tu.uid)))
    from target_users tu
  )
) as snapshot;
