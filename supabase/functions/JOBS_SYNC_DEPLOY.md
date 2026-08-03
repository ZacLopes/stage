# Deploy do sistema de sync de vagas

Sistema novo (2026-05-06) que popula a tabela `jobs` com vagas reais via:
- **Apify Gupy scraper** (estágio/aprendiz/trainee, ~2.500+ vagas BR ativas)
- **Greenhouse + Lever boards públicos** (~50-150 vagas premium de tech/scale-up)

Custo recorrente: **~$5-30/mês** (Apify, dependendo de `maxResults` e frequência).

## Pré-requisitos

- Conta Apify com plano FREE (já criada — `stageapp`)
- Acesso ao Supabase Dashboard do projeto `gaxfmniffjvwrwyunorl`
- CLI Supabase instalada e linked: `supabase link --project-ref gaxfmniffjvwrwyunorl`

## 1. Aplicar migrations

Aplicar via SQL Editor do Dashboard (recomendado, dada a divergência histórica
de migrations resolvida em 2026-05-04):

**a)** Cola o conteúdo de `supabase/migrations/20260506_external_jobs_setup.sql` e roda.

**b)** No SQL Editor, gere um secret aleatório:

```sql
SELECT encode(gen_random_bytes(32), 'hex') AS cron_secret;
-- copia o valor retornado, vamos usar nos passos 2 e 3
```

## 2. Setar secrets das Edge Functions

```bash
# Apify token (pode rotacionar depois)
supabase secrets set APIFY_API_TOKEN=<APIFY_TOKEN>

# Cron secret (use o valor gerado no passo 1.b)
supabase secrets set CRON_SECRET=<cole_aqui_o_hex_de_64_chars>

# Verificar
supabase secrets list
```

## 3. Salvar CRON_SECRET no Vault do Postgres (pra pg_cron usar)

No SQL Editor:

```sql
SELECT vault.create_secret(
  '<MESMO_HEX_DE_64_CHARS_DO_PASSO_1.b>',
  'cron_secret_jobs_sync',
  'Shared secret pg_cron → Edge Functions sync-jobs-*'
);
```

## 4. Deploy das Edge Functions

```bash
supabase functions deploy sync-jobs-apify
supabase functions deploy sync-jobs-ats
supabase functions deploy sync-jobs-brazil
```

> ⚠️ **NÃO use `--no-verify-jwt` aqui.** Esta seção mandava usar, e a instrução
> ficou obsoleta e perigosa. Corrigido em 30/07/2026.
>
> **O que mudou:** as três functions rodam hoje com `verify_jwt = true` em
> produção (confirmado em `list_edge_functions`), e o pg_cron manda
> `Authorization: Bearer <anon_key>` — que é um JWT válido e passa no gateway.
> A premissa do texto antigo ("não há JWT no header") deixou de valer.
>
> **Por que é perigoso e não só desatualizado:** o gateway do Supabase é a
> ÚNICA barreira real. A checagem interna `isAuthorized()`
> (`_shared/jobs.ts`) aceita **qualquer** `Bearer <algo>` — ela não valida o
> conteúdo do token. Deployar com `--no-verify-jwt` desliga o gateway e
> rebaixa as três functions de sync para invocação praticamente pública:
> qualquer pessoa com a URL e um header `Authorization: Bearer x` dispara um
> sync.
>
> Se um dia o cron voltar a chamar sem JWT, o conserto é fortalecer o
> `isAuthorized()` (comparar o `x-cron-secret` do Vault em tempo constante),
> **não** desligar o gateway.

## 5. Aplicar o cron schedule

No SQL Editor, cola e roda `supabase/migrations/20260506_jobs_cron_schedule.sql`.

Valida:

```sql
SELECT jobname, schedule, active FROM cron.job WHERE jobname LIKE 'sync-jobs-%';
```

Deve retornar 2 linhas: `sync-jobs-apify-daily` (`0 7 * * *`) e
`sync-jobs-ats-daily` (`30 7 * * *`).

