# FASE-1-RELATORIO — A espinha de dados

**Executada em:** 2026-06-10/11 (branch `fase-1-espinha-de-dados`, empilhada sobre `fase-0-seguranca`)
**Plano:** `PLANO-FASE-1.md` (aprovado 10/06 com 3 correções da lupa + ajustes — todos incorporados)
**Commits:** `561d239` (plano) → `7032ad0` (PR1 T1.0) → `23f65a6` (PR2 core) → `1972c65` (PR3 dados) → `9f1e422` (PR4 client) → `cc88ffd` (PR5 T1.8) → este relatório.

---

## Aceites × medições (verificado, não declarado)

| # | Aceite | Status | Evidência |
|---|---|---|---|
| 1 | T1.0 drift = 0 | ✅ | 9 redeploys conscientes (6 wrapper-only + daily-report + broadcast + adapt por `_shared` defasado). `check_functions_drift.sh` final: **OK, 24 functions ativas, repo == deployado** (agora 25 com a nova). Smokes: daily-report 200/9,9s; adapt 422 estruturado (R5 não disparou — diff era 1 constante de telemetria). |
| 2 | Backfill 493±delta, idempotente, eventos 1:1 | ✅ | **499 applications** (493 do plan-mode + 6 applied do dia) com **499 eventos iniciais actor=system**. Re-execução literal em prod = **0 rows**. |
| 3 | Matriz + guardas (script SQL rollback) | ✅ | `supabase/scripts/test_fase1_state_machine.sql` executado em prod: **FASE1_TESTS_OK** (T1-T9: criação+evento, pipeline user com retrocesso-por-design, hired terminal, imutabilidade type/sla, stage user-só-withdrawn + admin reabre/SLA, Bridge 1 user-path + unicidade, Bridge 1 service-role→withdrawn, idempotência, Bridge 2 INSERT mínimo, ON DELETE RESTRICT). Rollback verificado: zero resíduos. |
| 4 | Pontes vivas | ✅ | **Testadas ao vivo no banco de prod**: campaign sintética → gate setado + `bridge_activity='campaign_onboarding'`; swipe applied sintético → application submitted + evento + `'swipe_applied'`. Sintéticos limpos. (As 2 campaigns reais de 23:43/23:47 eram pré-migration — cobertas pelo backfill, timestamps batem exato.) |
| 5 | Merge prefs | ✅ | Áreas: **19 users exatos** (=dry-run V6) via `source='legacy_merge'` (CHECK estendido — ajuste previsto na decisão (b)). Locations/work/job_types nos padrões "só onde vazio". Re-execução = 0. min_salary/min_match morrem (decisão 27/05). Smoke do feed no app fica no checklist do fundador (device). |
| 6 | Institutions ≥70% college | ✅ | **74,1% college** (de 50,4% cru), 51,0% global, catálogo **95 IES** (32 aprovadas + tiers 1/2 da cauda real — o gap era amplitude, não aliases; `unesa`→Estácio e `link`→Link School adicionados). Typeahead no onboarding + modal do perfil (client 2.3.0). |
| 7 | Curtidas 2.3.0 | ✅ código / ⏳ device | Rewire completo (applied ← applications.countsAsApplied; toggle cria/withdrawn/reabre; zero escrita em `swipe_actions.applied` — `setApplied` do repo REMOVIDO e `restoreLike` sem applied); badge Expirada (`is_active=false` OU deadline — **69% dos applied apontavam pra vaga morta**); copy do diálogo corrigida. Eventos `application_created/state_changed/reopened` no catálogo + emissores (R7). ⏳ Validação visual num device = checklist do fundador (build local 2.3.0). |
| 8 | T1.8 | ✅ deploy / ⏳ fundador | Edge `admin-candidates-search` (search com 7 filtros + save_list) + página "Busca" no dashboard + consent com `granted_via`/`scope`/nota em `status_reason` + eventos server `candidate_search_performed`/`candidate_list_created`. Export CSV consent-gated **já existia** no `admin-candidate-lists` (exportable = consent granted) — verificado, não duplicado. Não-admin → 403 (testado). ⏳ "Shortlist real em <5min" = teste do fundador (preciso de conta admin). |
| 9 | CI/testes | ✅ | `flutter test` **15/15** (6 antigos + 9 novos: matriz client, serialização, badge); analyze 0 errors, warnings = baseline 46; `migration list` limpo (86 local = remoto); manifest atualizado; CI roda no PR. |

