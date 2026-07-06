# FASE 7 — Onda 1 (higiene do backend) — RELATÓRIO

Branch: `fase-7-onda-1-higiene` (de `fix/trilha-abertura-adaptativa` @ `3fce8f4`).
3 commits, um por tarefa. Sem migration (as 3 correções são só de leitura/config).
Todas reversíveis. **Nada foi deployado ainda** — aguarda sua confirmação (ver §Deploy).

| Tarefa | Commit | O que mudou | Estado |
|---|---|---|---|
| 1 — cache do match | `a36bef7` | flip `app_config` (prod) + fallback do `ai_service` (branch) | **flip JÁ em prod**; código no próximo release |
| 2 — COALESCE de cidade | `0547be8` | 3 edges de leitura (busca, auto-rank, CSV) | na branch, aguarda **deploy** |
| 3 — uma verdade de candidaturas | `5ae1b6d` | admin-overview + daily-report | na branch, aguarda **deploy** |

> ⚠️ **O fato venceu em 1 ponto:** o prompt sugeria `SELECT ... WHERE key='match_prompt_version'`
> (modelo key/value). O código real lê `app_config` como **linha única com coluna**
> `match_prompt_version` (`ai_service.dart` → `.select('match_prompt_version').eq('id',1)`).
> O valor que o prompt afirmava (`v10`) estava correto; só a forma do SELECT não. Usei a forma real.

---

## O QUE JÁ ESTÁ EM PRODUÇÃO AGORA (reversível)

**Flip `app_config.match_prompt_version` `v10` → `v13`** (o "botão de rollback" desenhado na análise I.3).
Efeito imediato: o client para de hidratar score `v10` defasado, passa a ler as ~200 rows `v13`
existentes, e para de queimar OpenAI recomputando/sobrescrevendo a cada vaga vista.

Antes/depois (colado):

```
-- ANTES (confirmado 2x):
app_config: { id:1, match_prompt_version:"v10", updated_at:"2026-05-13..." }

-- UPDATE app_config SET match_prompt_version='v13', updated_at=now()
--   WHERE id=1 AND match_prompt_version='v10' RETURNING ...;
[{ id:1, match_prompt_version:"v13", updated_at:"2026-07-06 01:16:55+00" }]

-- DEPOIS (SELECT de conferência):
[{ id:1, match_prompt_version:"v13", updated_at:"2026-07-06 01:16:55+00" }]
```

**Rollback:** `UPDATE app_config SET match_prompt_version='v10' WHERE id=1;` (sem release).

Confirmação de que o alvo era mesmo `v13` (o fato vence):
- Servidor: `analyze-match/index.ts:29` → `const PROMPT_VERSION = 'v13'`; grava (`:894,:950`) e exige
  no cache-hit (`:822`) exatamente `v13`.
- Distribuição do cache (37,8k rows): `v4` 18.414 · `v10` 15.238 · `v12` 2.246 · `v13` 202 (30/06→05/07, crescendo) · resto cauda.

