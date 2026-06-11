#!/usr/bin/env bash
# check_functions_types.sh — Fase 1 (fechamento, item 3).
#
# `deno check` em todos os entrypoints das edge functions: valida PARSE
# (classe "parêntese do wrapper" — 4 ocorrências até hoje) + tipos grossos
# (config relaxada em scripts/deno-check.jsonc; strict é dívida futura).
#
# Exclusão documentada: adapt-resume-to-job (index.ts + v2.ts) — o backlog
# de tipos do pipeline de adaptação só será pago junto com uma rodada de
# golden_set (R5: qualquer toque no adapt exige o harness antes/depois;
# casts cosméticos não valem o risco/cerimônia). Parse do adapt continua
# coberto indiretamente: o bundler do deploy falha em parse error.
#
# Roda no CI (job functions-check) e localmente:
#   bash scripts/check_functions_types.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

if ! command -v deno >/dev/null 2>&1; then
  echo "deno não encontrado — instale (https://deno.land) ou rode só no CI."
  exit 1
fi

# Dirs de function são kebab-case sem espaços — expansão simples é segura.
FILES=$(ls supabase/functions/*/index.ts | grep -v "adapt-resume-to-job")

# shellcheck disable=SC2086
deno check --config=scripts/deno-check.jsonc $FILES
echo "check_functions_types: OK ($(echo "$FILES" | wc -l | tr -d ' ') entrypoints; adapt excluído — ver header)"
