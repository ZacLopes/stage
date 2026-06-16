# FASE-3-RELATORIO — Tracker de candidaturas + prompt de retorno + saída instrumentada

**Executada em:** 2026-06-16 (branch `fase-3-tracker`, de `main`).
**Plano:** `PLANO-FASE-3.md` (aprovado pelo fundador com 2 correções + 1 verificação — todas incorporadas antes de codar).
**Commits (8):** `9d7a96c` (plano+CLAUDE) → `9dd3e34` (PR1 T3.4 schema) → `f86fd76` (PR2 T3.5 digest+índice) → `b7f2b35` (PR2 drift fix) → `e4015a3` (PR3 T3.4 client) → `61e3074` (PR4 T3.1 tracker) → `a085f1c` (PR5 T3.2 prompt) → `129ac7d` (PR6 T3.3 manual).

---

## Aceites × medições (verificado, não declarado)

| # | Aceite F3 | Status | Evidência |
|---|---|---|---|
| 1 | ≥30% dos apply-clicks respondem ao prompt em 2 semanas | ⏳ pós-flag | Baseline B6 medido: ~200-300 `job_details_apply_clicked`/sem (336/05-31, 200/06-07). Funil `job_details_apply_clicked → (apply_confirmed\|apply_abandon_reason)`. **Janela conta da ATIVAÇÃO de `applications_tracker_v1`** (verificação do fundador): com flag OFF o prompt não dispara (gate em `_maybeShowApplyPrompt`). |
| 2 | Tracker exibindo os 3 types | ✅ render / ⏳ stage | Hoje só `external_confirmed` (543) + `manual` (criável in-app). Aba renderiza os 4 segmentos e os 3 types corretamente (widget tests + grouping puro). `stage` real só pós-F4. |
| 3 | 1ª análise de `apply_abandon_reason` por fonte | ⏳ pós-flag | Evento + emissor prontos (`reason` ∈ 4 chips + `job_source` no payload). Análise quando a flag estiver ao vivo. |
| 4 | `outbound_clicks` populando | ✅ infra / ⏳ release | Tabela em prod (RLS own, anon revogado); client grava no apply http(s). count>0 fecha pós-release 2.5.0. |
| 5 | Zero push novo fora do digest | ✅ | T3.5 = 2ª passada da MESMA edge, intent `saved_deadline_48h`, mesmo canal OneSignal. Nenhum template novo. |
| — | Server-imediato em prod (PR1/PR2) | ✅ | Migrations aplicadas via `supabase db push`; digest deployado (commit→deploy); `check_functions_drift` OK (25, repo==deployado). |
| — | CI/testes (R3) | ✅ | `flutter test` **77 verde** (+26 da fase); `flutter analyze` 0 erros / 46 warnings = baseline; `deno test` 6/6; `deno check` 27; `migration list` limpo (96); manifest atualizado; `check_env_safety` OK. |

---

## O que foi entregue, por camada

### SERVER-IMEDIATO (em prod hoje)

**PR1 — T3.4 schema** (`20260616120000_outbound_clicks.sql`):
- `outbound_clicks (id, user_id, job_id, created_at)` RLS own-insert/own-select, anon revogado, service_role read (relatório B2B na F4).
- `applications.external_url text` (aditiva, link do manual).
- **Teste SQL** `test_fase3_outbound_manual.sql` = `FASE3_PR1_TESTS_OK` em prod (BEGIN…ROLLBACK): own-insert OK, RLS barra outro user, own-select isolado, anon negado, `external_url` persiste, CHECK `manual_fields` trava manual sem empresa. Verificado pós-deploy: tabela existe, 0 rows, 2 policies, anon 0 grants.

**PR2 — T3.5 digest com prazos** (`20260616130000_digest_deadline_cohort.sql` + edge):
- **Índice MEDIDO** `jobs_deadline_active_idx (deadline) where is_active and deadline is not null` (correção 1 do fundador). EXPLAIN ANALYZE em prod **antes**: varredura full-active filtrando deadline, `Rows Removed by Filter: 427`, **303ms**. **Depois**: `Index Scan using jobs_deadline_active_idx`, `Index Cond (deadline >= now() AND <= now()+48h)`, range scan 5 rows, **33.8ms** (~9×), buffers jobs 391→5, sem `Rows Removed`.
- RPC `get_saved_jobs_expiring(hours)` SECURITY DEFINER, execute só service_role.
- Edge `notifications-daily-digest`: 2ª passada de prazo (liked + deadline≤48h + sem application) reusando `sendOneSignalPush`, intent `saved_deadline_48h`, source `daily_digest_deadline`. **Dedupe prazo>nudge** extraída p/ `digest_plan.ts` (pura) + `deno test` 6/6.
- **Dedupe verificada, não afirmada** (correção 2): smoke ao vivo (dryRun, targetEmails=conta interna, seed de 1 liked expirando) → `candidates:1, deadlineCandidates:1, results=[1×saved_deadline_48h]` — recebeu **exatamente 1 push (o de prazo)**, sem 2º nudge. Seed limpo.

### CLIENT — saem na release 2.5.0 atrás da flag `applications_tracker_v1` (OFF/0%, seed `20260616140000`)

