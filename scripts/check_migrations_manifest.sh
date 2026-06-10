#!/usr/bin/env bash
# check_migrations_manifest.sh — Fase 0 (T0.5, ref. auditoria C6/R2)
#
# Guarda de disciplina de migrations no CI SEM credenciais do banco:
# compara os arquivos em supabase/migrations/ com o manifest commitado.
# Pega migration adicionada/removida/renomeada sem registro consciente.
#
# A checagem REAL contra o remoto (`supabase migration list`) roda LOCAL,
# no checklist de release — decisão do fundador (sem secrets no GitHub).
#
# Uso:
#   bash scripts/check_migrations_manifest.sh           # verifica (CI)
#   bash scripts/check_migrations_manifest.sh --update  # regrava o manifest
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

manifest="supabase/migrations.manifest"
current=$(ls supabase/migrations/*.sql | xargs -n1 basename | sort)

if [ "${1:-}" = "--update" ]; then
  printf '%s\n' "$current" > "$manifest"
  echo "manifest atualizado: $(printf '%s\n' "$current" | wc -l | tr -d ' ') migrations"
  exit 0
fi

if [ ! -f "$manifest" ]; then
  echo "ERRO: $manifest não existe. Gere com: bash scripts/check_migrations_manifest.sh --update"
  exit 1
fi

if ! diff <(printf '%s\n' "$current") "$manifest" >/dev/null; then
  echo "ERRO: supabase/migrations/ diverge do manifest commitado:"
  diff <(printf '%s\n' "$current") "$manifest" || true
  echo ""
  echo "Se a mudança é intencional (migration nova via CLI — R2), atualize junto no mesmo commit:"
  echo "  bash scripts/check_migrations_manifest.sh --update"
  exit 1
fi
echo "check_migrations_manifest: OK ($(printf '%s\n' "$current" | wc -l | tr -d ' ') migrations)"
