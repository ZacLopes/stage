# FASE-0-RELATORIO — Segurança, drift e fundação de release

**Executada em:** 2026-06-10 (branch `fase-0-seguranca`, base `0d3cc36`)
**Plano:** `PLANO-FASE-0.md` (aprovado pelo fundador em 10/06 com 5 ajustes condicionais, todos incorporados)
**Commits:** `f768bf7` (plano) → `c62a340` (fundação) → `c6d0341` (rate limit) → `a1f754e` (ntfy) → `94ce97b` (culture_fit/drift) → `4f60339` (bump 2.2.0+5) → este relatório.

---

## O que foi feito × critérios de aceite

| # | Critério | Status | Evidência |
|---|---|---|---|
| 1 | Chave OpenAI fora do bundle | ✅ código / ⏳ fundador | `OPENAI_API_KEY` removida do `.env`; bundle buildado (`flutter build ios --no-codesign`) inspecionado: `flutter_assets/.env` contém só SUPABASE_URL, SUPABASE_ANON_KEY, POSTHOG_API_KEY, POSTHOG_HOST, ONESIGNAL_APP_ID — **0 ocorrências de OPENAI**. ⏳ Pendente fundador: checar usage dashboard + rotacionar a chave + `supabase secrets set` (a chave antiga segue extraível da 2.0.0+2 pública até a rotação). |
| 2 | Rate limit ativo com evento | ✅ | `generate-resume` v42 deployada. Teste e2e real: conta interna + `RESUME_RATE_LIMIT_PER_DAY=1` + 1 linha semeada em `ai_generation_logs` → chamada retornou **HTTP 429 `{"error":"rate_limit_exceeded","limit":1}`** e o evento **`rate_limit_hit`** apareceu no PostHog (10/06 01:14 BRT, function=generate-resume, limit_type=daily_per_user). Secret restaurado para 10; linha semeada deletada. Confirmado: INSERT no log é pós-sucesso (falha não come cota) e policy SELECT-own cobre o count. |
| 3 | ntfy sem PII + tópicos novos | ✅ | `notify-signup` v22 (verify_jwt=false preservado) e `notify-auto-apply-swipe` v3 deployadas. Payloads novos sem PII de candidato (signup: `"Novo cadastro (#N hoje) · User <id8>"`; auto-apply: dados da vaga + IDs). 3 tópicos rotacionados pra alta entropia via secrets. Teste real: signup interno disparou o webhook; auto-apply chamado com vaga e-mail retornou `{"ok":true}` (ntfy aceitou no tópico novo). ⏳ Fundador: assinar os 3 tópicos novos no celular (nomes entregues em canal privado, não commitados). |
| 4 | Drift resolvido + migration list limpo | ✅ | Pré-check: única pendente era `20260607000000`. `supabase db push` aplicou; pós-check: `to_regclass` ok, RLS on, 4 policies own; `supabase migration list` limpo (local = remoto). `culture_fit_repository`: `_saveRemoteBestEffort`/`_loadRemote` agora emitem `captureException(handled: true)` com contexto em vez de `developer.log` mudo. **Sem backfill de culture_fit: a feature nunca chegou a usuário real, prod está em 2.0.0+2.** ⏳ Verificação app-level (salvar culture fit num device e ver a row) fica pro próximo run do fundador. |
| 5 | CI verde (4 jobs) | ✅ local / ⏳ PR | `.github/workflows/ci.yml`: analyze (`--no-fatal-warnings` + ratchet), test (.env dummy), env-safety, migrations-manifest. Rodados localmente: analyze 0 errors / **46 warnings** (baseline atualizada 47→46 — deleção do world_screen), `flutter test` 6/6 verde, `check_env_safety: OK`, manifest OK (77+0 migrations... 78 com a culture_fit já contada). Confirmação no GitHub acontece no PR da fase. |
| 6 | Build-régua submetida | ⏳ fundador | `pubspec.yaml` → **2.2.0+5** commitado. Fundador: archive + upload via Xcode → revisão. `posthog_annotate_deploy.sh` roda **na liberação aos usuários** (não no upload). |
| 7 | Testes verdes + R5 | ✅ | `flutter test` 6/6. **Golden_set NÃO requerido — nenhuma mudança no pipeline adapt nesta fase (R5).** |

## Desvios do plano

1. **Fix colateral em `generate-resume/index.ts`:** o arquivo do repo tinha parêntese faltando no fechamento do `withEdgeAnalytics` — **não parseava no bundler**. Ou seja: o código deployado (v40) não veio do arquivo do repo; deploys anteriores dessa function foram feitos de uma cópia fora do repo (mesma classe de drift do C6, agora em função). Corrigido junto com o rate limit; a partir de v42 o deploy vem do repo.
2. **`parse-cv-pdf` já tinha header DEPRECATED** (desde 22/05) — só `parse-cv` e `generate-profile` precisaram do header novo.
3. **`generate-profile` não está 100% sem caller** como o plano-mãe assumia: existe o wrapper `AIService.generateProfileContent` (`ai_service.dart:339`), porém **sem nenhum call site** — morto de fato, deprecação segura. (Regra "auditoria vence": registrado aqui.)
4. **Baseline de warnings nasceu 46, não 47** — a deleção do `world_screen.dart` removeu 1 warning; o ratchet já trava no número menor.

## Decisões documentadas

- **`.env` permanece como asset do bundle** contendo apenas chaves públicas-by-design (SUPABASE_URL/ANON_KEY, POSTHOG_*, ONESIGNAL_APP_ID). Migração para `--dart-define` anotada como melhoria futura — não bloqueia.
- **Drift-check real (`supabase migration list`) roda local** (checklist de release); o CI usa o manifest commitado. Sem secrets no GitHub (decisão do fundador, 10/06).
- **Operação do auto-apply muda:** o push não traz mais contato do candidato — consulta no admin dashboard (decisão do fundador, 10/06).
- **Conta de teste interna criada:** `internal-fase0-test@stage.app` (user `3eaf8faa…`) — usada nos e2e desta fase, mantida para as próximas; conta +1 no signup de hoje (10/06) nos relatórios.

## Pendências (checklist do fundador)

| # | Ação | Referência |
|---|---|---|
| 1 | Usage dashboard OpenAI: checar consumo anômalo → me passar o veredito (entra neste relatório) | T0.1 |
| 2 | Rotacionar chave OpenAI + `supabase secrets set OPENAI_API_KEY=<nova>` → eu rodo o smoke de `analyze-match` na sequência | T0.1 |
| 3 | Assinar os 3 tópicos ntfy novos no celular (nomes em canal privado) | T0.3 |
| 4 | Abrir/aprovar o PR da fase (CI roda lá) e mergear | T0.5 |
| 5 | Archive + upload 2.2.0+5 → revisão App Store | T0.6 |
| 6 | Na liberação aos usuários: `scripts/posthog_annotate_deploy.sh` | T0.6 |
| 7 | Setup one-time do hook local: `git config core.hooksPath scripts/githooks` (já feito nesta máquina) | T0.1 |

## Estado final

- `supabase migration list`: **limpo** (78 migrations local = remoto, até `20260607000000`).
- Functions deployadas a partir do repo: `generate-resume` v42, `notify-signup` v22, `notify-auto-apply-swipe` v3.
- Secrets alterados: `RESUME_RATE_LIMIT_PER_DAY=10`, `NTFY_TOPIC`, `NTFY_TOPIC_AUTO_APPLY`, `NTFY_TOPIC_REPORT` (rotacionados). `OPENAI_API_KEY` pendente de rotação pelo fundador.
- Golden_set: **não requerido** nesta fase (adapt intocado — R5).