**PR3 — T3.4 client:** `decorateOutboundUrl` (pura: só http(s), mailto intacto, query/UTM preservados via putIfAbsent) no único call site de apply; no sucesso do `launchUrl` grava `outbound_clicks` (own-insert) + emite `job_details_apply_external_opened` (reuso de constante morta do catálogo, R7). `url_utils_test` 7/7.

**PR4 — T3.1 aba Candidaturas:** `liked_jobs_screen` vira tracker (flag ON): 4 segmentos via `segmentForStatus` puro (Salvas=liked sem app / Enviadas=submitted / Em processo=in_review|shortlisted|interview|offer / Finalizadas=hired|rejected|withdrawn|expired); flag OFF = 3 buckets legacy intocados. `ApplicationStatusControl` (chip+menu por `canTransition`) só pra type editável; `updateApplicationStatus` otimista → `application_state_changed` (reuso, R7). Tab renomeia Salvas→Candidaturas no bottom nav. +16 testes.

**PR5 — T3.2 prompt de retorno:** `pending_apply{job_id,title,company,source,ts}` (slot dedicado no `JobSwipeContext`) gravado no apply (site E email). `_HomeForegroundObserver` (camada UI) decide via `pendingApplyDecision` puro (<30min → mostra; Depois → re-ask único in-app +24h, **sem push**; fora da janela → expira). Sheet Sim/Não/Depois: Sim → `markAppliedFromPrompt` + `apply_confirmed`; Não → 4 chips fixos → `apply_abandon_reason` (reason+job_source); reuso de `job_details_apply_returned` (R7). **Gate na flag** (aceite #1). +14 testes.

**PR6 — T3.3 adição manual:** FAB → `manual_application_sheet` (empresa+vaga+link opcional+status, ≤10s) → `createManual` (INSERT type='manual', job_id null). Tracker renderiza `ManualApplicationCard` (selo manual, status chip, link c/ UTM) nos mesmos segmentos; `updateManualApplicationStatus` id-based. `Application.externalUrl` adicionado. +2 testes.

---

## Estado real medido (queries 16/06)

- `applications`: 543 (542 submitted + 1 withdrawn), todas `external_confirmed`; 147 users. `manual`/`stage` = 0 (manual nasce com o uso da feature; stage na F4).
- "Salvas" (liked sem application): **6.802** rows / 1.036 users distintos.
- Cohort de prazo (deadline≤48h, sem application): 2 users reais hoje.
- `outbound_clicks`: 0 (client escreve pós-release).

---

## Desvios do plano (o fato venceu) — registrados

1. **Apply tem UM call site, não dois** (auditoria H1/PLANO-MÃE desatualizados): só `liked_jobs_screen::_openApplication`; `JobDetailsSheet` não tem botão de aplicar. Cobrir "swipe E lista" sai de graça (apply é downstream, sempre na Salvas). Prova por grep no plano §0/B3.
2. **Reuso de constantes mortas** `job_details_apply_external_opened`/`job_details_apply_returned` (catálogo sem emissor → dívida R7 zerada) em vez de inventar `outbound_click`/return novo; `application_state_changed` (já carrega `application_type`) cobre status manual — sem `application_status_changed_manual`.
3. **Re-pergunta in-app, não push** (espec §6.2 dizia "push suave"): a F3 proíbe push novo → constraint vence; re-ask no próximo foreground ≥24h.
4. **Digest amplia a audiência** além do cohort D+1 (todos com vaga salva expirando), dentro da mesma função/canal — necessário pro feature fazer sentido.
5. **Drift script:** `*.test.ts` colocado no dir da function gerava falso-positivo ("Only in repo"); allowlist do `fn_diff` agora exclui `*.test.ts` (espelha a regra de `*.md`).
6. **Conta interna logável por telefone:** o email da conta interna em prod é `phone_5500900000001@stage.app` — a conversão T2.0 (telefone sintético) **aparenta ter sido aplicada** (contra a pendência registrada na F2). Validação device ainda do fundador.

---

## Pendências do fundador

| # | Ação |
|---|---|
| 1 | Abrir PR no GitHub (branch `fase-3-tracker`) e mergear |
| 2 | **Release 2.5.0**: bump + archive; `posthog_annotate_deploy.sh` na LIBERAÇÃO |
| 3 | **Ativar `applications_tracker_v1`** (rollout 10→50→100 pós-aceitação) — só então o prompt dispara e a janela de ≥30% (aceite #1) começa a contar |
| 4 | Validação device (conta interna por telefone): aba Candidaturas (4 segmentos + status menu + FAB manual), prompt de retorno pós-apply (Sim/Não/Depois), digest de prazo |
| 5 | Pós-flag ao vivo: aceites #1 (≥30%), #3 (1ª análise `apply_abandon_reason` por fonte), #4 (`outbound_clicks` count>0) |

## Fora de escopo confirmado
F4-F6; tracker/console da EMPRESA; candidatura 1-toque/`type='stage'`; match v2; qualquer push além do digest estendido; feed/ranking/holdout/RPC/adapt (R5 intocado); revogação das legacy (critério diferido segue no checklist semanal).
