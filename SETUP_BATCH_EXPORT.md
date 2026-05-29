# A.11 — Batch Export PostHog → Supabase

> Objetivo: arquivo histórico próprio dos eventos no Supabase, sem
> depender do retention plan do PostHog. Sprint B usa pra reanálise
> retroativa e backfill de dashboards quando mudarmos filtros.

## Por quê

PostHog free tier mantém eventos crus por 1 ano. Após esse prazo, agregados
sobrevivem mas eventos individuais somem. Pra pitch + auditoria de longa
janela, precisamos de cópia própria. Supabase tem espaço barato e já
roda no Stage — caminho natural.

## Arquitetura (decidida)

```
PostHog (ClickHouse)
   │
   │  Batch Export (nightly 03:00 BRT)
   │  destination: Postgres direct (Supabase)
   ▼
Supabase Postgres
   posthog_events_archive   ← table particionada por mês
```

**Não** vamos passar por S3 intermediário — adiciona latência + custo +
complexidade. PostHog suporta destination Postgres direto (necessário criar
via UI; MCP só cobre Databricks/Azure/BigQuery hoje).

---

## Passo 1 — Criar tabela destino no Supabase

Rodar no SQL Editor do Supabase **antes** de configurar o export. Particionar
por mês mantém queries rápidas mesmo com 1+ ano de histórico.

```sql
-- Schema dedicado pra isolamento e RLS
CREATE SCHEMA IF NOT EXISTS analytics_archive;

-- Tabela principal particionada por mês.
-- PostHog manda colunas canônicas: distinct_id, event, timestamp,
-- properties (jsonb), elements_chain, person_id, etc.
CREATE TABLE IF NOT EXISTS analytics_archive.posthog_events_archive (
  uuid              UUID,
  event             TEXT NOT NULL,
  timestamp         TIMESTAMPTZ NOT NULL,
  distinct_id       TEXT NOT NULL,
  person_id         UUID,
  team_id           BIGINT,
  properties        JSONB,
  elements_chain    TEXT,
  -- Coluna que PostHog usa pra dedup (event_id)
  ingested_at       TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (timestamp, uuid)
) PARTITION BY RANGE (timestamp);

-- Partições futuras (ajustar conforme avança o tempo)
CREATE TABLE IF NOT EXISTS analytics_archive.posthog_events_archive_2026_05
  PARTITION OF analytics_archive.posthog_events_archive
  FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');

CREATE TABLE IF NOT EXISTS analytics_archive.posthog_events_archive_2026_06
  PARTITION OF analytics_archive.posthog_events_archive
  FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

CREATE TABLE IF NOT EXISTS analytics_archive.posthog_events_archive_2026_07
  PARTITION OF analytics_archive.posthog_events_archive
  FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

-- Index pra queries comuns por event_name (top N)
CREATE INDEX IF NOT EXISTS idx_archive_event_ts
  ON analytics_archive.posthog_events_archive (event, timestamp DESC);

-- Index pra queries por usuário
CREATE INDEX IF NOT EXISTS idx_archive_distinct_id_ts
  ON analytics_archive.posthog_events_archive (distinct_id, timestamp DESC);

-- Index GIN pra busca em properties (ex.: filtrar por job_id)
CREATE INDEX IF NOT EXISTS idx_archive_properties_gin
  ON analytics_archive.posthog_events_archive USING GIN (properties);
```

> Cron Postgres pra criar partições automaticamente (rodar 1x):
>
> ```sql
> SELECT cron.schedule(
>   'create_monthly_archive_partition',
>   '0 1 1 * *',  -- 1º dia do mês, 01:00 UTC
>   $$
>   DO $do$
>   DECLARE
>     start_d TEXT := to_char(date_trunc('month', now() + interval '1 month'), 'YYYY-MM-DD');
>     end_d TEXT := to_char(date_trunc('month', now() + interval '2 months'), 'YYYY-MM-DD');
>     name TEXT := 'posthog_events_archive_' || to_char(now() + interval '1 month', 'YYYY_MM');
>   BEGIN
>     EXECUTE format(
>       'CREATE TABLE IF NOT EXISTS analytics_archive.%I PARTITION OF analytics_archive.posthog_events_archive FOR VALUES FROM (%L) TO (%L)',
>       name, start_d, end_d
>     );
>   END
>   $do$;
>   $$
> );
> ```

