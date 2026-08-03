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

# ── 1b. Segredo pelo VALOR, não pelo nome da variável ───────────────────
# Por que existe: em 02/08/2026 o `.env` carregava a chave SECRETA do Supabase
# (`sb_secret_…`, a que ignora RLS) dentro de `SUPABASE_ANON_KEY`, e este script
# passava VERDE. O bloco 1 só olha o NOME da variável — e "SUPABASE_ANON_KEY"
# não casa com (OPENAI|SERVICE_ROLE|SECRET|…). O bloco 3b só decodifica JWT
# `eyJ…` — e as chaves novas do Supabase são opacas, não são JWT. O valor
# escapava dos dois. Aqui a checagem é sobre o VALOR.
for f in .env .env.example; do
  [ -f "$f" ] || continue
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    n=${hit%%:*}
    var=$(printf '%s' "${hit#*:}" | cut -d= -f1)
    echo "ERRO [$f:$n]: variável '$var' contém um segredo pelo formato do VALOR"
    echo "       (prefixo proibido: sb_secret_ / sk- / sk_live_ / re_ / apify_api_)"
    echo "       lembre: este arquivo embarca no IPA — só chave pública-by-design."
    fail=1
  done <<EOF
$(grep -nE '^[[:space:]]*[A-Za-z_]+=[[:space:]]*(sb_secret_|sk-[A-Za-z0-9]|sk_live_|re_[A-Za-z0-9]|apify_api_)' "$f" || true)
EOF
done

# ── 1c. SUPABASE_ANON_KEY tem que ser publicável (allowlist, não denylist) ──
# Denylist sempre atrasa em relação a formato novo de chave. Esta asserção é
# positiva: o valor PRECISA ser `sb_publishable_…` ou um JWT com role=anon.
# Qualquer outra coisa falha, inclusive um formato que ainda não existe.
if [ -f .env ]; then
  akey=$(grep -E '^[[:space:]]*SUPABASE_ANON_KEY=' .env | head -1 | cut -d= -f2- | tr -d '[:space:]' || true)
  if [ -n "$akey" ]; then
    ok=0
    case "$akey" in
      sb_publishable_*) ok=1 ;;
      eyJ*)
        pl=$(printf '%s' "$akey" | cut -d. -f2)
        dec=$(python3 -c "
import base64, sys
s = sys.argv[1]; s += '=' * (-len(s) % 4)
try: print(base64.urlsafe_b64decode(s).decode('utf-8','ignore'))
except Exception: pass
" "$pl" 2>/dev/null || true)
        printf '%s' "$dec" | grep -q '"role"[[:space:]]*:[[:space:]]*"anon"' && ok=1
        ;;
    esac
    if [ "$ok" -ne 1 ]; then
      echo "ERRO [.env]: SUPABASE_ANON_KEY não é uma chave publicável."
      echo "       esperado: 'sb_publishable_…' ou JWT com role=anon."
      echo "       recebido: prefixo '$(printf '%s' "$akey" | cut -c1-13)…' (${#akey} chars)."
      echo "       o .env embarca no IPA: chave secreta ali = banco aberto a quem baixar o app."
      fail=1
    fi
  fi
fi

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

# 3c. Chave SECRETA do Supabase (formato novo, opaco): proibida em qualquer
# arquivo rastreado. Não é JWT, então o 3b nunca a veria.
sb_hits=$(git grep -lIE 'sb_secret_[A-Za-z0-9_-]{10,}' -- . "${EXCLUDES[@]}" || true)
if [ -n "$sb_hits" ]; then
  echo "ERRO: chave SECRETA do Supabase (sb_secret_...) em arquivo rastreado:"
  echo "$sb_hits"
  echo "       ela ignora RLS — trate como incidente: rotacione no painel antes de mais nada."
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
