-- 20260727120000_sync_display_name.sql
--
-- Mantém `user_profiles.name` em sincronia com o nome que a pessoa REALMENTE
-- informou, que vive em `profile_personal.first_name/last_name`.
--
-- ## O defeito (device-test 24/07 B1/B2, refinado em 27/07)
--
-- O PDF exportado saía como `curriculo_.pdf`, sem nome. A causa aparente era
-- "o cadastro não pergunta o nome". Medido, é outra coisa: **o cadastro
-- pergunta e a pessoa responde** — o nome só não chega em `user_profiles.name`,
-- que é de onde metade do app o lê.
--
-- Números de produção em 27/07 (cadastros por telefone, `phone_*@stage.app`):
--
--   mês     cadastros   sem user_profiles.name   MAS com first_name preenchido
--   jul     4           4                        3
--   jun     91          91                       82
--   mai     15          14                       14
--
-- Ou seja: 100% dos cadastros por telefone ficam com o campo vazio, e a
-- esmagadora maioria dessas pessoas JÁ informou o nome — 79 das 91 de junho
-- concluíram o onboarding inteiro. O dado existe; está na gaveta errada.
--
-- ## Por que no banco, e não no cliente
--
-- `profile_personal` é escrito por vários caminhos: onboarding, editor manual,
-- importação de CV e RPCs de merge guiado. Corrigir só o cliente deixaria os
-- outros de fora e a assimetria voltaria na próxima porta de entrada. Um
-- gatilho cobre todos, inclusive os que ainda não existem.
--
-- ## Invariantes
--
--  • MANUAL VENCE (regra de domínio 2 do handoff): só preenche quando
--    `user_profiles.name` está VAZIO. Nunca sobrescreve um nome existente.
--  • Não dispara webhook: `notify_new_signup` é AFTER **INSERT** em
--    user_profiles (verificado em prod, 27/07); este gatilho só faz UPDATE.
--  • Não colide com as travas existentes: `zzz_fence_gamification_stmt` e
--    `zzz_guard_import_cache_update` são `UPDATE OF gamification_data`.
--  • Idempotente: reaplicar não muda linha nenhuma além das que ainda estão
--    vazias.

-- ── 1. Função de sincronização ──────────────────────────────────────────────

create or replace function public._sync_display_name_from_personal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  composed text;
begin
  composed := btrim(
    coalesce(new.first_name, '') || ' ' || coalesce(new.last_name, '')
  );

  -- Sem nome informado ainda: nada a espelhar.
  if composed = '' then
    return new;
  end if;

  -- MANUAL VENCE: só preenche o slot vazio.
  update public.user_profiles
     set name = composed
   where id = new.user_id
     and btrim(coalesce(name, '')) = '';

  return new;
end;
$$;

revoke all on function public._sync_display_name_from_personal() from public;

comment on function public._sync_display_name_from_personal() is
  'Espelha profile_personal.first_name+last_name em user_profiles.name quando '
  'este está vazio. Manual vence: nunca sobrescreve nome existente.';

-- ── 2. Gatilho ──────────────────────────────────────────────────────────────

drop trigger if exists sync_display_name_from_personal on public.profile_personal;

create trigger sync_display_name_from_personal
  after insert or update of first_name, last_name on public.profile_personal
  for each row
  execute function public._sync_display_name_from_personal();

-- ── 3. Backfill de quem já passou pelo onboarding ───────────────────────────
--
-- Alcance esperado em prod (medido em 27/07): ~100 das 110 linhas com
-- `user_profiles.name` vazio têm first_name preenchido. As ~10 restantes
-- seguem vazias — ninguém informou nome, e inventar seria pior.

update public.user_profiles up
   set name = btrim(
         coalesce(pp.first_name, '') || ' ' || coalesce(pp.last_name, '')
       )
  from public.profile_personal pp
 where pp.user_id = up.id
   and btrim(coalesce(up.name, '')) = ''
   and btrim(
         coalesce(pp.first_name, '') || ' ' || coalesce(pp.last_name, '')
       ) <> '';