## Desvios do plano (regra "o fato vence")

1. **`profile_desired_titles.source` tinha CHECK fechado** (`user_added|from_resume`) — estendido com `legacy_merge` (caminho previsto na decisão (b) da revisão).
2. **Meta de instituições exigiu expandir o CATÁLOGO, não só aliases**: a cauda não-casada era de IES reais fora do seed (Uninter, Unopar, Univesp, federais...). 32 → 95 IES em 2 tiers, guiado pelos dados. "puc" genérica ficou de fora (ambígua entre PUCs).
3. **Export CSV consent-gated já existia** (`admin-candidate-lists`: `exportable = consentStatus==='granted'`, owner-only, log em `candidate_list_exports`) — T1.8 reusou em vez de reimplementar; o que faltava era a BUSCA + criação de lista por seleção + colunas de consent.
4. **`admin-users` já tinha `update_consent`** — estendido (granted_via/scope) em vez de criar endpoint novo.
5. **Drift adicional descoberto no T1.0**: bundles com `_shared/` defasado mesmo com function-dir idêntico (adapt-resume-to-job) → o script compara `_shared` por bundle e o redeploy cobriu; 2 functions tinham o parêntese-do-wrapper quebrado no repo (generate-bullets, generate-summary — mesma classe da F0), corrigidos.

## Estado final (queries 11/06 ~02:30 UTC)

- `applications`: 499 (todas backfill real; sintéticos de teste limpos) + máquina de estados ativa.
- `bridge_activity`: 2 rows (testes ao vivo) — base do critério de revogação diferida (<5% builds antigas por 2 semanas E zero pontes na janela; monitorar também `user_preferences.updated_at` semanal).
- `onboarding_completed_at`: 1.622 users (backfill) + bridge cobrindo builds antigas.
- Functions: 25 ativas com repo == deployado; novas versões: admin-candidates-search v1, admin-users v4.
- `supabase migration list`: limpo (até `20260610162000`).

## Checklist do fundador

| # | Ação |
|---|---|
| 1 | Abrir PRs no GitHub (branch `fase-1-espinha-de-dados`; base = `fase-0-seguranca` até a F0 mergear — depois rebase) e mergear na ordem |
| 2 | **Build local 2.3.0 num device**: aba Curtidas (marcar/desmarcar aplicada → conferir `applications` + eventos no PostHog; badge Expirada numa vaga inativa), onboarding novo (gate sem campaign), typeahead de instituição, feed da conta interna filtrando igual pós-merge |
| 3 | **Shortlist real em <5min**: dashboard → Busca → filtros → selecionar → consent (nota de evidência) → salvar lista → aba Listas → aprovar → exportar CSV (bloqueio sem consent é automático) |
| 4 | Pendências herdadas da F0 que continuam: rotação da chave OpenAI (se ainda não feita), assinar tópicos ntfy, archive 2.2.0+5 |
| 5 | Quando decidir a release: client da Fase 1 sai como **2.3.0** (bump no merge + archive) |

## Fora de escopo confirmado
Nenhuma revogação de escrita nas legacy executada; adapt intocado (R5 — golden_set não requerido; o redeploy do adapt foi telemetria, smoke colado no aceite #1); prompt de retorno pós-apply e adição manual de candidatura ficam na F3; force-update não usado (decisão #1).
