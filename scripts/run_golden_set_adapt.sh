#!/usr/bin/env bash
# Bateria reguladora do pipeline ADAPT (R5).
#
# Rode ANTES e DEPOIS de qualquer mudança em:
#   - supabase/functions/adapt-resume-to-job/v2.ts   (validador, prompt, schema)
#   - supabase/functions/_shared/cv_text.ts          (normalize/tokenize — o
#                                                     validador inteiro depende)
#
# Qualquer caso [ADV] falhando é BLOQUEANTE: não faça deploy.
#
# Por que `--no-check`: `v2.ts` tem 2 erros de tipo PRÉ-EXISTENTES (o import
# 'supabase' via import map e um `unknown` no laço de languages). É a mesma
# razão pela qual o adapt está excluído por nome do check_functions_types.sh.
# Trocar isso é dívida à parte — não silencia nada desta bateria, que é runtime.
set -euo pipefail

cd "$(dirname "$0")/.."

deno run \
  --no-check \
  --allow-env \
  --allow-read \
  --import-map=supabase/functions/import_map.json \
  golden_set/adapt/runner.ts
