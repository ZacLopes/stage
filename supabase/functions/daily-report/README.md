# daily-report

Edge Function que monta e envia o **relatório diário do Stage**: email rico via Resend + teaser via ntfy.sh.

Roda **todo dia às 10h UTC (7h BRT)** via `pg_cron`. Aos domingos (UTC), adiciona um bloco de resumo dos últimos 7 dias com WoW.

## O que o relatório cobre

- **Usuários novos** (D-1): total + delta, top faculdades / cursos / semestres, taxas de AI consent / telefone / conclusão de onboarding e conclusão da trilha de currículo
- **Engajamento**: DAU (swipes), CV adapters, appliers
- **Vagas inseridas** (D-1): total + delta, por área / fonte / empresa / modelo / tipo / cidade
- **Estoque atual**: vagas ativas totais, idade média, % de vagas aplicáveis (URL ou email), top áreas
- **Match & engajamento**: curtidas, aplicações reais, conversão swipe→apply, top 5 vagas/empresas curtidas, match score médio
- **CV adaptado**: total e por área da vaga
- **Gap oferta vs demanda**: áreas com mais curtidas que vagas no estoque
- **Saúde**: chamadas IA e tokens consumidos
- **Semanal (domingos)**: cadastros / vagas / curtidas / aplicações dos últimos 7d com WoW

## Setup (uma vez)

### 1. Criar conta no Resend

1. Vai em https://resend.com → cria conta
2. **(Opcional, recomendado)** Verifica domínio próprio (ex: `stage-app.com.br`) em Domains → adiciona DNS records. Sem domínio, usa o sandbox `onboarding@resend.dev` (entrega só pra você).
3. Em **API Keys**, cria uma key com permissão "Sending access". Copia o valor `re_xxxxxxxx`.

### 2. Configurar secrets na Edge Function

```bash
cd career_gamification

supabase secrets set RESEND_API_KEY=re_xxxxxxxxxxxxxxxxxxxx
supabase secrets set REPORT_EMAIL_FROM="Stage <reports@stage-app.com.br>"
# Se não verificou domínio ainda:
# supabase secrets set REPORT_EMAIL_FROM="Stage <onboarding@resend.dev>"

supabase secrets set REPORT_EMAIL_TO="voce@email.com,socio@email.com"

# Pode usar o MESMO topic do notify-signup ou criar um novo dedicado.
# Topic novo: invente uma string aleatória, ex.:
supabase secrets set NTFY_TOPIC_REPORT="stage-reports-9k7d2f3a"
```

> `CRON_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` e `POSTHOG_API_KEY` já existem do digest — não precisa setar de novo.

### 3. Deploy

```bash
supabase functions deploy daily-report
```

### 4. Aplicar a migration de pg_cron

```bash
supabase db push
```

Ou aplicar direto as migrations do `daily-report` no projeto remoto. A migration
`20260601000000_fix_daily_report_cron_timeout.sql` reagenda o cron com timeout de
30s no `pg_net`.

### 5. Subscribe no ntfy (iPhone)

App ntfy.sh → Add subscription → cola o topic (mesmo valor de `NTFY_TOPIC_REPORT`).

## Testar localmente

```bash
supabase functions serve daily-report

curl -X POST http://localhost:54321/functions/v1/daily-report \
  -H "Authorization: Bearer <anon-key-do-projeto>" \
  -H "x-cron-secret: <CRON_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"dryRun": true}'
```

Retorna JSON com `summary`, `ntfy` e `htmlPreview` sem enviar nada.

## Disparar manual em produção (sem esperar 7h BRT)

```bash
# Via curl com cron secret:
curl -X POST https://gaxfmniffjvwrwyunorl.supabase.co/functions/v1/daily-report \
  -H "Authorization: Bearer <anon-key-do-projeto>" \
  -H "x-cron-secret: <CRON_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"dryRun": false}'

# Ou via SQL (re-usa o mesmo path do pg_cron):
SELECT net.http_post(
  url := 'https://gaxfmniffjvwrwyunorl.supabase.co/functions/v1/daily-report',
  headers := jsonb_build_object(
    'Content-Type','application/json',
    'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_anon_key'),
    'x-cron-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'cron_secret_jobs_sync')
  ),
  body := '{}'::jsonb,
  timeout_milliseconds := 30000
);
```

## Perfil educacional, onboarding e trilha

- Universidade/curso/semestre usam primeiro as tabelas novas
  (`profile_education`, `profile_education_majors`, `current_semester`),
  priorizando a linha de faculdade e ignorando a linha de escola.
- Se o usuário ainda não tem educação migrada, o relatório cai para o legado:
  `user_profiles.gamification_data.university`, `user_profiles.course` e
  `user_profiles.semester`.
- A taxa de onboarding concluído usa o mesmo flag operacional do app:
  existência de uma linha em `campaigns` para o usuário. Esse é o que o
  `AuthGate` usa como "onboarding finalizado" após `createCampaign`.
- A taxa de trilha completa é separada: usuário só entra quando tem
  `user_progress.completed = true` para todas as fases cadastradas em `phases`.

## Forçar modo semanal (sem esperar domingo)

```bash
curl ... -d '{"weeklyDigest": true}'
```

## Verificar agendamento

```sql
SELECT jobname, schedule, command FROM cron.job WHERE jobname = 'daily-report';

SELECT status, start_time, end_time, return_message
FROM cron.job_run_details
WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'daily-report')
ORDER BY start_time DESC LIMIT 5;
```

## Trocar destinatário

Sem precisar redeploy:

```bash
supabase secrets set REPORT_EMAIL_TO="outro@email.com"
```

Ou override via body do request:

```bash
curl ... -d '{"targetEmail": "outro@email.com"}'
```

## Como funcionam as janelas de tempo

- **Ontem** = `[ontem 00:00 BRT, hoje 00:00 BRT)`
- **Anteontem** = janela equivalente de D-2 pra calcular delta
- **Últimos 7 dias** = `[hoje-7d 00:00 BRT, hoje 00:00 BRT)`
- **Semana anterior** = `[hoje-14d 00:00 BRT, hoje-7d 00:00 BRT)`

BRT é assumido como UTC-3 fixo (sem DST desde 2019).
