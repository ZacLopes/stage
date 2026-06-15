# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Sistema de trabalho (leia ANTES de qualquer tarefa)

O Stage está sendo evoluído por um **plano-mãe de 7 fases (0–6)** desenhado por arquiteto externo sobre a `AUDITORIA-STAGE.md` (raiz). Ciclo de cada fase: **`PLANO-FASE-N.md` na raiz, aprovado pelo fundador ANTES de codar → execução → `FASE-N-RELATORIO.md`**. Duas regras de ouro:

- **"O fato vence":** em conflito entre plano-mãe/auditoria e o que o código/banco mostram, o fato verificado ganha — e o desvio é registrado no plano/relatório.
- **"Verificado, não declarado":** aceite = medição real (query, HTTP, output de script colado). Smoke precisa forçar o **caminho real** — ex.: `analyze-match` com perfil vazio cai no bypass do Cenário C (score 50 sem chamar OpenAI) e não prova nada; semeie 1 preferência antes.

### Regras R1–R8 do plano-mãe

- **R1** — Plano antes de código: `PLANO-FASE-N.md` aprovado pelo fundador; `FASE-N-RELATORIO.md` ao final (feito, desvios, aceites medidos).
- **R2** — Schema SÓ via migration + CLI (`supabase db push`); dashboard proibido; `supabase migration list` limpo antes de cada PR.
- **R3** — Código novo não nasce nu: unit tests pra lógica de domínio + 1 widget test por tela crítica nova (sem meta retroativa).
- **R4** — Comportamento visível atrás de flag (`app_feature_flags` estrutural; PostHog pra experimento), rollout 10→50→100%.
- **R5** — Encostar no pipeline adapt = rodar `golden_set/` antes/depois; mudança de prompt = bump de `PROMPT_VERSION`.
- **R6** — Sem reescritas arquiteturais (Provider/Navigator ficam); legacy se CONGELA, não se deleta; sem refactor oportunista fora do caminho da tarefa.
- **R7** — Evento novo = constante em `analytics_events.dart` + emissor no MESMO PR (nunca catálogo morto); transições server-side emitem via `_shared/posthog.ts` `captureEvent`.
- **R8** — Uma branch por fase (`fase-N-...`), conventional commits, PRs pequenos por frente.

### Aprendizados permanentes

- **Deploy só a partir do repo** + `scripts/check_functions_drift.sh` no checklist de release — compara o `_shared/` embarcado em CADA bundle, não só o function-dir (bundles ficam com `_shared` defasado mesmo com function-dir idêntico).
- **Deploy só de código COMMITADO** — deployar do working tree cria drift instantâneo entre repo e prod (aconteceu em 12/06 com os fixes do admin deployados antes de commitar; flagrado por `check_functions_drift.sh` e alinhado no mesmo dia). Ordem certa: commit → deploy, nunca o inverso.
- **Migrations só via CLI + manifest** (`scripts/check_migrations_manifest.sh`); nunca pelo dashboard.
- **`deno check` no CI** (job `functions-check`; config relaxada em `scripts/deno-check.jsonc`; adapt excluído por R5) — matou a classe "parêntese do wrapper" (4 ocorrências: generate-resume, generate-bullets, generate-summary, generate-profile).
- **`verify_jwt` dos webhooks vive em `supabase/config.toml`** (`ingest-jobs-email`, `notify-signup`) — deploy sem isso reativaria JWT e quebraria os webhooks silenciosamente.
- **Testes SQL em `BEGIN…ROLLBACK`** curtos (padrão: DO block que termina em `RAISE EXCEPTION 'TESTS_OK'`), **sem tocar `user_profiles` dentro** (trigger `notify_new_signup` dispara webhook http REAL).
- **Edits manuais em `applications` via Studio:** `set_config('app.actor', 'admin', true)` na MESMA transação — senão o actor resolve como `system` e a matriz de transições bloqueia/loga errado.
- **Pontes legacy** marcadas `BRIDGE` (triggers `_bridge_*`) com critério de revogação diferida: builds antigas <5% dos eventos semanais por 2 semanas **E** zero `bridge_activity` na janela; monitorar também `user_preferences.updated_at` semanal.
- **Conta interna de teste:** `internal-fase0-test@stage.app` (user `3eaf8faa-…`) — instrumento dos e2e; tem desired_title **"Tecnologia" semeado** (feed/match dela refletem isso).
- **Tópicos ntfy são bearer tokens** de canal público — nunca em commit/PR/screenshot.
- **`.env` é asset do bundle** (embarca no IPA) — só chaves públicas-by-design; `scripts/check_env_safety.sh` (CI + pre-commit via `git config core.hooksPath scripts/githooks`) garante.