## 6. Teste manual de cada função

```bash
# Pega tua service role do dashboard → Settings → API
SR=eyJ...

# Apify (Gupy) — pega 5 vagas pra teste rápido
curl -i -X POST \
  -H "Authorization: Bearer $SR" \
  -H "Content-Type: application/json" \
  -d '{"maxResults": 5}' \
  "https://gaxfmniffjvwrwyunorl.supabase.co/functions/v1/sync-jobs-apify"

# ATS (Greenhouse + Lever) — sincroniza todas as 20 empresas seedadas
curl -i -X POST \
  -H "Authorization: Bearer $SR" \
  "https://gaxfmniffjvwrwyunorl.supabase.co/functions/v1/sync-jobs-ats"
```

Resposta esperada do Apify (após ~2-3 min):

```json
{
  "ok": true,
  "fetched": 5,
  "upserted": 5,
  "skipped": 0,
  "errors": 0,
  "markedStale": 0,
  "durationMs": 152340
}
```

Resposta esperada do ATS (~30s):

```json
{
  "ok": true,
  "sources": 20,
  "totalInserted": 60-80,
  "totalErrors": 0-2,
  "markedStale": { "greenhouse": 0, "lever": 0 },
  "durationMs": 8000-15000
}
```

## 7. Forçar uma rodada do cron pra popular já

No SQL Editor:

```sql
-- Rodar manualmente AGORA (sem esperar o cron)
SELECT command FROM cron.job WHERE jobname = 'sync-jobs-apify-daily';
-- (Copia o `command` retornado e roda numa query separada)
SELECT command FROM cron.job WHERE jobname = 'sync-jobs-ats-daily';
```

## 8. Verificar resultado

```sql
SELECT
  source,
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE is_active) AS active,
  MIN(last_seen_at) AS oldest_seen,
  MAX(last_seen_at) AS newest_seen
FROM jobs
WHERE source IS NOT NULL
GROUP BY source
ORDER BY total DESC;
```

Esperado depois de ambas as rodadas:
- `gupy`: 100-200 (depende do `maxResults`)
- `greenhouse`: 60-100

## Custo estimado mensal (Apify)

| `maxResults` por run | Frequência | Vagas/mês | Custo/mês (FREE tier $0.00299/job) |
|---|---|---|---|
| **50** | **diário (default)** | **1.500** | **$4.49 (cabe nos $5 grátis)** |
| 200 | diário | 6.000 | $17.94 |
| 500 | diário | 15.000 | $44.85 |
| 1000 | semanal | 4.000 | $11.96 |

Padrão atual: **50/dia → ~$4.49/mês** (dentro do plano FREE). Pra escalar
quando quiser mais volume, edite o `'maxResults', 50` no SQL do cron job
(no arquivo `20260506_jobs_cron_schedule.sql` ou direto no SQL Editor):

```sql
-- Pra mudar pra 200/dia (sai do FREE, ~$18/mês):
SELECT cron.unschedule('sync-jobs-apify-daily');
-- Depois reaplique o trecho do migration com o novo valor de maxResults.
```

## Adicionar mais empresas Greenhouse/Lever

```sql
INSERT INTO external_job_sources (ats, company_slug, display_name) VALUES
  ('greenhouse', 'novaempresa', 'Nova Empresa');
```

Confirma se o slug existe testando:
```bash
curl -s "https://boards-api.greenhouse.io/v1/boards/novaempresa/jobs" | jq '.jobs | length'
```

## Logs

```bash
supabase functions logs sync-jobs-apify --tail
supabase functions logs sync-jobs-ats --tail
```

## Rotacionar Apify token

Importante depois do primeiro deploy (a token foi exposta em chat):

1. Apify Console → Settings → Integrations → Personal API tokens → Revoke
2. Criar nova
3. `supabase secrets set APIFY_API_TOKEN=<nova>`
4. Não precisa redeploy — a function lê do env.
