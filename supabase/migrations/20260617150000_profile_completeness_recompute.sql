-- P3: completeness_score CALCULADO pra TODOS, não só importadores de CV.
--
-- Bug (auditoria): o score só era escrito pela extração de CV; quem preenchia à
-- mão ficava em 0 (76% da base = 0, mas 729 deles têm CV, 844 têm área). O campo
-- media "importou CV", não "perfil completo". Spec §5.4: "completude é calculada,
-- nunca digitada".
--
-- Solução: fórmula §5.4 sobre as tabelas relacionais, com um ÚNICO ponto de
-- cálculo — trigger BEFORE em profile_personal que SEMPRE seta o score computado
-- (ignora qualquer valor escrito direto pelo app/extração → "calculada, nunca
-- digitada"). Tabelas-fonte (educação/experiência/bullets/skills/idiomas/prefs/
-- áreas) têm trigger AFTER que "toca" profile_personal pra forçar o recálculo.
-- email entra por parâmetro (NEW.email) pra evitar self-read no BEFORE INSERT.
--
-- Pesos §5.4: formação 15 · 1ª exp c/ bullets 25 · ≥5 skills 15 · prefs/área 15 ·
-- contato 10 · idiomas 10 · 2ª exp 10 = 100. (Foto não pontua.)

create or replace function public.compute_profile_completeness(p_uid uuid, p_email text)
returns int language sql stable security definer set search_path = public as $function$
  select least(100,
      (case when exists (select 1 from profile_education e where e.user_id = p_uid) then 15 else 0 end)
    + (case when exists (
          select 1 from profile_experiences x
          join profile_bullets b on b.experience_id = x.id
          where x.user_id = p_uid) then 25 else 0 end)
    + (case when (
          select count(distinct coalesce(s.canonical_skill_id::text, lower(btrim(s.name))))
          from profile_skills s where s.user_id = p_uid) >= 5 then 15 else 0 end)
    + (case when exists (select 1 from profile_desired_titles t
                           where t.user_id = p_uid and coalesce(btrim(t.title), '') <> '')
              or exists (select 1 from profile_job_preferences jp where jp.user_id = p_uid
                           and (coalesce(array_length(jp.job_types, 1), 0) > 0
                                or coalesce(array_length(jp.work_mode, 1), 0) > 0))
            then 15 else 0 end)
    + (case when coalesce(btrim(p_email), '') <> '' then 10 else 0 end)
    + (case when exists (select 1 from profile_languages l where l.user_id = p_uid) then 10 else 0 end)
    + (case when (select count(*) from profile_experiences x where x.user_id = p_uid) >= 2 then 10 else 0 end)
  );
$function$;

-- BEFORE em profile_personal: ÚNICO ponto que escreve o score (sempre computado).
create or replace function public.set_profile_completeness() returns trigger
language plpgsql security definer set search_path = public as $function$
begin
  new.completeness_score := public.compute_profile_completeness(new.user_id, new.email);
  return new;
end $function$;

drop trigger if exists trg_profile_personal_completeness on public.profile_personal;
create trigger trg_profile_personal_completeness
  before insert or update on public.profile_personal
  for each row execute function public.set_profile_completeness();

-- AFTER nas tabelas-fonte: "toca" profile_personal → dispara o BEFORE (recálculo).
create or replace function public.touch_profile_completeness() returns trigger
language plpgsql security definer set search_path = public as $function$
declare v_uid uuid;
begin
  if TG_TABLE_NAME = 'profile_bullets' then
    select x.user_id into v_uid from profile_experiences x
      where x.id = case when TG_OP = 'DELETE' then OLD.experience_id else NEW.experience_id end;
  elsif TG_OP = 'DELETE' then
    v_uid := OLD.user_id;
  else
    v_uid := NEW.user_id;
  end if;
  if v_uid is not null then
    update public.profile_personal pp
      set completeness_score = public.compute_profile_completeness(pp.user_id, pp.email)
      where pp.user_id = v_uid;
  end if;
  return null;
end $function$;

do $$
declare t text;
begin
  foreach t in array array[
    'profile_education','profile_experiences','profile_bullets','profile_skills',
    'profile_languages','profile_job_preferences','profile_desired_titles']
  loop
    execute format('drop trigger if exists trg_%s_completeness on public.%I', t, t);
    execute format(
      'create trigger trg_%s_completeness after insert or update or delete on public.%I '
      || 'for each row execute function public.touch_profile_completeness()', t, t);
  end loop;
end $$;

-- Backfill: recomputa TODOS (some o 76%-em-0).
update public.profile_personal pp
  set completeness_score = public.compute_profile_completeness(pp.user_id, pp.email);
