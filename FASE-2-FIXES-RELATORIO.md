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
| `deno test jobs.test.ts` | **11/11** (#4: suspeitos saem de Tech; boilerplate→Geral; dev real→Tecnologia; controles não regridem; +5 regressões de saúde/operações) |
| `check_functions_types` (deno check) | **OK, 27 entrypoints** |
| `check_env_safety` | OK |

## Deploy — FEITO (15/06, em 2 rodadas)

**As 4 functions que embarcam `_shared/jobs.ts` deployadas** (de código
commitado): `sync-jobs-apify`, `sync-jobs-ats`, `sync-jobs-brazil`,
`ingest-jobs-email` → `gaxfmniffjvwrwyunorl`. `ingest-jobs-email` manteve
`verify_jwt=false` (config.toml). **`check_functions_drift.sh` → OK (25 ativas,
repo == deployado)** nas duas rodadas. (2ª rodada = fix-forward abaixo.)

## Backfill — FEITO (15/06)

**O dry-run do backfill (revisado pelo fundador) PEGOU regressões** que o
estreitamento da 2ª passada introduziu e o deploy já tinha posto em prod:
`nutricion` não casava "nutrição", e saúde/segurança-do-trabalho/educação-física
caíam em Marketing/Finanças/Geral; "Eficiência Operacional" ia pra Vendas.
**Fix-forward** (commit `035ab1c`): `inferArea` Saúde `nutri`/educação física/
segurança do trabalho (título+desc), Operações `operacional`; +5 testes;
**re-deploy + drift OK**. (Bônus: bug de path do `--apply` — `import.meta.url`
percent-encoda "Gameficação Duolingo" → o 1º `--apply` abortou no backup **antes
de qualquer UPDATE**, DB intacto; corrigido p/ `import.meta.dirname`.)

**Aplicado** (via MCP `execute_sql`, dry-run revisado + backup local
`tools/reclassify_active_areas/backup_*.json`, revertível): **57 vagas**
gupy/brz reclassificadas — maioria → "Geral" honesto (24 "Trainee Produção/
Manutenção" Friboi que eram Produto-falso; Tech/RH sem sinal) + correções p/
Saúde/Operações. greenhouse/polifinance fora de escopo (hint ≠ descrição;
auto-curam no sync).

**Aceites pós-backfill (medidos em prod):**
- **Tech ativas sem token tech no título: 16 → 1** (o 1 = `polifinance` "Risco
  de Mercado", fonte fora de escopo). Tech ativas: 19.
- **Regressão de saúde: 0** — nenhum título de saúde (nutri/enfermagem/
  fisioterap/educação física/segurança do trabalho/psicolog/odonto) em
  Marketing/Finanças/Geral.
- **Paridade `tools/feed_parity/` 7/7 md5 idênticos** client × RPC pós-backfill
  (área entra nos filtros do feed → garante RPC == client).

## #5 — Exaustão do feed mostrava "filtros restritivos" em vez de "esgotou" (achado no device, 15/06)

Ao swipar TODAS as vagas que batiam com os filtros, o feed flipava (depois de
segundos, no `tryAutoReload`) pra **"Nenhuma vaga bate com seus filtros / 218
ativas, afrouxe"** (estado B) — quando o certo é **"você viu as relevantes"**
(estado A). Causa: `filtersAreTooRestrictive` usava `_totalAfterFilters`
(pós-swipe), que vira 0 quando os matches são swipados → conflava "esgotou" com
"filtros zeram tudo".

**Fix** (commit `ab95d2e`): repo legacy passa a contar `totalMatchingCatalog`
= vagas que batem com os filtros no catálogo inteiro **ignorando swipe** (>0 →
havia relevantes, é A; 0 → filtros restritivos, é B). Decisão em função pura
`feedFiltersTooRestrictive` (5 testes). `flutter test` **45 verde** (+5),
analyze 0/0.

**Follow-up RPC — FEITO (commit `5901461`):** `get_feed_page` **v1.3** (migration
`20260615120000`) retorna `total_matching_catalog` (matches dos filtros
ignorando swipe). `base` passa a incluir swipadas (flag `is_swiped`) e os
conjuntos distintos de área/cidade saem do catálogo INTEIRO (corrige "swipou
todas da área X" → a área sumia → falso B); `scored` filtra `not is_swiped`
(feed inalterado). Client (FeedPager + JobsViewModel) lê a contagem (tirou o
-1). Verificado: migration list limpo; mini-test A vs B em prod (esgotou
after=0/tmc=2; restritivo tmc=0); **feed_parity 7/7** (feed inalterado); perf
v1.3 13,8/4,5/8,9ms (c/b/a, sem regressão); **suíte completa `test_fase2_feed_rpc`
T0–T10 = `FASE2_TESTS_OK` em prod (rollback)** — gate inteiro verde, não só os
cenários novos.

## Pendências do fundador

1. **Device:** abrir a vaga Mills pela LISTA e pelas SALVAS → ring **50%** (= swipe),
   nunca "0% Match razoável"; durante o load, spinner; célula sem chip "Match Alta".
2. **Device (#5):** swipar até esgotar → deve aparecer "você viu as relevantes" (A),
   não "filtros muito restritivos" (B).

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
