#!/usr/bin/env bash
# Fase 3 / Gate 3.0A — executa migration + testes em PostgreSQL efêmero.
# Não usa credenciais Supabase, não acessa rede e sempre apaga o cluster local.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PGPORT_TEST:-$((55000 + RANDOM % 5000))}"
TMP="$(mktemp -d)"
PGDATA="$TMP/pgdata"

cleanup() {
  pg_ctl -D "$PGDATA" -s -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

# ICU deixa lower()/comparações Unicode determinísticos no harness (Português,
# Inglês, Francês etc.), como no cluster Supabase, sem depender do locale do Mac.
initdb -D "$PGDATA" -U postgres \
  --locale-provider=icu --icu-locale=und -E UTF8 >/dev/null
pg_ctl -D "$PGDATA" -s -w \
  -o "-p $PORT -c listen_addresses='' -c unix_socket_directories='$TMP'" \
  start
createdb -h "$TMP" -p "$PORT" -U postgres profileguidedtest

PSQL=(psql -h "$TMP" -p "$PORT" -U postgres -d profileguidedtest)

echo "[profile-guided-write] migration + contratos"
"${PSQL[@]}" -v ON_ERROR_STOP=1 -q \
  -f "$ROOT/supabase/tests/profile_guided_write_foundation_test.sql"

# Concorrência real: um UPDATE autenticado direto segura o advisory adquirido
# pela trigger BEFORE STATEMENT. O merge guiado precisa esperar o mesmo lock e,
# ao final, preservar a edição manual e adicionar somente o item novo.
echo "[profile-guided-write] concorrência writer manual x RPC"
U='33333333-3333-3333-3333-333333333333'
AUTH="SET ROLE authenticated; SELECT set_config('request.jwt.claims','{\"sub\":\"$U\",\"role\":\"authenticated\"}',false);"
QUIET=("${PSQL[@]}" -v ON_ERROR_STOP=1 -qtA)

"${QUIET[@]}" -c \
  "INSERT INTO public.profile_skills(user_id,name,category) VALUES('$U','Manual Base','manual') ON CONFLICT DO NOTHING;" \
  >/dev/null

HOLDER_OUT="$TMP/holder.out"
RPC_OUT="$TMP/rpc.out"
"${QUIET[@]}" -c \
  "$AUTH BEGIN; UPDATE public.profile_skills SET category='manual-edited' WHERE user_id='$U' AND name='Manual Base'; SELECT pg_sleep(3); COMMIT;" \
  >"$HOLDER_OUT" 2>&1 &
HOLDER_PID=$!

wait_for_lock() {
  local mode="$1"
  local i count
  for i in $(seq 1 120); do
    count="$("${QUIET[@]}" -c "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND granted=$mode;" 2>/dev/null || echo 0)"
    if [ "${count:-0}" -ge 1 ] 2>/dev/null; then
      return 0
    fi
    sleep 0.05
  done
  echo "FALHOU: timeout esperando advisory granted=$mode"
  exit 1
}

wait_for_lock true
"${QUIET[@]}" -c \
  "$AUTH SELECT public.merge_guided_profile_list('$U'::uuid,'skills','[\"RPC Add\"]'::jsonb);" \
  >"$RPC_OUT" 2>&1 &
RPC_PID=$!
wait_for_lock false
wait "$HOLDER_PID"
wait "$RPC_PID"

if grep -qiE 'deadlock|40P01|lock timeout|canceling statement' \
  "$HOLDER_OUT" "$RPC_OUT"; then
  echo "FALHOU: deadlock/timeout na corrida"
  cat "$HOLDER_OUT" "$RPC_OUT"
  exit 1
fi

FINAL="$("${QUIET[@]}" -c \
  "SELECT string_agg(name||':'||COALESCE(category,''),',' ORDER BY name) FROM public.profile_skills WHERE user_id='$U' AND name IN ('Manual Base','RPC Add');")"
if [ "$FINAL" != 'Manual Base:manual-edited,RPC Add:' ]; then
  echo "FALHOU: estado concorrente inesperado: '$FINAL'"
  exit 1
fi

echo "PROFILE_GUIDED_WRITE_CONCURRENCY_OK"

# O editor abre com [Manual Base, RPC Add]. Enquanto o card está aberto, um
# INSERT manual real segura o advisory pela trigger. O CAS precisa esperar,
# observar o novo item e responder stale, sem remover/mesclar nada.
echo "[profile-guided-write] concorrência card CAS x writer manual"
CAS_HOLDER_OUT="$TMP/cas-holder.out"
CAS_OUT="$TMP/cas.out"
CAS_OP='45454545-4545-4454-8454-454545454545'
UC='44444444-4444-4444-8444-444444444444'
AUTH_C="SET ROLE authenticated; SELECT set_config('request.jwt.claims','{\"sub\":\"$UC\",\"role\":\"authenticated\"}',false);"
"${QUIET[@]}" -c \
  "INSERT INTO auth.users(id) VALUES('$UC') ON CONFLICT DO NOTHING; INSERT INTO public.profile_skills(user_id,name,order_index) VALUES('$UC','Manual Base',0),('$UC','RPC Add',1);" \
  >/dev/null
"${QUIET[@]}" -c \
  "$AUTH_C SELECT public.open_assist_skills_edit_v1('$UC'::uuid,'$CAS_OP'::uuid);" \
  >/dev/null
"${QUIET[@]}" -c \
  "$AUTH_C BEGIN; INSERT INTO public.profile_skills(user_id,name,order_index) VALUES('$UC','Manual Concurrent',2); SELECT pg_sleep(3); COMMIT;" \
  >"$CAS_HOLDER_OUT" 2>&1 &
CAS_HOLDER_PID=$!
wait_for_lock true
"${QUIET[@]}" -c \
  "$AUTH_C SELECT public.apply_assist_skills_edit_v1('$UC'::uuid,'$CAS_OP'::uuid,'[\"Manual Base\",\"RPC Add\"]'::jsonb,'[\"Manual Base\",\"SQL\"]'::jsonb)->>'outcome';" \
  >"$CAS_OUT" 2>&1 &
CAS_PID=$!
wait_for_lock false
wait "$CAS_HOLDER_PID"
wait "$CAS_PID"
if grep -qiE 'deadlock|40P01|lock timeout|canceling statement' \
  "$CAS_HOLDER_OUT" "$CAS_OUT"; then
  echo "FALHOU: deadlock/timeout na corrida CAS"
  cat "$CAS_HOLDER_OUT" "$CAS_OUT"
  exit 1
fi
CAS_RESULT="$(tail -n 1 "$CAS_OUT" | tr -d '[:space:]')"
CAS_FINAL="$("${QUIET[@]}" -c \
  "SELECT string_agg(name,',' ORDER BY order_index,name) FROM public.profile_skills WHERE user_id='$UC';")"
if [ "$CAS_RESULT" != 'stale' ] || \
   [ "$CAS_FINAL" != 'Manual Base,RPC Add,Manual Concurrent' ]; then
  echo "FALHOU: CAS concorrente result='$CAS_RESULT' final='$CAS_FINAL'"
  exit 1
fi
echo "PROFILE_ASSIST_SKILLS_CAS_CONCURRENCY_OK"

# Duas aberturas simultâneas do mesmo card compartilham um único recibo. A
# primeira fixa o baseline; a segunda espera o advisory e recebe replay.
echo "[profile-guided-write] concorrência open x open do mesmo operation_id"
OPEN_HOLDER_OUT="$TMP/open-holder.out"
OPEN_REPLAY_OUT="$TMP/open-replay.out"
OPEN_OP='46464646-4646-4464-8464-464646464646'
UO='55555555-5555-4555-8555-555555555555'
AUTH_O="SET ROLE authenticated; SELECT set_config('request.jwt.claims','{\"sub\":\"$UO\",\"role\":\"authenticated\"}',false);"
"${QUIET[@]}" -c \
  "INSERT INTO auth.users(id) VALUES('$UO') ON CONFLICT DO NOTHING; INSERT INTO public.profile_skills(user_id,name,order_index) VALUES('$UO','Baseline',0);" \
  >/dev/null
"${QUIET[@]}" -c \
  "BEGIN; SELECT pg_advisory_xact_lock(public.profile_write_lock_key('$UO'::uuid)); $AUTH_O SELECT public.open_assist_skills_edit_v1('$UO'::uuid,'$OPEN_OP'::uuid)->>'status'; SELECT pg_sleep(2); COMMIT;" \
  >"$OPEN_HOLDER_OUT" 2>&1 &
OPEN_HOLDER_PID=$!
wait_for_lock true
"${QUIET[@]}" -c \
  "$AUTH_O SELECT public.open_assist_skills_edit_v1('$UO'::uuid,'$OPEN_OP'::uuid)->>'status';" \
  >"$OPEN_REPLAY_OUT" 2>&1 &
OPEN_REPLAY_PID=$!
wait_for_lock false
wait "$OPEN_HOLDER_PID"
wait "$OPEN_REPLAY_PID"
if grep -qiE 'deadlock|40P01|lock timeout|canceling statement|duplicate key' \
  "$OPEN_HOLDER_OUT" "$OPEN_REPLAY_OUT"; then
  echo "FALHOU: erro na corrida open x open"
  cat "$OPEN_HOLDER_OUT" "$OPEN_REPLAY_OUT"
  exit 1
fi
OPEN_STATUSES="$(grep -hE '^(opened|replay)$' \
  "$OPEN_HOLDER_OUT" "$OPEN_REPLAY_OUT" | sort | paste -sd, -)"
OPEN_RECEIPTS="$("${QUIET[@]}" -c \
  "SELECT count(*) FROM public.profile_assist_skill_operations WHERE user_id='$UO' AND operation_id='$OPEN_OP';")"
if [ "$OPEN_STATUSES" != 'opened,replay' ] || [ "$OPEN_RECEIPTS" != '1' ]; then
  echo "FALHOU: open concorrente statuses='$OPEN_STATUSES' receipts='$OPEN_RECEIPTS'"
  cat "$OPEN_HOLDER_OUT" "$OPEN_REPLAY_OUT"
  exit 1
fi
echo "PROFILE_ASSIST_SKILLS_OPEN_CONCURRENCY_OK"

# O Edge continua chamando o writer canônico fenced instalado pela fundação de
# importação anterior. O Gate 3.0A não o renomeia. Este cenário instala o lock
# personal→skill e o caminho inverso skill→personal do trigger de completude;
# ambos precisam serializar sem ciclo.
echo "[profile-guided-write] concorrência writer service x writer manual"
SERVICE_OUT="$TMP/service.out"
MANUAL_OUT="$TMP/manual.out"
"${QUIET[@]}" -c \
  "SET ROLE service_role; SELECT public.save_profile_from_json('$U'::uuid,'{\"inject_skill\":\"Service Add\",\"hold_seconds\":\"3\"}'::jsonb);" \
  >"$SERVICE_OUT" 2>&1 &
SERVICE_PID=$!
wait_for_lock true
"${QUIET[@]}" -c \
  "$AUTH UPDATE public.profile_skills SET category='service-race-manual' WHERE user_id='$U' AND name='Manual Base';" \
  >"$MANUAL_OUT" 2>&1 &
MANUAL_PID=$!
wait_for_lock false
wait "$SERVICE_PID"
wait "$MANUAL_PID"

if grep -qiE 'deadlock|40P01|lock timeout|canceling statement' \
  "$SERVICE_OUT" "$MANUAL_OUT"; then
  echo "FALHOU: deadlock/timeout entre writer service e writer manual"
  cat "$SERVICE_OUT" "$MANUAL_OUT"
  exit 1
fi
SERVICE_FINAL="$("${QUIET[@]}" -c \
  "SELECT count(*) FROM public.profile_skills WHERE user_id='$U' AND ((name='Manual Base' AND category='service-race-manual') OR name='Service Add');")"
if [ "$SERVICE_FINAL" != '2' ]; then
  echo "FALHOU: writer service/manual perdeu estado"
  exit 1
fi
echo "PROFILE_GUIDED_WRITE_SERVICE_CONCURRENCY_OK"
