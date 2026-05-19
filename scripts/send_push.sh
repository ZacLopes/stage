#!/usr/bin/env bash
#
# send_push.sh — Dispara uma push broadcast pra todos os users do Stage.
#
# Uso:
#   ./scripts/send_push.sh "Título" "Mensagem"
#   ./scripts/send_push.sh "Título" "Mensagem" --segment "Active Users"
#   ./scripts/send_push.sh "Título" "Mensagem" --dry-run     # só simula
#
# Segmentos disponíveis:
#   "Subscribed Users" (default) — TODOS com push ativo
#   "Active Users"               — login últimos 7 dias (mais relevante)
#   "Engaged Users"              — abriu push recente
#
# Requisitos:
#   - .env com SUPABASE_URL e SUPABASE_ANON_KEY (já existe, foi setado em main.dart)
#   - bash, curl, jq (opcional, deixa o output legível)
#
# Exemplos:
#   ./scripts/send_push.sh "🚀 Vagas novas" "12 vagas em Marketing chegaram"
#   ./scripts/send_push.sh "📊 Update" "Adicionamos filtro de remoto" --segment "Active Users"
#   ./scripts/send_push.sh "teste" "validando" --dry-run

set -euo pipefail

# Carrega .env
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env não encontrado em $ENV_FILE" >&2
  exit 1
fi
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "ERROR: SUPABASE_URL ou SUPABASE_ANON_KEY ausente no .env" >&2
  exit 1
fi

# Parse args
TITLE="${1:-}"
MESSAGE="${2:-}"
SEGMENT="Subscribed Users"
DRY_RUN="false"

if [[ -z "$TITLE" || -z "$MESSAGE" ]]; then
  cat <<EOF >&2
Uso: $0 "Título" "Mensagem" [--segment "Nome"] [--dry-run]

Exemplos:
  $0 "🚀 Vagas novas" "12 em Marketing chegaram"
  $0 "📊 Update" "Nova feature" --segment "Active Users"
  $0 "teste" "validando" --dry-run
EOF
  exit 1
fi

shift 2 || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --segment)
      SEGMENT="$2"; shift 2 ;;
    --dry-run)
      DRY_RUN="true"; shift ;;
    *)
      echo "ERROR: argumento desconhecido: $1" >&2
      exit 1 ;;
  esac
done

URL="$SUPABASE_URL/functions/v1/notifications-broadcast"

# Confirmação antes de mandar de verdade
if [[ "$DRY_RUN" == "false" ]]; then
  echo "Vai disparar:"
  echo "  Title:   $TITLE"
  echo "  Message: $MESSAGE"
  echo "  Segment: $SEGMENT"
  echo ""
  read -p "Confirma envio pra TODOS os users do segmento? [y/N] " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelado."
    exit 0
  fi
fi

# Monta o JSON body com jq se disponível (mais robusto pra escape), senão printf
if command -v jq >/dev/null 2>&1; then
  PAYLOAD=$(jq -nc \
    --arg t "$TITLE" \
    --arg m "$MESSAGE" \
    --arg s "$SEGMENT" \
    --argjson d "$DRY_RUN" \
    '{title:$t, message:$m, segment:$s, dryRun:$d}')
else
  # Fallback: cuidado com aspas/caracteres especiais no title/message
  PAYLOAD=$(printf '{"title":"%s","message":"%s","segment":"%s","dryRun":%s}' \
    "$TITLE" "$MESSAGE" "$SEGMENT" "$DRY_RUN")
fi

echo "→ Posting to $URL"
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "$URL" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" =~ ^2 ]]; then
  echo "✓ HTTP $HTTP_CODE"
else
  echo "✗ HTTP $HTTP_CODE"
fi

if command -v jq >/dev/null 2>&1; then
  echo "$BODY" | jq .
else
  echo "$BODY"
fi