---

## Passo 2 — Criar role dedicado pra PostHog escrever

Não usar service_role nem dar permissão geral. Role específico só com
`INSERT` no schema analytics_archive.

```sql
-- Role com password forte (gerar via openssl rand -base64 32)
CREATE USER posthog_export
  WITH PASSWORD 'COLE_AQUI_SENHA_GERADA';

-- Permissões mínimas
GRANT USAGE ON SCHEMA analytics_archive TO posthog_export;
GRANT INSERT ON ALL TABLES IN SCHEMA analytics_archive TO posthog_export;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA analytics_archive TO posthog_export;
-- Permission pra DDL automática (PostHog precisa criar índices em
-- algumas operações). Se quiser zero risk, omitir e criar manualmente.
GRANT CREATE ON SCHEMA analytics_archive TO posthog_export;
```

> **Guardar senha em local seguro** (1Password, env do PostHog). NÃO
> commitar no repo.

---

## Passo 3 — Pegar conection string Supabase

No Supabase dashboard → Project Settings → Database → Connection string
**Direct connection** (não usar pgbouncer — batch export precisa de
direct).

Formato:
```
postgresql://posthog_export:PASS@db.PROJECT_REF.supabase.co:5432/postgres
```

Substituir `PASS` pela senha gerada acima.

---

## Passo 4 — Criar Batch Export no PostHog UI

1. PostHog → Data pipeline → Batch exports → New batch export
2. **Destination**: Postgres
3. **Connection**:
   - Host: `db.PROJECT_REF.supabase.co`
   - Port: `5432`
   - User: `posthog_export`
   - Password: (senha gerada)
   - Database: `postgres`
   - Schema: `analytics_archive`
   - Table: `posthog_events_archive`
4. **Interval**: Daily
5. **Timezone**: America/Sao_Paulo
6. **Offset hour**: 3 (03:00 BRT — fora de pico, depois do daily_report)
7. **Filters**:
   - Exclude internal users: usar `properties.is_internal != true`
     (filtro JSONB no PostHog UI)
   - Exclude pre-cutover users: `properties.is_pre_cutover_user != true`
   - Date range: leave open (export tudo a partir de hoje)
8. **Test connection** → deve passar
9. **Create** → primeiro run roda à noite

---

## Passo 5 — Validar primeiro export

Manhã seguinte (~10:00 BRT):

```sql
-- Conferir que veio dado pro mês corrente
SELECT
  event,
  COUNT(*) as count,
  MIN(timestamp) as first_event,
  MAX(timestamp) as last_event
FROM analytics_archive.posthog_events_archive
WHERE timestamp >= date_trunc('day', now() - interval '1 day')
GROUP BY event
ORDER BY count DESC
LIMIT 20;
```

Esperado: top eventos batem com PostHog Live Events do dia anterior.

---

## Passo 6 — Monitoring contínuo (Sprint B)

```sql
-- Snapshot diário de health
CREATE OR REPLACE VIEW analytics_archive.daily_export_health AS
SELECT
  date_trunc('day', timestamp) as day,
  COUNT(*) as events_total,
  COUNT(DISTINCT distinct_id) as users_distinct,
  COUNT(DISTINCT event) as event_types,
  MAX(ingested_at) - MAX(timestamp) as export_lag
FROM analytics_archive.posthog_events_archive
WHERE timestamp >= now() - interval '30 days'
GROUP BY 1
ORDER BY 1 DESC;
```

**Red flags pra alertar:**
- `events_total` cai >50% dia-a-dia → export falhou
- `export_lag` > 36h → backlog
- Dia sem dado → revisar PostHog UI → Batch Exports → Logs

---

## Custos estimados

- Supabase free tier: 500MB database. ~10k eventos/dia × 1KB cada ≈ 10MB/dia
  → 300MB/mês → cabe ~50 dias de free tier
- Após free tier estourar: Supabase Pro $25/mês inclui 8GB database
- Se passar de 8GB (raro pré-Series A): considerar S3 intermediário +
  cold storage

---

## Rollback se algo der ruim

```sql
-- Stop o export no PostHog UI: Batch Exports → Pause
-- Tabela continua, dados antigos preservados

-- Drop completo (último recurso, perde histórico):
DROP SCHEMA analytics_archive CASCADE;
```

> Última atualização: 2026-05-28 (Sprint A Dia 6 finalização).