### Estado atual (2026-06-12)

**Fases 0–1 mergeadas no main** (relatórios na raiz); 2.2.0 em produção desde ~09/06 com baseline anotada no PostHog; **2.3.0+6 submetida à revisão da App Store**; fixes do admin commitados (f1d7cb9). **Fase 2 EXECUTADA em 12/06** (`PLANO-FASE-2.md` + REV-1; branch `fase-2-feed-server`, 4 commits escopados = PR1-PR4 do §6): server — RPC `get_feed_page` v1.2 em prod (v1.0 → v1.1 fix perf 167→20ms → v1.2 rank 6dp cursor float-safe), D-11 (50 títulos legacy → 0), `feed_list_v1` OFF, `company_requests`; client 2.4.0 — lista + swipe por snapshot atrás da flag, exaustão honesta + "Pedir uma empresa" (+ aba Pedidos no admin, edge deployada), bandas + holdout (flag PostHog 693925 reconfigurada 80/20, INATIVA) + selo de fonte no detalhe. `FASE2_TESTS_OK_V12` + paridade 7/7 verificados contra prod (harness `tools/feed_parity/`). Falta: device-validação (conta interna), release 2.4.0, rollout 10→50→100 + ativação do holdout, fechamento (deletar shuffle, aceite #4). Relatório: `FASE-2-RELATORIO.md`.

**Ajustes pré-2.4.0 (15/06, branch `fase-2-fixes` de main; `FASE-2-FIXES-RELATORIO.md`)** — 4 defeitos da validação device, saem JUNTOS na 2.4.0: #3 detalhe da lista/salvas mostrava 0% (abria sem match) → cache de resultado movido pro `JobsViewModel` (compartilhado swipe↔detalhe) + `resolveMatchForJob` + pending=spinner; #1 célula da lista só com razões (banda saiu — divergia do detalhe; ordenação segue por rank_score); #2 copy do detalhe com baldes 85/70/40/<40; #4 `inferArea` com 2 rulesets (título completo, descrição forte — sem boilerplate) + backfill `tools/reclassify_active_areas/`. Commits `07c5185`+`4a97c3b`+`035ab1c` (fix-forward de regressões de saúde pegas no dry-run do backfill). Verde: analyze 0/0, flutter test 40, deno test 11/11, deno check 27. **Deploy+backfill FEITOS (15/06):** as 4 functions que embarcam `_shared/jobs.ts` deployadas (2 rodadas), `check_functions_drift` OK; backfill de 57 vagas gupy/brz aplicado via MCP (backup local revertível). Aceites em prod: **Tech-sem-token-no-título 16→1**, regressão de saúde 0, **paridade feed_parity 7/7**. **+ Fix #5 (`ab95d2e`):** exaustão do feed mostrava "filtros restritivos" (B) em vez de "esgotou as relevantes" (A) após swipar tudo — `filtersAreTooRestrictive` usava totais pós-swipe; agora usa `totalMatchingCatalog` (matches ignorando swipe), via função pura `feedFiltersTooRestrictive`. Caminho RPC degrada pra A até `get_feed_page` retornar `total_matching_catalog` (follow-up antes do rollout da lista). flutter test 45. **Falta (fundador):** só validação device. Detalhe: `FASE-2-FIXES-RELATORIO.md`.

Pendências do fundador: **validação device dos fixes (ver `FASE-2-FIXES-RELATORIO.md`)**; rodar `scripts/convert_internal_account.sh` + `scripts/validate_internal_login.sh` (T2.0 — telefone sintético (00) 90000-0001; gate de onboarding já semeado); validação device da 2.3.0 quando aprovada (Curtidas/gate/typeahead); shortlist real em <5min (dashboard → Busca); assinar tópicos ntfy; `scripts/posthog_annotate_deploy.sh` na **liberação** de cada build aos usuários (não no upload); momento do rollout `feed_list_v1` e ativação do holdout (pós-aceitação da 2.4.0).

---

## Commands

```bash
flutter run                 # device/emulator (iOS only — não há /android)
flutter analyze --no-fatal-warnings   # 0 errors; ratchet de warnings no CI (baseline em scripts/analyze_warnings_baseline.txt)
flutter test                # suite completa
bash scripts/check_env_safety.sh
bash scripts/check_migrations_manifest.sh
bash scripts/check_functions_drift.sh      # release checklist (baixa deployado e difa)
bash scripts/check_functions_types.sh      # deno check (parse + tipos grossos)
supabase db push            # migrations (CLI linkado; R2)
supabase functions deploy <slug>           # webhooks pegam verify_jwt do config.toml
```

Requires a `.env` file at project root with `SUPABASE_URL` and `SUPABASE_ANON_KEY` (see `.env.example`). O `.env` é ASSET do bundle — nunca colocar chave de servidor nele.

## Architecture

**Pattern:** MVVM + Repository. Feature-first em `lib/features/` (3 gerações de estilo coexistem; `profile/` é a referência com domain/data/application/presentation).

**State management:** Provider + ChangeNotifier; providers registrados em `main.dart` (`MultiProvider`). `JobsViewModel` recebe `JobRepository`, `SwipeRepository`, `ApplicationsRepository`, `AIService`.

**Espinha de dados (Fase 1):** `applications` + `application_events` com máquina de estados validada por trigger no banco (matriz por actor via GUC `app.actor` > JWT > system; espelho client em `lib/features/jobs/models/application.dart` `canTransition`). `swipe_actions.applied` é DEPRECATED (bridge converte builds antigas). Gate de onboarding = `profile_personal.onboarding_completed_at` (`hasCompletedOnboarding`), não mais `hasCampaign`. Preferências: fonte única relacional (`profile_job_preferences` + `profile_desired_titles` — que contém ÁREAS — + `profile_other_locations`); `user_preferences` é fóssil. Instituições: catálogo `institutions` (95 IES) + `profile_education.institution_id` + typeahead.

**Data layer:** `SupabaseRepository` (legacy/trilha, cache em memória), repositories por feature em `lib/features/*/data/`, `ProfileRepositorySupabase` pras tabelas `profile_*`.

**Backend:** Supabase (Postgres + Auth + Storage + ~28 Edge Functions Deno — IA via OpenAI server-side; inventário na `AUDITORIA-STAGE.md` C4). Admin B2B: `admin_dashboard/` (React/Vite) + edges `admin-*` (auth via `admin_users`).

## Navigation

No routing package — `Navigator.push` direto. Entry: `SplashScreen` → `AuthGate` (`splash_screen.dart`) → decide por `hasCompletedOnboarding` / `isInProfileFirstFlow` / `needsProfileSetup` → `HomeScreen` (4 tabs: Vagas, Salvas, Currículo, Perfil) ou onboarding. Tab change profunda via `HomeViewModel.requestTabChange(index)`.

## Key Design Decisions

- **Resume export:** só PDF, client-side (`Printing.convertHtml` em `PdfService.generateResumeBytes`); 5 templates como `_buildXxxHtml` em `pdf_service.dart` (default `harvard_ats`). Thumbnails: regenerar via Settings → "[DEV] Gerar thumbnails" após mudar template.
- **Match score:** IA (`analyze-match`, gpt-4o-mini, cache `match_analyses`, versão ativa em `app_config.match_prompt_version`) com fallback determinístico (`match_score.dart`, pesos 30/20/15/15/10/10). Exibição por confidence (low = "Análise limitada").
- **Adapt v2** (`adapt-resume-to-job/v2.ts`, flag `adapt_v2_enabled`=100%): anti-invenção + diff explicável. Tocar = R5 (golden_set).
- **Sempre** `await ensureProfilePrefsLoaded()` antes de `MatchScoreCalculator.calculate` (race condition conhecida).

## Theme & Localization

- Design system em `lib/core/theme/` (barrel `theme.dart`) + componentes em `lib/core/widgets/`. **Nunca hardcode** `Color(0xFF...)`/`EdgeInsets`/`TextStyle` em feature code — use `AppColors.*`, `AppSpacing.*`, `AppTextStyles.*` etc.
- Brand: azul Stage (`AppColors.primary` #1565A8); verde só pra success.
- Fonts: Outfit (headings) + Inter (body), bundladas estáticas (não usar google_fonts).
- App é pt-BR only; strings hardcoded (sem i18n). Exceção: output do CV adaptado tem PT/EN server-side.
