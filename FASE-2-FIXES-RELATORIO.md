# FASE-2-FIXES — RELATÓRIO (ajustes pré-release 2.4.0)

**Branch:** `fase-2-fixes` (de `main`, pós-merge da F2 PR #3 `527a3ea`).
**Commits:** `07c5185` (#1/#2/#3 client) · `4a97c3b` (#4 edge/tool) · este doc.
**Saem JUNTOS na 2.4.0.** Plano aprovado: `siga-o-arquivo-anexado-zesty-liskov.md`
(diagnóstico dos 4 + decisões do fundador + REV das condições).

4 defeitos achados na validação device (conta `f2c7f374`/Apple relay
`sgxvydk4bn`, perfil rico), todos na vaga Mills "Estágio Universitário
(Administração)" (`a27b7a4d`, área Administrativo).

## O que foi feito

**#3 (causa-raiz, prioridade) — 50% vs 0% no detalhe.** Não era cache de IA:
o detalhe aberto da LISTA/SALVAS abria com `match=null` → `_score` caía em
`job.matchScore` (const 0) → "Match razoável 0%". O swipe passava o match (IA
50%, row real em `match_analyses`). Fix: mapa de RESULTADOS movido pro
`JobsViewModel` (`cachedMatch`/`cacheMatch`, cache compartilhado swipe↔detalhe;
sliding-window/`_matchInflight` ficaram locais no swipe — condição do fundador);
`resolveMatchForJob` = cache memória → `match_analyses` → determinístico (sem N
round-trips); `JobDetailsSheet` resolve async, **pending = SPINNER (nunca 0%)**,
noResume/unknown → CTA.

**#1 (decisão A) — score único.** Célula da lista mostra SÓ razões; banda
removida (vinha do ranking server e divergia do match IA/determinístico do
detalhe; espec 3.3). **Ordenação do feed inalterada** (segue por `rank_score`).

**#2 — copy honesta.** Detalhe: baldes `≥85 Excelente · ≥70 Bom · ≥40 Match
parcial · <40 Match baixo` (limiares alinhados ao `match_band.dart`). Acabou o
"Match razoável — vale tentar!" para score baixo/zero.

**#4 (decisão A) — classificação de área.** `inferArea` agora tem 2 rulesets:
título = COMPLETO; descrição = FORTE (remove boilerplate `sistemas/dados/data/
tech/TI/testes/cloud` do Tech e tokens fracos de Produto/RH/Operações). Título
sem sinal + descrição só fraca → "Geral" honesto. + tokens de título
(esteriliza→Saúde, inclusão/diversidade→RH, criação→Produto). Backfill das
ativas em `tools/reclassify_active_areas/` (escopado às fontes de descrição-hint).

## Aceites medidos (verificado, não declarado)

| Item | Medição |
|---|---|
| `flutter analyze` | **0 erros, 0 warnings novos** (só `info`/baseline) |
| `flutter test` | **40 verde** (+5: 4 da copy do #2, 1 da célula sem banda do #1) |
| `match_band_holdout_test` | verde (intocado — `match_band.dart` segue no card do swipe) |
| `deno test jobs.test.ts` | **9/9** (#4: suspeitos saem de Tech; boilerplate→Geral; dev real→Tecnologia; controles não regridem) |
| `check_functions_types` (deno check) | **OK, 27 entrypoints** |
| `check_env_safety` | OK |
| **#4 dry-run** (local, `inferArea` real sobre prod, fiel ao pipeline) | gupy/brz: **59 vagas** mudam (maioria → "Geral" honesto: 28 Produto→Geral, 11 Tech→Geral, 8 RH→Geral…). **Tech ativas sem token tech no título: 16 → 1** (o 1 restante é `polifinance` "Risco de Mercado", fonte fora de escopo). 127 ativas de greenhouse/polifinance ficam fora (hint ≠ descrição; auto-curam no sync). |

## Deploy — FEITO (15/06)

**As 4 functions que embarcam `_shared/jobs.ts` foram deployadas** (de código
commitado): `sync-jobs-apify`, `sync-jobs-ats`, `sync-jobs-brazil`,
`ingest-jobs-email` → projeto `gaxfmniffjvwrwyunorl`. `ingest-jobs-email`
manteve `verify_jwt=false` (config.toml).
**`check_functions_drift.sh` → OK (25 functions ativas, repo == deployado)** —
o `inferArea` novo está em produção; a janela repo≠prod fechou no mesmo dia.

## Pendências do fundador

1. **Backfill das ativas** (corrige já; senão o próximo sync auto-corrige as
   vivas na fonte):
   ```bash
   export SERVICE_ROLE=<service-role-key>
   deno run --allow-env --allow-net tools/reclassify_active_areas/reclassify.ts             # DRY-RUN: revisar de→para
   deno run --allow-env --allow-net --allow-write tools/reclassify_active_areas/reclassify.ts --apply
   unset SERVICE_ROLE
   ```
   (Opcional: com o deploy já feito, rodar os syncs uma vez também re-classifica
   as ativas vivas na fonte. O backfill é o caminho imediato + cobre as que não
   reaparecem logo.)
2. **Verificação pós-backfill:** re-rodar a query "Tech ativas sem token tech no
   título" (deve cair de **17/36 → ~0**; no snapshot de hoje, 16→1) e o harness
   `tools/feed_parity/` (paridade verde pós-mudança de dado).
3. **Device:** abrir a vaga Mills pela LISTA e pelas SALVAS → ring **50%** (= swipe),
   nunca "0% Match razoável"; durante o load, spinner; célula sem chip "Match Alta".

## Notas / desvios (o fato venceu)

- **Backfill é RETROATIVO:** vaga que muda de área entra/sai de feeds por filtro,
  mas o histórico de `swipe_actions`/`applications` (por `job_id`) NÃO é reescrito
  — esperado.
- **Backup local (não tabela):** R2 proíbe DDL ad-hoc; o `--apply` salva backup
  JSON local (`backup_<ts>.json`, revertível com `--revert`) em vez do
  `_jobs_area_backup_<data>` do plano. Desvio consciente.
- **Backfill escopado a gupy/brz_infojobs:** recomputar greenhouse/lever/
  polifinance com descrição divergiria do hint real desses pipelines (depto/IA);
  ficam de fora e auto-curam no próximo sync (upsert sobrescreve `area`).
- **adapt-resume-to-job NÃO embarca `_shared/jobs.ts`** → R5 não disparou.
