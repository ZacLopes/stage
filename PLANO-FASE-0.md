# PLANO-FASE-0 — Segurança, drift e fundação de release

**Status:** aprovado pelo fundador em 2026-06-10 (aprovação condicionada incorporada — 5 ajustes + 4 não-bloqueantes).
**Branch:** `fase-0-seguranca` (a partir de `0d3cc36`). **Refs da auditoria:** M1, M4, C6, L3 #1, J5 #1, O2 #4/#5.
**Objetivo:** parar os vazamentos (chave OpenAI no bundle, PII no ntfy), restabelecer confiança no schema (drift de 07/06), reativar o rate limit, criar CI mínimo e publicar a build-régua 2.2.x — baseline de todas as medições futuras.

---

## Tarefas e ordem de execução

A rotação da chave OpenAI é **dia 1** (a exposição está na 2.0.0+2 pública desde 29/05 e não depende da build nova). O resto segue em paralelo.

### T0.1 — Chave OpenAI fora do bundle (M1)
- [ ] **FUNDADOR (dia 1):** conferir usage dashboard da OpenAI por consumo anômalo → resultado vai no relatório.
- [ ] **FUNDADOR (dia 1):** rotacionar a chave no painel OpenAI e rodar `supabase secrets set OPENAI_API_KEY=<nova>`.
- [x] Remover linha `OPENAI_API_KEY` do `.env` local (sem uso no código Dart — grep vazio em `lib/`); `.env.example` já não tinha.
- [ ] Smoke test pós-rotação: 1 chamada de `analyze-match` (conta interna).
- [x] `scripts/check_env_safety.sh`: falha se `.env`/`.env.example` tiver chave proibida (OPENAI|SERVICE_ROLE|SECRET|RESEND|APIFY|NTFY); falha se `.env` aparecer em `git ls-files`; varre arquivos rastreados por `sk-...` (falha sempre) e JWTs `eyJ...` decodificados (falha SÓ com `"role":"service_role"` — anon key é pública by design). Exclusões: `admin_dashboard/dist|node_modules`, `build/`, `ios/Pods/`, `*.lock`, `.dart_tool/`.
- [x] `scripts/githooks/pre-commit` chama o check. Setup one-time: `git config core.hooksPath scripts/githooks`.
- Decisão documentada: `.env` permanece como asset contendo APENAS chaves públicas-by-design (SUPABASE_URL/ANON_KEY, POSTHOG_*, ONESIGNAL_APP_ID). Migração pra `--dart-define` anotada como melhoria futura, não bloqueia.
- Verificação de aceite: `flutter build ios --no-codesign` + inspeção do `.env` dentro do `flutter_assets` do bundle.

### T0.2 — Reativar rate limit de `generate-resume` (L3 #1)
- Restaurar o check comentado (`index.ts:35-51`) com `RESUME_RATE_LIMIT_PER_DAY` (env, default **10**/dia/usuário).
- 429 emite `rate_limit_hit` via `trackRateLimitHit` (`_shared/posthog.ts` — já existia). Corpo: `{error:'rate_limit_exceeded', limit}`.
- Client (`ai_service.dart`): 429 vira mensagem amigável em vez de erro genérico.
- **Verificado em plan mode:** o INSERT em `ai_generation_logs` é pós-sucesso (falha não come cota) e a policy SELECT-own existe (count sob JWT funciona). Contingência: se o e2e com limit=1 não der 429, corrigir via migration (R2).
- Verificação: `RESUME_RATE_LIMIT_PER_DAY=1` temporário → 1ª chamada ok, 2ª = 429 + evento no PostHog → restaurar 10.

### T0.3 — Minimizar PII no ntfy + rotacionar tópicos (M4)
- `notify-signup`: payload vira `"Novo cadastro (#N hoje) · User <id8>"` (count de `user_profiles` do dia em America/Sao_Paulo — UTC-3 fixo, sem lib de timezone). Sai: nome, e-mail, curso, semestre.
- `notify-auto-apply-swipe`: saem nome/e-mail/telefone do candidato (e os SELECTs que só serviam a eles). Ficam dados DA VAGA: título · empresa, `Enviar para: <application_email>`, assunto, Job ID, `User <id8>`. **Mudança de operação:** o contato do candidato passa a ser consultado no admin dashboard (decisão do fundador, 10/06).
- Tópicos ntfy rotacionados pra alta entropia (tópico é bearer token de canal público): 3 secrets novos via `openssl rand -hex 12`.
- [ ] **FUNDADOR:** re-assinar os 3 tópicos novos no app ntfy do celular (os nomes são entregues em canal privado, nunca commitados).
- Verificação: 1 signup de teste + 1 auto-apply de teste chegando nos tópicos novos, sem PII de candidato.

