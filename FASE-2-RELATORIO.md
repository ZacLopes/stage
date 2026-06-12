# FASE-2-RELATORIO — Feed server-side, lista e holdout

**Status: PARCIAL — PR1 (server) executado em 12/06.** PR2-PR4 (client 2.4.0) pendentes.
Branch `fase-2-feed-server`. Refs: `PLANO-FASE-2.md` (aprovado 12/06, REV-1 incorporada).

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

## Pendências do PR1 (fundador)

1. **Rodar `scripts/convert_internal_account.sh`** no terminal (precisa `SERVICE_ROLE`
   exportada + senha nova via prompt; telefone sintético: **(00) 90000-0001**).
2. **Rodar `scripts/validate_internal_login.sh`** (HTTP 200 = verificação i do T2.0) e
   logar no device pelo fluxo normal (verificação ii — feed da área "Tecnologia").
3. Decisões já tomadas que seguem valendo: rollout 10→50→100 pós-aceitação da 2.4.0;
   swipe padrão/lista opt-in; holdout 20%.

## Próximos passos

- **PR2 [client]:** T2.2 — lista + swipe por snapshot + eventos (`feed_source`,
  `feed_mode`, `feed_mode_toggled`) + testes; consome sentinela e counts da 1ª página.
- **PR3 [client+admin]:** T2.3 — estados de exaustão + "Pedir uma empresa" + página admin.
- **PR4 [client+PostHog]:** T2.4 + T2.5 — bandas, holdout (flag 693925 → 80/20), detalhe.
- Aceites #2-#7 fecham pós-release/rollout (medições PostHog descritas no §8 do plano).
