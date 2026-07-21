#!/usr/bin/env bash
# Fase 3 (Perfil Central) — roda a cadeia combinada das fundações de Fonte
# importada + edição guiada contra um Postgres EFÊMERO (initdb/pg_ctl). NÃO toca
# em prod e não precisa de Docker. Aplica 14/07 → 17/07, roda contratos,
# reapply e concorrência em duas sessões, e sempre derruba o cluster.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PGPORT_TEST:-$((50000 + RANDOM % 10000))}"
TMP="$(mktemp -d)"
PGDATA="$TMP/pgdata"

cleanup() {
  pg_ctl -D "$PGDATA" -s -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "[fase3-sql] initdb em $PGDATA"
initdb -D "$PGDATA" -U postgres \
  --locale-provider=icu --icu-locale=und -E UTF8 >/dev/null

echo "[fase3-sql] start (porta $PORT, socket em $TMP)"
pg_ctl -D "$PGDATA" -s -w \
  -o "-p $PORT -c listen_addresses='' -c unix_socket_directories='$TMP'" \
  start

createdb -h "$TMP" -p "$PORT" -U postgres fase3test

echo "[fase3-sql] rodando o teste SQL..."
psql -h "$TMP" -p "$PORT" -U postgres -d fase3test -v ON_ERROR_STOP=1 -q \
  -f "$ROOT/supabase/tests/perfil_central_fase3_combined_test.sql"

# ── Testes CONCORRENTES (2 sessões) — ordenação de locks SEGURA, writer REAL.
#
# Blocker 1: o fencing por BEFORE STATEMENT adquire o advisory por-usuário ANTES
# de qualquer tuple lock (ao contrário do BEFORE ROW, que em UPDATE/DELETE trava
# a tupla PRIMEIRO → inversão → deadlock). Provamos por cenários reais:
#   1. import  vs manual UPDATE da mesma linha;
#   2. manual UPDATE primeiro + import;
#   3. DELETE concorrente;
#   4. UPSERT concorrente;
#   5. fill-empty × guided nas duas ordens;
#   6. janela DELETE→import preenche→INSERT (blocker 2);
#   7. composite RPC × UPDATE da mesma linha;
#   8. duas candidatas apply/promote em sessões distintas;
#   9. writer service canônico × merge guiado.
# Em NENHUM pode haver deadlock (SQLSTATE 40P01), timeout, mistura ou perda.
#
# O "outro" writer é o REAL do app: statement authenticated direto sob RLS — sem
# chamar pg_advisory_xact_lock à mão; é a TRIGGER de fencing que pega o lock.
# Sincronização = observação de pg_locks (determinística), não sleep cego; o
# pg_sleep do holder é só teto pra manter a transação aberta.
echo "[fase3-sql] testes concorrentes (writer real, ordenação de locks segura)..."
PSQL="psql -h $TMP -p $PORT -U postgres -d fase3test -v ON_ERROR_STOP=1 -qtA"
U='11111111-1111-1111-1111-111111111111'
AS_AUTH="SET ROLE authenticated; SELECT set_config('request.jwt.claims','{\"sub\":\"$U\"}',false);"
IMPORT_SKILLS="$AS_AUTH SELECT public.save_profile_fill_empty('$U'::uuid, '{\"personal\":{},\"skills\":[{\"name\":\"Import Skill\"}]}'::jsonb);"

wait_for() {  # $1 = SQL que retorna inteiro; $2 = rótulo. Sai no evento, não no tempo.
  local i out
  for i in $(seq 1 200); do
    out=$($PSQL -c "$1" 2>/dev/null || echo 0)
    [ "${out:-0}" -ge 1 ] 2>/dev/null && return 0
    sleep 0.05
  done
  echo "FALHOU concorrência: timeout esperando '$2'"; exit 1
}
no_deadlock() {  # $1 = arquivo de saída; $2 = rótulo
  if grep -qiE "deadlock|40P01|lock timeout|canceling statement due to lock" "$1"; then
    echo "FALHOU $2: deadlock/timeout detectado"; cat "$1"; exit 1
  fi
}

# race HOLDER-vs-CONTENDER: o holder pega o lock (via trigger) num statement real
# e segura; o contender bloqueia no MESMO lock; confirmamos granted→waiting via
# pg_locks; holder commita; ambos terminam SEM deadlock.
race() {  # $1 rótulo  $2 seed SQL  $3 holder op (sem BEGIN/COMMIT)  $4 contender SQL  $5 cnt  $6 names
  local label="$1" seed="$2" hold="$3" cont="$4" expc="$5" expn="$6"
  $PSQL -c "$seed" >/dev/null
  local ho="$TMP/hold.$$" co="$TMP/cont.$$"
  $PSQL -c "$AS_AUTH BEGIN; $hold; SELECT pg_sleep(6); COMMIT;" >"$ho" 2>&1 &
  local hp=$!
  wait_for "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND granted;" "$label: holder segurar o lock"
  $PSQL -c "$cont" >"$co" 2>&1 &
  local cp=$!
  wait_for "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND NOT granted;" "$label: contender bloquear"
  wait "$hp"; wait "$cp"
  no_deadlock "$ho" "$label"; no_deadlock "$co" "$label"
  local cnt names
  cnt=$($PSQL -c "SELECT count(*) FROM public.profile_skills WHERE user_id='$U';")
  names=$($PSQL -c "SELECT COALESCE(string_agg(name, ',' ORDER BY name), '') FROM public.profile_skills WHERE user_id='$U';")
  if [ "$cnt" = "$expc" ] && [ "$names" = "$expn" ]; then
    echo "NOTICE:  T-CONC[$label] OK: sem deadlock; estado final $cnt/'$names'"
  else
    echo "FALHOU $label: cnt=$cnt names='$names' (esperava $expc/'$expn')"; exit 1
  fi
}

# 1. import vs manual UPDATE da mesma linha (seção não-vazia → import preserva).
race "update-mesma-linha" \
  "DELETE FROM public.profile_skills WHERE user_id='$U'; INSERT INTO public.profile_skills(user_id,name) VALUES('$U','Base');" \
  "UPDATE public.profile_skills SET name='BaseEdited' WHERE user_id='$U' AND name='Base'" \
  "$IMPORT_SKILLS" 1 "BaseEdited"

# 2. manual UPDATE primeiro + import (holder=manual pega o lock antes; ordem
#    advisory→tuple idêntica → sem inversão). Cobre o "manual primeiro".
race "manual-primeiro" \
  "DELETE FROM public.profile_skills WHERE user_id='$U'; INSERT INTO public.profile_skills(user_id,name) VALUES('$U','First');" \
  "UPDATE public.profile_skills SET name='FirstEdited' WHERE user_id='$U'" \
  "$IMPORT_SKILLS" 1 "FirstEdited"

# 3. DELETE concorrente: holder deleta tudo e commita; import destrava, vê vazio,
#    preenche — sem fantasma da linha deletada, sem dup.
race "delete-concorrente" \
  "DELETE FROM public.profile_skills WHERE user_id='$U'; INSERT INTO public.profile_skills(user_id,name) VALUES('$U','ToDelete');" \
  "DELETE FROM public.profile_skills WHERE user_id='$U'" \
  "$IMPORT_SKILLS" 1 "Import Skill"

# 4. UPSERT concorrente (INSERT ... ON CONFLICT): holder faz upsert → seção
#    não-vazia → import preserva.
race "upsert-concorrente" \
  "DELETE FROM public.profile_skills WHERE user_id='$U';" \
  "INSERT INTO public.profile_skills(user_id,name) VALUES('$U','Up') ON CONFLICT (user_id, lower(name)) DO UPDATE SET name=EXCLUDED.name" \
  "$IMPORT_SKILLS" 1 "Up"

# 4b. writer fill-empty de 14/07 primeiro, merge guiado de 17/07 depois: ambos
#     serializam e o merge aditivo preserva o importado.
race "fill-primeiro-guided" \
  "DELETE FROM public.profile_skills WHERE user_id='$U';" \
  "SELECT public.save_profile_fill_empty('$U'::uuid, '{\"personal\":{},\"skills\":[{\"name\":\"Import Skill\"}]}'::jsonb)" \
  "$AS_AUTH SELECT public.merge_guided_profile_list('$U'::uuid,'skills','[\"Guided\"]'::jsonb);" \
  2 "Guided,Import Skill"

# 4c. ordem inversa: guided cria a seção; fill-empty vê conteúdo manual/vivo e
#     preserva a seção inteira, sem misturar o item importado.
race "guided-primeiro-fill" \
  "DELETE FROM public.profile_skills WHERE user_id='$U';" \
  "SELECT public.merge_guided_profile_list('$U'::uuid,'skills','[\"Guided\"]'::jsonb)" \
  "$IMPORT_SKILLS" 1 "Guided"

# 4d. writer service REAL de 14/07 (payload de produção) vs merge guiado de
#     17/07. O trigger test-only mantém a transação aberta depois que o writer
#     adquiriu o advisory; o guided precisa aparecer como waiting e preservar
#     tanto personal quanto skill ao destravar.
US='99999999-9999-9999-9999-999999999999'
AS_AUTHS="SET ROLE authenticated; SELECT set_config('request.jwt.claims','{\"sub\":\"$US\"}',false);"
$PSQL -c "INSERT INTO auth.users(id) VALUES('$US') ON CONFLICT DO NOTHING; INSERT INTO public.user_profiles(id) VALUES('$US') ON CONFLICT DO NOTHING; DELETE FROM public.profile_skills WHERE user_id='$US'; DELETE FROM public.profile_personal WHERE user_id='$US';" >/dev/null
SO="$TMP/service-real.$$"; GO="$TMP/guided-real.$$"
$PSQL -c "SET ROLE service_role; SELECT set_config('test.hold_profile_write','on',false); SELECT public.save_profile_from_json('$US'::uuid, '{\"personal\":{\"first_name\":\"Service\"}}'::jsonb);" >"$SO" 2>&1 &
SP=$!
wait_for "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND granted;" "service real: holder segurar lock"
$PSQL -c "$AS_AUTHS SELECT public.merge_guided_profile_list('$US'::uuid,'skills','[\"Guided Service\"]'::jsonb);" >"$GO" 2>&1 &
GP=$!
wait_for "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND NOT granted;" "service real: guided bloquear"
wait "$SP"; wait "$GP"
no_deadlock "$SO" "service-real"; no_deadlock "$GO" "service-real"
SFIRST=$($PSQL -c "SELECT COALESCE(first_name,'') FROM public.profile_personal WHERE user_id='$US';")
SSKILL=$($PSQL -c "SELECT COALESCE(string_agg(name,','),'') FROM public.profile_skills WHERE user_id='$US';")
if [ "$SFIRST" = "Service" ] && [ "$SSKILL" = "Guided Service" ]; then
  echo "NOTICE:  T-CONC[service-real] OK: writer service × guided preservam ambos, sem deadlock"
else
  echo "FALHOU service-real: first='$SFIRST' skills='$SSKILL'"; exit 1
fi

# 5. Janela DELETE→import preenche→INSERT (blocker 2): a sequência serializa pelo
#    lock. Depois do DELETE commitar, import(fill) e INSERT('New') DISPUTAM o
#    lock — as duas ordens são serializações VÁLIDAS (import-primeiro →
#    {Import Skill, New}; insert-primeiro → import vê não-vazio e pula → {New}).
#    O que a janela NÃO pode produzir: duplicata, fantasma de 'Old', ou estado
#    torto. Asseguramos o INVARIANTE (não uma ordem fixa) + zero deadlock.
$PSQL -c "DELETE FROM public.profile_skills WHERE user_id='$U'; INSERT INTO public.profile_skills(user_id,name) VALUES('$U','Old');" >/dev/null
WO="$TMP/w1.$$"; WI="$TMP/w2.$$"; WN="$TMP/w3.$$"
$PSQL -c "$AS_AUTH BEGIN; DELETE FROM public.profile_skills WHERE user_id='$U'; SELECT pg_sleep(4); COMMIT;" >"$WO" 2>&1 &
WP=$!
wait_for "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND granted;" "janela: delete segurar o lock"
$PSQL -c "$IMPORT_SKILLS" >"$WI" 2>&1 &
IP=$!
$PSQL -c "$AS_AUTH INSERT INTO public.profile_skills(user_id,name) SELECT '$U','New' WHERE NOT EXISTS (SELECT 1 FROM public.profile_skills WHERE user_id='$U' AND lower(name)=lower('New'));" >"$WN" 2>&1 &
NP=$!
wait "$WP"; wait "$IP"; wait "$NP"
no_deadlock "$WO" "janela"; no_deadlock "$WI" "janela"; no_deadlock "$WN" "janela"
# Invariantes: sem duplicata (distinct == total), 'Old' apagado, todo nome ∈
# {Import Skill, New}, e a serialização é uma das duas válidas.
WDUP=$($PSQL -c "SELECT count(*) - count(DISTINCT lower(name)) FROM public.profile_skills WHERE user_id='$U';")
WGHOST=$($PSQL -c "SELECT count(*) FROM public.profile_skills WHERE user_id='$U' AND name='Old';")
WBAD=$($PSQL -c "SELECT count(*) FROM public.profile_skills WHERE user_id='$U' AND name NOT IN ('Import Skill','New');")
WNAMES=$($PSQL -c "SELECT COALESCE(string_agg(name, ',' ORDER BY name), '') FROM public.profile_skills WHERE user_id='$U';")
if [ "$WDUP" = "0" ] && [ "$WGHOST" = "0" ] && [ "$WBAD" = "0" ] \
   && { [ "$WNAMES" = "Import Skill,New" ] || [ "$WNAMES" = "New" ]; }; then
  echo "NOTICE:  T-CONC[janela] OK: DELETE→import→INSERT sem dup/fantasma/torto (final '$WNAMES')"
else
  echo "FALHOU janela: dup=$WDUP ghost=$WGHOST bad=$WBAD names='$WNAMES'"; exit 1
fi

# 6. INVERSÃO advisory↔tuple: RPC COMPOSTA (que ATUALIZA uma linha existente) vs
#    UPDATE manual da MESMA linha. É o cenário que o BEFORE ROW antigo deadlockava
#    (manual: tuple→advisory; RPC: advisory→tuple). Com o fencing por statement a
#    ordem é advisory→tuple nos DOIS → sem ciclo. Determinístico + zero deadlock.
UX='33333333-3333-3333-3333-333333333333'
AS_AUTH3="SET ROLE authenticated; SELECT set_config('request.jwt.claims','{\"sub\":\"$UX\"}',false);"
$PSQL -c "DELETE FROM public.profile_experiences WHERE user_id='$UX';" >/dev/null
EID=$($PSQL -c "INSERT INTO public.profile_experiences(user_id,title,company,start_date,end_date) VALUES('$UX','Base','C','2020-01-01','2021-01-01') RETURNING id;")
IO="$TMP/inv1.$$"; IC="$TMP/inv2.$$"
# holder = UPDATE manual (authenticated) da linha EID: stmt trigger pega advisory
# ANTES de travar a tupla; segura a transação.
$PSQL -c "$AS_AUTH3 BEGIN; UPDATE public.profile_experiences SET title='Manual' WHERE id='$EID'; SELECT pg_sleep(5); COMMIT;" >"$IO" 2>&1 &
HP=$!
wait_for "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND granted;" "inversão: manual segurar lock"
# contender = RPC composta que UPDATEa a MESMA linha EID → advisory primeiro → bloqueia.
$PSQL -c "$AS_AUTH3 SELECT public.save_experience_with_bullets('$UX'::uuid, jsonb_build_object('id','$EID','title','RPC','company','C','start_date','2020-01-01','end_date','2021-01-01'));" >"$IC" 2>&1 &
CP=$!
wait_for "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND NOT granted;" "inversão: RPC bloquear"
wait "$HP"; wait "$CP"
no_deadlock "$IO" "inversão"; no_deadlock "$IC" "inversão"
ITITLE=$($PSQL -c "SELECT title FROM public.profile_experiences WHERE id='$EID';")
if [ "$ITITLE" = "RPC" ]; then
  echo "NOTICE:  T-CONC[inversão] OK: composite RPC vs UPDATE manual da mesma linha, sem deadlock (final '$ITITLE')"
else
  echo "FALHOU inversão: title='$ITITLE' (esperava 'RPC' — RPC roda após o manual commitar)"; exit 1
fi

# 7. DUAS candidatas em DUAS SESSÕES reais (apply_and_promote): serializam no lock;
#    exatamente 1 vira atual e o perfil casa com a vencedora (nunca dados de A com
#    B atual, nunca mistura). Ambas iniciam concorrentes; sem barreira de ordem.
UY='44444444-4444-4444-4444-444444444444'
AS_AUTH4="SET ROLE authenticated; SELECT set_config('request.jwt.claims','{\"sub\":\"$UY\"}',false);"
ATT_A='000000aa-0000-0000-0000-0000000000aa'; ATT_B='000000bb-0000-0000-0000-0000000000bb'
$PSQL -c "SELECT public._t_reset('$UY');" >/dev/null
CA=$($PSQL -c "SELECT public._t_seed_candidate('$UY'::uuid,'CA','{\"skills\":[{\"name\":\"ASkill\"}]}'::jsonb,'$ATT_A'::uuid);")
CB=$($PSQL -c "SELECT public._t_seed_candidate('$UY'::uuid,'CB','{\"skills\":[{\"name\":\"BSkill\"}]}'::jsonb,'$ATT_B'::uuid);")
SA="$TMP/s1.$$"; SB="$TMP/s2.$$"
$PSQL -c "$AS_AUTH4 SELECT public.apply_and_promote_imported_source('$CA'::uuid,'$ATT_A'::uuid);" >"$SA" 2>&1 &
PA=$!
$PSQL -c "$AS_AUTH4 SELECT public.apply_and_promote_imported_source('$CB'::uuid,'$ATT_B'::uuid);" >"$SB" 2>&1 &
PB=$!
# A PERDEDORA erra com profile_not_empty_use_review (esperado) → psql sai !=0.
# Toleramos esse exit; o que importa é o INVARIANTE + ausência de deadlock.
wait "$PA" || true; wait "$PB" || true
no_deadlock "$SA" "2-sessões"; no_deadlock "$SB" "2-sessões"
# exatamente uma das sessões deve ter sido rejeitada por profile_not_empty (a perdedora).
if ! grep -qE "profile_not_empty_use_review" "$SA" "$SB"; then
  echo "FALHOU 2-sessões: nenhuma perdedora rejeitada (as duas promoveram?)"; cat "$SA" "$SB"; exit 1
fi
NCUR=$($PSQL -c "SELECT count(*) FROM public.saved_resumes WHERE user_id='$UY' AND is_current_source;")
CURTITLE=$($PSQL -c "SELECT COALESCE(string_agg(title,','),'') FROM public.saved_resumes WHERE user_id='$UY' AND is_current_source;")
SKILLS=$($PSQL -c "SELECT COALESCE(string_agg(name,','),'') FROM public.profile_skills WHERE user_id='$UY';")
# invariante: exatamente 1 atual; skill do perfil casa com a candidata atual; sem mistura.
OKINV=no
if [ "$NCUR" = "1" ]; then
  if { [ "$CURTITLE" = "CA" ] && [ "$SKILLS" = "ASkill" ]; } || { [ "$CURTITLE" = "CB" ] && [ "$SKILLS" = "BSkill" ]; }; then OKINV=yes; fi
fi
if [ "$OKINV" = "yes" ]; then
  echo "NOTICE:  T-CONC[2-sessões apply] OK: 1 atual ($CURTITLE), perfil casa ($SKILLS), sem mistura, sem deadlock"
else
  echo "FALHOU 2-sessões: ncur=$NCUR cur='$CURTITLE' skills='$SKILLS'"; exit 1
fi

echo "ALL_SQL_TESTS_OK (combined 14→17; update/delete/upsert/fill×guided/service/janela/inversão/2-sessões, sem deadlock)"