**Sanidade do `v13` antes do flip (colado):** n=202, média **43,1**, min 0, máx 90; exatamente-50 = 43
(21% — bypass do Cenário C p/ perfil vazio, que o client já renderiza como card amarelo "configure
preferências" via `_parseMatchResult`, **não** como "50% de match"); exatamente-0 = 12. Amostras
com breakdown completo das 5 dimensões (label/matched/weight). **Coerente** (não são todos 50, reasons
detalhadas). Os scores baixos refletem o gargalo de cobertura/denominador conhecido (análise I.1/I.6),
**não** um bug do v13 — e mexer nisso está fora do escopo desta onda (não tocar prompt/pesos).

---

## TAREFA 1 — cache do match

**Código na branch (só tem efeito no PRÓXIMO release do app):** `lib/services/ai_service.dart`.
O fallback de versão era `'v4'` hardcoded — a MAIOR coorte morta (18,4k rows). Em qualquer falha de
leitura do `app_config` (rede/RLS) o app hidratava scores dessa versão que o servidor não grava mais.
Agora `_resolveMatchPromptVersion()` devolve `null` quando não há versão de confiança, e
`fetchCachedMatches` retorna vazio **sem consultar** → o determinístico assume. Núcleo puro
`resolveMatchPromptVersionFromConfig` extraído p/ teste (R3).

**Aceite (medido):**
- `app_config` = `v13` (SELECT colado acima). ✅
- amostra `v13` coerente (colada acima). ✅
- `flutter test test/services/ai_service_prompt_version_test.dart` → **5/5 passed**. ✅
- `flutter analyze` no arquivo: só infos `avoid_print` **pré-existentes** (não adicionei nenhum).

---

## TAREFA 2 — COALESCE de cidade (176 candidatos invisíveis)

**176** candidatos têm cidade só em `profile_job_preferences.primary_location_city` (confirmado:
`jp_only_gap=176`; base 1.718; `has_pp_city=1.132`; `has_any_city=1.308`). Corrigi a LEITURA em 3 pontos:

1. **Busca** (`admin-candidates-search`): o union das duas fontes
   (`profile_personal.location_city` + `profile_job_preferences.primary_location_city`) é computado
   ANTES da base e aplicado como `.in('user_id', …)` — cidade continua **filtro PRÉ-corte** (como era),
   só que agora unindo as duas fontes. A base vira "top 1000 por completude ENTRE quem é daquela cidade",
   então pega TODOS os 176 (inclusive os magros, abaixo do top-1000 geral) e **não** derruba candidatos
   de cidades médias que um Set pós-corte derrubaria. `.in` é seguro nesta base (~1.7k; nenhuma cidade
   sozinha passa de 1000). Guard p/ cohort vazio evita `.in([])`. *(revisão pós-feedback do fundador:
   a 1ª versão usava Set pós-corte e tinha essa regressão.)*
2. **Auto-rank** (`admin-candidate-lists`): `primary_location_city` entra em `candidateLocations`
   (15 pts de Localização). `scoreCandidate` foi extraído p/ `scoring.ts` só p/ virar testável (o
   `index.ts` chama `serve()` no top-level e não pode ser importado por `deno test`) — **zero mudança
   no bootstrap de deploy**. `buildCandidateProfiles` já carregava `profile_job_preferences`.
3. **CSV export**: cidade = `location_city || primary_location_city`.

**Aceite (medido):**
- (a) aparece na busca — **re-verificado com candidato MAGRO** `ea0eddd4` (Curitiba, completude 0,
  rank GERAL 1717, bem abaixo do corte top-1000 = 41): simulação exata das queries do código →
  aparece no pré-corte NOVO (`target_appears_new=true`) e **sumia** no pós-corte
  (`target_appears_old_postcut=false`); cohort Curitiba = 37 (< 1000, base retorna todos os 37 sem
  truncar). O caso "gordo" (`530575da`, SP, completude 90) também casa: filtro antigo só-PP `= 0` →
  fonte JP `= 1`. ✅
- (b) recebe os 15 pts de Localização — `scoring.test.ts`: "cidade só em primary_location_city → 15" **passa**; regressões (PP city ainda 15; cidade divergente 0; remoto passa) também. ✅
- (c) sai com cidade no CSV — `COALESCE(location_city, primary_location_city) = "São Paulo"` (colado). ✅
- `deno test scoring.test.ts` → **5/5**; `deno check` das 3 edges → **OK**.

> A verificação end-to-end pelos ENDPOINTS reais (busca retornando o user; auto-rank marcando 15;
> CSV com a coluna) só é possível **após o deploy** — está listada em §Deploy.

---

## TAREFA 3 — uma verdade de "candidaturas"

`admin-overview` e o relatório diário contavam `swipe_actions.applied` (DEPRECATED, **541**, só builds
≤2.2.0 escrevem), ignorando a tabela viva `applications` (**595** `countsAsApplied`; 598 total, 3
withdrawn/expired, 0 status null). Divergência **+54 e crescente** — todo apply de build novo era
invisível ao dashboard.

Critério `countsAsApplied` = `status NOT IN ('withdrawn','expired')` — o MESMO de
`lib/features/jobs/models/application.dart:61` (inclui `rejected`: o candidato aplicou; o desfecho é
que foi negativo).

- `admin-overview`: KPI `totalApplies` + série diária de applies agora vêm de `applications`.
- `daily-report`: `fetchEngagementBlock` (appliers D-1), `fetchMatchBlock` (applies D-1),
  `fetchWeeklyBlock` (applies 7d). Helper puro `countsAsApplied` (espelha o Dart) + teste.
- `html_template`: footnote **"Fonte de aplicações: tabela `applications` a partir de 10/06"**.
- Coluna deprecated **mantida** só como entrada da bridge (não apagada).

**ATENÇÃO (impacto no número que você vê todo dia):** o total sobe de **541 → 595** e a **série
histórica muda** — `applications` foi backfillada em 10/06 (o backfill e a bridge preservam o
`applied_at` original como `created_at`, então a série continua historicamente fiel, mas passa a
incluir as candidaturas nativas que a coluna deprecated nunca capturou).

**Aceite (medido):**
- número novo bate com SELECT direto: `count(*) FROM applications WHERE status NOT IN ('withdrawn','expired')` = **595** (colado). ✅
- `deno test queries.test.ts` → **6/6** (submitted/rejected/vivos contam; withdrawn/expired não). ✅
- nota de mudança de fonte adicionada ao email. ✅
- `check_functions_types.sh` → **30 entrypoints OK** (cobre queries.ts/html_template.ts transitivamente).

> Idem T2: os números que os ENDPOINTS `admin-overview`/`daily-report` retornam só mudam após deploy.

---

## DEPLOY (aguarda sua confirmação — NÃO deployei)

Só de código COMMITADO. Edges a deployar (as 3 admin embarcam `_shared/admin.ts` — **eu não toquei
esse arquivo**, mas o drift é fácil, então rodo `check_functions_drift.sh` logo após):

```
supabase functions deploy admin-candidates-search
supabase functions deploy admin-candidate-lists
supabase functions deploy admin-overview
supabase functions deploy daily-report
bash scripts/check_functions_drift.sh
```

**Verificações que farei logo após o deploy (colo o resultado):**
- T2(a): `admin-candidates-search` action=search filtro city="Curitiba" → user MAGRO `ea0eddd4`
  presente (prova o caso geral, não só o top-1000).
- T2(b): `admin-candidate-lists` auto-rank de vaga em SP → item do user com breakdown Localização=15.
- T2(c): export CSV de uma lista contendo o user → coluna cidade = "São Paulo".
- T3: resposta de `admin-overview` → `kpis.totalApplies = 595` (== SELECT).

## BACKFILL dos 176 (OPCIONAL — aguarda sua decisão, NÃO rodei)

O fix de **leitura** acima já resolve a invisibilidade (busca, auto-rank e CSV). O backfill que copia
`primary_location_city` → `location_city` p/ os 176 é **opcional** e só valeria p/ consumidores que
ainda leem só `location_city` (ex.: `completeness_score`). Se você quiser, eu preparo como **migration
CLI** (não dashboard) com backup revertível (`_bak_...`) e um SELECT de conferência antes — **me avisa**.

## Pendências pré-existentes (não são desta onda)
- Working tree traz WIP de trilha não-commitado (`fix/trilha-abertura-adaptativa`) — **não toquei**.
- Drift pré-existente do fundador (extract-profile, ingest-jobs-email) pode aparecer no drift-check
  pós-deploy; sinalizo se surgir, sem "consertar" nada fora de escopo.
