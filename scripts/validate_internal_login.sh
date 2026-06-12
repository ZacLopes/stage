#!/usr/bin/env bash
# validate_internal_login.sh — FASE 2 (T2.0, verificação i do plano)
#
# Valida o signInWithPassword da conta interna convertida
# (phone_5500900000001@stage.app — ver convert_internal_account.sh) SEM a
# senha aparecer em argv/history/chat: read -s + payload via stdin.
# Usa só a ANON key (pública by design, mesma do .env do app).
#
# Uso: bash scripts/validate_internal_login.sh
# Saída esperada: "OK: HTTP 200, access_token presente."
set -euo pipefail

SUPABASE_URL="${SUPABASE_URL:-https://gaxfmniffjvwrwyunorl.supabase.co}"
SYNTH_EMAIL="phone_5500900000001@stage.app"

command -v jq >/dev/null 2>&1 || { echo "ERRO: jq não encontrado (brew install jq)."; exit 1; }

# ANON key: do ambiente ou do .env do repo (chave pública by design)
ANON_KEY="${SUPABASE_ANON_KEY:-}"
if [ -z "$ANON_KEY" ] && [ -f "$(dirname "$0")/../.env" ]; then
  ANON_KEY=$(grep -E '^SUPABASE_ANON_KEY=' "$(dirname "$0")/../.env" | cut -d= -f2- | tr -d '"' | tr -d "'")
fi
: "${ANON_KEY:?ERRO: SUPABASE_ANON_KEY não encontrada (env ou .env)}"

read -r -s -p "Senha da conta interna (não ecoa): " PW; echo

resp_file=$(mktemp)
trap 'rm -f "$resp_file"' EXIT

http_code=$(jq -n --arg email "$SYNTH_EMAIL" --arg pw "$PW" \
    '{email: $email, password: $pw}' \
  | curl -sS -o "$resp_file" -w '%{http_code}' \
      -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" \
      -H "apikey: $ANON_KEY" \
      -H "Content-Type: application/json" \
      --data-binary @-)

if [ "$http_code" = "200" ] && jq -e '.access_token | length > 0' "$resp_file" >/dev/null 2>&1; then
  echo "OK: HTTP 200, access_token presente."
else
  echo "FALHOU: HTTP $http_code"
  jq -r '.error_description // .msg // .error // "sem detalhe"' "$resp_file" 2>/dev/null | head -2 || true
  exit 1
fi
