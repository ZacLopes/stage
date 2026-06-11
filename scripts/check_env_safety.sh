#!/usr/bin/env bash
# check_env_safety.sh — Fase 0 (T0.1, ref. auditoria M1)
#
# Impede que segredo de SERVIDOR chegue ao repo ou ao bundle do app:
#  1. `.env`/`.env.example` não podem conter chave de servidor (o `.env` é
#     empacotado como asset do app — pubspec.yaml — e viaja dentro do IPA;
#     só chaves públicas-by-design podem viver nele).
#  2. `.env` nunca pode estar rastreado pelo git.
#  3. Nenhum arquivo rastreado pode conter chave OpenAI (`sk-...`) nem JWT
#     com `"role":"service_role"`. JWTs com role anon são públicos by design
#     (a anon key está cozida no bundle do admin_dashboard, por exemplo) e
#     por isso o JWT é DECODIFICADO antes de condenar.
#
# Roda no CI (.github/workflows/ci.yml) e no pre-commit (scripts/githooks).
# Uso: bash scripts/check_env_safety.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

fail=0

# ── 1. Chaves de servidor proibidas no .env/.env.example ───────────────
for f in .env .env.example; do
  [ -f "$f" ] || continue
  bad=$(grep -nE '^[[:space:]]*[A-Z_]*(OPENAI|SERVICE_ROLE|SECRET|RESEND|APIFY|NTFY)[A-Z_]*=' "$f" || true)
  if [ -n "$bad" ]; then
    echo "ERRO [$f]: contém chave de servidor proibida (esse arquivo embarca no bundle do app):"
    echo "$bad"
    fail=1
  fi
done

# ── 2. .env nunca rastreado pelo git ────────────────────────────────────
if git ls-files --error-unmatch .env >/dev/null 2>&1; then
  echo "ERRO: .env está rastreado pelo git — remova com 'git rm --cached .env'."
  fail=1
fi

# ── 3. Valores de segredo em arquivos rastreados ────────────────────────
# Exclusões: artefatos/bundles onde a anon key (pública) é esperada e lockfiles.
EXCLUDES=(
  ':(exclude)admin_dashboard/dist'
  ':(exclude)admin_dashboard/node_modules'
  ':(exclude)build'
  ':(exclude)ios/Pods'
  ':(exclude).dart_tool'
  ':(exclude)*.lock'
  ':(exclude)scripts/check_env_safety.sh'
)

# 3a. Chave OpenAI: proibida sempre, em qualquer arquivo rastreado.
sk_hits=$(git grep -nIE 'sk-[A-Za-z0-9]{20,}' -- . "${EXCLUDES[@]}" || true)
if [ -n "$sk_hits" ]; then
  echo "ERRO: possível chave OpenAI (sk-...) em arquivo rastreado:"
  echo "$sk_hits"
  fail=1
fi

# 3b. JWTs: decodifica o payload e falha SÓ se role=service_role.
jwt_tokens=$(git grep -hoIE 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' -- . "${EXCLUDES[@]}" 2>/dev/null | sort -u || true)
if [ -n "$jwt_tokens" ]; then
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    payload=$(printf '%s' "$tok" | cut -d. -f2)
    decoded=$(python3 -c "
import base64, sys
s = sys.argv[1]
s += '=' * (-len(s) % 4)
try:
    print(base64.urlsafe_b64decode(s).decode('utf-8', 'ignore'))
except Exception:
    pass
" "$payload" 2>/dev/null || true)
    if printf '%s' "$decoded" | grep -q '"role"[[:space:]]*:[[:space:]]*"service_role"'; then
      echo "ERRO: JWT com role=service_role em arquivo rastreado. Ocorrências:"
      git grep -lF "$tok" -- . "${EXCLUDES[@]}" || true
      fail=1
    fi
  done <<< "$jwt_tokens"
fi

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "check_env_safety: FALHOU — corrija antes de commitar/mergear."
  exit 1
fi
echo "check_env_safety: OK"
