# ingest-jobs-email — Setup

Ingestão de vagas via emails encaminhados (caso 1: Polifinance, 1 vaga/email, imagem).

Pipeline:
```
Email Polifinance → Outlook (Zac)
  └─ regra: forward pra vagas@inbound.stagevagas.app
       └─ Resend Inbound recebe
            └─ webhook POST → ingest-jobs-email
                 ├─ GPT-4o vision extrai vaga da imagem
                 ├─ upsert companies + jobs (source='polifinance')
                 └─ application_method='email', application_email=...
```

## 1. Migration

```bash
supabase db push
```

Aplica `20260527000002_add_email_application_to_jobs.sql`:
- `application_method` (`'url'|'email'`, default `'url'`)
- `application_email`, `application_subject`
- CHECK constraint: se method='email', email obrigatório

## 2. Deploy da edge function

```bash
cd career_gamification
supabase functions deploy ingest-jobs-email --no-verify-jwt
```

`--no-verify-jwt` é obrigatório — o Resend não manda JWT. A autenticação é via assinatura Svix do payload.

## 3. Secrets necessários

`RESEND_API_KEY` e `OPENAI_API_KEY` já existem. Faltam:

```bash
# Whsec... vai aparecer no painel quando criar o webhook (passo 5)
supabase secrets set RESEND_INBOUND_WEBHOOK_SECRET=whsec_xxx

# Opcional — regex de remetentes aceitos. Default "polifinance"
supabase secrets set POLIFINANCE_ALLOWED_SENDERS="polifinance|outroboletim"
```

## 4. DNS — receber email no stagevagas.app

No DNS de `stagevagas.app` (provedor do domínio):

| Tipo | Nome | Valor | TTL |
|---|---|---|---|
| MX | `inbound` | `feedback-smtp.us-east-1.amazonses.com` (priority 10) | 300 |
| TXT | `inbound` | `"v=spf1 include:amazonses.com ~all"` | 300 |

(Resend usa SES por baixo dos panos — confirmar valores exatos no painel do Resend após criar o domínio inbound.)

Endereço final: `vagas@inbound.stagevagas.app`

## 5. Resend Dashboard

1. Domains → Add domain → `inbound.stagevagas.app` → marcar como **inbound**
2. Verificar DNS (passo 4)
3. Webhooks → Add endpoint:
   - URL: `https://gaxfmniffjvwrwyunorl.supabase.co/functions/v1/ingest-jobs-email`
   - Events: `email.received` apenas
   - Copiar o **Signing Secret** (`whsec_...`) → setar como `RESEND_INBOUND_WEBHOOK_SECRET` (passo 3)
4. Receiving → Add address: `vagas@inbound.stagevagas.app`

## 6. Regra no Outlook

Outlook web → Settings → Mail → Rules → Add new rule:

- **Name**: Forward Polifinance pra Stage
- **Condition**: From contains `polifinance`
- **Action 1**: Forward to `vagas@inbound.stagevagas.app`
- **Action 2** (opcional): Move to folder "Polifinance/ingerido"

⚠️ Outlook às vezes adiciona prefixo "Fwd:" ao subject — o parser GPT-4o lida com isso (extrai do conteúdo da imagem, não do subject).

## 7. Teste end-to-end

```bash
# Trigger manual (sem precisar receber email):
curl -X POST \
  -H "Authorization: Bearer $SERVICE_ROLE" \
  -H "Content-Type: application/json" \
  -H "svix-id: msg_test" \
  -H "svix-timestamp: $(date +%s)" \
  https://gaxfmniffjvwrwyunorl.supabase.co/functions/v1/ingest-jobs-email \
  -d '{"type":"email.received","data":{...}}'
# (signature check vai falhar se RESEND_INBOUND_WEBHOOK_SECRET estiver setado)
```

Pra teste real: encaminhar um email da Polifinance manualmente pro endereço.

Logs:
```bash
supabase functions logs ingest-jobs-email --tail
```

Procurar por `event:"job_ingested"` no JSON do console.log pra confirmar sucesso.

## 8. Verificar no banco

```sql
SELECT
  j.title,
  c.name AS company,
  j.application_method,
  j.application_email,
  j.application_subject,
  j.deadline,
  j.area,
  j.created_at
FROM jobs j
JOIN companies c ON c.id = j.company_id
WHERE j.source = 'polifinance'
ORDER BY j.created_at DESC
LIMIT 10;
```

## Custos

| Item | Custo |
|---|---|
| Resend Inbound (free tier) | $0 até 100/dia |
| OpenAI GPT-4o vision | ~$0.005-0.01 por email (1 imagem detail=high) |
| Edge Function invocation | desprezível |
| **Total estimado** | **~$0.30/mês** (1 email/dia da Polifinance) |

## Próximos passos (não MVP)

- Logo da empresa: extrair também via vision (pular pra MVP)
- Substituir `[SEU NOME]` no `application_subject` pelo nome do usuário ao montar mailto (hoje fica literal — usuário precisa editar antes de enviar)
- Detecção de duplicatas: se a Polifinance reenviar a mesma vaga em dias diferentes, vira 2 jobs (external_id = email_id Resend). Mitigar via hash de (company_name + title) normalizado
- Suportar outras newsletters de vagas: ajustar `POLIFINANCE_ALLOWED_SENDERS` ou criar source separada
