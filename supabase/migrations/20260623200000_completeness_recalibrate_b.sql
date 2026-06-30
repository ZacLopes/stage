-- Migration: completeness_recalibrate_b
--
-- PLANO-FASE-6 T6.6 (Increment 6): recalibra o completeness_score pra pesar os
-- campos MONETIZÁVEIS (Tier 1/2), não cosméticos — alinhando a fórmula do banco
-- à filosofia do cérebro de lacunas (profile_gaps.dart) e dos pesos do match.
--
-- Corrige 3 buracos da fórmula anterior (§5.4 / migration 20260617150000):
--   (1) CIDADE não pontuava — é filtro duro do admin + 15 pts no match;
--   (2) skills exigia >=5, mas "shortlist-ready" é >=3 (kMinSkillsForComplete);
--   (3) área/tipo-de-vaga/modalidade estavam fundidos num único eixo OR.
--
-- Variante CONSERVADORA (B), escolhida pelo fundador após simulação em prod
-- (1.704 perfis): mantém o email (quase-universal → não muda ordenação, mas
-- segura a barra de progresso e o KPI >=60). Distribuição estável (média 49,3→50,0,
-- >=60: 699→714, zero: 64→64), top-25 da shortlist muda só ~8/25, e quem não tem
-- cidade (Tier 1) cai ~7pts — exatamente o efeito desejado.
--
-- Pesos B (=100): email 8 · área 11 · cidade 10 · tipo 5 · modalidade 5 ·
-- educação 8 · skills>=3 12 · 1ª exp c/ bullets 23 · 2ª exp 8 · idiomas 8 · resumo 2.
--
-- Detalhe técnico: cidade e resumo vêm de profile_personal, então — como o email —
-- entram por PARÂMETRO (a função roda num trigger BEFORE, onde a linha está stale).
-- A assinatura muda de (uuid,text) pra (uuid,text,text,text); a antiga é dropada.
--
-- R2: migration via CLI (`supabase db push`) + manifest; nunca pelo dashboard.

BEGIN;

-- Nova fórmula (4 args: uid, email, city, summary). Pesos monetizáveis (Tier 1/2).
create or replace function public.compute_profile_completeness(
  p_uid uuid, p_email text, p_city text, p_summary text)
returns int language sql stable security definer set search_path = public as $function$
  select least(100,
      -- Tier 1 — filtros duros (match + shortlist) = 51 (+ email 8 = 59)
      (case when coalesce(btrim(p_email), '') <> '' then 8 else 0 end)
    + (case when exists (select 1 from profile_desired_titles t
                           where t.user_id = p_uid and coalesce(btrim(t.title), '') <> '')
            then 11 else 0 end)
    + (case when coalesce(btrim(p_city), '') <> '' then 10 else 0 end)
    + (case when exists (select 1 from profile_job_preferences jp where jp.user_id = p_uid
                           and coalesce(array_length(jp.job_types, 1), 0) > 0) then 5 else 0 end)
    + (case when exists (select 1 from profile_job_preferences jp where jp.user_id = p_uid
                           and coalesce(array_length(jp.work_mode, 1), 0) > 0) then 5 else 0 end)
    + (case when exists (select 1 from profile_education e where e.user_id = p_uid) then 8 else 0 end)
    + (case when (
          select count(distinct coalesce(s.canonical_skill_id::text, lower(btrim(s.name))))
          from profile_skills s where s.user_id = p_uid) >= 3 then 12 else 0 end)
      -- Tier 2 — substância = 39
    + (case when exists (
          select 1 from profile_experiences x
          join profile_bullets b on b.experience_id = x.id
          where x.user_id = p_uid) then 23 else 0 end)
    + (case when (select count(*) from profile_experiences x where x.user_id = p_uid) >= 2 then 8 else 0 end)
    + (case when exists (select 1 from profile_languages l where l.user_id = p_uid) then 8 else 0 end)
      -- Tier 3 — acabamento = 2
    + (case when coalesce(btrim(p_summary), '') <> '' then 2 else 0 end)
  );
$function$;

-- BEFORE em profile_personal: passa cidade e resumo de NEW (não da tabela stale).
create or replace function public.set_profile_completeness() returns trigger
language plpgsql security definer set search_path = public as $function$
begin
  new.completeness_score := public.compute_profile_completeness(
    new.user_id, new.email, new.location_city, new.summary);
  return new;
end $function$;

-- AFTER nas tabelas-fonte: "toca" profile_personal com os valores atuais da linha;
-- o BEFORE refaz o cálculo a partir de NEW (mesmos valores) — resultado idêntico.
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
      set completeness_score = public.compute_profile_completeness(
            pp.user_id, pp.email, pp.location_city, pp.summary)
      where pp.user_id = v_uid;
  end if;
  return null;
end $function$;

-- Remove a assinatura antiga (2 args), agora sem callers.
drop function if exists public.compute_profile_completeness(uuid, text);

-- Backfill: recomputa TODOS com a fórmula B (idempotente — o BEFORE refaz igual).
update public.profile_personal pp
  set completeness_score = public.compute_profile_completeness(
        pp.user_id, pp.email, pp.location_city, pp.summary);

COMMIT;