### T0.4 — Resolver o drift `user_culture_fit_preferences` (C6)
- `supabase migration list` antes (registrar) → `supabase db push` (aplica só a `20260607000000`) → pós-check `to_regclass` + `pg_policies`.
- `culture_fit_repository.dart`: `_saveRemoteBestEffort` e `_loadRemote` deixam de engolir falha em `developer.log` mudo → `Analytics.shared.captureException(e, handled: true, extra: {...})`. Comportamento local-first permanece.
- Nota pro relatório: **sem backfill de culture_fit — a feature nunca chegou a usuário real, prod está em 2.0.0+2.**

### T0.5 — CI mínimo (O2 #4)
`.github/workflows/ci.yml` (PR + push em main), Flutter 3.38.5 pinado:
1. **analyze:** `flutter analyze --no-fatal-warnings` (0 errors hoje) + ratchet de warnings: falha se > baseline (47, em `scripts/analyze_warnings_baseline.txt`; só desce, nunca sobe sem justificativa no PR).
2. **test:** cria `.env` dummy (asset declarado precisa existir no CI) → `flutter test`.
3. **env-safety:** `scripts/check_env_safety.sh`.
4. **migrations-manifest:** `scripts/check_migrations_manifest.sh` compara `supabase/migrations/*.sql` com `supabase/migrations.manifest` commitado. A checagem REAL contra o remoto (`supabase migration list`) é passo local do checklist de release — decisão do fundador: sem secrets no GitHub.

### T0.6 — Build-régua 2.2.0+5 (J5 #1, O2 #5)
- Bump `pubspec.yaml` → `2.2.0+5` (fix `a72dedb` já está em main).
- [ ] **FUNDADOR:** archive + upload via Xcode/Transporter → submeter à revisão.
- [ ] **FUNDADOR/Claude:** `scripts/posthog_annotate_deploy.sh` **na liberação aos usuários** (não no upload).
- Aceite da fase: "build na revisão da App Store" (não exige aprovação da Apple).

### T0.7 — Higiene leve (L4)
- Deletar `lib/features/gamification/world_screen.dart` (zero callers).
- Header `DEPRECATED` em `parse-cv`, `parse-cv-pdf`, `generate-profile` (comentário; sem redeploy). Nota: `generate-profile` tem wrapper `generateProfileContent` (`ai_service.dart:339`) sem call sites — morto de fato.
- Nada mais (R6).

---

## Checklist do fundador (ações que só você pode fazer)

| # | Ação | Quando |
|---|---|---|
| 1 | Conferir usage dashboard OpenAI (consumo anômalo?) e me passar o veredito | Dia 1, antes de revogar |
| 2 | Rotacionar chave OpenAI no painel + `supabase secrets set OPENAI_API_KEY=<nova>` | Dia 1 |
| 3 | Re-assinar os 3 tópicos ntfy novos no celular (nomes entregues em privado) | Quando T0.3 deployar |
| 4 | Archive + upload 2.2.0+5 via Xcode → submeter à revisão | Pós-merge da fase |
| 5 | Avisar na liberação aos usuários → anotação PostHog | Pós-aprovação Apple |

## Critérios de aceite (espelho do plano aprovado)

1. Chave antiga revogada (dia 1) + bundle local inspecionado sem `OPENAI_API_KEY`.
2. Rate limit: 429 + `rate_limit_hit` no PostHog com limit=1; restaurado pra 10; count só conta sucesso.
3. Pushes ntfy sem PII de candidato, nos tópicos novos.
4. `supabase migration list` limpo + tabela culture_fit em prod + save persiste.
5. CI verde no PR da fase (4 jobs, ratchet ≤ 47).
6. 2.2.0+5 submetida à revisão.
7. `flutter test` verde; golden_set NÃO requerido (nada de adapt foi tocado — R5).

## Fora de escopo

Fases 1–6; correção dos 47 warnings (ratchet futuro); dart-define; build iOS no CI; qualquer mudança no pipeline adapt; deleção de tabelas/functions legacy.
