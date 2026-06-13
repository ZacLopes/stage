# FASE-2-RELATORIO — Feed server-side, lista e holdout

**Status: EXECUÇÃO COMPLETA dos 4 PRs em 12/06** (commits 9714fa9 → d51ba1b →
b22c6b3 → bde9706 na branch `fase-2-feed-server`). Aceites server-side medidos;
aceites de produção (#2, #3, #5, #6, #7) fecham pós-release 2.4.0 + rollout.
Refs: `PLANO-FASE-2.md` (aprovado 12/06, REV-1 incorporada).

> **Desvio de agrupamento (registrado):** os "PRs 1-4" do §6 viraram 4 commits
> escopados na MESMA branch (1 PR de fase no GitHub, padrão de merge da F1) —
> revisão por commit preserva a granularidade sem stack de PRs dependentes.

---

## PR1 — o que foi entregue (tudo SERVER-IMEDIATO, zero efeito visível)

| Item | Artefato | Estado |
|---|---|---|
| T2.0 script de conversão | `scripts/convert_internal_account.sh` | commitado; **fundador ainda não rodou** |
| T2.0 validação de login | `scripts/validate_internal_login.sh` | commitado; roda após a conversão |
| T2.0 gate de onboarding | `UPDATE profile_personal` (via MCP, dry-run antes) | **aplicado** — `onboarding_completed_at = 2026-06-12 23:00:38Z` |
| T2.1 RPC `get_feed_page` | migrations `20260612120000` (v1.0) + `20260612130000` (v1.1 perf) | **em prod** |
| T2.1 D-11 títulos legacy | migration `20260612120100` | **aplicada** — 50 rewrites + 41 dedups |
| T2.1 teste SQL | `supabase/scripts/test_fase2_feed_rpc.sql` | **FASE2_TESTS_OK em prod** (2×: v1.0 e v1.1) |
| T2.1 harness de paridade | `tools/feed_parity/` (README + fetch .sh/.sql + Dart + SQL) | **7/7 contra RPC real** |
| Seed `feed_list_v1` | migration `20260612120200` | em prod, `enabled=false, rollout_pct=0` |
| `company_requests` | migration `20260612120300` | em prod, RLS own-insert/own-select, 0 rows |

`supabase migration list` limpo (local = remoto, 91 migrations); manifest atualizado;
`check_env_safety` OK; `check_functions_drift` OK (25 functions, repo == deployado —
PR1 não toca functions); `flutter analyze` 0 errors/warnings; `flutter test` verde.

## Aceites do §8 medidos neste PR

**#1 Paridade — 7/7 md5 idênticos contra o RPC real em prod (12/06 ~22:50Z, pós-D-11):**
lado client = pipeline Dart real (`FilterHelpers` importado direto do app — melhor que a
cópia sha256 do plan mode: zero drift por construção) sobre snapshot de prod; lado RPC =
`get_feed_page` v1.1 paginado por keyset (50/página) com claims por usuário.

| user | n | md5 (idêntico nos 2 lados) |
|---|---|---|
| a91e0ed2 | 2 | `9ea9150df55abe06f57dad961a0f1fd0` |
| b7226e54 | 0 | `d41d8cd98f00b204e9800998ecf8427e` |
| 456ea636 | 322 | `26f4a54a76979da93d997b0b8e43cf25` |
| 1d052e97 | 155 | `1c5f50765cb3b2f4a7392928cab06101` |
| 16835f3d | 159 | `c4abf1e3ba16de011e62ba1775476d46` |
| d466f487 | 461 | `892ccde4722391478b194c7d525a2c6c` |
| c5bdb3ac | 0 | `d41d8cd98f00b204e9800998ecf8427e` |

Counts e md5 = exatamente os do D2 do plano: a D-11 normalizou títulos de `a91e0ed2` e
`c5bdb3ac` sem mudar os conjuntos (os zeros seguem explicados por localização ∩ tipos,
nos DOIS lados — paridade legítima). A re-execução paginada também re-prova o keyset
REV-1 em dados reais.

**#8 (server) — `FASE2_TESTS_OK` em prod, rollback limpo**, cobrindo:
auth obrigatório + anon sem EXECUTE · exclusões (swipada/inativa/vencida) ·
null-permissividade (args null e `'{}'`) · clamp do limit (0→1, null→20, 200→50) ·
score exato 63 (50/80) com reasons · guard anti-inflação (dimensão não-declarada fora
do numerador; max score do catálogo = 100) · **salário REV-1** (null passa sem pontuar
75, abaixo cai, acima pontua 100 + reason) · **all-ties REV-1** (usuário sem prefs, 10
páginas × 50, zero overlap, união = total_after_filters) · **jitter REV-1**
(determinístico no mesmo `p_frozen_at`, rotaciona por dia, frozen futuro clampa) ·
sentinela do estado B (1 row job_id null, after=0/available>0).

**#9 Títulos legacy zerados:** query de contagem dos mapeamentos D-11 = **0** pós-migration
(50 rows reescritas — plano estimava ~25, o B6 listava só a cabeça da cauda; 41
duplicatas removidas). Harness re-rodado verde (tabela acima).

**Performance (verificação T2.1; aceite #2 só fecha com `feed_loaded` em produção):**
- Baseline atual (B3): P50 2.228ms / P95 4.606ms no `feed_loaded` frio.
- v1.1 warm, função completa (6 execuções por perfil, `clock_timestamp`):
  perfil (a) heavy swiper **9ms** · (b) sem prefs **4-6ms** · (c) prefs completas
  **20-21ms** — dentro da projeção 5-21ms do B1.
- Shape (EXPLAIN da query espelhada, perfil c): `idx_jobs_active_published_at` (Index
  Cond is_active, Filter deadline removendo 8) + Index Only Scan
  `swipe_actions_user_id_job_id_key` no anti-join (estratégia hash — equivalente ao
  nested-loop do B1 nessa cardinalidade) + top-N quicksort 25kB. Lookups de
  área/cidade rodam 1× sobre 12 áreas / 104 combos distintos (`loops=1`), matching
  per-row é hashed subplan. Buffers: 540 hits.

## Desvios do plano (o fato venceu) — todos verificados

1. **`unaccent` vive no schema `extensions`** — o SQL do §3.1 (`set search_path = public`
   + `unaccent` nu) quebraria em runtime. Migration usa `extensions.unaccent`
   qualificado, search_path segue pinado em `public`.
2. **Bug de spec no m_loc do §3.1:** o atalho do remoto ficava FORA do gate
   `r_locations is not null` → +15 no numerador sem 15 no denominador → score 150 pra
   user sem cidade declarada (divergia do client, que só pontua dimensão declarada).
   Corrigido (todos os `m_*` gateados); teste T5 trava regressão.
3. **Sentinela do estado B:** o desenho do plano devolvia counts em colunas das rows —
   com 0 rows (exatamente o estado B) o client ficava cego. 1ª página vazia → 1 row
   `job_id NULL` com os totais. Contrato documentado na migration; PR2 consome.
4. **Regressão de performance flagrada e corrigida (v1.0 → v1.1):** a regra do plano
   ("regressão vs plan mode = parar e investigar") pegou o perfil (c) em 167-175ms warm
   — os EXISTS de área-sinônimos/cidade viravam subplans CORRELACIONADOS re-executados
   por vaga (O(vagas × sinônimos), furaria a projeção de 5k). v1.1
   (`20260612130000`): mesmos predicados avaliados 1× POR VALOR DISTINTO (12 áreas,
   ~104 combos cidade/estado), per-row vira hash lookup; `unaccent` roda ~130× total
   independente do nº de vagas. 167ms → 20ms; paridade e testes re-verificados.
5. **Espelhos finos do client** (paridade by construction): checks de vazio CRUS
   (`isNotEmpty` sem trim) na montagem de `r_areas`/`r_locations`; args `'{}'`
   normalizados pra null (= isEmpty); `ul <> ''` no match de localização (espelha o
   `continue` do Dart); guards defensivos `hashtext::bigint` (abs(INT_MIN) estoura),
   idade de publicação ≥0, `coalesce(p_limit,20)`, cursor incompleto = 1ª página.
6. **D-11:** contagem real 50 rows (não ~25); padrão do plano (UPDATE anti-duplicata +
   DELETE) tinha hazard de snapshot no mesmo statement (2 legacy do mesmo user pro
   mesmo alvo criariam duplicata) → decomposto em rewrite-tudo + dedup mantendo menor
   `(order_index, id)`, mesmo estado final, idempotente (dry-run: re-execução = 0).
7. **Vocabulário de `swipe_actions.action` é `liked|rejected`** (não `disliked`) —
   teste ajustado.
8. **Harness importa `filter_helpers.dart` via package import** em vez de cópia
   conferida por sha256 — drift cópia↔original deixa de existir; o espelhamento que o
   harness vigia continua sendo Dart ↔ SQL.

## PR2 — T2.2: modo lista + swipe por snapshot (client 2.4.0, commit d51ba1b)

- **Server v1.2** (migration `20260612140000`): `rank_score` quantizado em 6
  casas — fecha o risco "cursor numeric float" do §9. A mitigação do plano
  ("client repassa a string exata") não sobrevive ao caminho real: PostgREST
  serializa numeric como JSON number e o `jsonDecode` do Dart entrega double;
  em EMPATES (batches do sync compartilham `published_at`) um cursor inexato
  flipava o tie-break. Com 6 casas (rank < 104 → ≤9 dígitos significativos) o
  roundtrip double é exato. **Verificado:** `FASE2_TESTS_OK_V12` + teste novo
  T7b (todo rank sobrevive a `text→float8→text`) em prod, rollback limpo.
- **FeedPager** (`lib/features/jobs/data/feed_pager.dart`): lógica pura de
  cursor/sentinela/dedup/totais com transporte injetado — 8 unit tests com
  RPC mockado (R3), incluindo paginação completa sem overlap (espelho do
  all-ties) e dedup de borda.
- **JobsViewModel:** `_performFetch` bifurca pro RPC com `feed_list_v1` ON;
  caminho legacy intocado (rollback = flag OFF). Filtros resolvidos como hoje
  (local-else-profile, D-8); `min_match_score` client-side por página (página
  pode encolher; busca a próxima se zerar, guard de 5). Lista = scroll
  infinito; swipe = snapshot por página, avanço no `tryAutoReload` e
  CardSwiper recriado via `Key(feedEpoch)` (B4 sem refatorar o plugin).
- **UI:** `JobsListView`/`JobsListCell` (célula: empresa, título, chips de
  razão do RPC, bolsa/"A combinar", frescor; Dismissible direita-salva/
  esquerda-descarta na MESMA `swipe_actions`); toggle swipe↔lista no AppBar,
  persistido por user, swipe é padrão (D-6).
- **R7:** `feed_mode_toggled` (catálogo+emissor) + props `feed_source`
  ('rpc'|'legacy', REV-1 — corte do aceite P50) e `feed_mode` em
  `feed_loaded`/`feed_exhausted`/`job_swiped`/`job_card_shown`.

## PR3 — T2.3: exaustão honesta + pedido de empresa + admin (commit b22c6b3)

- **Estados A/B** no swipe e na lista. B (filtros zeraram; sentinela do RPC
  alimenta `filtersAreTooRestrictive`): "limpar filtros". A (fim das
  relevantes): CTA de alerta (permissão de push pro digest diário existente),
  **expansão honesta** — "incluir remotas" só aparece quando o filtro de
  MODELO as exclui (sem filtro de modelo, remotas já passam por localização;
  oferecer seria expansão de mentira) — e "Pedir uma empresa".
- **CompanyRequestSheet:** own-insert em `company_requests` + evento
  `company_requested` (R7). Aceite #7 (≥1 pedido real) fecha pós-release.
- **Admin:** action `company_requests` na edge `admin-jobs` (service role +
  audit log + nome/email via `user_profiles`) e aba "Pedidos" no dashboard.
  Edge **deployada pós-commit** (ordem commit→deploy);
  `check_functions_drift` OK (25 functions, repo == deployado). tsc + vite
  build do dashboard verdes.

## PR4 — T2.4 bandas + holdout · T2.5 detalhe (commit bde9706)

- **Bandas:** número 0-100 saiu do pré-swipe. Card mostra banda no ring
  (Alta ≥70 / Média 40-69 / Baixa <40 — `match_band.dart`, unit test dos
  limiares); célula da lista ganha chip de banda do score do RANKING server
  (D-2: ranking ordena, card explica; sem prefs declaradas a banda não
  aparece — score 0 viraria "Baixa" pra tudo). Número completo só no detalhe.
  R5 não disparou (pipeline adapt intocado).
- **Holdout (§5/D3):** gate puro em `holdout_gate.dart` — confidence low →
  flag NÃO avaliada (unit test: zero chamadas), failure-safe = controle.
  `JobsViewModel.resolveMatchScoreHoldout()` 1× por sessão pós-prefs;
  variante 'hidden' oculta banda E chips pré-swipe no card e na célula
  (revelados no detalhe). Props `score_visible` (o que o user VIU, pós-flag
  e pós-confidence) + `holdout_variant` em `job_card_shown`/`job_swiped`.
- **Flag PostHog 693925 reconfigurada via MCP** (12/06, version 2): variantes
  `percent` **80** / `hidden` **20**, exclusão do cohort interno 303703
  preservada, bucketing distinct_id, **SEGUE INATIVA** — ativação é do
  fundador na liberação da 2.4.0 (checklist #5; seguro: `last_called_at`
  ainda null).
- **T2.5:** as razões já abrem o detalhe (o match card com razões é o 1º
  bloco após o header — nada a mover); adicionado selo discreto
  "via {source}" no header (`jobs.source` novo no model Job).

## Validações finais (12/06)

`flutter analyze` 0 errors/warnings (ratchet 46 = baseline 46) ·
`flutter test` verde (35 testes, 13 novos da fase) · `deno check` 27
entrypoints OK · tsc + vite build do dashboard OK · `migration list` limpo
(local = remoto, 93 migrations) · manifest atualizado ·
`check_functions_drift` OK · `check_env_safety` OK.

## Pendências (fundador)

1. **Rodar `scripts/convert_internal_account.sh`** no terminal (precisa `SERVICE_ROLE`
   exportada + senha nova via prompt; telefone sintético: **(00) 90000-0001**).
2. **Rodar `scripts/validate_internal_login.sh`** (HTTP 200 = verificação i do T2.0) e
   logar no device pelo fluxo normal (verificação ii — feed da área "Tecnologia").
3. Decisões já tomadas que seguem valendo: rollout 10→50→100 pós-aceitação da 2.4.0;
   swipe padrão/lista opt-in; holdout 20%.

## Próximos passos (fechamento da fase)

1. Validação device com a conta interna (T2.0 verificação ii): login, toggle
   lista, P50 percebido — **antes** do rollout (risco §9: e2e ≠ EXPLAIN).
2. Release 2.4.0: bump + archive; `posthog_annotate_deploy.sh` na LIBERAÇÃO.
3. Pós-aceitação: rollout `feed_list_v1` 10→50→100 (degraus 3-4 dias; gatilho
   zero regressão crash/`feed_load_failed` + save-rate estável) + ativar a
   flag do holdout no PostHog.
4. Aceites de produção: #2 P50<800ms (`feed_loaded` com `feed_source='rpc'`,
   `cache_hit=false`, ≥7 dias com flag ≥50%); #3 sem regressão; #5 holdout
   ≥14 dias + análise do §5; #6 exaustão por `feed_mode`; #7 ≥1
   `company_request` real.
5. Fechamento (flag 100% + janela estável): deletar `jobs.shuffle(Random())`
   + fetch-tudo (aceite #4, commit dedicado) — os emissores legacy de
   `feed_loaded` continuam com `feed_source='legacy'` até lá.
