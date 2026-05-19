#!/usr/bin/env bash
#
# posthog_annotate_deploy.sh
#
# Posta uma annotation no PostHog marcando o release atual. Lê a versão
# direto de pubspec.yaml (campo `version:`).
#
# Por quê: pré-fix, o projeto Stage estava fazendo 7 versões em 7 dias
# (1.1.0 → 1.5.2) sem nenhuma marcação. Comparações antes/depois de deploy
# viravam especulação. Com annotation no PostHog, qualquer insight mostra
# uma linha vertical no eixo do tempo indicando "aqui subiu v1.5.3".
#
# Uso (manual):
#   ./scripts/posthog_annotate_deploy.sh
#   ./scripts/posthog_annotate_deploy.sh "Hotfix: undo do swipe"
#
# Uso (CI/fastlane):
#   Após cada upload pro TestFlight/Play, chamar este script.
#   No GitHub Actions: armazenar Personal API Key em secret.
#
# Requisitos:
#   - curl
#   - POSTHOG_PERSONAL_API_KEY env var (PostHog Personal API Key com escopo
#     annotation:write). NÃO é o mesmo que o phc_xxx do .env — esse aqui é
#     uma chave PESSOAL gerada em /settings/user-api-keys.
#   - POSTHOG_PROJECT_ID env var (opcional, default: 419792 = Stage)
#   - POSTHOG_HOST env var (opcional, default: https://us.posthog.com)

set -euo pipefail

POSTHOG_HOST="${POSTHOG_HOST:-https://us.posthog.com}"
POSTHOG_PROJECT_ID="${POSTHOG_PROJECT_ID:-419792}"
EXTRA_NOTE="${1:-}"

if [[ -z "${POSTHOG_PERSONAL_API_KEY:-}" ]]; then
  echo "ERROR: POSTHOG_PERSONAL_API_KEY env var não setada." >&2
  echo "Gere uma Personal API Key em $POSTHOG_HOST/settings/user-api-keys com escopo annotation:write." >&2
  echo "Depois rode: export POSTHOG_PERSONAL_API_KEY=phx_..." >&2
  exit 1
fi

# Localiza pubspec.yaml a partir do dir do script (../pubspec.yaml).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBSPEC="$SCRIPT_DIR/../pubspec.yaml"

if [[ ! -f "$PUBSPEC" ]]; then
  echo "ERROR: pubspec.yaml não encontrado em $PUBSPEC" >&2
  exit 1
fi

# Extrai versão (formato: "version: 1.5.2+1")
VERSION=$(grep -E '^version:' "$PUBSPEC" | sed 's/^version:[[:space:]]*//; s/[[:space:]]*$//')

if [[ -z "$VERSION" ]]; then
  echo "ERROR: linha 'version:' não encontrada em $PUBSPEC" >&2
  exit 1
fi

# ISO 8601 UTC com sufixo Z.
NOW="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

CONTENT="Stage app v$VERSION"
if [[ -n "$EXTRA_NOTE" ]]; then
  CONTENT="$CONTENT — $EXTRA_NOTE"
fi

# scope=project: aparece em todas insights/dashboards do projeto.
# date_marker: timestamp visível no gráfico.
PAYLOAD=$(printf '{"content":"%s","date_marker":"%s","scope":"project"}' \
  "$CONTENT" "$NOW")

echo "→ Posting annotation: $CONTENT"

HTTP_CODE=$(curl -s -o /tmp/posthog_annotation.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $POSTHOG_PERSONAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$POSTHOG_HOST/api/projects/$POSTHOG_PROJECT_ID/annotations/")

if [[ "$HTTP_CODE" =~ ^2 ]]; then
  echo "✓ Annotation criada ($HTTP_CODE)"
  exit 0
else
  echo "✗ Falha ao criar annotation (HTTP $HTTP_CODE):" >&2
  cat /tmp/posthog_annotation.json >&2
  exit 1
fi
