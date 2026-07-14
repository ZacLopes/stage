#!/usr/bin/env bash
# check_functions_drift.sh — Fase 1 T1.0 (ref. FASE-0 desvio #1, plano-mãe A1)
#
# Premissa quebrada na F0: "repo = deployado" não era verdade (generate-resume
# v40 rodava de cópia fora do repo; 6 functions ativas rodavam sem o wrapper
# withEdgeAnalytics; bundles com _shared/ defasado). Este script baixa o código
# DEPLOYADO de cada function ativa e difa contra supabase/functions/ — tanto o
# diretório da function quanto o _shared/ embarcado no bundle dela.
#
# Allowlists:
#  - arquivos só-no-repo que o bundler não embarca: *.md, sources/types.ts,
#    *.test.ts (testes deno colocados ao lado do entrypoint — nunca no bundle);
#  - functions DEPRECATED ficam fora (parse-cv, parse-cv-pdf, generate-profile
#    — T0.7; divergência delas é esperada e sem valor comportamental);
#  - módulos _shared que existem no repo mas a function não importa (aparecem
#    como "Only in <repo>/_shared" — ignorados).
#
# Roda LOCAL no checklist de release, ao lado de `supabase migration list`
# (sem secrets no GitHub — decisão do fundador, F0).
# Uso: bash scripts/check_functions_drift.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

PROJECT_REF=$(cat supabase/.temp/project-ref)
REPO_FN="supabase/functions"

ACTIVE=(
  adapt-resume-to-job analyze-match
  admin-me admin-overview admin-jobs admin-users admin-clients
  admin-candidate-lists admin-candidates-search admin-audit
  sync-jobs-apify sync-jobs-ats sync-jobs-brazil
  generate-resume generate-bullets generate-summary generate-profile-summary
  suggest-tools suggest-profile-skills
  extract-profile extract-job-skills interpret-step-answer trilha-assistant
  notifications-daily-digest notifications-broadcast
  notify-signup notify-auto-apply-swipe
  ingest-jobs-email daily-report
)

TMP=$(mktemp -d /tmp/stage-fn-drift.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
fail=0

for slug in "${ACTIVE[@]}"; do
  mkdir -p "$TMP/$slug"
  if ! (cd "$TMP/$slug" && supabase functions download "$slug" \
        --project-ref "$PROJECT_REF" >/dev/null 2>&1); then
    echo "DOWNLOAD FALHOU: $slug"
    fail=1
    continue
  fi
  dl="$TMP/$slug/supabase/functions"

  # 1. Diretório da function.
  fn_diff=$(diff -r "$REPO_FN/$slug" "$dl/$slug" 2>&1 \
    | grep -v "^Only in $REPO_FN/$slug.*\.md$" \
    | grep -v "^Only in $REPO_FN/$slug.*: types\.ts$" \
    | grep -v "^Only in $REPO_FN/$slug.*\.test\.ts$" || true)

  # 2. _shared embarcado no bundle (só os módulos que a function importa).
  sh_diff=""
  if [ -d "$dl/_shared" ]; then
    sh_diff=$(diff -rq "$REPO_FN/_shared" "$dl/_shared" 2>&1 \
      | grep -v "^Only in $REPO_FN/_shared" || true)
  fi

  if [ -n "$fn_diff$sh_diff" ]; then
    echo "DIVERGE: $slug"
    [ -n "$fn_diff" ] && echo "$fn_diff" | sed 's/^/    /' | head -4
    [ -n "$sh_diff" ] && echo "$sh_diff" | sed 's/^/    [_shared] /' | head -4
    fail=1
  else
    echo "ok: $slug"
  fi
done

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "check_functions_drift: FALHOU — reconcilie (revisar diff + deploy consciente do repo)."
  exit 1
fi
echo "check_functions_drift: OK (${#ACTIVE[@]} functions ativas, repo == deployado)"
