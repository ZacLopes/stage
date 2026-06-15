# reclassify_active_areas (FASE 2 fixes #4)

Recomputa `jobs.area` das vagas **ativas** com o `inferArea` corrigido (2
rulesets: título completo + descrição forte). Importa o MESMO `inferArea` das
edge functions (`supabase/functions/_shared/jobs.ts`) — zero drift.

## Por que existe
O upsert do sync já sobrescreve `area`, então vagas vivas na fonte
auto-corrigem no próximo crawl. Este script conserta **já** (sem esperar a
cadência) e cobre vagas que não vão reaparecer logo.

## Uso
```bash
export SERVICE_ROLE=<service-role-key>     # dashboard → Settings → API
# 1) DRY-RUN — não escreve nada, imprime de→para por transição/fonte + lista
deno run --allow-env --allow-net tools/reclassify_active_areas/reclassify.ts
# 2) APPLY — backup JSON local + UPDATE só nos diffs
deno run --allow-env --allow-net --allow-write tools/reclassify_active_areas/reclassify.ts --apply
# 3) REVERT (se preciso) — restaura do backup
deno run --allow-env --allow-net tools/reclassify_active_areas/reclassify.ts --revert tools/reclassify_active_areas/backup_<ts>.json
unset SERVICE_ROLE
```

## Notas
- `SERVICE_ROLE` só via ambiente (nunca em arquivo/argv).
- O UPDATE é **dado** (não schema) — não viola R2. O backup é arquivo **local**
  JSON (não cria tabela: R2 proíbe DDL fora de migration) — desvio consciente
  vs. o `_jobs_area_backup` do plano, registrado no relatório.
- Após o apply: re-rodar `tools/feed_parity/` e a query "Tech ativas sem token
  tech no título" (deve cair de 17/36 → ~0). Reclassificação é **retroativa**:
  vaga muda de área e entra/sai de feeds por filtro, mas histórico de
  `swipe_actions`/`applications` (por `job_id`) NÃO é reescrito.
