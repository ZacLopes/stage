# PLANO-FASE-3 — Tracker de candidaturas + prompt de retorno + saída instrumentada

> **Entregável desta sessão (plan mode):** este documento, commitado como
> `PLANO-FASE-3.md` na raiz, na branch `fase-3-tracker`, no padrão das fases
> anteriores. Aprovado pelo fundador (revisado pelo arquiteto) via ExitPlanMode
> **antes** de qualquer código, migration ou deploy. Regras de ouro valem:
> **o fato vence** · **verificado, não declarado**.

---

## Context — por que esta fase, e o que muda no desenho

A Fase 1 já construiu a **espinha de dados** da candidatura (`applications` +
`application_events`, máquina de estados por actor, RLS own, 543 rows
backfilladas). A Fase 3 é **majoritariamente UI nova + um pouco de
instrumentação POR CIMA** dessa espinha — não é criar entidade. Objetivo (espec
§6.2 e §7; refs auditoria H1-H3, E5, O1 #1): (1) virar o sistema-de-registro da
busca do usuário (aba Candidaturas sobre `applications`); (2) iluminar o funil
externo que hoje morre no `launchUrl` cru (prompt de retorno + UTM +
`outbound_clicks`); (3) lembrar prazos de vagas salvas pelo digest existente.

**Desvio estrutural confirmado por grep (o fato vence — muda o desenho de T3.2/T3.4):**
o app tem **um único call site de "aplicar"** —
`lib/features/jobs/screens/liked_jobs_screen.dart::_openApplication` (L106-152).
O `JobDetailsSheet` é aberto pelos 3 surfaces (swipe `:377`, lista `:151`, salvas
`:102`) mas recebe só `job`/`match` — **não tem botão de aplicar nem callback
`onApply`** (o único `launchUrl` dele, `:1077`, é o `onLinkTap` de links
embutidos na descrição HTML, não apply). A auditoria H1 e o PLANO-MÃE ("dois call
sites: liked + job_details_sheet") estão **desatualizados**. Consequência boa: o
apply é **downstream dos dois feeds** (swipe e lista salvam no mesmo
`swipe_actions`/liked; aplica-se sempre pela aba Salvas) → cobrir "swipe E lista"
(A2) é satisfeito **estruturalmente por um único ponto de instrumentação**.

---

## 0. Verificações de plan mode (fatos medidos — verificado, não declarado)

**B1 — Estado real de `applications` (query MCP, 2026-06-16):**
| dim | valor |
|---|---|
| total | **543** |
| por type | `external_confirmed` 543 · `manual` 0 · `stage` 0 |
| por status | `submitted` 542 · `withdrawn` 1 · (todos os demais = 0) |
| usuários com ≥1 application | **147** |

Hoje só existe `external_confirmed` (a F1 backfillou `swipe_actions.applied →
external_confirmed/submitted`). `manual` nasce nesta fase (T3.3); `stage` só na
F4. **Em processo e Finalizadas ficam quase vazias hoje** (só 1 withdrawn) — a aba
aparece com Salvas e Enviadas populadas.

**B1b — "Salvas" (liked sem application), join real (query MCP):**
liked total **7.345** / **1.036** usuários distintos; **liked SEM application
(Salvas) = 6.802**; liked COM application = 543 (= total de applications, todas
vieram de liked→applied). É com isso que a aba aparece no device hoje.

**B2 — Aba "Salvas/Curtidas" atual:** `liked_jobs_screen.dart` (tab label
`'Salvas'`, `home_screen.dart:426`, `HomeTabs.saved=1`). Carrega via
`JobsViewModel.loadLikedJobs()` (`jobs_viewmodel.dart:1349`): `getLikedJobsWithDetails`
(`swipe_repository.dart:75`, embed `jobs(*, companies(*))`) + `fetchForUser`
(applications) → mapa `_applicationsByJob`. **Já lê "aplicada" de `applications`**
(`applied = app?.status.countsAsApplied`, L1369) — pós-F1, **não** de
`swipe_actions.applied`. Hoje segmenta em 3 baldes (pending/applied/expired,
L286-344). Vira "Candidaturas" com 4 segmentos.

**B3 — TODOS os call sites de "aplicar" (grep exaustivo):** **um só** —
`liked_jobs_screen.dart::_openApplication` (L106-152): emite
`job_details_apply_clicked` (L119), resolve url-vs-mailto em `_resolveApplyAction`
(L391-413), `launchUrl(action.uri, externalApplication)` (L140). Swipe card e
célula da lista: **sem botão de aplicar** (só salvam/descartam). Detalhe: **sem
botão de aplicar**. (Verificado: `grep launchUrl lib/` → só `liked_jobs_screen:140`
e o `onLinkTap` da descrição `job_details_sheet:1077`.)

**B4 — Observer de foreground:** `_AnalyticsLifecycleObserver` (`WidgetsBindingObserver`,
`analytics_service.dart:1894-1926`) → `didChangeAppLifecycleState` → `resumed` →
`_onForegrounded()` (L268-286, emite `app_foregrounded`). Registrado em
`bindLifecycle()` (L211-216), chamado em `main.dart:140`. **É um service sem
BuildContext** → o prompt (que mostra bottom sheet) **não** pode disparar daqui;
precisa de um observer na camada UI (HomeScreen) — ver T3.2.

**B5 — Persistência local (`pending_apply`):** padrão estabelecido =
`JobSwipeContext` (`lib/features/jobs/job_swipe_context.dart`, SharedPreferences
key `job_swipe_context_v1`, mapa job_id→`{m,a,s}`, TTL 30 dias, GC no load). É o
lugar natural de um slot `pending_apply {job_id, ts}` (novo método/slot).

**B6 — Funil externo hoje (PostHog, medido):** evento de apply-clique **existe**
(`job_details_apply_clicked`, props `job_id/match_score/application_method/used_adapted_cv`).
URL aberta crua (sem UTM — confirmado). Volume semanal:
| semana | clicks | usuários |
|---|---|---|
| 2026-05-24 | 38 | 22 (pré-ads) |
| 2026-05-31 | 336 | 185 (pico pós-Facebook Ads) |
| 2026-06-07 | 200 | 93 |
**Baseline para o aceite:** ~**200-300 apply-clicks/semana**. ≥30% de resposta ⇒
~60-90 respostas/semana esperadas.

**B7 — `notifications-daily-digest`:** (`supabase/functions/notifications-daily-digest/index.ts`)
hoje escolhe 1 de 3 variantes (`pickVariant`, L60-93) e mira **só o cohort D+1**
(usuários criados 22-26h atrás, L152-195). Lê `adapted_resumes` e `user_progress`
— **não lê `jobs`/`swipe_actions`/`deadline`**. Push via `sendOneSignalPush`
(L95-118); cron em `20260519000000_cron_notifications_daily_digest.sql`; emite
`notifications_digest_sent` (`_shared/posthog.ts`, L277-291). `jobs.deadline`
(timestamptz) e `jobs.is_active` existem; saved jobs = `swipe_actions action='liked'`.

**B8 — Catálogo de eventos (`lib/services/analytics_events.dart`):** já existem
`application_created/state_changed/reopened` (L537-545, `application_state_changed`
**carrega `application_type`**) e — **achado-chave** — `job_details_apply_external_opened`
(L302) e `job_details_apply_returned` (L303) **sem nenhum emissor** (catálogo
morto, dívida de R7). Reutilizá-los (em vez de inventar `outbound_click`/return novo)
zera essa dívida no mesmo PR.

**A4 — Conta interna logável por telefone:** o T2.0 da F2 **NÃO foi rodado pelo
fundador** (`FASE-2-RELATORIO.md` pendências #1: `convert_internal_account.sh`
ainda não executado). **Sinalizado:** o e2e device da F3 depende de rodar
`scripts/convert_internal_account.sh` + `validate_internal_login.sh` (telefone
sintético (00) 90000-0001) antes da validação device.

**Schema pronto (query MCP):** `applications` tem `external_company`,
`external_title`, `job_id` **nullable** com CHECK `(job_id IS NOT NULL) OR
(type='manual')`, `notes`, `rejection_category`, RLS insert/select/update own.
Status CHECK = os 9 estados. **`outbound_clicks` NÃO existe. Não há `external_url`
em applications** (decisão D3 abaixo).

---

## 1. Decisões de design (cada uma com o fato que a sustenta)

1. **Aba = nova UI sobre `applications`, zero entidade nova.** Renomeia
   `Salvas → Candidaturas`, 4 segmentos. Fato: B1/B1b/B2 — os dados já existem;
   `loadLikedJobs` já junta liked+applications.
2. **4 segmentos** (decisão do fundador, recomendada): Salvas / Enviadas /
   **Em processo** (in_review+shortlisted+interview+offer) / Finalizadas
   (hired+rejected+withdrawn+expired). Fato: 100% das apps hoje em
   submitted/withdrawn → 4 e 5 segmentos são visualmente idênticos até a F4;
   separar "Entrevistas" fica para a F4 (quando entrevista real existir).
3. **Atualização manual de status só para `type ∈ (manual, external_confirmed)`;
   `stage` é read-only para o usuário.** Fato: a matriz da F1 (`canTransition`,
   `application.dart:142-173`) já impõe isso no banco e no espelho client; a UI só
   não oferece os controles para `stage`.
4. **Prompt de retorno num único choke point** (`_openApplication`). Fato B3:
   apply só existe lá; cobre swipe E lista por construção.
5. **Prompt dispara da camada UI (HomeScreen), não do service.** Fato B4:
   `_onForegrounded` não tem BuildContext.
6. **Re-pergunta "Depois" = IN-APP em 24h** (decisão do fundador), **não push**.
   Fato/constraint: a F3 proíbe push novo (só o digest). Desvio consciente da
   espec §6.2 ("push suave") — o constraint vence.
7. **4 chips de abandono fixos** (decisão do fundador): `processo_longo` ·
   `vaga_fechada` · `pediram_demais` · `so_olhando` (sem "Outro"). Preserva o
   sinal estruturado de fricção por fonte (espec §6.2).
8. **Reusar constantes mortas em vez de inventar.** Fato B8:
   `job_details_apply_external_opened` ← outbound click; `job_details_apply_returned`
   ← retorno detectado; `application_state_changed` (com `application_type`) ←
   mudança manual de status. **Não** criar `outbound_click` nem
   `application_status_changed_manual`.
9. **Link do manual em coluna nova `applications.external_url`** (server-imediato),
   paralela a external_company/external_title. Fato: schema não tem onde guardar;
   `notes` é semântica de "nota/próximo passo".
10. **UTM + outbound só no apply (não no `onLinkTap` da descrição).** Fato B3: o
    `:1077` abre links arbitrários da descrição, fora do funil de candidatura.

---

## 2. (D1) Mapa segmento→status + a query da aba

**Fonte de dados (client, reusando repos existentes):** união de
`getLikedJobsWithDetails(userId)` (liked + job + company) **com**
`ApplicationsRepository.fetchForUser(userId)` (todas as applications). Para apps
com `job_id` que não estão no conjunto liked (ou manuais sem job), **estender
`fetchForUser` com embed PostgREST** `applications.select('*, jobs(*, companies(*))')`
(jobs/companies já são readable — o liked-join faz o mesmo embed hoje). Manual
(`job_id` null) renderiza de `external_company`/`external_title`/`external_url`.

| Segmento | Critério | Count hoje (B1/B1b) |
|---|---|---|
| **Salvas** | liked (`swipe_actions.action='liked'`) cujo `job_id` **não tem** application | **6.802** (1.036 users) |
| **Enviadas** | application `status='submitted'` | 542 |
| **Em processo** | `status ∈ {in_review, shortlisted, interview, offer}` | 0 |
| **Finalizadas** | `status ∈ {hired, rejected, withdrawn, expired}` | 1 |

Bucketing = **função pura** `segmentForStatus(ApplicationStatus) → Segment` +
regra "liked sem app ⇒ Salvas" (unit-testável, R3). Badge "Expirada" da aba atual
(`!is_active OR deadline<now`) preservado dentro de Salvas/Enviadas.

---

## 3. (D2) Cobertura de apply + desenho do `pending_apply`

| Ponto de apply | Existe hoje? | O que dispara | Como o prompt captura |
|---|---|---|---|
| Swipe card | **sem apply** (só salva) | — | n/a (apply é downstream, na aba Salvas) |
| Célula da lista (F2) | **sem apply** (só salva) | — | n/a (idem) |
| Detalhe (`JobDetailsSheet`) | **sem apply** (só `onLinkTap` da descrição) | — | n/a |
| **Salvas `_openApplication`** | **SIM (único)** | grava `pending_apply{job_id,ts,title,company}` após `launchUrl==true` (url **e** mailto) | observer de foreground lê e mostra o sheet |

**`pending_apply` (extensão de `JobSwipeContext`):** slot único (key dedicada
`pending_apply_v1` = `{job_id, title, company, ts, reask_after?}`), gravado em
`_openApplication` para **ambos** os métodos (url e mailto — o usuário aplicou nos
dois). Métodos novos: `recordPendingApply(job)`, `readPendingApply()`,
`clearPendingApply()`, `scheduleReask()` (seta `reask_after = ts+24h`).

**Observer do prompt (camada UI):** `_HomeScreenState` ganha `WidgetsBindingObserver`;
no `resumed`, lê `pending_apply`: se `age < 30min` (ou `now ≥ reask_after`) →
`showModalBottomSheet` com `_HomeScreenState.context`. Fluxo:
- **Sim** → `ApplicationsRepository.markApplied(userId, jobId, method)` (já cria
  `external_confirmed/submitted` ou reabre; **já emite** `application_created`/
  `application_reopened`, R7) + emite `apply_confirmed`; `clearPendingApply()`.
- **Não** → chips → emite `apply_abandon_reason` (props `reason`, **`job_source`** =
  o ouro: fricção por fonte); `clearPendingApply()`.
- **Depois** → `scheduleReask()` (re-ask no 1º foreground ≥24h; depois disso,
  `clearPendingApply()` sem 3ª).
- Ao exibir: emite `apply_prompt_shown`; ao detectar retorno: reusa
  `job_details_apply_returned`.

---

## 4. (D3) `outbound_clicks` + UTM

**DDL (migration, SERVER-IMEDIATO):**
```sql
create table public.outbound_clicks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  job_id uuid references public.jobs(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.outbound_clicks enable row level security;
create policy outbound_clicks_insert_own on public.outbound_clicks
  for insert to authenticated with check (auth.uid() = user_id);
create policy outbound_clicks_select_own on public.outbound_clicks
  for select to authenticated using (auth.uid() = user_id);
create index outbound_clicks_user_created_idx on public.outbound_clicks (user_id, created_at desc);
create index outbound_clicks_job_idx on public.outbound_clicks (job_id);
-- coluna do link do manual (decisão #9), aditiva:
alter table public.applications add column external_url text;
```
(Leitura cross-user para o relatório B2B "X salvaram, Y clicaram" = service
role/console na F4; own-select basta agora.)

**Regra de UTM (função pura `decorateOutboundUrl(Uri) → Uri`):** só `http(s)`;
`mailto` e outros schemes **intocados**; `putIfAbsent` preserva query/utm
existentes; preserva fragment.
```dart
if (uri.scheme != 'http' && uri.scheme != 'https') return uri; // mailto intacto
final qp = Map<String,String>.from(uri.queryParameters)
  ..putIfAbsent('utm_source', () => 'stage')
  ..putIfAbsent('utm_medium', () => 'app')
  ..putIfAbsent('utm_campaign', () => 'job_apply');
return uri.replace(queryParameters: qp);
```
| antes | depois |
|---|---|
| `https://jobs.gupy.io/vaga/123?src=abc` | `…/vaga/123?src=abc&utm_source=stage&utm_medium=app&utm_campaign=job_apply` |
| `https://x.com/a` (sem query) | `https://x.com/a?utm_source=stage&utm_medium=app&utm_campaign=job_apply` |
| `mailto:rh@x.com?subject=Vaga` | **inalterado** |

Aplicada em `_openApplication` (branch url) antes do `launchUrl`; no mesmo ponto,
**insere `outbound_clicks` own-insert** e emite `job_details_apply_external_opened`
(reuso B8) com `job_id`/`job_source`. mailto → sem UTM, sem outbound row. Client
sai na 2.5.0; tabela é server-imediato.

---

## 5. Tarefas — camada por tarefa

| T | Escopo | Camada |
|---|---|---|
| **T3.1** | Aba Candidaturas (rename + 4 segmentos + embed em `fetchForUser` + menu manual de status) | **CLIENT-2.5.0** |
| **T3.2** | Prompt de retorno (`pending_apply` + observer HomeScreen + sheet + eventos) | **CLIENT-2.5.0** |
| **T3.3** | Adição manual (FAB + sheet → `application type='manual'`) | **CLIENT-2.5.0** (usa `external_url` de T3.4) |
| **T3.4** | UTM + `outbound_clicks` + `applications.external_url` | **migration SERVER-IMEDIATO** + client 2.5.0 |
| **T3.5** | Digest com prazos (vagas salvas deadline ≤48h) | **SERVER-IMEDIATO (edge)** |

**T3.1 — Aba Candidaturas.** Arquivos: `liked_jobs_screen.dart` (vira tracker;
4 segmentos via `segmentForStatus`), `home_screen.dart` (label `Salvas→Candidaturas`,
ícone), `applications_repository.dart` (`fetchForUser` com embed jobs/companies),
`application.dart` (helper de segmento). Menu de status por célula: só renderiza
para `type ∈ (manual, external_confirmed)`, opções validadas por `canTransition`;
ao mover, chama um novo `ApplicationsRepository.updateStatus(...)` → emite
`application_state_changed` (reuso). **Atrás de flag** `applications_tracker_v1`
(estrutural; OFF default; rollout 10→50→100, R4) — flag OFF mantém a Salvas atual.

**T3.2 — Prompt de retorno.** Arquivos: `job_swipe_context.dart` (slot
`pending_apply`), `liked_jobs_screen.dart` (`recordPendingApply` em `_openApplication`),
`home_screen.dart` (`WidgetsBindingObserver` + `showModalBottomSheet` do prompt),
novo `apply_return_prompt_sheet.dart`, `analytics_events.dart` + emissores
(R7, mesmo PR). Mesma flag `applications_tracker_v1`.

**T3.3 — Adição manual.** FAB na aba → `manual_application_sheet.dart` (empresa +
título + link opcional + status inicial; meta UX ≤10s). Novo
`ApplicationsRepository.createManual({externalCompany, externalTitle, externalUrl, status})`
→ INSERT `type='manual'`, `job_id=null` (passa o CHECK), emite `application_created`
(`application_type='manual'`). A matriz da F1 já permite INSERT manual em qualquer
status inicial (confirmado na F1). Mesma flag.

**T3.4 — UTM + outbound_clicks.** Migration (DDL §4) + `supabase db push`;
`url_utils.dart` (`decorateOutboundUrl`) + insert em `_openApplication` + emissor
de `job_details_apply_external_opened`. UTM/outbound podem ficar **sempre-on** na
2.5.0 (invisíveis; tabela pronta).

**T3.5 — Digest com prazos.** `notifications-daily-digest/index.ts`: **2ª
passada** na mesma rodada diária — seleciona usuários com liked job
(`swipe_actions action='liked'`) cujo `jobs.deadline ∈ [now, now+48h]`,
`is_active=true`, **sem application** para aquele job; reusa `sendOneSignalPush`
(copy "⏰ {n} vaga(s) salva(s) fecha(m) em 48h", `data.intent='saved_deadline_48h'`).
Dedupe por `external_user_id` na rodada (deadline tem prioridade sobre o nudge
D+1) → **1 push/usuário/dia**. Estende o breakdown do `notifications_digest_sent`
com a nova intent. **Zero novo tipo/template de push.**
**Desvio registrado:** o digest atual mira só o cohort D+1; T3.5 amplia para
"todos com vaga salva expirando" — dentro da mesma função/canal.

**EXPLAIN ANALYZE da query candidata em prod (2026-06-16) — decisão de índice
MEDIDA (correção 1 do fundador):** o plano hoje varre `idx_jobs_active_published_at`
(`is_active=true`) e **filtra** a janela de deadline sobre TODAS as ativas —
`Rows Removed by Filter: 427`, mantém 5; anti-join via `applications_user_job_uniq`
(Index Only Scan) e swipe via `idx_swipe_actions_job_id` (ambos ok). **Execution
303ms** com ~432 vagas ativas (Buffers hit=429; o custo é a varredura de deadline
sobre todas as ativas). A janela de deadline **não está indexada** → na projeção
de 5k ativas (F2) essa varredura cresce ~10×. **Decisão (não mais "opcional"):
entra no PR2 a migration**
```sql
create index jobs_deadline_active_idx on public.jobs (deadline)
  where is_active and deadline is not null;
```
que troca o filtro full-active por um range scan na janela `[now, now+48h]`
(~5 rows). Re-rodar EXPLAIN ANALYZE pós-índice no relatório (aceite: range scan
no novo índice, sem `Rows Removed by Filter` na ordem das ativas).

---

## 6. Ordem de PRs/commits (branch `fase-3-tracker`; padrão F1/F2: 1 PR de fase, commits escopados)

1. **PR1 (SERVER-IMEDIATO):** migration `outbound_clicks` + `applications.external_url`
   + teste SQL `BEGIN…ROLLBACK`. `supabase db push`; `migration list` limpo; manifest.
2. **PR2 (SERVER-IMEDIATO):** migration `jobs_deadline_active_idx` (índice MEDIDO,
   §5 T3.5) + extensão do digest (cohort de prazo). `migration list` limpo;
   `deno check` + `check_functions_drift` OK (commit→deploy, nunca o inverso).
3. **PR3 (CLIENT 2.5.0):** T3.4 client (UTM + outbound insert + emissor reusado).
4. **PR4 (CLIENT 2.5.0):** T3.1 tracker (atrás de `applications_tracker_v1`).
5. **PR5 (CLIENT 2.5.0):** T3.2 prompt de retorno (mesma flag).
6. **PR6 (CLIENT 2.5.0):** T3.3 adição manual (mesma flag).

Server-imediato (PR1/PR2) pode subir antes da release. Cliente sai na **2.5.0**.
R5 intocado: nada de adapt/golden_set/ranking/RPC/holdout. R6: legacy congelada.

---

## 7. Testes (R3 — com local de execução)

**Dart unit** (`flutter test`): `decorateOutboundUrl` (mailto intacto · query
preservada · sem dup de utm · sem-query) · `segmentForStatus` + "liked sem app ⇒
Salvas" · `pending_apply` (write/read/expiry 30min/re-ask 24h) · mapeamento dos 4
chips de abandono.
**Widget** (1 por tela crítica nova): tracker com 4 segmentos (dados semeados,
incl. 1 manual) · `apply_return_prompt_sheet` (Sim/Não/Depois) ·
`manual_application_sheet` (cria manual ≤10s).
**SQL `BEGIN…ROLLBACK`** (em `supabase/scripts/`, padrão DO block → `RAISE
EXCEPTION 'TESTS_OK'`, sem tocar `user_profiles`): `outbound_clicks` RLS
(own-insert/own-select; anon negado) · `applications.external_url` aditiva (INSERT
manual `type='manual'`, `job_id=null`, `external_url` setado passa o CHECK) ·
query do digest (saved jobs expirando) devolve o cohort certo.
**Edge** (`deno check` + smoke): digest em modo `dry_run`/`targetEmails` com 1
saved job de deadline semeado → retorna a intent `saved_deadline_48h`.
**Dedupe verificada, não afirmada (correção 2 do fundador):** caso explícito no
smoke — usuário que está **no cohort D+1 E** tem vaga salva expirando recebe
**exatamente 1 push, o de prazo** (intent `saved_deadline_48h`, não o nudge D+1).
Asserts: 1 entrada no `variant_breakdown` para esse `external_user_id`, intent =
prazo; nenhum 2º push na mesma rodada.

---

## 8. Critérios de aceite F3 (mensuráveis)

1. **≥30% dos apply-clicks respondem ao prompt em 2 semanas.** Baseline B6:
   ~200-300 `job_details_apply_clicked`/semana. Medição: funil PostHog
   `job_details_apply_clicked → (apply_confirmed | apply_abandon_reason)` ≥30%.
   **Janela conta a partir da ATIVAÇÃO da flag `applications_tracker_v1`, não da
   release da 2.5.0 (verificação do fundador):** com a flag OFF, o prompt de
   retorno também fica OFF (a aba é a Salvas atual) → `apply_abandon_reason`/
   `apply_confirmed` só fluem pós-ativação. As 2 semanas (e a 1ª análise de
   `apply_abandon_reason` por fonte, aceite #3) só começam a contar quando a flag
   estiver ≥ algum % de rollout com o prompt ao vivo.
2. **Tracker exibindo os 3 types.** Com dados de hoje só `external_confirmed`
   existe; aceite = a aba **renderiza corretamente os 3 buckets** (verificado com
   1 `manual` criado in-app + os external_confirmed reais; `stage` real só pós-F4).
3. **1ª análise de `apply_abandon_reason` por fonte** no `FASE-3-RELATORIO.md`.
4. **`outbound_clicks` populando** (count > 0 após release; query MCP).
5. **Zero push novo fora do digest** (nenhum template OneSignal novo; só a variante
   `saved_deadline_48h` no digest existente).

---

## 9. Riscos & fora de escopo

**Riscos:** (a) e2e device depende da conta interna logável por telefone — **T2.0
ainda pendente** (rodar `convert_internal_account.sh`+`validate_internal_login.sh`
antes da validação device da F3). (b) Observer do prompt na HomeScreen: garantir
um único disparo por foreground (debounce; não reabrir se já visível). (c) UTM em
URLs malformadas da fonte → `decorateOutboundUrl` é defensiva (scheme-guard;
fallback = abre crua).

**Fora de escopo (reafirmado):** F4-F6; tracker/console da EMPRESA (é F4 — esta
fase é o lado do candidato); candidatura 1-toque / `type='stage'`; match v2;
qualquer push novo além do digest estendido; portal de empresa;
feed/ranking/holdout/RPC/adapt (R5); revogação das legacy (critério diferido segue
no checklist semanal: `bridge_activity` + builds antigas).

**Perguntas ao fundador — resolvidas (AskUserQuestion):** 4 segmentos (Entrevistas
só na F4) · 4 chips de abandono fixos (sem "Outro") · re-pergunta in-app em 24h
(sem push).
