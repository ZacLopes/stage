#!/usr/bin/env bash
# convert_internal_account.sh — FASE 2 (T2.0 do PLANO-FASE-2)
#
# Converte a conta interna de teste (internal-fase0-test@stage.app,
# user 3eaf8faa-a905-4d80-aced-40be7781f623) pro e-mail sintético de
# telefone, permitindo o fundador logar num DEVICE físico pelo fluxo
# normal do app: digita telefone + senha → signup detecta "already
# registered" → fallback automático pra signIn (caminho confirmado no
# B11 do plano: user_viewmodel.dart:580-585).
#
# Telefone sintético escolhido (decisão do fundador, 12/06):
#   +55 (00) 90000-0001 → phone_5500900000001@stage.app
#   (formato de phone_auth_helpers.dart; prefixo 55 ∈ {351,55,44,1} ✓)
#
# `user_id` é PRESERVADO → FKs e dados semeados (área "Tecnologia",
# gate de onboarding) ficam intactos.
#
# SEGURANÇA (regras desta sessão de execução):
#   - SERVICE_ROLE entra SÓ via ambiente: export no shell, nunca em
#     arquivo, nunca em argv (não aparece em `ps`).
#   - A senha é pedida via `read -s`: sem eco, sem shell history; o
#     payload viaja pro curl via stdin (também fora do argv).
#   - Nada além de status/email é impresso.
#
# Uso (no terminal do fundador):
#   export SERVICE_ROLE=<service-role-key>    # dashboard → Settings → API
#   bash scripts/convert_internal_account.sh
#   unset SERVICE_ROLE                        # higiene pós-uso
set -euo pipefail

USER_ID="3eaf8faa-a905-4d80-aced-40be7781f623"
SUPABASE_URL="${SUPABASE_URL:-https://gaxfmniffjvwrwyunorl.supabase.co}"
SYNTH_EMAIL="phone_5500900000001@stage.app"

command -v jq >/dev/null 2>&1 || { echo "ERRO: jq não encontrado (brew install jq)."; exit 1; }
: "${SERVICE_ROLE:?ERRO: export SERVICE_ROLE=<service-role-key> antes de rodar}"

read -r -s -p "Nova senha da conta interna (não ecoa): " NEW_PW; echo
read -r -s -p "Confirme a senha: " NEW_PW2; echo
[ "$NEW_PW" = "$NEW_PW2" ] || { echo "ERRO: senhas não conferem."; exit 1; }
[ "${#NEW_PW}" -ge 10 ] || { echo "ERRO: senha muito curta (mínimo 10 caracteres)."; exit 1; }

resp_file=$(mktemp)
trap 'rm -f "$resp_file"' EXIT

# jq monta o JSON (escapa a senha com segurança) e entrega via stdin.
http_code=$(jq -n --arg email "$SYNTH_EMAIL" --arg pw "$NEW_PW" \
    '{email: $email, password: $pw, email_confirm: true}' \
  | curl -sS -o "$resp_file" -w '%{http_code}' \
      -X PUT "$SUPABASE_URL/auth/v1/admin/users/$USER_ID" \
      -H "apikey: $SERVICE_ROLE" \
      -H "Authorization: Bearer $SERVICE_ROLE" \
      -H "Content-Type: application/json" \
      --data-binary @-)

if [ "$http_code" = "200" ]; then
  echo "OK: conta convertida (HTTP 200)."
  echo "Email agora: $(jq -r '.email // "?"' "$resp_file")"
  echo "Próximo passo: no app, entrar com telefone (00) 90000-0001 + a senha."
else
  echo "FALHOU: HTTP $http_code"
  jq -r '.msg // .message // .error_description // .' "$resp_file" 2>/dev/null | head -3 || true
  exit 1
fi
