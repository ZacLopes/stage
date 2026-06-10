# AUDITORIA-STAGE.md

**Data da auditoria:** 2026-06-09 (queries ao banco executadas em 2026-06-09, ~20:45–21:30 BRT)
**Auditor:** engenheiro responsável pelo app (Claude Code), acesso completo a código + Supabase prod (MCP) + PostHog (MCP)
**Escopo:** repositório `career_gamification/` (raiz git), projeto Supabase `gaxfmniffjvwrwyunorl`, projeto PostHog 419792

---

## TL;DR EXECUTIVO

**Stack:** Flutter 3.38.5 / Dart 3.10.4, iOS-only (min iOS 13.0), Provider + ChangeNotifier (MVVM), sem pacote de rotas (Navigator.push direto). Backend 100% Supabase (Postgres + Auth + Storage + 27 Edge Functions Deno ativas). IA: OpenAI GPT-4o / GPT-4o-mini server-side. Analytics: PostHog (client + parcialmente server). Push: OneSignal. Ads: Facebook App Events. Versão local `2.2.0+4` (`pubspec.yaml:19`); **em produção na App Store: 2.0.0+2** (commit `23d151e`, 2026-05-29).

**5 números que resumem o estado:**

| Métrica | Valor |
|---|---|
| Telas Flutter (rotas alcançáveis) | ~38 telas / 208 arquivos Dart / 79.429 linhas em `lib/` |
| Tabelas no schema `public` | 58 (+ 23 no schema `analytics_archive`) — 2.033 users em `auth.users` |
| Eventos PostHog | 318 constantes catalogadas (`analytics_events.dart`); ~110 com emissor real no código; resto é catálogo morto |
| Cobertura de testes | 2 arquivos de teste, 6 testes (todos verdes) — cobertura efetiva ≈ 0% |
| Stage Resume (paradigma híbrido) implementado | ~70%: trilha ✅, bullets incrementais ✅, raw_responses ✅, export PDF Harvard ✅, upload/parse ✅; perguntas abertas dirigidas PARCIAL; "campanhas por vaga" degenerou (99% das campaigns são marcador de onboarding skipado) |

**5 descobertas mais importantes para quem vai planejar:**

1. **Android não existe.** Não há diretório `android/` no repo. Não é "configuração pendente" — é projeto a criar do zero (Seção A8).
2. **O feed não tem backend de feed.** `JobRepository.fetchJobsWithDiagnostics` baixa TODAS as vagas ativas (469 hoje) com `select('*, companies(*)')`, filtra preferências em Dart e **embaralha com `Random()` sem seed** (`job_repository.dart:111`). Não há ranking, paginação real (`_pageSize = 5000`) nem query server-side. Reestruturar o feed = construir a camada que hoje não existe.
3. **Drift de migration em produção:** `20260607000000_user_culture_fit_preferences.sql` existe no repo e o código do app (commit `7964983`, 09/06) já depende da tabela, mas ela **não existe no banco de produção** (verificado via `to_regclass` em 09/06). O save remoto degrada silenciosamente pra SharedPreferences local (`culture_fit_repository.dart`).
4. **A "candidatura automatizada" é concierge manual.** Swipe-right em vaga com `application_method='email'` é vendido na UI como aplicação automática/assistida por IA, mas tecnicamente dispara `notify-auto-apply-swipe` → notificação **ntfy para o fundador** (`supabase/functions/notify-auto-apply-swipe/index.ts:1-10`). O apply real continua sendo `mailto:`/URL externa. Não existe máquina de estados de candidatura; "applied" é um boolean em `swipe_actions`.
5. **Instrumentação server-side JÁ tem fundação.** `supabase/functions/_shared/posthog.ts` (454 linhas) emite `$ai_generation`, `edge_function_invoked`, `llm_call_failed` etc. de TODAS as edge functions via `withEdgeAnalytics`. O futuro "eventos server-side" não parte do zero — parte daqui.

**3 maiores riscos (detalhe na Seção O):**

1. **Modelo de candidatura inexistente sobre dados legados:** `swipe_actions` mistura swipe + candidatura (`applied` boolean, 493 true de 47.288 rows). Qualquer `applications` com máquina de estados exige migração + backfill + reescrita da aba Curtidas, e o funil termina num `launchUrl` externo sem rastro próprio em tabela (só PostHog).
2. **Escala e ranking do feed:** o full-scan client-side + shuffle aleatório funciona com 469 vagas e ~2k users; quebra com 5k vagas ou qualquer ranking por usuário. O `CardSwiper` exige array imutável na sessão (comentário em `job_repository.dart:30-34`), então paginação progressiva implica refactor de UI também.
3. **Zero rede de proteção:** 6 testes, sem CI/CD, lint default, deploy manual via Xcode, migrations com drift e operação dependente do fundador (ntfy + Supabase Studio + migrations SQL "datadas" como ferramenta de limpeza). Frentes grandes em paralelo nesse estado têm alto risco de regressão invisível.

---

# SEÇÃO A — Visão geral do projeto e arquitetura Flutter

## A1. Árvore de diretórios e padrão de organização

`[EXISTE]` — Comando: `find lib -type d | sort`. Árvore até 3 níveis:

```
lib/
├── core/
│   ├── analytics/            (screen_tracking.dart — mixin de $screen)
│   ├── constants/            (job_areas.dart, stage_app_links.dart)
│   ├── theme/                (8 arquivos de tokens — design system 2026-05-27)
│   ├── utils/                (formatters, auth_error_formatter, display_name)
│   └── widgets/              (badges/, buttons/, cards/, chips/, feedback/, inputs/, pii_mask)
├── data/
│   ├── models/               (models.dart — 1.057 linhas, models legacy)
│   ├── database_helper.dart  (SQLite)
│   ├── local_storage_repository.dart (SharedPreferences)
│   ├── repository.dart / supabase_repository.dart (1.472 linhas)
│   └── seed_data.dart        (seed da trilha)
├── domain/                   (vazio — diretório existe sem arquivos Dart)
├── features/
│   ├── auth/                 (flat: 8 arquivos)
│   ├── gamification/         (trilha: screens + services/ + widgets/ — 40+ widgets de pergunta)
│   ├── home/                 (home_screen 4 tabs + widgets/)
│   ├── jobs/                 (data/ models/ screens/ utils/ widgets/)
│   ├── onboarding/           (presentation/ {masking_questions/, preferences/} + utils/)
│   ├── profile/              (application/ data/repositories/ domain/{entities,repositories}/ presentation/widgets/)
│   ├── resume/               (flat + data/ + services/ + widgets/)
│   ├── settings/ shared/ splash/ tutorial/ version/
└── services/                 (13 services transversais: analytics, ai, cv_import, notifications, facebook, flags...)
```

**Padrão: feature-first MISTO, sem consistência entre features.** Três gerações coexistem:
- **Geração 1 (flat):** `auth/`, `resume/`, `gamification/` — tela + viewmodel no mesmo nível, sem camadas.
- **Geração 2 (data dirs):** `jobs/` — `data/` (repositories), `models/`, `screens/`, `utils/`, `widgets/`.
- **Geração 3 (clean-ish):** `profile/` — `domain/entities`, `domain/repositories`, `data/repositories`, `application/` (ViewModels), `presentation/widgets`. Único feature com camada de domínio formal.
- Resíduo layer-first: `lib/data/` e `lib/services/` globais; `lib/domain/` existe mas está vazio.

## A2. Versões

`[EXISTE]` — Comandos: `flutter --version`, leitura de `pubspec.yaml` (completo no Apêndice 1).

- **Flutter 3.38.5** (stable, revision f6ff1529fd, 2025-12-11) • **Dart 3.10.4** • SDK constraint `^3.10.0`.
- App version: **2.2.0+4** (local, não publicada). Produção: 2.0.0+2.

15 dependências mais estruturais (`pubspec.yaml:30-76`):

| Pacote | Versão | Papel |
|---|---|---|
| `provider` | ^6.1.5+1 | State management (único) |
| `supabase_flutter` | ^2.0.0 | Backend (auth, DB, storage, functions) |
| `posthog_flutter` | ^4.10.1 | Analytics + session replay |
| `onesignal_flutter` | ^5.2.9 | Push |
| `facebook_app_events` | ^0.20.0 | Meta Ads (AEM/SKAdNetwork) |
| `app_tracking_transparency` | ^2.0.6+1 | ATT iOS |
| `printing` | ^5.13.4 | HTML→PDF + share (export de CV) |
| `pdf` | ^3.11.1 | Suporte ao printing |
| `syncfusion_flutter_pdf` | ^33.1.46 | Extração de texto de PDF (import CV) |
| `flutter_card_swiper` | ^7.2.0 | Feed de swipe |
| `flutter_html` | ^3.0.0-beta.2 | Render de descrição de vaga (HTML Greenhouse) |
| `file_picker` | ^10.3.10 | Upload de CV |
| `sign_in_with_apple` | ^6.1.1 | Apple Sign-In |
| `flutter_dotenv` | ^5.1.0 | Config (.env **bundlado como asset** — ver M1) |
| `app_links` | ^6.3.0 | Deep link / atribuição (sem AASA — ver B6) |

Outros relevantes: `sqflite`, `shared_preferences`, `url_launcher`, `share_plus`, `tutorial_coach_mark`, `geolocator`/`geocoding`, `cached_network_image`, `path_drawing` (splash), `intl`. **Sem roteador** (go_router etc.), **sem DI** (get_it etc.), **sem Riverpod/Bloc**.

## A3. Gerenciamento de estado

`[EXISTE]` — **Provider + ChangeNotifier (MVVM)**, usado consistentemente. 11 providers registrados em `MultiProvider` em `main.dart:221-281`: `ProfileEditorViewModel`, `UserViewModel` (via `ChangeNotifierProxyProvider` dependente do ProfileEditor), `GamificationViewModel`, `ProfileViewModel`, `PreferencesViewModel`, `ExtractionStatusViewModel`, `HomeViewModel`, `ResumeViewModel`, `JobsViewModel`, `TutorialController`, `PendingAdaptedCvTracker` (singleton `.value`).

Exemplos do padrão típico:
- `lib/features/jobs/jobs_viewmodel.dart` (1.000 linhas) — `class JobsViewModel extends ChangeNotifier`, recebe 3 repositories + AIService no construtor, expõe getters + `notifyListeners()`.
- `lib/features/profile/application/profile_editor_view_model.dart` — geração 3, recebe `ProfileRepository` (interface de domínio), mesma mecânica.

Desvio: vários singletons fora do Provider (`Analytics.shared`, `NotificationsService.shared`, `FacebookEventsService.shared`, `FeatureFlagsService.instance`, `JobSwipeContext.shared`, `ProfileTabPrefs.shared`) — acesso estático global, não injetado.

## A4. Roteamento

`[EXISTE]` mas **sem pacote**: `Navigator.push/pushReplacement` direto com `MaterialPageRoute`, **sem `RouteSettings.name`** (motivo pelo qual o `PosthogObserver` foi removido — `main.dart:298-304`). Entry: `MaterialApp(home: VersionGate(child: SplashScreen()))` → `AuthGate` (`splash_screen.dart:492-547`) decide por estado: `hasCampaign→HomeScreen`, `isInProfileFirstFlow||needsProfileSetup→TwoDoorsScreen`, senão `CompletionScreen`; deslogado → `OnboardingScreen` (landing de auth).

Inventário de telas (tela = widget de página inteira navegável):

| Tela | Arquivo | O que faz | Estado |
|---|---|---|---|
| SplashScreen | `features/splash/splash_screen.dart` | Animação do glifo "S" + boot | [ATIVA] |
| VersionGate | `features/version/version_gate.dart` | Force-update via `app_config` | [ATIVA] |
| OnboardingScreen (auth landing) | `features/auth/onboarding_screen.dart` | Carrossel + botões de login social/telefone | [ATIVA] |
| AuthScreen | `features/auth/auth_screen.dart` | Login/cadastro e-mail+senha e métodos | [ATIVA] |
| PhoneSignupScreen | `features/auth/phone_signup_screen.dart` | Cadastro por telefone (e-mail sintético) | [ATIVA] |
| AccountMigrationScreen | `features/auth/account_migration_screen.dart` | Migra conta phone→OAuth (link identity) | [ATIVA] |
| CompletionScreen | `features/auth/completion_screen.dart` | Fluxo legacy pós-login (cria campaign) | [ATIVA] (fallback legacy) |
| TwoDoorsScreen | `features/onboarding/presentation/two_doors_screen.dart` | Escolha: importar CV vs trilha | [ATIVA] |
| UploadPreviewSheet | `.../upload_preview_sheet.dart` | Confirma PDF e dispara extração | [ATIVA] |
| ExtractionInProgressScreen | `.../extraction_in_progress_screen.dart` | Loading da extração → masking questions | [ATIVA] |
| AttributionScreen, FirstName, LastName, Email, Phone, Gender, AgeRange, Education | `.../masking_questions/*.dart` (8 telas) | Perguntas que mascaram a latência da extração | [ATIVA] |
| AllSetScreen | `.../all_set_screen.dart` | "Tudo pronto" pós-extração | [ATIVA] |
| ReviewPersonalInfoScreen | `.../review_personal_info_screen.dart` | Revisão dos dados pessoais extraídos | [ATIVA] |
| ReviewResumeScreen | `.../review_resume_screen.dart` | Revisão das seções do CV extraído | [ATIVA] |
| DesiredTitles, Location, WorkLocations, WorkMode, JobTypes, OnboardingComplete | `.../preferences/*.dart` (6 telas) | Preferências de vaga | [ATIVA] |
| HomeScreen | `features/home/home_screen.dart` | Shell com 4 tabs: Vagas, Salvas, Currículo, Perfil (`home_screen.dart:404-450`) | [ATIVA] |
| JobsSwipeScreen | `features/jobs/screens/jobs_swipe_screen.dart` | Feed de swipe (tab 1) | [ATIVA] |
| LikedJobsScreen | `features/jobs/screens/liked_jobs_screen.dart` | Aba Salvas/Curtidas (tab 2) | [ATIVA] |
| JobDetailsSheet | `features/jobs/screens/job_details_sheet.dart` | Bottom sheet de detalhes da vaga | [ATIVA] |
| JobPreferencesScreen | `features/jobs/screens/job_preferences_screen.dart` | Filtros do feed | [ATIVA] |
| AdaptedResumePreviewScreen | `features/jobs/widgets/adapted_resume_preview_screen.dart` | Preview/edição do CV adaptado | [ATIVA] |
| ResumeTab | `features/resume/resume_tab.dart` | Tab 3: entry trilha/import | [ATIVA] |
| TracksTab / OpenTrailView | `features/home/tracks_tab.dart`, `open_trail_view.dart` | Mapa da trilha | [ATIVA] |
| QuestionScreen | `features/gamification/question_screen.dart` | Player de perguntas da trilha | [ATIVA] |
| BulletReviewScreen | `features/gamification/bullet_review_screen.dart` | Revisão dos 3 ângulos de bullet | [ATIVA] |
| SummaryGenerationScreen | `features/gamification/summary_generation_screen.dart` | Geração do resumo do CV | [ATIVA] |
| GamifiedPhaseList | `features/gamification/gamified_phase_list.dart` | Lista de fases da trilha | [ATIVA] |
| WorldScreen | `features/gamification/world_screen.dart` | Tela de "mundo" | **[MORTA — nenhum call site; mundo secreto removido em 2026-05-06]** |
| ProfileScreen | `features/profile/profile_screen.dart` | Tab 4: sub-abas Currículos/Informações | [ATIVA] |
| ResumeDetailScreen | `features/profile/resume_detail_screen.dart` | CV salvo: preview, template, **export PDF** | [ATIVA] |
| ResumePreviewScreen | `features/profile/resume_preview_screen.dart` | Preview fullscreen | [ATIVA] |
| ResumeEditScreen | `features/resume/resume_edit_screen.dart` | Edição manual do CV (2.768 linhas) | [ATIVA] |
| AddExperienceWizard / EditExperienceScreen | `features/resume/*.dart` | CRUD de experiências | [ATIVA] |
| SettingsScreen | `features/settings/settings_screen.dart` | Config, conta, privacidade, deleção | [ATIVA] |
| ChangePasswordScreen | `features/settings/change_password_screen.dart` | Troca de senha | [ATIVA] |
| TemplateThumbnailGeneratorScreen | `features/resume/widgets/template_thumbnail_generator_screen.dart` | Ferramenta dev (só debug mode) | [ATIVA-DEV] |

## A5. Injeção de dependências e camada de serviços

`[EXISTE]` com inconsistência geracional. Sem container de DI; dependências instanciadas manualmente em `main.dart:186-208` e passadas via construtor aos ViewModels.

Camada de dados:
- `lib/data/supabase_repository.dart` (1.472 linhas) — repositório "deus" legacy: trilha (tracks/phases/questions com cache em memória 3 níveis), user_profiles, campaigns, saved_resumes, storage, deleção de conta.
- `lib/features/jobs/data/` — `job_repository.dart`, `swipe_repository.dart`, `preferences_repository.dart`, `culture_fit_repository.dart` (cada um cria seu próprio `Supabase.instance.client`).
- `lib/features/profile/data/repositories/profile_repository_supabase.dart` — implementa interface `ProfileRepository` (`domain/repositories/`), cobre as 20 tabelas `profile_*`.
- `lib/services/ai_service.dart` — invoca as edge functions de IA (`analyze-match`, `adapt-resume-to-job`, `generate-*`, `suggest-tools`).
- Chamadas diretas ao Supabase fora de repositório existem em services (`cv_import_service.dart` invoca `extract-profile`; `feature_flags_service.dart` lê `app_feature_flags`) e pontualmente em telas, mas a regra geral é passar por repository/service.

## A6. Ambientes e configuração

`[NÃO EXISTE]` flavors. Um único ambiente = produção. Config via `flutter_dotenv` com arquivo `.env` na raiz, **declarado como asset do bundle** (`pubspec.yaml:133` — `- .env`), carregado em `main.dart:103`.

Nomes das variáveis (valores omitidos):
- No `.env` real: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `OPENAI_API_KEY`, `POSTHOG_API_KEY`, `POSTHOG_HOST`, `ONESIGNAL_APP_ID`.
- No `.env.example`: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `POSTHOG_API_KEY`, `POSTHOG_HOST`.
- ⚠️ `OPENAI_API_KEY` está no `.env` local mas **não tem nenhum uso em `lib/`** (grep vazio) — e como o `.env` inteiro vira asset, a chave embarca no IPA. Achado crítico — detalhado em M1. `.env` está no `.gitignore` (linha 57) e não está commitado (`git ls-files` = 0).

Secrets server-side (Supabase secrets; nomes extraídos por grep `Deno.env.get` nas functions): `OPENAI_API_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `APIFY_API_TOKEN`, `CRON_SECRET`, `RESEND_API_KEY`, `RESEND_INBOUND_WEBHOOK_SECRET`, `POLIFINANCE_ALLOWED_SENDERS`, `ONESIGNAL_APP_ID`, `ONESIGNAL_REST_API_KEY`, `NTFY_HOST`, `NTFY_TOPIC`, `NTFY_TOPIC_REPORT`, `NTFY_TOPIC_AUTO_APPLY`, `POSTHOG_API_KEY`, `POSTHOG_HOST`, `REPORT_EMAIL_FROM`, `REPORT_EMAIL_TO`, `REFINEMENT_ENABLED`, `ENVIRONMENT`.

## A7. Build e distribuição iOS

- **iOS mínimo: 13.0** (`ios/Runner.xcodeproj/project.pbxproj:458`).
- **Deploy: manual via Xcode/Transporter.** Não há fastlane, codemagic, nem `.github/` no repo (verificado por `ls`). `[NÃO EXISTE]` automação.
- Tamanho do build: `[INCERTO]` — não gerei IPA nesta auditoria. Fontes bundladas somam ~5MB (`pubspec.yaml:151-153`).
- Frequência de release (90 dias, via `git log` — não há tags git): cadência ~semanal em maio. Marcos visíveis nos commits: v1.1.0 (11/05), 1.3.0 (13/05), "antes da 1.5.0" (14/05), **2.0.0+2 (29/05, em prod)**, 2.2.0+4 local sem release. Memória do projeto registra 1.5.3+1 como release anterior em prod.

## A8. Android (crítico)

`[NÃO EXISTE]`. **O diretório `/android` não existe no repositório** (verificado: `ls` da raiz mostra apenas `ios/`, `web/`). `flutter build apk --debug` falharia imediatamente por ausência do projeto Android — não executei o build por ser conclusivo sem ele.

Checklist factual do que falta para um beta Android (sem estimativas — ver O3):

- [ ] `flutter create --platforms=android .` (gerar projeto: Gradle, AndroidManifest, MainActivity)
- [ ] `flutter_native_splash` — regenerar pra Android 12+ (config já tem `android_12.color`, `pubspec.yaml:114`)
- [ ] `flutter_launcher_icons` — config atual só gera iOS/web/windows/macos (`pubspec.yaml:92-106`; falta `android: true`)
- [ ] OneSignal Android: Firebase/FCM (google-services.json, FCM key no painel OneSignal)
- [ ] `sign_in_with_apple` no Android: exige fluxo web (service ID + redirect URL) — hoje só o flow nativo iOS está implementado (`user_viewmodel.dart:668-702` usa `signInWithIdToken` com credencial nativa)
- [ ] Google OAuth: redirect `io.supabase.stage://login-callback` precisa de intent-filter no AndroidManifest
- [ ] `facebook_app_events`: meta-data no AndroidManifest (app id `fb1268158548810380` existe só no Info.plist)
- [ ] `app_tracking_transparency` é iOS-only — código já guarda com try/catch, verificar no-op
- [ ] `geolocator`/`geocoding`: permissões de localização no Manifest
- [ ] `app_links`: intent-filters pra deep link `stage://`
- [ ] PostHog session replay Android (suporte e máscaras divergem do iOS)
- [ ] `printing` (export PDF): testar render HTML→PDF no Android (engine diferente do iOS)
- [ ] `app_config.android_store_url` está `null` no banco (query 09/06) — VersionGate sem URL de loja Android
- [ ] Keystore de assinatura + Play Console + listing

## A9. CI/CD e lint

`[NÃO EXISTE]` CI/CD: sem `.github/`, sem `codemagic.yaml`, sem fastlane (verificado por `ls`). Lint: `analysis_options.yaml` é o **default do `flutter_lints` sem nenhuma regra customizada** (todas as linhas de `rules:` comentadas). Rigidez mínima.

## A10. Internacionalização

`[NÃO EXISTE]` i18n. Strings hardcoded em pt-BR nos arquivos Dart (confirmado em CLAUDE.md:74 e por amostragem). `supportedLocales: [Locale('pt','BR')]` (`main.dart:351-353`). Exceção: o **output do CV adaptado** tem i18n PT/EN server-side (adapt v2, `_shared`/pipeline — vagas em inglês geram CV em inglês).

---

# SEÇÃO B — Autenticação e identidade

## B1. Provedores ativos

`[EXISTE]` 4 caminhos (arquivos: `lib/features/auth/auth_screen.dart`, `phone_signup_screen.dart`, `user_viewmodel.dart`, `phone_auth_helpers.dart`, `account_migration_screen.dart`):
1. **Google OAuth** — `signInWithOAuth(provider)` com redirect `io.supabase.stage://login-callback` (`user_viewmodel.dart:646-651`).
2. **Apple Sign-In nativo** — `sign_in_with_apple` + `signInWithIdToken` (`user_viewmodel.dart:668-702`); entitlement em `ios/Runner/Runner.entitlements`.
3. **Telefone via e-mail sintético** — NÃO é OTP/SMS. Gera `phone_<cc><digits>@stage.app` + senha (`phone_auth_helpers.dart:16-22`) e usa signUp/signInWithPassword normais. Workaround documentado (Twilio não configurado).
4. **E-mail/senha** — legacy, `signUp`/`signIn` (`user_viewmodel.dart:524-607`).
Magic link: `[NÃO EXISTE]`. Há fluxo de **migração** phone→OAuth (`linkAppleIdentity`/`linkGoogleIdentity`, `user_viewmodel.dart:982-1054`).

## B2. Sequência técnica do signup

`[EXISTE]` — verificado no banco (definições de trigger/function extraídas em 09/06):
1. `auth.users` INSERT (Supabase Auth).
2. Trigger `on_auth_user_created` (AFTER INSERT em `auth.users`) → `public.handle_new_user()` (SECURITY DEFINER): `INSERT INTO user_profiles (id, email, name, course, semester)` com name/course/semester vindos de `raw_user_meta_data` (defaults `'User'`, `''`, `''`).
3. Trigger `notify_new_signup` (AFTER INSERT em `user_profiles`) → `supabase_functions.http_request` pra edge `notify-signup` → push ntfy ao fundador com nome/e-mail.
4. **`profile_personal` NÃO é criada no signup** — só durante o onboarding profile-first (masking questions / extração de CV salvam nela).
5. Client-side, o listener `onAuthStateChange` (`user_viewmodel.dart:301-370`) dispara `Analytics.identify(uid)` + `signUpCompleted`/`loginCompleted` + `OneSignal.login(userId)`.

## B3. Estado anônimo/pré-login

`[NÃO EXISTE]` navegação anônima — auth é obrigatória antes de qualquer conteúdo (AuthGate → OnboardingScreen de auth). No PostHog, eventos pré-login (landing de auth, `auth_signup_*`) saem com distinct_id anônimo do device; o merge acontece via `Posthog().alias(alias: user.id)` chamado **uma única vez por install** dentro de `identifyIfLoggedIn()` (`analytics_service.dart:316-364`, flag `cutover_alias_done` em SharedPreferences). Dados de produto pré-login não existem (nada é gravado no banco antes da conta).

## B4. O corte de ~28/05

`[EXISTE]` — reconstruído via `git log` + código:
- **Commits:** `79d73c3` "Antes de alterações no PostHog" (28/05) → `3723634` "posthog configurado + fix de sessão e bugs de perfil" (29/05) → `73ecf95`/`19ed03d` (Facebook Ads Phase 1) → `23d151e` bump 2.0.0+2 (29/05). Build 2.0.0+2 ao vivo ~30/05. Pós-release: `a72dedb` "fix(analytics): corrige is_pre_cutover_user e feed_exhausted" (30/05) — **esse fix NÃO está na build de produção** (entrou depois do bump).
- **ANTES:** SDK PostHog com `captureApplicationLifecycleEvents` default (eventos `Application Opened/...` automáticos), `PosthogObserver` registrando tudo como `root('/')`, identify simples sem alias, taxonomia de eventos ad-hoc (~28k `job_swiped` históricos com prop `action`).
- **DEPOIS:** init manual (`main.dart:107-131`) com `captureApplicationLifecycleEvents=false`, observer removido, `$screen` manual via `ScreenTrackingMixin`, catálogo fechado de 318 eventos (`analytics_events.dart`), super properties (session_id, build, flow_version), alias one-time + person property `is_pre_cutover_user` calculada por `user.createdAt < 2026-05-30T03:00:00Z` (`analytics_service.dart:333`).
- **A quebra de continuidade:** users antigos só ganham alias quando abrem a build nova; quem não voltou ficou com distinct_id antigo desconectado. O cohort "post-cutover" inicialmente pegava todos (memória de auditoria 29-30/05).

## B5. PostHog identify

`[EXISTE]` — init em `main.dart:117-130` (key/host do .env, `sessionReplay=true`, `maskAllTexts=false` + máscara por widget via `PiiMask`). `identify()` chamado em 2 lugares: (1) listener de auth `user_viewmodel.dart:325` com properties `{provider, signup_method}`; (2) `identifyIfLoggedIn()` em `analytics_service.dart:316` (boot) com `email`, `is_internal`, `is_pre_cutover_user` e `$set_once cutover_alias_at`. `alias()` — só o one-time do cutover (`analytics_service.dart:324`). `reset()` no logout (`user_viewmodel.dart` via `Analytics.shared.reset()`). **distinct_id = `auth.users.id` (UUID Supabase)**.

## B6. Deep links / universal links

`[PARCIAL]` — Só **custom URL schemes** no `ios/Runner/Info.plist:30-52`: `io.supabase.stage` (callback OAuth), `fb1268158548810380` (Facebook), `stage` (deep links de produto/atribuição via `app_links` + `lib/core/constants/stage_app_links.dart`). **Universal Links: [NÃO EXISTE]** — `Runner.entitlements` só tem `aps-environment` e `applesignin`; sem `associated-domains`, sem AASA. Consequência documentada no próprio pubspec (`pubspec.yaml:68-73`): `getInitialLink` retorna null pra links https e installs caem como 'organic'. Para páginas web de vaga + notificações com rota, universal links teriam que ser configurados do zero.

## B7. Data de nascimento, menores, exclusão de conta

- **DOB:** `[EXISTE]` coluna `profile_personal.date_of_birth` (migration `20260522000013`) + `age_range` (texto) coletado na masking question `AgeRangeScreen`. 
- **Menores de idade:** `[NÃO EXISTE]` qualquer tratamento diferenciado (grep por idade/menor sem resultados de lógica).
- **Exclusão de conta:** `[EXISTE]` e é **hard delete**: `SettingsScreen → UserViewModel.deleteAccount()` (`user_viewmodel.dart:843-872`) → `repository.deleteUserData()` (apaga arquivos do bucket `resumes` + deleta linhas tabela a tabela via `_safeDelete`, `supabase_repository.dart:265-310`) → `repository.deleteAuthAccount()` → RPC `delete_user()` (SECURITY DEFINER, `DELETE FROM auth.users WHERE id = auth.uid()`) com cascades.

---

# SEÇÃO C — Modelo de dados completo (Supabase)

## C1. Inventário de tabelas

`[EXISTE]` — Fonte: `list_tables` MCP + `count(*)` reais executados 2026-06-09 (~21:00 BRT). ⚠️ Os row-counts do dashboard/`n_live_tup` estão MUITO defasados para tabelas quentes (ex.: `swipe_actions` estimava 2.933; real = 47.288). Os números abaixo são `count(*)` reais para as tabelas marcadas com *; estimativas `n_live_tup` nas demais. DDL completo no Apêndice 2. RLS: **todas as 58 tabelas têm RLS habilitada**.

| Tabela | Propósito | Linhas | RLS |
|---|---|---|---|
| `user_profiles` | Perfil legacy (1 row/user; `gamification_data` JSONB guarda trilha+CV importado) | 2.018* | ✅ 4 policies (own) |
| `profile_personal` | Perfil relacional novo (nome, contato, DOB, headline, links) | 1.114* | ✅ own |
| `profile_experiences` / `profile_bullets` | Experiências + bullets Harvard relacionais | 139 / 239 | ✅ own |
| `profile_education` (+`_majors`, `_minors`, `_activities`) | Formação | 135 / 63 / 0 / 21 | ✅ own |
| `profile_skills` / `profile_languages` / `profile_certifications` | Listas do perfil | 402 / 51 / 44 | ✅ own |
| `profile_projects` / `profile_project_bullets` / `profile_interests` / `profile_awards` / `profile_coursework` | Listas secundárias | 5 / 0 / 20 / 5 / 0 | ✅ own |
| `profile_job_preferences` | Preferências (job_types, work_models, min_salary) | 1.108* | ✅ own |
| `profile_desired_titles` / `profile_other_locations` / `profile_application_countries` | Listas de preferência | 3.233 / 118 / 0 | ✅ own |
| `profile_extraction_logs` | Log das extrações de CV | 1.281* | ✅ RLS on, **0 policies = deny-all client** |
| `jobs` | Vagas (469 ativas / 3.090 total) | 3.090* | ✅ SELECT p/ authenticated |
| `companies` | Empresas das vagas | 1.026 | ✅ SELECT p/ authenticated |
| `swipe_actions` | Swipes + flag `applied`/`applied_at` | **47.288*** (6.801 liked / 40.487 rejected / 493 applied) | ✅ own (4) |
| `match_analyses` | Cache do match IA (score, reasons, prompt_version) | **35.462*** | ✅ own (4) |
| `adapted_resumes` | Cache de CV adaptado por (user, vaga, prompt_version) | 31* | ✅ own |
| `jobs_skill_extraction` | Cache de skills extraídas por vaga | est. 0 | ✅ 0 policies (server-only) |
| `external_job_sources` | Fontes ATS (64 greenhouse, 5 lever) | 69* | ✅ deny client |
| `campaigns` / `target_jobs` | "Campanha" de CV + vaga-alvo (legacy onboarding) | 1.599* / 1.599* (**1.584 is_skipped = 99%**) | ✅ own |
| `raw_responses` | Respostas brutas da trilha por user | 5.284* | ✅ own (ALL) |
| `user_answers` / `user_progress` | Respostas estruturadas + progresso da trilha | 5.452* / 1.425* | ✅ own |
| `tracks` / `phases` / `questions` | Conteúdo da trilha (5 / 9 / 172) | 5* / 9* / 172* | ✅ SELECT all |
| `saved_resumes` | Biblioteca de CVs (JSON + template + storage path) | 1.218* | ✅ own |
| `approved_bullets` / `bullet_versions` / `section_versions` | Bullets legacy (pré-relacional) | 19 / 0 / 15 | ✅ own |
| `bullet_generation_logs` / `ai_generation_logs` | Telemetria de IA no banco | 50 / **37.182*** | ✅ |
| `user_preferences` | Filtros do feed (aba Vagas) — AINDA ATIVA (`preferences_repository.dart:11`) | 470* | ✅ own (3) |
| `app_config` | Config remota (force-update, store URLs, `match_prompt_version='v10'`) | 1* | ✅ SELECT public |
| `app_feature_flags` | Flags caseiras (3 rows: `templates_v2_enabled` off, `match_v2_enabled` off, `adapt_v2_enabled` **on 100%**) | 3* | ✅ SELECT auth |
| `admin_users`, `employer_clients`, `candidate_list_requests`, `candidate_list_items`, `candidate_list_exports`, `candidate_data_sharing_consents`, `admin_audit_log` | Dashboard B2B (migration `20260601030000`) | 2* / 0 / 0 / 0 / 0 / 0 / 0 | ✅ deny-all client (acesso só via edge admin-*) |
| `security_audit_log` | Log de segurança (não populado) | 0 | ✅ |
| `user_profiles_backfill_snapshot_20260521`, `_jobs_area_backup_20260530` | Backups de migração | 0 est. | ✅ 0 policies |
| **Schema `analytics_archive`** | `posthog_events_archive` particionada mensal (2026_05→2027_12) + `daily_export_health` | **261.911*** eventos | n/a (server-only) |

## C2. RLS — resumo das policies

Fonte: `pg_policies` (09/06). Padrões:
- **User-owned (perfil, swipes, matches, resumes, respostas):** 4 policies CRUD com `auth.uid() = user_id` (ou `= id` em `user_profiles`). Sem leitura cross-user.
- **Catálogo público a autenticados:** `jobs`, `companies` (SELECT `true` p/ authenticated); `tracks/phases/questions` SELECT; `app_feature_flags` SELECT auth.
- **`app_config`:** SELECT com `using(true)` para role `public` — **legível com anon key sem login** (conteúdo: versões mínimas, URLs de loja, match_prompt_version; sem dado sensível).
- **Deny-all explícito:** `admin_users`, `candidate_*`, `employer_clients`, `external_job_sources` (`using false`).
- **RLS ligada com 0 policies (= deny-all implícito a clients; só service_role):** `profile_extraction_logs`, `jobs_skill_extraction`, `_jobs_area_backup_20260530`, `user_profiles_backfill_snapshot_20260521`.
- **Tabelas SEM RLS expostas via API: nenhuma.** `[NÃO EXISTE]` esse achado — todas as 58 têm RLS habilitada.

## C3. Functions e triggers Postgres

Fonte: `pg_proc` + `information_schema.triggers` (09/06):

| Objeto | Tipo | Propósito / disparo |
|---|---|---|
| `handle_new_user()` | fn trigger | Cria `user_profiles` no INSERT de `auth.users` (trigger `on_auth_user_created`) |
| `delete_user()` | fn SECURITY DEFINER | Hard delete de `auth.users` (RPC chamada pelo app) |
| `save_profile_from_json(jsonb)` | fn | Upsert transacional das tabelas `profile_*` a partir do JSON da extração (usada por `extract-profile`) |
| `_set_phone_e164()` | fn trigger | Normaliza telefone E.164 em `profile_personal` (BEFORE INS/UPD) |
| `update_updated_at_column()` / `touch_app_feature_flags_updated_at()` | fn trigger | `updated_at` automático (user_profiles, user_experiences, employer_clients, candidate_*, app_feature_flags) |
| `notify_new_signup` | trigger | AFTER INSERT `user_profiles` → `supabase_functions.http_request` → edge `notify-signup` |
| `check_rate_limit()` / `cleanup_old_logs()` / `safe_date/integer/numeric()` | fn | Rate limit (ver L3 — check desativado no generate-resume), housekeeping, casts defensivos |
| `admin_job_metrics()` | fn sql | RPC de métricas de vagas pro dashboard admin (migration `20260601213000`) |
| `analytics_archive.create_next_month_partition()` / `ensure_events_partitions()` / `skip_duplicate_events()` | fn | Particionamento do archive PostHog + dedupe trigger |

## C4. Edge Functions

27 deployadas e ACTIVE (via `list_edge_functions`, 09/06; código no repo `supabase/functions/`, 14.001 linhas TS). Resumo fiel no Apêndice 3. Inventário:

| Função | Propósito | Quem chama | Secrets usados |
|---|---|---|---|
| `analyze-match` (v41) | Match IA user×vaga, gpt-4o-mini, cache `match_analyses`, PROMPT_VERSION v10 | App (`ai_service.dart:39`) | OPENAI, SERVICE_ROLE, POSTHOG |
| `adapt-resume-to-job` (v80) | Adaptação de CV por vaga; v1 legacy + `v2.ts` (PROMPT v27-v2, flag `adapt_v2_enabled`=on) com validator anti-invenção | App (`ai_service.dart:173`) | OPENAI, SERVICE_ROLE, POSTHOG |
| `extract-profile` (v15) | Parse de CV PDF (GPT-4o vision/base64) → `save_profile_from_json` + dual-write legacy | App (`cv_import_service.dart:240`) | OPENAI, SERVICE_ROLE, POSTHOG |
| `parse-cv` (v22) / `parse-cv-pdf` (v9) | Parsers legados (mantidos como rollback; sem caller no app desde 26/05) | — (legacy) | OPENAI |
| `generate-bullets` (v30) | 3 ângulos de bullet (trilha/campanha) | App (`ai_service.dart:420`) | OPENAI, POSTHOG |
| `generate-summary` (v28) | Resumo profissional do CV | App | OPENAI, POSTHOG |
| `generate-resume` (v40) | Monta ResumeData final da trilha (**rate-limit comentado** — `index.ts:36`) | App (`ai_service.dart:384`) | OPENAI, POSTHOG |
| `generate-profile` (v29) | Perfil/relatório da trilha (legacy) | App (`ai_service.dart:349`) | OPENAI |
| `suggest-tools` (v29) | Sugestão de ferramentas (trilha) | App (`ai_service.dart:465`) | OPENAI |
| `extract-job-skills` (v19) | Extrai skills atômicas da vaga (cache `jobs_skill_extraction`) | App (skills confirmation) | OPENAI, SERVICE_ROLE |
| `sync-jobs-apify` (v48) | Scraper Gupy via Apify (cron 07h/19h) | pg_cron | APIFY, CRON_SECRET, SERVICE_ROLE |
| `sync-jobs-ats` (v45) | Greenhouse/Lever API pública (cron 07:30) | pg_cron | CRON_SECRET, SERVICE_ROLE, POSTHOG |
| `sync-jobs-brazil` (v33) | Scraper InfoJobs etc. (cron 08h) | pg_cron | CRON_SECRET, SERVICE_ROLE |
| `ingest-jobs-email` (v13, verify_jwt=false) | Webhook Resend Inbound (Polifinance) + GPT-4o vision | Resend | RESEND_INBOUND_WEBHOOK_SECRET, POLIFINANCE_ALLOWED_SENDERS, OPENAI |
| `notify-signup` (v20, verify_jwt=false) | ntfy ao fundador no signup | trigger DB | NTFY_* |
| `notify-auto-apply-swipe` (v1) | ntfy ao fundador quando swipe-right em vaga email ("candidatura automatizada") | App | NTFY_TOPIC_AUTO_APPLY |
| `notifications-daily-digest` (v19) | Push diário OneSignal (vagas novas) | pg_cron (19/05) | ONESIGNAL_REST_API_KEY |
| `notifications-broadcast` (v16) | Push manual broadcast | founder (script) | ONESIGNAL_REST_API_KEY |
| `daily-report` (v14) | E-mail Resend + ntfy 07h BRT com KPIs | pg_cron | RESEND, REPORT_EMAIL_*, NTFY |
| `admin-me/-overview/-jobs/-users/-clients/-candidate-lists/-audit` (7 fns, v2-3) | API do dashboard B2B (auth via `admin_users`) | admin_dashboard React | SERVICE_ROLE |

## C5. Storage

1 bucket: **`resumes` (privado)** — 1.225 objetos (query `storage.objects`, 09/06). Guarda PDFs de CV importados (`{userId}/...`) e PDFs de CVs salvos/re-renderizados. Policies: own-folder por `auth.uid()` (migrations `20260526000004_storage_resumes_update_policy` e baseline); deleção de conta limpa via `deleteUserData()`.

## C6. Migrations e drift

- **Gerência:** Supabase CLI, arquivos em `supabase/migrations/` (77 arquivos). Sem branches do Supabase, sem config.toml de ambientes.
- **Aplicadas em prod:** até `20260601213000_admin_jobs_metrics_rpc` (via `list_migrations`, 09/06).
- **DRIFT CONFIRMADO:** `20260607000000_user_culture_fit_preferences.sql` está no repo mas **não aplicada** (`to_regclass('public.user_culture_fit_preferences')` → null). O app local (commit `7964983`) já grava nessa tabela com fallback silencioso pra SharedPreferences (`culture_fit_repository.dart:36-41`).
- **Drift histórico institucionalizado:** 4 arquivos `*_remote_history_placeholder.sql` (28-30/05) = mudanças feitas direto no dashboard/MCP e só "carimbadas" depois. Indica que o repo nem sempre é a fonte de verdade do schema.

## C7. Views, agregações e jobs agendados

- **Views no schema public:** `[NÃO EXISTE]` nenhuma (information_schema.views = 0 relevantes; única "agregação" é a RPC `admin_job_metrics`).
- **pg_cron (7 jobs ativos, via `cron.job` 09/06):** `sync-jobs-ats` 07:30; `sync-jobs-apify` 07:00 (estágio, max 150) e 19:00 (trainee, max 100); `sync-jobs-brazil` 08:00 (40 listings, keyword "estagio"); `daily-report` 10:00 UTC (07h BRT); partições do archive dia 1 do mês (jobids 17 e 18). ⚠️ Os comandos do cron embutem a anon key e o `x-cron-secret` em texto plano na tabela `cron.job`.
- **Batch export PostHog→Supabase:** diário, pro schema `analytics_archive` (261.911 eventos arquivados; partições automatizadas até 2027-12).

---

# SEÇÃO D — Ingestão e ciclo de vida das vagas

## D1. Fontes ativas

`[EXISTE]` 4 pipelines (volumes = total acumulado por `source`, query 09/06):

| Fonte | Mecanismo | Código | Frequência | Volume acumulado |
|---|---|---|---|---|
| **Gupy (via Apify)** | Scraper Apify actor, REST | `sync-jobs-apify/index.ts` (462 l.) | 2x/dia (07h estágio máx 150; 19h trainee máx 100) | 2.243 jobs (73%) |
| **InfoJobs/BR scrapers** | Scraping HTTP próprio | `sync-jobs-brazil/index.ts` (414 l.) | 1x/dia 08h (máx 40) | 653 jobs (`brz_infojobs`) |
| **Greenhouse/Lever (ATS API)** | API pública JSON por company slug (`external_job_sources`: 51 greenhouse ativas, 13 inativas; 5 lever inativas) | `sync-jobs-ats/index.ts` (176 l.) | 1x/dia 07:30 | 171 jobs |
| **Polifinance (e-mail)** | Resend Inbound webhook + GPT-4o vision parseia o e-mail/imagem | `ingest-jobs-email/index.ts` (634 l.) | Por e-mail recebido | 18 jobs |

(+5 jobs com `source` NULL — inserções manuais antigas.)

## D2. Onde roda o pipeline

`[EXISTE]` — 100% Supabase: **pg_cron → `net.http_post` → edge function** (sem n8n/Zapier/serviço externo). Fluxo de uma vaga: fetch da fonte → normalização em `_shared/jobs.ts` (703 linhas: `htmlToText`, `stripHtml`, `inferArea`, `inferJobType`, sanitização, cidade/UF) → upsert de `companies` (por nome/slug) → upsert de `jobs` com `(source, external_id)` → ao final do sync, `markStaleJobsInactive(source, 48h)` desativa o que a fonte parou de listar. Publicação no feed é implícita: `is_active=true` aparece no próximo fetch do app.

## D3. Schema da vaga

26 colunas (information_schema, 09/06; DDL no Apêndice 2): `id, company_id (FK NOT NULL), title, description, requirements text[], benefits text[], location_city, location_state, salary_min, salary_max (int, centavos? — int simples), work_model NOT NULL, job_type NOT NULL, area NOT NULL, is_active bool default true, published_at, deadline, created_at, source, external_id, external_url, last_seen_at, raw_payload jsonb, description_html, application_method default 'url', application_email, application_subject`.

Mapeamento fonte→schema (o que se perde/infere): salário raramente vem (48/469 ativas = 10%); `area` é **inferida** (D4); `work_model`/`job_type` inferidos por keyword (`inferJobType` em `_shared/jobs.ts`); `requirements` extraído heurística do texto; `raw_payload` preserva o original; HTML da Greenhouse vai pra `description_html`.

## D4. Taxonomia de área

`[EXISTE]` — **Regex/keywords no código**, função `inferArea(title, contextHints)` em `supabase/functions/_shared/jobs.ts:529-575`. Estratégia title-first (1ª passada só título; 2ª passada descrição com `stripBenefitNoise` pra não classificar "plano de saúde" como Saúde). Lista de áreas válidas: **hardcoded nas rules da função** — Saúde, Jurídico, Tecnologia, Marketing, Vendas, Finanças, Recursos Humanos, Operações, Produto, Engenharia, Administrativo + fallback `"Geral"`. No banco é `text` livre (sem enum/constraint). No app, a lista espelhada vive em `lib/core/constants/job_areas.dart`. Distribuição atual das 469 ativas: Geral 55, Finanças 52, Tecnologia 49, Operações 49, Saúde 46, Engenharia 37, Jurídico 36, Marketing 36, RH 30, Produto 29, Vendas 28, Administrativo 22.

## D5. Deduplicação

`[PARCIAL]` — Chave de dedupe é `(source, external_id)` via upsert (migration `20260506000002_fix_unique_constraints`). **Não há dedupe cross-fonte** (mesma vaga via Gupy e InfoJobs vira 2 rows). Query em 09/06: **11 grupos (title, company_id) duplicados entre as ativas**.

## D6. Frescor

`[EXISTE]` — mecanismo técnico exato: cada sync chama `markStaleJobsInactive(supabase, source, 48)` (`_shared/jobs.ts:618-637`): `UPDATE jobs SET is_active=false WHERE is_active AND last_seen_at < now()-48h AND source=...`. Ou seja: **a vaga é "revisada" porque a fonte é re-listada diariamente e `last_seen_at` é atualizado no upsert; sumiu da fonte por 48h → desativa**. Não há recheck de link individual. Saída do feed: (1) `is_active=false` pelo stale-mark; (2) `deadline` no passado (filtro client-side, `job_repository.dart:86-93`); (3) usuário swipou (exclusão por `swipe_actions`). Não há delete físico.

## D7. Contagens atuais (queries 2026-06-09 ~21:00 BRT)

- Por status: **469 ativas / 2.621 inativas** (3.090 total).
- Por fonte: gupy 2.243, brz_infojobs 653, greenhouse 171, polifinance 18, NULL 5.
- Por área (ativas): tabela em D4.
- **Bolsa preenchida: 48/469 (10,2%)**. **Cidade preenchida: 469/469 (100%)** — mas sem lat/long e sem normalização formal (texto; ~23 vagas históricas tinham city="Remoto"/"Brasil", comentário em `analyze-match/index.ts:~560`).

## D8. Vaga manual

`[PARCIAL]` — Não há UI de criação. Caminhos usados até hoje: (1) INSERTs via SQL/migrations (5 vagas com source NULL; migrations de seed/cleanup); (2) Polifinance por e-mail é "semi-manual" (humano encaminha e-mail); (3) o dashboard admin (`admin-jobs`) lista e mostra métricas, **não cria** vagas.

---

# SEÇÃO E — Feed e swipe (estado atual)

## E1. Montagem do feed

`[EXISTE]` — query exata em `JobRepository.fetchJobsWithDiagnostics` (`lib/features/jobs/data/job_repository.dart:52-132`):
1. `SELECT job_id FROM swipe_actions WHERE user_id = X` (pra excluir).
2. `SELECT *, companies(*) FROM jobs WHERE is_active = true ORDER BY published_at DESC` — **todas as ativas, sem limit server-side**.
3. Client-side: exclui swipadas e deadline vencido; aplica filtros de preferência (`_applyPreferenceFilters`, permissivos com null — `job_repository.dart:151-176`); **`jobs.shuffle(Random())`** (linha 111 — ordem aleatória por sessão, comentário explica que `published_at DESC` fixo matava engajamento).
4. "Paginação" com `_pageSize = 5000` (linha 35) = página única.
**Ranking: [NÃO EXISTE].** Filtro por perfil: sim, via preferências declaradas (áreas/cidades/modelos/tipos/salário com sinônimos e acento-insensível em `filter_helpers.dart`) + filtro opcional por match score mínimo (`JobsViewModel._filterByMatchScore`, `jobs_viewmodel.dart:347`, usa cache `match_analyses`). Curso/instituição NÃO influenciam o feed.

## E2. Paginação e cache

- Carga: tudo de uma vez (E1). Sem cache local de vagas (nem Hive nem SQLite pra isso; `DatabaseHelper` SQLite existe pra outros dados). Refetch a cada `init/reloadJobs`.
- Repetição: vagas já swipadas **não voltam** (exclusão por `swipe_actions`); o registro de "já visto sem swipe" não existe — vaga vista mas não swipada reaparece (em posição aleatória).
- "Já visto/decidido" mora em `swipe_actions` (Postgres). Contexto efêmero por sessão (score IA por card, CV adaptado) em `JobSwipeContext.shared` (`lib/features/jobs/job_swipe_context.dart`, SharedPreferences).

## E3. Swipe

`[EXISTE]` — Persistência: upsert em `swipe_actions (user_id, job_id, action 'liked'|'rejected', created_at)` com `onConflict: 'user_id,job_id'` (`swipe_repository.dart:9-21`) + colunas `applied bool` / `applied_at` (migration `20260507000001`). **Undo existe**: botão na UI → `undoLastSwipe` deleta a última row (`swipe_repository.dart:25-52`; `jobs_viewmodel.dart:792-823` emite `job_swiped` com `action:'undo'`).
Propriedades do evento `job_swiped` (`analytics_service.dart:981-1018`): `job_id`, `action` E `direction` (dupla proposital pra compat histórica), `match_score`, `match_source` ('ai'|'fallback_deterministic'), `match_confidence`, `application_method`, `position_in_feed`, `company_id`, `company_name`, `modality`, `salary_bucket`, `location_bucket`, `time_on_card_ms`.

## E4. Fim do feed

`[EXISTE]` estado desenhado (não quebra): ao esgotar, 1º tenta **auto-reload silencioso** uma vez (`jobs_viewmodel.dart:710-720`, emite `feed_exhausted`); persiste vazio → empty state com 2 variantes (`jobs_swipe_screen.dart:1180-1260`): "Nenhuma vaga bate com seus filtros" (CTA limpar filtros, mostra `totalAvailable`) vs "Você explorou tudo!" (CTA ajustar filtros/voltar depois).

## E5. Aba de salvas

`[EXISTE]` — `liked_jobs_screen.dart` (1.170 linhas): lista curtidas via `getLikedJobsWithDetails` (`swipe_repository.dart:75-105`, join `swipe_actions → jobs → companies`), ordenada por curtida recente. Ações: abrir detalhes, **Aplicar** (H1), toggle "Aplicada" manual (`setApplied`), adaptar CV, remover (com undo via SnackBar que restaura `created_at` original).
**Vaga expirada:** a query **não filtra `jobs.is_active`** — a vaga curtida continua listada após expirar; o usuário fica com card cujo link externo pode estar morto. Só some se a row de `jobs` for deletada (skip no join, comentário linha 89). `[PARCIAL]` — sem tratamento de expiração na UI.

## E6. Filtros e busca

- Filtros: `[EXISTE]` — `JobPreferencesScreen` (1.032 linhas): áreas, cidades, modelo, tipo, salário mínimo, match mínimo. Persistidos em `user_preferences` (470 rows; `preferences_repository.dart:11-30`) + espelho local.
- **Busca textual: [NÃO EXISTE]** — confirmado por grep (nenhum campo de busca no feed).

---

# SEÇÃO F — Match score

## F1. Fórmula/algoritmo exato

`[EXISTE]` **dois sistemas com os mesmos pesos**:

**(a) Determinístico client-side (fallback)** — `MatchScoreCalculator.calculate` (`lib/features/jobs/utils/match_score.dart:162-287`). Pesos: **Área 30, Tipo 20, Cidade 15 (remoto sempre passa), Modelo 15, Salário 10 (só se user setou), Skills/keyword-overlap 10 (proporcional, ratio×2.5 capped)**; só dimensões declaradas entram no denominador; normaliza pra 0-100; sem prefs → `MatchResult.unknown()`. Features: preferências declaradas + pseudo-texto agregado das tabelas `profile_*` (`ProfileSnapshot.toPseudoText`) + legacy `whoIAm.derived`. Trecho integral do código no arquivo citado (108 linhas da fórmula).

**(b) IA server-side (primário)** — edge `analyze-match` com gpt-4o-mini, `PROMPT_VERSION = 'v10'` (`analyze-match/index.ts:29`; versão ativa controlada por `app_config.match_prompt_version='v10'`, fallback client 'v4' em `ai_service.dart:50-95`). O prompt instrui os MESMOS pesos (30/20/15/15/10/10), score = soma exata dos weights matched, 3 cenários (A prefs / B só perfil / C nada → 50) — prompt literal no Apêndice 4. Output: `{score, reasons[]}` persistido em `match_analyses` com `profile_hash` e `prompt_version`.

**(c) Confiança** — `computeConfidence` (`match_score.dart:307-366`): 6 dimensões declaráveis; ≥5 = high, 3-4 = medium, <3 = low.

## F2. Onde e quando é calculado

- IA: por card, on-demand, com **sliding window** no client: prefetch dos 3 primeiros + pipeline de 2 à frente do índice atual (`jobs_swipe_screen.dart:76-92, 695, 789`). Antes de chamar IA, hidrata em batch o cache (`fetchCachedMatches` — 1 SELECT em `match_analyses` filtrado por `prompt_version`).
- Cache server: `match_analyses` (35.462 rows) por (user, job, prompt_version, profile_hash) — recomputa se perfil ou prompt mudou.
- Latência: timeout client 12s (`ai_service.dart:33-40`), server `OPENAI_TIMEOUT_MS=8000`. Falha → fallback determinístico. Custo: ~US$1/mês (gpt-4o-mini; rastreado via `$ai_generation`).

## F3. Lógica de exibição (por que ~72% dos cards mostram score)

`[EXISTE]` — condição em `job_card.dart:436-446` (e CTA inline 220-235): mostra o **número** apenas quando `confidence ∈ {high, medium}` e não está `isPending` nem `isNoResume`. `confidence == low` (<3 dimensões declaradas) → badge **"Análise limitada"** + CTA com `missingDimensions`; `isPending` → skeleton; `isNoResume` → CTA criar CV. Portanto a fração sem score = users com perfil/prefs ralos — não é A/B nem bug.

## F4. Score por impressão logado?

`[EXISTE]` desde a build 2.0.0+2 (~30/05): `job_card_shown` (`jobCardShown`, `analytics_service.dart:1163`) e `job_swiped` carregam `match_score` + `match_source` + `match_confidence` (F1/E3). Antes do cutover, `job_swiped` histórico (~28k eventos) tinha `action` e `match_score` parcial `[INCERTO sobre completude pré-cutover]`. Análise retroativa de ancoragem é viável **a partir de 30/05**; além do PostHog, o batch export diário arquiva os eventos em `analytics_archive.posthog_events_archive` (261.911 rows).

## F5. Infra de A/B test / feature flags

`[EXISTE]` em 3 mecanismos (nenhum experimento ativo):
1. **PostHog feature flags** — `Analytics.getFlag(key)` (`analytics_service.dart` + uso em `jobs_swipe_screen.dart`, `completion_screen.dart`). Flags existentes no projeto (dashboards auto-gerados): `ai_match_v1`, `adapt_diff_mode_v1`, `card_design_v1`, `empty_state_cta_v1`, `match_score_visibility_v1`, `new_onboarding_enabled`, `push_reactivate_tone_v1`.
2. **`app_feature_flags` (Supabase)** — `FeatureFlagsService` com cache no boot (`main.dart:147-152`); 3 flags (C1), só `adapt_v2_enabled` ligada.
3. **`app_config`** — config remota (force-update + `match_prompt_version` como botão de rollback do prompt).

---

# SEÇÃO G — Stage Resume / perfil

## G1. Mapa implementado × especificado

| Item da especificação | Status | Evidência |
|---|---|---|
| Trilha gamificada | **[EXISTE]** | 5 tracks / 9 phases / 172 questions no banco (query 09/06); player `question_screen.dart` (1.247 l.) + 40 widgets de pergunta; progresso `user_progress` (1.425 rows) |
| Perguntas fechadas → abertas dirigidas | **[PARCIAL]** | A trilha mistura formatos: abertos (`mini_text_box_widget`, `chat_interface_widget`, `experience_detail_form_widget`) e MUITOS fechados/lúdicos (`binary_choice`, `drag_and_drop`, `quick_time_event`, `badge_multiselect`...). Não houve substituição sistemática por perguntas abertas dirigidas |
| Geração incremental de bullets por IA | **[EXISTE]** | `generate-bullets` edge (3 ângulos: resultado/processo/habilidade) + `BulletReviewScreen`; grava `approved_bullets` (legacy) + `profile_bullets` (forward-only desde 23/05, comment na tabela) |
| `raw_responses` por usuário | **[EXISTE]** | Tabela `raw_responses` (5.284 rows), RLS own, escrita pelo `GamificationViewModel.saveAnswer` |
| Campanhas / variantes de CV por vaga | **[PARCIAL→degenerou]** | Tabelas `campaigns` + `target_jobs` existem (migration `20260430000000`), mas **1.584 de 1.599 target_jobs têm `is_skipped=true` (99%)** — viraram marcador "terminou onboarding" (`createCampaignWithTargetJob` cria "Campanha 1" draft, `supabase_repository.dart:1067-1095`). Não há UI de múltiplas campanhas. O conceito "CV mira vaga" sobrevive em `adapted_resumes` (CV adaptado por vaga, 31 rows) |
| Export PDF-only, HTML+CSS, template Harvard | **[EXISTE]** | `PdfService.generateResumeBytes` → `Printing.convertHtml` (client-side; `pdf_service.dart:66-126`); template `harvard_ats` default (linha 397) + 4 outros (`jakes_resume`, `forte_foundation`, `one_page_compact`, `cobalt_modern`, linhas 181-186); só PDF (DOCX/Web nunca construídos — CLAUDE.md:59) |
| Upload/parse de CV | **[EXISTE]** | `file_picker` → `pdf_text_extractor` (Syncfusion, local) → edge `extract-profile` (GPT-4o, PDF base64) → `save_profile_from_json` nas `profile_*` + dual-write `imported_resume` legacy (`cv_import_service.dart:171-292`) |

## G2. Schema real do perfil e divergências

Dados de currículo vivem em **três gerações simultâneas**:
1. **Legacy JSONB:** `user_profiles.gamification_data` (inclui `whoIAm.derived` da trilha e `imported_resume.raw_text/parsed` do upload antigo).
2. **Relacional (Semana 1, em produção):** 20 tabelas `profile_*` (C1) com FK `user_id → auth.users`; escrita via `save_profile_from_json` (extração) + `ProfileRepositorySupabase` (edição manual) + `TrailToProfileBridge` (trilha).
3. **Artefatos de CV:** `saved_resumes` (1.218; JSON do resume + template + path no Storage), `adapted_resumes` (31; cache por user×job×prompt_version), bullets em `approved_bullets`/`profile_bullets`.

Divergências espec ↔ banco: (a) campanhas degeneraram (G1); (b) bullets têm **dupla morada** com corte temporal — pré-23/05 só em `approved_bullets`, sem FK pra ligar retroativamente (comment da tabela `profile_bullets`); (c) `experience_raw_responses`/`user_experiences`/`profile_coursework` criadas e **vazias** (0 rows) — código morto de schema; (d) dual-write legacy⇄relacional ainda ativo (não houve cutover do legado).

## G3. A trilha

- **Estrutura técnica:** conteúdo no banco (`tracks` 5 / `phases` 9 / `questions` 172), seedado de `lib/data/seed_data.dart`, cacheado em memória no boot (`SupabaseRepository`). IDs de fase com prefixo `m1..m5`.
- **Progresso:** `user_progress` (user×phase, status) + respostas em `user_answers` (5.452) e `raw_responses` (5.284).
- **"Completou a trilha" =** todas as 5 tracks com fases concluídas → `PhaseCompletionWidget` modo 3 ("resume ready", `phase_completion_widget.dart:807`) → dispara `generate-resume` e navega pra aba Currículo; evento `trilha_completed` emitido em `phase_completion_widget.dart:184`. Os ~20 completions medem exatamente isso (fim da 5ª track).
- **Onde os dados caem:** dual-write — caminho legacy (`user_answers`/`raw_responses` + JSONB `whoIAm`) E relacional via `TrailToProfileBridge.route(phaseId, answer)` (`trail_to_profile_bridge.dart:36-58`): m1→job_preferences/desired_titles, m2→education, m3→experiences/bullets, m4→skills/languages/certifications, m5→personal. Bridge é defensiva (no-op silencioso pra fase não mapeada).

## G4. Geração de IA

- **Provedor/modelo:** OpenAI; gpt-4o-mini (match, bullets, summary, resume) e gpt-4o (extração de CV/vision, refine do adapt). Chamadas **sempre em edge function** (chave server-side; nenhum uso client — A6).
- **Prompts literais:** Apêndice 4 (analyze-match v10, adapt v2 v27-v2, generate-bullets, parse-cv, extract-job-skills, PROFILE_SYSTEM_PROMPT do extract-profile, generate-summary).
- **Erro/retry:** sem retry automático server-side; client tem timeout (12s match; adapt mais longo) e fallbacks (match→determinístico; extração→`profile_extraction_logs` com `recovery_status` e reprocesso em `_reprocessLatestResumeIfNeeded`, `user_viewmodel.dart:487`). Telemetria de toda chamada via `trackAIGeneration` (`_shared/posthog.ts`) + `ai_generation_logs` (37.182 rows).
- **Custo médio:** `[INCERTO]` por geração; tabela de preço em `_shared/posthog.ts:42-47` (gpt-4o-mini $0.15/$0.60 por Mtok; gpt-4o $2.5/$10). Ordem de grandeza observada: match ~US$1/mês total.
- **Output:** bullets → usuário escolhe ângulo e edita (`BulletReviewScreen`) antes de aprovar (grava `approved_bullets`+`profile_bullets`); extração de CV → usuário revisa (`ReviewPersonalInfo`/`ReviewResume`) antes de confirmar; adapt → preview com diff explicável + edição inline (`adapted_resume_preview_screen.dart`) antes de baixar/salvar. Nada vai "direto pro banco" sem tela de revisão, exceto o save inicial da extração (que já grava e a revisão edita por cima).

## G5. Export PDF

- **Pipeline técnico exato:** 100% client-side. `ResumeDetailScreen` → `PdfService.generateResumeBytes(user, resume, templateId)` → monta HTML+CSS inline em Dart (templates como funções `_buildXxxHtml`, com loop adaptativo de tiers pra caber em 1 página, `pdf_service.dart:100-167`) → **`Printing.convertHtml`** (plugin nativo iOS renderiza local) → bytes → **`Printing.sharePdf`** (share sheet iOS) (`resume_detail_screen.dart:373, 449`). Sem edge function, sem headless browser, sem serviço externo.
- **Template Harvard:** `harvard_ats` é o default e vive em `pdf_service.dart` (seção iniciando linha 397).
- **Por que só ~29 exports:** o botão **não está quebrado nem escondido por flag** — está fundo no funil. Caminho: ter CV na biblioteca (= completar trilha OU importar e gerar OU salvar um adaptado) → tab **Perfil** → sub-aba "Currículos" → tocar no card → `ResumeDetailScreen` → botão "Exportar PDF" (`resume_detail_screen.dart:761`). Portões: (1) biblioteca não vazia — a maioria dos 2k users não chega a ter `saved_resumes` utilizável; (2) o export fica na aba Perfil, não na aba "Currículo" onde o usuário constrói (a aba Currículo é só entry de trilha/import — `resume_tab.dart:13-24`); (3) evento `cv_exported` só é emitido nesse fluxo (`resume_detail_screen.dart:377`). Há também export do CV adaptado (`cvAdaptationPdfDownloaded`) que é fluxo separado.

## G6. Upload de CV (cv_upload_completed = 52)

O fluxo hoje: TwoDoors "Importar currículo" → `file_picker` (PDF) → `UploadPreviewSheet` → sobe o PDF pro bucket `resumes` + extrai texto local (Syncfusion) → dispara `extract-profile` **fire-and-forget** (`cv_import_service.dart:208-292`) → masking questions cobrem a latência → review screens mostram o resultado. Ou seja: **armazena o arquivo + parseia + preenche `profile_*` e o legacy `imported_resume`**. Se o usuário pula (porta trilha), nada de arquivo; masking questions + Education coletam o mínimo manualmente. Re-upload depois existe na aba Currículo (`import_cv_button.dart`) e em Settings. Falha de extração → `profile_extraction_logs.recovery_status` + retry no próximo boot (`_reprocessLatestResumeIfNeeded`).

## G7. Campos de perfil fora do currículo

- `profile_personal` (colunas reais, 09/06): first/last_name, email, phone (+e164), headline, summary, gender, age_range, location_country/state/city/postal/street, attribution_source, profile_source, completeness_score, schema_version, date_of_birth, linkedin_url, website, timestamps.
- `profile_job_preferences` (+ `profile_desired_titles`, `profile_other_locations`): tipos, modelos, salário, títulos desejados, cidades.
- Legacy `user_profiles`: name, course, semester, university (texto), gamification_data.
- **Instituição: texto 100% livre** — `TextField` simples (`education_screen.dart:680-693`); é por isso que aparece lixo tipo "Ensino Médio" no campo universidade. **Curso: idem, texto livre** (mesma tela, campo de curso/major sem autocomplete/normalização). `[NÃO EXISTE]` tabela canônica de instituições ou cursos.

---

# SEÇÃO H — Clique externo (fim atual do funil)

## H1. O que acontece no tap de aplicar

`[EXISTE]` — `launchUrl(uri, mode: LaunchMode.externalApplication)` = **browser externo (Safari) ou app de e-mail** — não é webview nem SFSafariViewController. Dois call sites de apply: `liked_jobs_screen.dart:139` (`_openApplication`) e `job_details_sheet.dart` (botão de aplicar). Resolução da ação (`_resolveApplyAction`, `liked_jobs_screen.dart:382-407`): `application_method=='email'` → `mailto:` com subject/body RFC 6068 (placeholders "[SEU NOME]" substituídos); senão `external_url` → fallback site da company.
**Evento exato:** `job_details_apply_clicked` (constante `evJobDetailsApplyClicked`, `analytics_events.dart:301`), props: `job_id`, `match_score` (lido do `JobSwipeContext` persistido no swipe), `used_adapted_cv` (bool), `application_method` (`analytics_service.dart:1031-1044`; emissão em `liked_jobs_screen.dart:119-124`). Complementos: `adapt_apply_used` quando usou CV adaptado, FB `SubmittedApplication` só se `launchUrl` retornou true, e milestone `first_apply`.

## H2. Decoração de URL e registro próprio

- **UTM/ref: [NÃO EXISTE]** — grep por `utm|ref=` em `lib/features/jobs` vazio; a URL sai crua da fonte.
- **Tabela própria de clicks: [NÃO EXISTE].** O que existe em banco: `swipe_actions.applied/applied_at` — mas é **toggle manual** do usuário ("Marcar como aplicada") ou pós-fluxo, não o click. O registro de QUEM clicou em QUAL vaga com timestamp só existe no PostHog (e no archive `analytics_archive`).

## H3. Detecção de retorno pós-clique

`[NÃO EXISTE]` detecção específica — confirmado. O lifecycle observer global emite `app_foregrounded`/`session_started` (`analytics_service.dart:211-292`), mas nada correlaciona o retorno com o apply que o precedeu.

---

# SEÇÃO I — Notificações e comunicação

## I1. Push

`[EXISTE]` — **OneSignal** (`onesignal_flutter` 5.x; `aps-environment: production` no entitlements). Wrapper `lib/services/notifications_service.dart`: init no boot sem prompt (`main.dart:177-183`); **permissão pedida na HomeScreen ~4s após exibir, depois do ATT (~1s)**; `OneSignal.login(userId)` no auth listener. Listeners de foreground/click/permission emitem `push_displayed`, `push_opened`, `push_permission_requested/granted/denied/revoked_detected`.
Notificações existentes hoje: (1) **daily digest** de vagas (edge `notifications-daily-digest`, cron 19/05); (2) **broadcast manual** (edge `notifications-broadcast` + `scripts/send_push.sh`); (3) pushes operacionais pro FUNDADOR via ntfy (signup, auto-apply, daily report) — não são push pra usuários. Taxa de opt-in: `[INCERTO]` (mediria no PostHog `push_permission_granted/requested`; não calculei nesta auditoria).

## I2. E-mail

`[PARCIAL]` — Transacional para USUÁRIOS: só os e-mails de auth do Supabase. Resend é usado para: **daily report interno** (founder/sócio; `daily-report/index.ts`, secrets REPORT_EMAIL_FROM/TO) e **inbound** (Polifinance). Marketing/CRM de usuário: `[NÃO EXISTE]`.

---

# SEÇÃO J — Analytics e eventos

## J1. Inventário de eventos PostHog

Método: catálogo central `lib/services/analytics_events.dart` (**318 constantes**, todas snake_case com prefixo de domínio; wrapper `track()` valida contra allowlist em debug — `analytics_service.dart:372-400`) + grep exaustivo `Analytics.shared.` (única forma de capture no app; nenhum `Posthog().capture` direto fora do service). **Todos os eventos do app são CLIENT**; os server estão em J3.

Eventos **com emissor verificado** (evento → arquivo emissor; todos via método tipado em `analytics_service.dart`):

| Domínio | Evento | Dispara em |
|---|---|---|
| Sistema | `app_opened`, `perf_app_cold_start`, `session_started/ended`, `app_backgrounded/foregrounded` | `main.dart:140-144` + lifecycle observer (`analytics_service.dart:211-292`) |
| Sistema | `system_version_outdated` (`appVersionOutdated`) | `version_gate.dart:82` |
| Sistema | `$screen` | `ScreenTrackingMixin` (`core/analytics/screen_tracking.dart`) + `home_screen.dart` |
| Erros | `$exception` (Error Tracking) | `main.dart:66-90` (3 caminhos globais) |
| Auth | `auth_signup_landing_shown`, `auth_signup_method_chosen`, `auth_signup_started`, `auth_signup_completed`, `auth_login_succeeded`, `auth_logout`, `auth_password_changed(+failed)`, `apple_signin_started/failed`, `oauth_migration_started/completed/failed` | `auth_screen.dart`, `phone_signup_screen.dart`, `user_viewmodel.dart` (listener :310-370) |
| Onboarding | `onboarding_started`, `onboarding_two_doors_shown`, `onboarding_door_chosen`, `onboarding_step_reached`, `onboarding_personal_review_shown/confirmed`, `onboarding_personal_field_edited`, `onboarding_cv_review_shown/confirmed`, `onboarding_cv_section_edited`, `onboarding_pref_step_shown/answered/skipped`, `onboarding_all_set_shown`, `onboarding_completed`, `onboarding_abandoned`, `onboarding_cv_import_abandoned` | `two_doors_screen.dart`, `review_*_screen.dart`, `preferences/*.dart`, `all_set_screen.dart`, `completion_screen.dart`, `onboarding_screen.dart` |
| Import CV | `onboarding_cv_upload_started`, `cv_import_succeeded/failed/parsed`, `cv_parser_failed` | `cv_import_service.dart` |
| Ativação | `activation_milestone_hit` (first_swipe/first_apply/first_adapt/trilha) | `jobs_swipe_screen.dart`, `liked_jobs_screen.dart`, `resume_adaptation_sheet.dart`, `gamification_viewmodel.dart` |
| Feed/Jobs | `feed_opened`, `feed_loaded`, `feed_load_failed`, `feed_exhausted`, `job_card_shown`, `job_swiped`, `job_details_opened`, `job_details_apply_clicked`, `job_shared`, `job_filters_applied` | `jobs_swipe_screen.dart`, `jobs_viewmodel.dart`, `liked_jobs_screen.dart` |
| Adapt | `adapt_intent_clicked`, `cv_adaptation_started/succeeded/failed`, `adapt_diff_shown`, `cv_adaptation_user_edited`, `cv_adaptation_pdf_downloaded`, `adapt_apply_used`, `cv_library_save_failed`, `skills_confirmation_opened/completed/auto_skipped` | `resume_adaptation_sheet.dart`, `adapted_resume_preview_screen.dart`, `skills_confirmation_sheet.dart` |
| Trilha | `trilha_phase_started/completed` (`trackPhaseStarted/Completed`), `phase_step_shown/completed/abandoned`, `trilha_completed` | `gamification_viewmodel.dart`, `phase_completion_widget.dart` |
| CV | `cv_exported`, `cv_template_changed`, `cv_template_selector_opened` | `resume_detail_screen.dart`, `resume_template_selector.dart`, `adapted_resume_preview_screen.dart` |
| Push | `push_displayed/opened`, `push_permission_requested/granted/denied/revoked_detected` | `notifications_service.dart` |
| Tutorial | `tutorial_started/step_shown/step_dismissed/completed/skipped` | `tutorial_controller.dart` |
| Nav/Misc | `nav_tab_switched`, `founders_contact_opened`, culture-fit (via `track()` genérico) | `home_screen.dart`, `settings_screen.dart`, `culture_fit_prompt_sheet.dart` |

**Constantes SEM emissor (catálogo morto, definidas em `analytics_events.dart` mas sem call site):** todo o bloco B2B (`b2b_company_registered`, `b2b_job_published`, `b2b_candidate_viewed/contacted` — métodos existem no service, zero callers), monetização (`paywall_*`, `pricing_*`, `purchase_*`, `subscription_*`), social (`share_*` parcial, `invite_*`, `qr_code_scanned`), `job_card_dwell_*`, `job_bulk_swipe_burst`, `job_revisited_from_curtidas`, `feed_refresh_pulled`, `deep_link_*`/`install_attributed` (T3.1 sem AASA), `feedback_*`, `modal_*`, e dezenas de `auth_email_verification_*`, `auth_phone_otp_*` etc. Estimativa: **~200 das 318 constantes não têm emissor**.

## J2. Inicialização e ciclo identify/alias/reset

Ver B5. Resumo de config (`main.dart:117-131`): init manual (AUTO_INIT=false no Info.plist), `captureApplicationLifecycleEvents=false` (lifecycle é manual), **session replay LIGADO** com `maskAllTexts/maskAllImages=false` + máscara seletiva via `PiiMask` (`core/widgets/pii_mask.dart`), sem autocapture de toques (não existe no SDK Flutter nesse modo), `$screen` manual. Super properties registradas no boot e refresh pós-login (`_loadAndRegisterSuperProperties`, `analytics_service.dart:109`). Logout → `reset()`.

## J3. Eventos server-side

**[EXISTE] — diferente do esperado.** `supabase/functions/_shared/posthog.ts` exporta `trackAIGeneration` (`$ai_generation` com custo USD por modelo), `captureEvent` (genérico), `trackEdgeFunctionInvoked` (`edge_function_invoked` com latência/status — TODAS as 27 functions estão envelopadas com `withEdgeAnalytics`), `trackLlmCallFailed`, `trackLlmResponseAntiInventionFlagged`, `trackRateLimitHit`, `groupIdentify`. `captureEvent` adicional usado por `sync-jobs-ats` e `notifications-daily-digest` (eventos de sync/push). distinct_id = user.id quando há user; eventos de sistema usam id sintético. Além do PostHog, há a "tabela própria de eventos" parcial: `ai_generation_logs` (37.182) e o archive diário PostHog→Supabase (`analytics_archive`). **O que NÃO existe:** eventos server-side de DOMÍNIO de produto (signup confirmado, swipe, apply) — esses são só client.

## J4. Funis/insights em uso

`[EXISTE]` acesso — 23 dashboards no projeto 419792 (listados via MCP em 09/06). **10 pinned pós-cutover** (criados 28-29/05, tags `cutover-2026-05`): "Ativação (Post-cutover)" (funil macro signup→onboarding→swipe→apply), "Canal & Aquisição", "CV Adapt (pós-cutover)" (pitch slide #4), "Health Check Diário", "Match Score v9 — qualidade", "Operação (custos, latência, erros)", "Pipeline B2B (proto)", "Retenção & Cohorts (Post-cutover)", "Swipe & Match", "Trilha (granular pós-cutover)". + 4 legacy `legacy-pre-cutover` (Activation Funnel, Job Feed, Métricas Chave, Retenção) + 7 auto-gerados por feature flag + "Aprendizado & Analise (UX/Growth)" e "CV Adaptado (qualidade IA)".

## J5. Discrepâncias conhecidas no tracking

Compilado de `AUDITORIA_POSTHOG.md` (repo pai, 30/05), `INSTRUMENTATION_QA.md` e do código:
1. **Fix de `is_pre_cutover_user` e `feed_exhausted` NÃO está em produção** — commit `a72dedb` (30/05) é posterior ao bump 2.0.0+2; números desses campos na build de prod estão errados.
2. **Build de prod é minoria do tráfego instrumentado** — na auditoria de 29/05, só ~1,4% dos eventos tinham as super-props novas; eventos do plano v2 só fluem de quem atualizou.
3. **Dupla taxonomia proposital** `action` + `direction` em `job_swiped` (compat histórico) — fácil de dupla-contar se alguém filtrar errado.
4. **`$pageview` de app mobile** apareceu em insights (mistura LP/app) — auditoria 29-30/05.
5. **Cohort/filtro de internos:** mudar `test_account_filters` não invalida cache de insights; person-on-events congela `is_internal` no valor da época do evento (memória `posthog_test_filter_cache`); conta Apple relay `sgxvydk4bn` é interna.
6. **Funis "de pitch" quebrados pré-29/05** (`jobCardShown`, `adaptIntentClicked` etc. sem caller) — corrigidos na instrumentação atual, mas o histórico antes disso é vazio, não zero real.
7. **Catálogo morto** (J1): ~200 constantes sem emissor — dashboards que referenciem esses eventos mostram vazio.
8. **Descontinuidade de identidade no cutover** (B4): comparações pré/pós-30/05 por usuário são não-confiáveis para quem não reabriu o app.

---

# SEÇÃO K — Onboarding atual (passo a passo)

## K1. Sequência exata do primeiro uso

Fluxo verificado pelos call sites de navegação (greps de `Navigator.push` citados na Seção B/G; eventos de cada tela em J1):

1. `SplashScreen` (animação) → `AuthGate`.
2. **Auth:** `OnboardingScreen` (landing: carrossel; evento `auth_signup_landing_shown`) → método: Google/Apple (1 tap + OAuth) ou telefone (`PhoneSignupScreen`: telefone+senha; pulável: não) ou email. Eventos `auth_signup_method_chosen/started/completed`.
3. `AuthGate` re-roteia → **`TwoDoorsScreen`** (`onboarding_two_doors_shown`): "Importar currículo" vs "Construir pela trilha" (`onboarding_door_chosen`).
4. **Porta CV:** `UploadPreviewSheet` (file_picker PDF; coleta: arquivo; pulável: volta) → `ExtractionInProgressScreen` (dispara `extract-profile` em background) → **masking questions** (mascaram a latência): `AttributionScreen` (como conheceu; pulável) → `FirstNameScreen` → `LastNameScreen` → `EmailScreen` → `PhoneScreen` → `GenderScreen` → `AgeRangeScreen` (cada uma salva em `profile_personal`; navegação confirmada em `masking_questions/*.dart`) → `AllSetScreen` → `ReviewPersonalInfoScreen` (`onboarding_personal_review_shown/confirmed`; valida/edita extração) → `ReviewResumeScreen` (`onboarding_cv_review_*`) → `EducationScreen` (formação; texto livre) → preferências.
5. **Porta trilha (sem CV):** mesmas masking questions (Attribution→...→AgeRange) → `EducationScreen` → preferências. (A trilha em si fica pra depois, na aba Currículo.)
6. **Preferências:** `DesiredTitlesScreen` → `LocationScreen` → `WorkLocationsScreen` (+busca de cidade) → `WorkModeScreen` → `JobTypesScreen` → `OnboardingCompleteScreen` (cria campaign marker → `hasCampaign=true` → AuthGate → `HomeScreen`). Eventos `onboarding_pref_step_shown/answered/skipped` por step + `onboarding_completed`.
7. `HomeScreen` abre na aba Vagas; ATT prompt ~1s, push prompt ~4s; tutorial spotlight no primeiro uso.

## K2. Tempo/taps até o primeiro card

Contagem pelo fluxo de código (caminho porta-CV, sem erros): auth social ≈ 3-4 taps; two doors 1; upload 2-3; 7 masking questions ≈ 8-14 taps (digitação à parte); 2 reviews ≈ 2-4; education ≈ 3-5; 6 telas de preferência ≈ 8-12; total ≈ **28-43 taps / 16-18 telas** antes do primeiro card de vaga. Estimativa de tempo: 3-6 min (+10-15s de extração mascarada). `[INCERTO]` o tempo real — medível por `onboarding_duration_ms` (prop de `onboarding_completed`).

## K3. O que do onboarding alimenta o feed/match HOJE

**Usados de verdade:** job_types, work_models, locations, min_salary (→ `profile_job_preferences`, consumidos pelo feed via `_loadProfilePrefs` em `jobs_viewmodel.dart:477` e pelo match F1); áreas de interesse; conteúdo do CV extraído (skills/bullets/summary → pseudo-texto do match e do adapt).
**Coletados e NÃO usados no feed/match:** `gender`, `age_range`/`date_of_birth`, `attribution_source` (só analytics), `desired_titles` (gravado em `profile_desired_titles`; **não filtra o feed** — nenhum uso em `job_repository`/`filter_helpers`), formação/instituição (não pontua match), first/last name (só CV), phone (contato).

---

# SEÇÃO L — Qualidade, testes e dívida técnica

## L1. Testes

`[EXISTE]` minimamente: **2 arquivos** (`test/features/profile/domain/education_test.dart`, `test/features/profile/presentation/widgets/add_edit_education_modal_test.dart`), **6 testes (3 unit + 3 widget), todos verdes** — rodei `flutter test` em 09/06: "All tests passed!" em 18s. Cobertura aproximada: ~0% (6 testes para 79.429 linhas; cobrem só o modal de educação de 01/06).

## L2. Crash/erro

- Sentry/Crashlytics: `[NÃO EXISTE]`. Captura global → PostHog Error Tracking via `$exception` (`main.dart:55-90`: FlutterError.onError + PlatformDispatcher.onError + runZonedGuarded, com enrichment last_screen/last_event).
- Crash rate: `[INCERTO]` — não computado nesta auditoria. Histórico: antes do fix de 29/05 havia 0 exceptions reportadas (app cego). 5 erros mais frequentes: `[SEM ACESSO nesta passada]` — disponível no produto Error Tracking do PostHog (projeto 419792), não consultado aqui.

## L3. TODO/FIXME/HACK

Grep em `lib/` (7 hits, maioria falso-positivo "TODOS"/"TODO espaço") + `supabase/functions`. Os relevantes — a base é **anormalmente limpa de TODOs**, o débito real está em código morto e drift, não em comentários:

1. ⚠️ `supabase/functions/generate-resume/index.ts:36` — "**TODO: re-enable before launch** — restore the `count >= N` check" → **rate limit de geração de CV DESATIVADO em produção**.
2. `lib/features/gamification/question_screen.dart:1049` — "TODO: Show error feedback? For now, button stays disabled." (falha silenciosa de UX na trilha).
3. `lib/features/gamification/widgets/corporate_form_widget.dart:34` — "TODO: Parse initialValue JSON if needed" (edição não re-hidrata).

## L4. Código morto

- **Telas:** `world_screen.dart` (WorldScreen — zero call sites desde a remoção do mundo secreto em 06/05). `account_migration_screen.dart` e `completion_screen.dart` são legacy-mas-alcançáveis.
- **Tabelas vazias/abandonadas:** `user_experiences`, `experience_raw_responses`, `bullet_versions`, `profile_coursework` (migrada pra skills em 22/05), `profile_application_countries`, `profile_education_minors`, `security_audit_log`, snapshots `user_profiles_backfill_snapshot_20260521` / `_jobs_area_backup_20260530`.
- **Edge functions legadas deployadas sem caller:** `parse-cv`, `parse-cv-pdf` (substituídas por `extract-profile` em 26/05, mantidas "por rollback"), `generate-profile` (uso residual da trilha legacy).
- **Dualidades vivas (meio-mortas):** adapt v1 (`index.ts` SYSTEM_PROMPT v14) convive com v2 atrás de flag (v2 está 100%); dual-write trilha legacy⇄relacional; `user_preferences` (filtros) vs `profile_job_preferences` (onboarding) — **duas tabelas de preferências ativas simultaneamente**, sincronizadas no app, não no banco.
- **Catálogo de eventos morto:** ~200 constantes (J1).

## L5. Os 5 arquivos mais longos (deus-classes)

Comando: `wc -l` (Seção A):
1. `lib/features/resume/resume_edit_screen.dart` — 2.768 l. (edição manual de CV inteira numa tela).
2. `lib/features/jobs/screens/jobs_swipe_screen.dart` — 2.154 l. (feed: UI + sliding window IA + tutorial + empty states).
3. `lib/features/resume/resume_viewmodel.dart` — 2.149 l. (estado do builder + export + idioma).
4. `lib/features/jobs/widgets/adapted_resume_preview_screen.dart` — 2.004 l. (preview/diff/edição do adapt).
5. `lib/features/resume/pdf_service.dart` — 1.871 l. (5 templates HTML inline + tiers adaptativos).
(Menções honrosas: `analytics_service.dart` 1.848; `supabase_repository.dart` 1.472; `adapt-resume-to-job/index.ts` 2.947 no backend.)

## L6. Git log 90 dias — frentes de trabalho

94 commits desde 11/03 (efetivamente desde 02/05; comando: `git log --since="90 days ago"`). As 10 frentes:
1. **Adaptação de CV** (F0-F9, 20/05: parsing estruturado, validação anti-invenção, quality_score, preview/edição) — maior frente do período.
2. **Profile-first**: backend relacional (22/05), UI Semana 2, Fase 2 client (27/05).
3. **Onboarding novo** (two doors + masking questions, 22-27/05).
4. **Match score**: v4→v10, confidence, bypass Cenário C, fix race conditions (27-30/05).
5. **Design system** (27-28/05: tokens, migração em massa de cores).
6. **PostHog**: instrumentação v2 + cutover + 2 auditorias + remediações (28-30/05).
7. **Facebook Ads Phase 1** (Advanced Matching, ATT, SKAdNetwork — 29/05).
8. **Vagas**: sync Gupy/ATS/Brazil, classificação de área, formatação HTML (maio).
9. **Admin dashboard B2B** (02/06) + relatório diário.
10. **Fit cultural + "candidaturas automatizadas"** (09/06 — local, com drift de migration).
Momentum: pico intenso 20-30/05 (pré-release 2.0.0), desaceleração em junho (3 commits).

---

# SEÇÃO M — Segurança e LGPD

## M1. Chaves no client (achados críticos primeiro)

1. ⚠️ **CRÍTICO: `OPENAI_API_KEY` embarca no bundle do app.** O `.env` contém a chave (nome verificado; valor não inspecionado) e `pubspec.yaml:133` declara `- .env` como **asset** — qualquer pessoa que extraia o IPA lê o arquivo. O código Dart NÃO usa a chave (grep vazio em `lib/`), ou seja, é resíduo histórico: **remover do `.env` e rotacionar a chave**. (O `.env` não está no git — `.gitignore:57`.)
2. Aceitáveis por design: `SUPABASE_ANON_KEY` (RLS cobre), `POSTHOG_API_KEY` (project key pública), `ONESIGNAL_APP_ID`.
3. Service role: **não está no client** (só em secrets de edge functions). ✅
4. Menor: anon key + `x-cron-secret` em texto plano nos comandos `cron.job` (visível pra quem tem acesso SQL; risco baixo, mas o cron-secret deveria estar no Vault).

## M2. O que um usuário/atacante com anon key lê

Dadas as policies (C2), caminhos óbvios testados mentalmente:
- **Sem login (anon):** apenas `app_config` (versões/URLs — inócuo). Tabelas de domínio exigem `authenticated`.
- **Logado (qualquer conta):** catálogo completo de `jobs` + `companies` (público por design — inclui `application_email` de recrutadores Polifinance, PII leve de terceiros exposta a todo usuário autenticado); conteúdo da trilha. **Dados de outros usuários: bloqueados** — todas as tabelas user-owned filtram `auth.uid()`.
- **Edge functions:** `verify_jwt=true` em todas exceto `notify-signup` e `ingest-jobs-email` (webhooks; o segundo valida `RESEND_INBOUND_WEBHOOK_SECRET` + allowlist de remetentes). `analyze-match`/`adapt` derivam o user do JWT — sem IDOR óbvio.
- Resíduo: criança de conta sintética `phone_*@stage.app` significa que **posse do telefone nunca é verificada** — qualquer um pode registrar o número de outra pessoa (não vaza dado, mas é spoofável).

## M3. Consentimento e privacidade

- **Termos/política no signup:** links "Termos de Uso" e "Política de Privacidade" na tela de cadastro por telefone (`phone_signup_screen.dart:398-406`). `[INCERTO]` se o fluxo OAuth/landing exibe aceite equivalente (não encontrei registro de aceite versionado).
- **Versão registrada do aceite: [NÃO EXISTE]** — nenhuma coluna/tabela de consent versionado de termos.
- **Consentimento IA:** `[EXISTE]` modal dedicado (`ai_consent_modal.dart`, com links pra políticas, inclusive da OpenAI) persistido via `updateAIConsent` (`user_viewmodel.dart:1138-1160`), com revogação.
- **Consent B2B:** tabela `candidate_data_sharing_consents` criada (0 rows — ainda não usada).
- **Session replay LGPD:** replay ligado por padrão sem opt-in explícito; máscara por `PiiMask` em telas sensíveis. Opt-in LGPD documentado como pendência (memória do projeto + `issues`).

## M4. PII em logs/analytics

- **PostHog:** `email` vai como person property no identify (`analytics_service.dart:340`) — prática comum, mas é PII no PostHog (e replicada no archive Supabase). Eventos de produto não carregam nome/telefone (verificado nos props de J1). Replay com `maskAllTexts=false` depende da disciplina do `PiiMask` — telas novas sem máscara vazam por default.
- **ntfy (push de terceiros, sem auth forte):** `notify-signup` envia **nome + e-mail** do usuário novo pro tópico ntfy do fundador; `notify-auto-apply-swipe` envia dados da ação. ntfy públicos são adivinháveis pelo nome do tópico — PII de usuário transitando por canal best-effort. ⚠️
- **Logs de edge:** `console.error` com mensagens de erro; não vi dump de CV completo em logs (amostragem), `[INCERTO]` cobertura total.

---

# SEÇÃO N — Operação manual hoje

## N1. Como o time vê/edita dados

- **Supabase Studio** direto (SQL editor) — operação primária do fundador; mudanças estruturais às vezes entram por lá e viram `remote_history_placeholder` (C6).
- **Admin Dashboard B2B** (`admin_dashboard/` — React 18 + Vite + Tailwind + supabase-js; deploy `[INCERTO]`, dist/ commitado): KPIs, usuários/candidatos, vagas (+métricas via RPC `admin_job_metrics`), clientes, listas de candidatos com export CSV, audit log. Autoriza via tabela `admin_users` (2 admins) através das 7 edge functions `admin-*`.
- **PostHog** (23 dashboards) + **relatório diário** (e-mail Resend + ntfy 07h BRT).
- **Operações manuais recorrentes:** limpeza/reclassificação de vagas via migrations SQL datadas (`cleanup_*`, `reclassify_*`, `deactivate_*` — ~12 no histórico); backfills (`backfill_profile_education_from_legacy`); **atender o ntfy de "auto-apply"** (encaminhar candidatura por e-mail manualmente); broadcast de push via script; correção de perfil sob demanda.

## N2. Ferramentas fora do app

Inventário pelo repo:
- `admin_dashboard/` (acima).
- `scripts/send_push.sh` (broadcast OneSignal), `scripts/posthog_annotate_deploy.sh` (annotation de deploy), `scripts/generate_static_fonts.py`.
- `tools/migrate_colors.py` + 2 variantes (migração de design tokens — one-off).
- `golden_set/` (CVs reais + ground truth + scripts — harness de avaliação da qualidade do adapt; roda manualmente).
- `supabase/scripts/` e `supabase/security_enhancements.sql`.
- Batch export PostHog→Supabase (configurado no PostHog, doc `SETUP_BATCH_EXPORT.md`).
- Docs operacionais no repo: `INSTRUMENTATION_QA.md`, `AUDITORIA_POSTHOG.md` (pai), `docs/*.md`, `RELATORIO_COMPLETO_APP.md` (01/06).
- n8n/Zapier/notebooks: `[NÃO EXISTE]` evidência no código/configs.

---

# SEÇÃO O — Avaliação do engenheiro (opinião)

## O1. Os 10 maiores riscos técnicos (ordenados por gravidade)

1. **Não existe entidade "candidatura" — e o produto já finge que existe.** `swipe_actions.applied` boolean + `mailto:` + ntfy manual (D8/H/E3). Construir candidatura nativa com estados e SLA exige criar o modelo do zero ENQUANTO a UI atual já promete "aplicação automática" — dívida de promessa, não só de código. Evidência: `notify-auto-apply-swipe/index.ts`, `swipe_actions` (493 applied).
2. **Feed sem camada server-side.** Full-scan + shuffle client (E1) torna "feed em lista com ranking" uma reescrita: query/RPC server-side, paginação, índice de ranking, e refactor do `CardSwiper` (que exige lista imutável). Tudo que o plano de feed assume (ordenar por relevância p/ usuário) não tem onde plugar hoje.
3. **Identidade analítica frágil para medir as frentes novas.** Cutover de 30/05 deixou cicatriz (B4, J5); fix de `is_pre_cutover_user` não está em prod; ~200 eventos do catálogo são vapor. Qualquer baseline "antes/depois" das mudanças grandes precisa primeiro de uma build publicada com a instrumentação corrente.
4. **Drift de schema ativo e processo de migração não-confiável.** Migration de 07/06 não aplicada com código dependente já em main (C6); placeholders de histórico remoto. Com 7 frentes paralelas, esse processo derruba alguém.
5. **Perfil em 3 gerações simultâneas** (G2): JSONB legacy + relacional + artefatos, com dual-writes e bullets bifurcados. "Perfil estruturado como centro do app" exige matar o legacy primeiro, senão cada feature nova escolhe uma fonte diferente (o match já lê as duas).
6. **Zero testes + zero CI + lint default** (A9, L1) sobre deus-classes de 2-2.8k linhas (L5). O custo não é hipotético: as frentes tocam exatamente os arquivos gigantes (swipe screen, resume).
7. **Operação concierge invisível no código.** Auto-apply via ntfy, vagas Polifinance por e-mail encaminhado, limpeza via SQL manual (N1). Tracker de candidaturas e portal de empresa vão expor essas costuras ao público externo.
8. **Android é greenfield com 14 integrações nativas pra portar** (A8) — não é "habilitar", é projeto novo competindo por atenção com as outras frentes.
9. **PII em canais fracos:** OPENAI_API_KEY no bundle (M1 — rotacionar JÁ), nome+e-mail de usuários via ntfy (M4), replay opt-out-only (M3). Portal de empresas multiplica a superfície LGPD (consents B2B existem só como tabela vazia).
10. **Dualidade de preferências** (`user_preferences` × `profile_job_preferences`, L4) sincronizada no client — feed em lista + perfil central vão tropeçar nisso na primeira semana (qual é a fonte de verdade dos filtros?).

## O2. O que refatorar ANTES de construir (máx. 5, critério: bloqueia ou contamina)

1. **Extrair o feed para o servidor** (RPC/endpoint com filtro+exclusão+orden+paginação) — bloqueia ranking, lista e escala; sem isso, todo trabalho de feed novo nasce no lugar errado.
2. **Unificar preferências e matar o dual-write de perfil** (eleger `profile_*` como única fonte; migrar `user_preferences`→`profile_job_preferences`; encerrar escrita no JSONB) — contamina perfil-central e match.
3. **Criar `applications` agora, mesmo que mínima** (tabela + escrita no clique de apply + backfill dos 493 applied) — tudo das frentes candidatura/tracker/portal/SLA pendura nela; cada semana sem ela gera mais dado pra migrar.
4. **Pipeline de release reprodutível:** CI com `flutter analyze` + testes + build, e migrations como gate (proibir mudança via dashboard sem arquivo). Bloqueia trabalhar em 7 frentes sem se atropelar.
5. **Publicar a build com instrumentação corrigida** (a72dedb+) antes de qualquer experimento — senão as frentes serão medidas com régua torta.

## O3. Android — estimativa honesta

Base: A8. **Mecânico (1-2 semanas de 1 dev):** `flutter create` da plataforma, ícones/splash, Manifest (schemes, permissões, FB meta-data), FCM/OneSignal, keystore + Play Console interno. **Incerto (mais 2-4 semanas, riscos reais):** (1) `Printing.convertHtml` no Android usa engine diferente — os 5 templates de PDF podem quebrar pixel a pixel (maior risco técnico); (2) Sign in with Apple via web flow (obrigatório se mantiver o botão); (3) session replay PostHog Android + máscaras; (4) teclado/gestos do CardSwiper e dos 40 widgets da trilha em devices Android variados; (5) QA real de ponta a ponta sem nenhum teste automatizado. **Total honesto: 3-6 semanas até beta fechado**, assumindo dedicação majoritária e sem paralelizar com outra frente grande.

## O4. Onde o schema briga com `applications`/`placements`

- **`swipe_actions` é o conflito central:** já carrega `applied`/`applied_at` (uma "candidatura" sem estados). Plano: nova tabela `applications (id, user_id, job_id, status, state_timestamps...)`, backfill dos 493 `applied=true` (com `applied_at` como `applied_em`), manter `swipe_actions` só como gesto. A aba Curtidas (`liked_jobs_screen`) lê `applied` do swipe — reescrever.
- **Nomenclatura `campaigns` colide** com qualquer conceito futuro de campanha (de vaga de empresa, de marketing). As 1.599 rows atuais são 99% marcador de onboarding — renomear/aposentar antes de o termo ganhar segundo significado.
- **`jobs` sem máquina de estados própria:** `is_active` boolean + `deadline`; um fluxo com SLA pedirá `status` enum (draft/active/paused/filled/expired) e `filled_by` → placements. `application_method/email/subject` já existentes ajudam o caminho e-mail.
- **Sem tabela de clicks/funil próprio** (H2): o tracker de candidaturas não tem histórico em banco pra backfillar além dos 493 applied — o passado vive só no PostHog/archive (recuperável de lá com trabalho).
- **`candidate_list_*`/`employer_clients` (B2B) já existem vazias** — bom: o portal de empresas tem esqueleto de schema; ruim: foi desenhado pra "listas exportadas", não pra portal self-service com vagas próprias (não há `employer_users`, nem vínculo employer→jobs).

## O5. Orgulho × vergonha (uma frase cada)

- **Orgulho:** o pipeline de adaptação de CV (v2 com validador anti-invenção, diff explicável, golden set de avaliação e telemetria de custo por geração) é trabalho de gente grande; e a disciplina do catálogo único de eventos + `withEdgeAnalytics` em 100% das functions é raro em time desse tamanho.
- **Não mostraria em entrevista:** `jobs.shuffle(Random())` como "algoritmo de feed", a chave da OpenAI passeando dentro do IPA, e um app com 79 mil linhas sustentado por 6 testes.

---

# APÊNDICES

## Apêndice 1 — pubspec.yaml completo

```yaml
name: career_gamification
description: "A new Flutter project."
# The following line prevents the package from being accidentally published to
# pub.dev using `flutter pub publish`. This is preferred for private packages.
publish_to: 'none' # Remove this line if you wish to publish to pub.dev

# The following defines the version and build number for your application.
# A version number is three numbers separated by dots, like 1.2.43
# followed by an optional build number separated by a +.
# Both the version and the builder number may be overridden in flutter
# build by specifying --build-name and --build-number, respectively.
# In Android, build-name is used as versionName while build-number used as versionCode.
# Read more about Android versioning at https://developer.android.com/studio/publish/versioning
# In iOS, build-name is used as CFBundleShortVersionString while build-number is used as CFBundleVersion.
# Read more about iOS versioning at
# https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html
# In Windows, build-name is used as the major, minor, and patch parts
# of the product and file versions while build-number is used as the build suffix.
version: 2.2.0+4

environment:
  sdk: ^3.10.0

# Dependencies specify other packages that your package needs in order to work.
# To automatically upgrade your package dependencies to the latest versions
# consider running `flutter pub upgrade --major-versions`. Alternatively,
# dependencies can be manually updated by changing the version numbers below to
# the latest version available on pub.dev. To see which dependencies have newer
# versions available, run `flutter pub outdated`.
dependencies:
  flutter:
    sdk: flutter

  # The following adds the Cupertino Icons font to your application.
  # Use with the CupertinoIcons class for iOS style icons.
  cupertino_icons: ^1.0.8
  sqflite: ^2.4.2
  path: ^1.9.1
  provider: ^6.1.5+1
  flutter_svg: ^2.2.3
  shared_preferences: ^2.5.3
  path_provider: ^2.1.5
  supabase_flutter: ^2.0.0
  flutter_dotenv: ^5.1.0
  pdf: ^3.11.1
  printing: ^5.13.4
  share_plus: ^12.0.1
  tutorial_coach_mark: ^1.3.3
  url_launcher: ^6.3.2
  flutter_html: ^3.0.0-beta.2
  intl: ^0.20.2
  flutter_localizations:
    sdk: flutter
  flutter_card_swiper: ^7.2.0
  file_picker: ^10.3.10
  syncfusion_flutter_pdf: ^33.1.46
  sign_in_with_apple: ^6.1.1
  crypto: ^3.0.3
  cached_network_image: ^3.4.1
  posthog_flutter: ^4.10.1
  package_info_plus: ^8.0.0
  onesignal_flutter: ^5.2.9
  facebook_app_events: ^0.20.0
  app_tracking_transparency: ^2.0.6+1
  geolocator: ^14.0.0
  geocoding: ^4.0.0
  http: ^1.2.0
  # T3.1 — deep-link / atribuição de canal. Captura o initial link + params UTM
  # pra derivar acquisition_source (puc/meta/organic/referral). REQUER config
  # nativa iOS (URL scheme / Universal Links + AASA) pra capturar links reais;
  # sem ela, getInitialLink retorna null e installs são marcadas 'organic'
  # (comportamento seguro). O código abaixo nunca quebra o boot (try/catch).
  app_links: ^6.3.0
  # Parseia o `d` do SVG do logo (símbolo "S" do brandbook) em dart:ui Path,
  # pra animar o glifo exato na splash. Pure-Dart, ~dezenas de KB.
  path_drawing: ^1.0.1

dev_dependencies:
  flutter_test:
    sdk: flutter

  # The "flutter_lints" package below contains a set of recommended lints to
  # encourage good coding practices. The lint set provided by the package is
  # activated in the `analysis_options.yaml` file located at the root of your
  # package. See that file for information about deactivating specific lint
  # rules and activating additional ones.

  flutter_lints: ^6.0.0
  flutter_launcher_icons: ^0.13.1
  flutter_native_splash: ^2.3.1

flutter_icons:
  ios: true
  image_path: "assets/images/image copy.png"
  web:
    generate: true
    image_path: "assets/images/image copy.png"
    background_color: "#hex_code"
    theme_color: "#hex_code"
  windows:
    generate: true
    image_path: "assets/images/image copy.png"
    icon_size: 48 # min:48, max:256, default: 48
  macos:
    generate: true
    image_path: "assets/images/image copy.png"

flutter_native_splash:
  # Cor = meio do gradient da marca (AppColors.brand #1E88B8). O 1º frame
  # Flutter (centro do gradient cyan→blue) bate com essa cor → handoff sem
  # o salto branco→azul. NÃO setar `image:` aqui: a splash Flutter constrói
  # o "S" do zero ("A Conexão") e o logo nativo estragaria o reveal.
  color: "#1E88B8"
  android_12:
    color: "#1E88B8"
# For information on the generic Dart part of this file, see the
# following page: https://dart.dev/tools/pub/pubspec

# The following section is specific to Flutter packages.
flutter:

  # The following line ensures that the Material Icons font is
  # included with your application, so that you can use the icons in
  # the material Icons class.
  uses-material-design: true

  # To add assets to your application, add an assets section, like this:
  assets:
    - assets/icons/
    - assets/images/
    - assets/images/flags/
    - assets/images/templates/
    - .env

  # An image asset can refer to one or more resolution-specific "variants", see
  # https://flutter.dev/to/resolution-aware-images

  # For details regarding adding assets from package dependencies, see
  # https://flutter.dev/to/asset-from-package

  # Fontes Outfit (headings) e Inter (body) bundleadas como arquivos
  # estáticos por peso. Os .ttf foram gerados a partir das variable fonts
  # via fontTools (scripts/generate_static_fonts.py) — 9 pesos × 2 famílias.
  #
  # Por que estáticos em vez de variable font? O Flutter NÃO acessa o axis
  # `wght` da variable font automaticamente a partir de `fontWeight:` em
  # `TextStyle`. Resultado prático: tudo renderiza no peso default
  # (~Regular), ignorando bold/semibold do código. Arquivos estáticos
  # eliminam o problema sem precisar de helper/fontVariations no código.
  #
  # Bundle size: ~5MB total (Inter ~4.5MB com cobertura latin extended,
  # Outfit ~500KB). Trade-off aceitável vs offline-first sem regressão
  # visual.
  fonts:
    - family: Outfit
      fonts:
        - asset: assets/fonts/Outfit-Thin.ttf
          weight: 100
        - asset: assets/fonts/Outfit-ExtraLight.ttf
          weight: 200
        - asset: assets/fonts/Outfit-Light.ttf
          weight: 300
        - asset: assets/fonts/Outfit-Regular.ttf
          weight: 400
        - asset: assets/fonts/Outfit-Medium.ttf
          weight: 500
        - asset: assets/fonts/Outfit-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Outfit-Bold.ttf
          weight: 700
        - asset: assets/fonts/Outfit-ExtraBold.ttf
          weight: 800
        - asset: assets/fonts/Outfit-Black.ttf
          weight: 900
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter-Thin.ttf
          weight: 100
        - asset: assets/fonts/Inter-ExtraLight.ttf
          weight: 200
        - asset: assets/fonts/Inter-Light.ttf
          weight: 300
        - asset: assets/fonts/Inter-Regular.ttf
          weight: 400
        - asset: assets/fonts/Inter-Medium.ttf
          weight: 500
        - asset: assets/fonts/Inter-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Inter-Bold.ttf
          weight: 700
        - asset: assets/fonts/Inter-ExtraBold.ttf
          weight: 800
        - asset: assets/fonts/Inter-Black.ttf
          weight: 900

  # Bloco original mantido como referência:
  # fonts:
  #   - family: Schyler
  #     fonts:
  #       - asset: fonts/Schyler-Regular.ttf
  #       - asset: fonts/Schyler-Italic.ttf
  #         style: italic
  #
  # For details regarding fonts from package dependencies,
  # see https://flutter.dev/to/font-from-package
```

## Apêndice 2 — Schema do banco (DDL via concatenação das migrations estruturais)

Critério: migrations que CRIAM/ALTERAM estrutura relevante (CREATE TABLE/POLICY/FUNCTION). Migrations puramente operacionais (cleanup de dados, seeds, ajustes de cron) foram omitidas — lista completa em `supabase/migrations/` (77 arquivos). Estado aplicado em produção: até `20260601213000` (ver C6; `20260607000000` NÃO aplicada).

### `supabase/migrations/00000000000000_baseline.sql`

```sql
-- Migration: baseline (tabelas legacy criadas antes do versionamento)
--
-- HISTÓRICO: as 9 tabelas abaixo foram criadas manualmente no UI do Supabase
-- antes do versionamento via migrations começar. Isso causa falha ao criar
-- Database Branches (branch nasce vazio; migrations posteriores que dependem
-- dessas tabelas falham).
--
-- Esta migration é IDEMPOTENTE — usa CREATE TABLE IF NOT EXISTS, DROP POLICY
-- IF EXISTS, DO blocks com EXCEPTION. Em prod, é no-op (tudo já existe).
-- Em branch novo, popula com schema idêntico a prod (snapshot 2026-05-21).
--
-- Tabelas legacy cobertas:
--   tracks, phases, questions, user_profiles, user_progress,
--   user_answers, saved_resumes, ai_generation_logs, security_audit_log

BEGIN;

-- ═══ 1. CREATE TABLE ═══

CREATE TABLE IF NOT EXISTS "public"."ai_generation_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "generation_type" "text" NOT NULL,
    "tokens_used" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "ai_generation_logs_generation_type_check" CHECK (("generation_type" = ANY (ARRAY['profile'::"text", 'resume'::"text", 'interview'::"text", 'bullets'::"text", 'resume_evaluation'::"text", 'resume_refine'::"text", 'match_analysis'::"text", 'resume_adaptation'::"text", 'skill_extraction'::"text", 'profile_extraction'::"text"])))
);

CREATE TABLE IF NOT EXISTS "public"."phases" (
    "id" "text" NOT NULL,
    "track_id" "text" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text" NOT NULL,
    "order_index" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);

CREATE TABLE IF NOT EXISTS "public"."questions" (
    "id" "text" NOT NULL,
    "phase_id" "text" NOT NULL,
    "type" integer NOT NULL,
    "content" "text" NOT NULL,
    "options" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);

CREATE TABLE IF NOT EXISTS "public"."saved_resumes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "title" "text" NOT NULL,
    "file_path" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "source" "text" DEFAULT 'manual'::"text" NOT NULL,
    CONSTRAINT "saved_resumes_source_check" CHECK (("source" = ANY (ARRAY['manual'::"text", 'imported'::"text", 'adapted'::"text"])))
);

CREATE TABLE IF NOT EXISTS "public"."security_audit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "event_type" "text" NOT NULL,
    "ip_address" "text",
    "user_agent" "text",
    "metadata" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);

CREATE TABLE IF NOT EXISTS "public"."tracks" (
    "id" "text" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text" NOT NULL,
    "color" bigint NOT NULL,
    "icon_asset" "text" NOT NULL,
    "order_index" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);

CREATE TABLE IF NOT EXISTS "public"."user_answers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "question_id" "text" NOT NULL,
    "answer" "text" NOT NULL,
    "answered_at" timestamp with time zone DEFAULT "now"()
);

CREATE TABLE IF NOT EXISTS "public"."user_profiles" (
    "id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "email" "text" NOT NULL,
    "course" "text",
    "semester" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "gamification_data" "jsonb" DEFAULT '{}'::"jsonb",
    "age" integer,
    "ai_consent" boolean DEFAULT false,
    "ai_consent_timestamp" timestamp with time zone,
    "phone" "text"
);

CREATE TABLE IF NOT EXISTS "public"."user_progress" (
    "user_id" "uuid" NOT NULL,
    "phase_id" "text" NOT NULL,
    "completed" boolean DEFAULT false,
    "completed_at" timestamp with time zone
);

-- ═══ 2. ALTER TABLE (constraints, FKs) ═══

DO $$
BEGIN
  ALTER TABLE "public"."ai_generation_logs" OWNER TO "postgres";
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE "public"."phases" OWNER TO "postgres";
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE "public"."questions" OWNER TO "postgres";
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE "public"."saved_resumes" OWNER TO "postgres";
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE "public"."security_audit_log" OWNER TO "postgres";
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE "public"."tracks" OWNER TO "postgres";
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE "public"."user_answers" OWNER TO "postgres";
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE "public"."user_profiles" OWNER TO "postgres";
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE "public"."user_progress" OWNER TO "postgres";
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."ai_generation_logs"
      ADD CONSTRAINT "ai_generation_logs_pkey" PRIMARY KEY ("id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."phases"
      ADD CONSTRAINT "phases_pkey" PRIMARY KEY ("id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."questions"
      ADD CONSTRAINT "questions_pkey" PRIMARY KEY ("id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."saved_resumes"
      ADD CONSTRAINT "saved_resumes_pkey" PRIMARY KEY ("id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."security_audit_log"
      ADD CONSTRAINT "security_audit_log_pkey" PRIMARY KEY ("id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."tracks"
      ADD CONSTRAINT "tracks_pkey" PRIMARY KEY ("id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."user_answers"
      ADD CONSTRAINT "user_answers_pkey" PRIMARY KEY ("id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."user_answers"
      ADD CONSTRAINT "user_answers_user_question_uniq" UNIQUE ("user_id", "question_id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."user_profiles"
      ADD CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."user_progress"
      ADD CONSTRAINT "user_progress_pkey" PRIMARY KEY ("user_id", "phase_id");
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."ai_generation_logs"
      ADD CONSTRAINT "ai_generation_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."phases"
      ADD CONSTRAINT "phases_track_id_fkey" FOREIGN KEY ("track_id") REFERENCES "public"."tracks"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."questions"
      ADD CONSTRAINT "questions_phase_id_fkey" FOREIGN KEY ("phase_id") REFERENCES "public"."phases"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."saved_resumes"
      ADD CONSTRAINT "saved_resumes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."security_audit_log"
      ADD CONSTRAINT "security_audit_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE SET NULL;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."user_answers"
      ADD CONSTRAINT "user_answers_question_id_fkey" FOREIGN KEY ("question_id") REFERENCES "public"."questions"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."user_answers"
      ADD CONSTRAINT "user_answers_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."user_profiles"
      ADD CONSTRAINT "user_profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."user_progress"
      ADD CONSTRAINT "user_progress_phase_id_fkey" FOREIGN KEY ("phase_id") REFERENCES "public"."phases"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  ALTER TABLE ONLY "public"."user_progress"
      ADD CONSTRAINT "user_progress_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

-- ═══ 3. ENABLE ROW LEVEL SECURITY ═══

ALTER TABLE "public"."ai_generation_logs" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."phases" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."questions" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."saved_resumes" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."security_audit_log" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."tracks" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."user_answers" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."user_profiles" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."user_progress" ENABLE ROW LEVEL SECURITY;

-- ═══ 4. CREATE INDEX ═══

CREATE INDEX IF NOT EXISTS "idx_ai_logs_user_type_date" ON "public"."ai_generation_logs" USING "btree" ("user_id", "generation_type", "created_at");

CREATE INDEX IF NOT EXISTS "idx_answers_question" ON "public"."user_answers" USING "btree" ("question_id");

CREATE INDEX IF NOT EXISTS "idx_answers_user" ON "public"."user_answers" USING "btree" ("user_id");

CREATE INDEX IF NOT EXISTS "idx_audit_event_date" ON "public"."security_audit_log" USING "btree" ("event_type", "created_at");

CREATE INDEX IF NOT EXISTS "idx_audit_user_date" ON "public"."security_audit_log" USING "btree" ("user_id", "created_at");

CREATE INDEX IF NOT EXISTS "idx_phases_track" ON "public"."phases" USING "btree" ("track_id");

CREATE INDEX IF NOT EXISTS "idx_progress_user" ON "public"."user_progress" USING "btree" ("user_id");

CREATE INDEX IF NOT EXISTS "idx_questions_phase" ON "public"."questions" USING "btree" ("phase_id");

-- ═══ 5. CREATE POLICY (DROP IF EXISTS + CREATE) ═══

DROP POLICY IF EXISTS "Allow authenticated users to insert questions" ON "public"."questions";
CREATE POLICY "Allow authenticated users to insert questions" ON "public"."questions" FOR INSERT TO "authenticated" WITH CHECK (true);

DROP POLICY IF EXISTS "Allow authenticated users to update questions" ON "public"."questions";
CREATE POLICY "Allow authenticated users to update questions" ON "public"."questions" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Anyone can view phases" ON "public"."phases";
CREATE POLICY "Anyone can view phases" ON "public"."phases" FOR SELECT USING (true);

DROP POLICY IF EXISTS "Anyone can view questions" ON "public"."questions";
CREATE POLICY "Anyone can view questions" ON "public"."questions" FOR SELECT USING (true);

DROP POLICY IF EXISTS "Anyone can view tracks" ON "public"."tracks";
CREATE POLICY "Anyone can view tracks" ON "public"."tracks" FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public can view phases" ON "public"."phases";
CREATE POLICY "Public can view phases" ON "public"."phases" FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public can view questions" ON "public"."questions";
CREATE POLICY "Public can view questions" ON "public"."questions" FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public can view tracks" ON "public"."tracks";
CREATE POLICY "Public can view tracks" ON "public"."tracks" FOR SELECT USING (true);

DROP POLICY IF EXISTS "Service can insert generation logs" ON "public"."ai_generation_logs";
CREATE POLICY "Service can insert generation logs" ON "public"."ai_generation_logs" FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Service role can view audit logs" ON "public"."security_audit_log";
CREATE POLICY "Service role can view audit logs" ON "public"."security_audit_log" FOR SELECT USING (false);

DROP POLICY IF EXISTS "Users can delete own answers" ON "public"."user_answers";
CREATE POLICY "Users can delete own answers" ON "public"."user_answers" FOR DELETE USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can delete own profile" ON "public"."user_profiles";
CREATE POLICY "Users can delete own profile" ON "public"."user_profiles" FOR DELETE USING (("auth"."uid"() = "id"));

DROP POLICY IF EXISTS "Users can delete own progress" ON "public"."user_progress";
CREATE POLICY "Users can delete own progress" ON "public"."user_progress" FOR DELETE USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can delete their own resumes" ON "public"."saved_resumes";
CREATE POLICY "Users can delete their own resumes" ON "public"."saved_resumes" FOR DELETE TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

DROP POLICY IF EXISTS "Users can insert own answers" ON "public"."user_answers";
CREATE POLICY "Users can insert own answers" ON "public"."user_answers" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can insert own profile" ON "public"."user_profiles";
CREATE POLICY "Users can insert own profile" ON "public"."user_profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));

DROP POLICY IF EXISTS "Users can insert own progress" ON "public"."user_progress";
CREATE POLICY "Users can insert own progress" ON "public"."user_progress" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can insert their own resumes" ON "public"."saved_resumes";
CREATE POLICY "Users can insert their own resumes" ON "public"."saved_resumes" FOR INSERT TO "authenticated" WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

DROP POLICY IF EXISTS "Users can update own answers" ON "public"."user_answers";
CREATE POLICY "Users can update own answers" ON "public"."user_answers" FOR UPDATE USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can update own profile" ON "public"."user_profiles";
CREATE POLICY "Users can update own profile" ON "public"."user_profiles" FOR UPDATE USING (("auth"."uid"() = "id"));

DROP POLICY IF EXISTS "Users can update own progress" ON "public"."user_progress";
CREATE POLICY "Users can update own progress" ON "public"."user_progress" FOR UPDATE USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can view own answers" ON "public"."user_answers";
CREATE POLICY "Users can view own answers" ON "public"."user_answers" FOR SELECT USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can view own generation logs" ON "public"."ai_generation_logs";
CREATE POLICY "Users can view own generation logs" ON "public"."ai_generation_logs" FOR SELECT USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can view own profile" ON "public"."user_profiles";
CREATE POLICY "Users can view own profile" ON "public"."user_profiles" FOR SELECT USING (("auth"."uid"() = "id"));

DROP POLICY IF EXISTS "Users can view own progress" ON "public"."user_progress";
CREATE POLICY "Users can view own progress" ON "public"."user_progress" FOR SELECT USING (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users can view their own resumes" ON "public"."saved_resumes";
CREATE POLICY "Users can view their own resumes" ON "public"."saved_resumes" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

-- ═══ 6. TRIGGERS ═══

DO $$
BEGIN
  CREATE OR REPLACE TRIGGER "notify_new_signup" AFTER INSERT ON "public"."user_profiles" FOR EACH ROW EXECUTE FUNCTION "supabase_functions"."http_request"('https://gaxfmniffjvwrwyunorl.supabase.co/functions/v1/notify-signup', 'POST', '{"Content-type":"application/json"}', '{}', '5000');
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

DO $$
BEGIN
  CREATE OR REPLACE TRIGGER "update_user_profiles_updated_at" BEFORE UPDATE ON "public"."user_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN duplicate_table THEN NULL;
  WHEN unique_violation THEN NULL;
  WHEN undefined_function THEN NULL;
  WHEN undefined_table THEN NULL;
  WHEN undefined_object THEN NULL;
  WHEN invalid_schema_name THEN NULL;
  WHEN OTHERS THEN
    -- Captura erros não-fatais (ex: schema 'supabase_functions' não existe
    -- em ambiente sem Webhooks). Log silencioso pra não derrubar a migration.
    RAISE WARNING '[baseline] skipping due to: % (%)', SQLERRM, SQLSTATE;
END $$;

-- ═══ 7. GRANTS ═══

GRANT ALL ON TABLE "public"."ai_generation_logs" TO "anon";
GRANT ALL ON TABLE "public"."ai_generation_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_generation_logs" TO "service_role";

GRANT ALL ON TABLE "public"."phases" TO "anon";
GRANT ALL ON TABLE "public"."phases" TO "authenticated";
GRANT ALL ON TABLE "public"."phases" TO "service_role";

GRANT ALL ON TABLE "public"."questions" TO "anon";
GRANT ALL ON TABLE "public"."questions" TO "authenticated";
GRANT ALL ON TABLE "public"."questions" TO "service_role";

GRANT ALL ON TABLE "public"."saved_resumes" TO "anon";
GRANT ALL ON TABLE "public"."saved_resumes" TO "authenticated";
GRANT ALL ON TABLE "public"."saved_resumes" TO "service_role";

GRANT ALL ON TABLE "public"."security_audit_log" TO "anon";
GRANT ALL ON TABLE "public"."security_audit_log" TO "authenticated";
GRANT ALL ON TABLE "public"."security_audit_log" TO "service_role";

GRANT ALL ON TABLE "public"."tracks" TO "anon";
GRANT ALL ON TABLE "public"."tracks" TO "authenticated";
GRANT ALL ON TABLE "public"."tracks" TO "service_role";

GRANT ALL ON TABLE "public"."user_answers" TO "anon";
GRANT ALL ON TABLE "public"."user_answers" TO "authenticated";
GRANT ALL ON TABLE "public"."user_answers" TO "service_role";

GRANT ALL ON TABLE "public"."user_profiles" TO "anon";
GRANT ALL ON TABLE "public"."user_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_profiles" TO "service_role";

GRANT ALL ON TABLE "public"."user_progress" TO "anon";
GRANT ALL ON TABLE "public"."user_progress" TO "authenticated";
GRANT ALL ON TABLE "public"."user_progress" TO "service_role";


COMMIT;
```

### `supabase/migrations/20260401180000_init_jobs.sql`

```sql
-- 1. Create tables
CREATE TABLE public.companies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  logo_url TEXT,
  description TEXT,
  website TEXT,
  industry TEXT,
  size TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID REFERENCES public.companies(id) NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  requirements TEXT[],
  benefits TEXT[],
  location_city TEXT,
  location_state TEXT,
  salary_min INTEGER,
  salary_max INTEGER,
  work_model TEXT NOT NULL CHECK (work_model IN ('presencial', 'hibrido', 'remoto')),
  job_type TEXT NOT NULL CHECK (job_type IN ('estagio', 'trainee', 'clt_junior', 'temporario')),
  area TEXT NOT NULL,
  is_active BOOLEAN DEFAULT true,
  published_at TIMESTAMPTZ DEFAULT now(),
  deadline TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.swipe_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  job_id UUID REFERENCES public.jobs(id) NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('liked', 'rejected')),
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (user_id, job_id)
);

CREATE TABLE public.user_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  areas TEXT[],
  locations TEXT[],
  work_models TEXT[],
  job_types TEXT[],
  min_salary INTEGER,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Setup RLS Policies
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.swipe_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;

-- Companies: readable by authenticated users
CREATE POLICY "Companies are viewable by authenticated users."
ON public.companies FOR SELECT
TO authenticated
USING (true);

-- Jobs: readable by authenticated users
CREATE POLICY "Jobs are viewable by authenticated users."
ON public.jobs FOR SELECT
TO authenticated
USING (true);

-- Swipe Actions: Users can manage their own swips
CREATE POLICY "Users can insert their own swipe actions."
ON public.swipe_actions FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own swipe actions."
ON public.swipe_actions FOR UPDATE
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can view their own swipe actions."
ON public.swipe_actions FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own swipe actions."
ON public.swipe_actions FOR DELETE
TO authenticated
USING (auth.uid() = user_id);

-- User Preferences: Users can manage their own preferences
CREATE POLICY "Users can insert their own preferences."
ON public.user_preferences FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view their own preferences."
ON public.user_preferences FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own preferences."
ON public.user_preferences FOR UPDATE
TO authenticated
USING (auth.uid() = user_id);

-- 3. Seed Data
-- We capture the generated IDs of the companies to reference them in the jobs table
DO $$
DECLARE
  company_1_id UUID := gen_random_uuid();
  company_2_id UUID := gen_random_uuid();
  company_3_id UUID := gen_random_uuid();
  company_4_id UUID := gen_random_uuid();
  company_5_id UUID := gen_random_uuid();
BEGIN
  INSERT INTO public.companies (id, name, logo_url, description) VALUES
  (company_1_id, 'Nubank', 'https://logo.clearbit.com/nubank.com.br', 'O Nubank nasceu para devolver às pessoas o controle sobre sua vida financeira. Somos uma das maiores plataformas digitais de serviços financeiros do mundo.'),
  (company_2_id, 'Ambev', 'https://logo.clearbit.com/ambev.com.br', 'Nós sonhamos em unir as pessoas por um mundo melhor. Para a Ambev, o consumidor é nosso patrão e servimos a ele todos os dias.'),
  (company_3_id, 'iFood', 'https://logo.clearbit.com/ifood.com.br', 'O iFood é uma empresa brasileira de tecnologia, sendo a maior foodtech da América Latina, atuando fortemente em delivery.'),
  (company_4_id, 'Itaú Unibanco', 'https://logo.clearbit.com/itau.com.br', 'Nós somos o Itaú Unibanco. Feito de futuro. O maior banco privado do Brasil e da América Latina focando na melhor experiência do cliente.'),
  (company_5_id, 'Mercado Livre', 'https://logo.clearbit.com/mercadolivre.com.br', 'O Mercado Livre é o maior site de comércio da América Latina e estamos transformando o digital commerce na região.');

  INSERT INTO public.jobs (company_id, title, description, requirements, benefits, location_city, location_state, salary_min, salary_max, work_model, job_type, area, published_at, deadline) VALUES
  (
    company_1_id, 
    'Estágio em Marketing Digital', 
    'Buscamos estagiário(a) para atuar na equipe de Growth Marketing, apoiando campanhas de aquisição e retenção. Você terá a oportunidade de trabalhar lado a lado com especialistas em marketing focado em dados e alta performance, impactando milhões de clientes.',
    ARRAY['Cursando Marketing, Publicidade, Administração ou áreas correlatas', 'A partir do 4º semestre', 'Conhecimento em Google Analytics e Meta Ads', 'Perfil analítico e criativo'],
    ARRAY['VT', 'VR (R$ 35/dia)', 'Gympass', 'Seguro de vida', 'Auxílio home office'],
    'São Paulo', 'SP', 220000, 220000, 'hibrido', 'estagio', 'Marketing', now() - interval '2 days', null
  ),
  (
    company_2_id, 
    'Programa Trainee 2026', 
    'O Programa Trainee Ambev é uma oportunidade para recém-formados que querem liderar a transformação de uma das maiores empresas do Brasil. Se você é apaixonado por grandes desafios e busca desenvolvimento acelerado, este é o seu lugar.',
    ARRAY['Formação entre dez/2024 e dez/2026 em qualquer curso', 'Disponibilidade para mudança de estado', 'Inglês intermediário'],
    ARRAY['PLR', 'Plano de saúde', 'Previdência privada', 'Carro corporativo após efetivação', 'Auxílio farmácia'],
    'São Paulo', 'SP', 850000, 850000, 'presencial', 'trainee', 'Geral', now() - interval '5 days', now() + interval '14 days'
  ),
  (
    company_3_id, 
    'Estágio em Engenharia de Dados', 
    'Faça parte do time de Data Engineering do iFood e ajude a processar milhões de eventos por dia. O estagiário atuará com as tecnologias mais recentes do mercado ajudando a construir pipelines robustos.',
    ARRAY['Cursando Ciência da Computação, Engenharia ou áreas correlatas', 'Noções de Python e SQL básicos', 'Interesse em big data e cloud', 'Disponibilidade para estagiar 6 horas/dia'],
    ARRAY['VR/VA (R$ 40/dia)', 'Gympass', 'Auxílio home office mensal', 'Day off no mês de aniversário', 'Aulas de idiomas'],
    'Nacional', 'BR', 280000, 280000, 'remoto', 'estagio', 'Tecnologia', now(), null
  ),
  (
    company_4_id, 
    'Estágio em Finanças Corporativas', 
    'Atue no time de FP&A do maior banco da América Latina, apoiando análises financeiras e projeções. O estágio proporciona uma visão estratégica de negócios e contato com alta liderança.',
    ARRAY['Cursando Administração, Economia, Engenharia ou Contabilidade', 'Excel avançado e conhecimento básico em VBA/PowerBI é um diferencial', 'A partir do 5º semestre'],
    ARRAY['VT', 'VR + VA', 'Plano de Saúde e Odontológico', 'Totalpass', 'Bolsa auxílio para idiomas'],
    'São Paulo', 'SP', 240000, 240000, 'hibrido', 'estagio', 'Finanças', now() - interval '3 days', null
  ),
  (
    company_5_id, 
    'Estágio em UX/UI Design', 
    'Venha criar experiências para mais de 100 milhões de usuários na América Latina. O estagiário atuará no time de Design de Produto, colaborando com Product Managers e Engenheiros em squads ágeis.',
    ARRAY['Cursando Design, Comunicação Visual ou áreas correlatas', 'Portfolio online no Behance, Dribbble ou Figma (obrigatório apresentar link)', 'Conhecimento básico em Design System', 'Facilidade de comunicação e trabalho em equipe'],
    ARRAY['VT e Van intermunicipal fretada', 'VR (R$ 42/dia)', 'Gympass', 'Desconto em compras no MELI e frete grátis ME', 'Aulas de idiomas online'],
    'São Paulo', 'SP', 260000, 260000, 'hibrido', 'estagio', 'Design', now() - interval '7 days', null
  );
END $$;
```

### `supabase/migrations/20260430000000_campaigns_target_jobs.sql`

```sql
-- Fase 1: Vaga-alvo e Campanhas
-- Cria as tabelas target_jobs e campaigns, com RLS e migração de usuários existentes.

-- Step 1: target_jobs
CREATE TABLE IF NOT EXISTS target_jobs (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID        NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  title                TEXT,
  description_text     TEXT,
  source_url           TEXT,
  parsed_requirements  JSONB,
  is_skipped           BOOLEAN     NOT NULL DEFAULT false,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE target_jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own target_jobs"
  ON target_jobs FOR ALL
  USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_target_jobs_user_id ON target_jobs(user_id);

-- Step 2: campaigns
CREATE TABLE IF NOT EXISTS campaigns (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID        NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  target_job_id  UUID        REFERENCES target_jobs(id) ON DELETE SET NULL,
  name           TEXT        NOT NULL DEFAULT 'Campanha 1',
  status         TEXT        NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'completed')),
  template_id    TEXT        NOT NULL DEFAULT 'harvard_ats',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_edited_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE campaigns ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own campaigns"
  ON campaigns FOR ALL
  USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_campaigns_user_id      ON campaigns(user_id);
CREATE INDEX IF NOT EXISTS idx_campaigns_target_job_id ON campaigns(target_job_id);

-- Step 3: Migrar usuários existentes sem campanha
-- Cria um target_job com is_skipped=true + uma campaign apontando para ele.
WITH new_jobs AS (
  INSERT INTO target_jobs (user_id, is_skipped)
  SELECT up.id, true
  FROM user_profiles up
  WHERE NOT EXISTS (
    SELECT 1 FROM campaigns c WHERE c.user_id = up.id
  )
  RETURNING id, user_id
)
INSERT INTO campaigns (user_id, target_job_id, name, status)
SELECT nj.user_id, nj.id, 'Campanha 1', 'draft'
FROM new_jobs nj;
```

### `supabase/migrations/20260430000002_incremental_bullets.sql`

```sql
-- ============================================
-- INCREMENTAL BULLET GENERATION - MIGRATION
-- ============================================
-- Run this in your Supabase SQL Editor
-- This adds the 3-layer data model for incremental CV generation:
--   Layer 1: user_experiences + experience_raw_responses (source of truth)
--   Layer 2: bullet_versions + approved_bullets (AI-generated, user-chosen)
--   Layer 3: section_versions (free-text sections like summary)
-- ============================================

-- ============================================
-- LAYER 1: EXPERIENCES & RAW RESPONSES
-- ============================================

-- User experiences (groups raw responses + bullets per experience)
CREATE TABLE IF NOT EXISTS user_experiences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    experience_type TEXT NOT NULL, -- 'corporate', 'startup', 'freelance', 'social', 'academic', 'leadership', 'extracurricular'
    title TEXT, -- cargo or title
    organization TEXT, -- company, league, etc
    period TEXT,
    section TEXT NOT NULL DEFAULT 'experiencias', -- 'experiencias', 'projetos', 'formacao', 'lideranca'
    source_phase_id TEXT, -- phase that originated this (t3_p1, t2_p3, etc)
    source_question_id TEXT, -- specific question ID (M3_1_1_Q2_0, etc)
    display_order INT DEFAULT 0,
    is_included BOOLEAN DEFAULT true, -- user can exclude from CV without deleting
    raw_form_data JSONB, -- the full experienceForm JSON as submitted by user
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Raw responses (exact Q&A pairs for each experience — source of truth)
CREATE TABLE IF NOT EXISTS experience_raw_responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    experience_id UUID NOT NULL REFERENCES user_experiences(id) ON DELETE CASCADE,
    question TEXT NOT NULL,
    answer TEXT NOT NULL,
    question_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- LAYER 2: BULLET VERSIONS & APPROVED BULLETS
-- ============================================

-- All bullet versions generated by AI (keep ALL, not just chosen)
CREATE TABLE IF NOT EXISTS bullet_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    experience_id UUID NOT NULL REFERENCES user_experiences(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    angle TEXT NOT NULL CHECK (angle IN ('resultado', 'processo', 'habilidade')),
    version_number INT DEFAULT 1,
    model_used TEXT DEFAULT 'gpt-4o',
    prompt_version TEXT DEFAULT 'v1', -- track which prompt generated this
    tokens_used INT DEFAULT 0,
    confidence REAL DEFAULT 0.8, -- AI self-reported confidence (0.0 to 1.0)
    was_chosen BOOLEAN DEFAULT false,
    was_edited BOOLEAN DEFAULT false,
    edited_content TEXT, -- final content if user edited it
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Bullets approved by the user (what goes into the CV)
CREATE TABLE IF NOT EXISTS approved_bullets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    experience_id UUID NOT NULL REFERENCES user_experiences(id) ON DELETE CASCADE,
    bullet_version_id UUID REFERENCES bullet_versions(id), -- null if user wrote from scratch
    final_text TEXT NOT NULL,
    display_order INT DEFAULT 0,
    source TEXT NOT NULL DEFAULT 'ai_chosen' CHECK (source IN ('ai_chosen', 'ai_edited', 'user_written', 'ai_mixed')),
    approved_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- LAYER 3: FREE-TEXT SECTION VERSIONS
-- ============================================

-- Versions for free-text sections (resumo_profissional, habilidades, interesses)
CREATE TABLE IF NOT EXISTS section_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    section_type TEXT NOT NULL, -- 'resumo_profissional', 'habilidades', 'interesses'
    content TEXT NOT NULL,
    angle TEXT, -- nullable for sections without angle
    version_number INT DEFAULT 1,
    model_used TEXT DEFAULT 'gpt-4o',
    was_chosen BOOLEAN DEFAULT false,
    was_edited BOOLEAN DEFAULT false,
    edited_content TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- AI GENERATION LOG (enhanced)
-- ============================================

-- Add bullet-specific generation tracking
-- (existing ai_generation_logs table is kept for backward compat)
CREATE TABLE IF NOT EXISTS bullet_generation_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    experience_id UUID NOT NULL REFERENCES user_experiences(id) ON DELETE CASCADE,
    generation_type TEXT NOT NULL DEFAULT 'bullets', -- 'bullets', 'deepening', 'regeneration'
    model_used TEXT DEFAULT 'gpt-4o',
    prompt_version TEXT DEFAULT 'v1',
    input_tokens INT DEFAULT 0,
    output_tokens INT DEFAULT 0,
    total_tokens INT DEFAULT 0,
    latency_ms INT, -- response time in milliseconds
    had_clarification BOOLEAN DEFAULT false, -- did the AI request needs_clarification?
    clarification_question TEXT, -- what it asked
    clarification_answered BOOLEAN DEFAULT false, -- did the user respond?
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- INDEXES
-- ============================================

CREATE INDEX IF NOT EXISTS idx_experiences_user ON user_experiences(user_id);
CREATE INDEX IF NOT EXISTS idx_experiences_phase ON user_experiences(source_phase_id);
CREATE INDEX IF NOT EXISTS idx_raw_responses_exp ON experience_raw_responses(experience_id);
CREATE INDEX IF NOT EXISTS idx_bullet_versions_exp ON bullet_versions(experience_id);
CREATE INDEX IF NOT EXISTS idx_bullet_versions_chosen ON bullet_versions(experience_id) WHERE was_chosen = true;
CREATE INDEX IF NOT EXISTS idx_approved_user ON approved_bullets(user_id);
CREATE INDEX IF NOT EXISTS idx_approved_exp ON approved_bullets(experience_id);
CREATE INDEX IF NOT EXISTS idx_sections_user ON section_versions(user_id);
CREATE INDEX IF NOT EXISTS idx_bullet_logs_user ON bullet_generation_logs(user_id);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

ALTER TABLE user_experiences ENABLE ROW LEVEL SECURITY;
ALTER TABLE experience_raw_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE bullet_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE approved_bullets ENABLE ROW LEVEL SECURITY;
ALTER TABLE section_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE bullet_generation_logs ENABLE ROW LEVEL SECURITY;

-- user_experiences: users manage their own
CREATE POLICY "Users manage own experiences" ON user_experiences
    FOR ALL USING (auth.uid() = user_id);

-- experience_raw_responses: access via experience ownership
CREATE POLICY "Users manage own raw responses" ON experience_raw_responses
    FOR ALL USING (
        experience_id IN (SELECT id FROM user_experiences WHERE user_id = auth.uid())
    );

-- bullet_versions: access via experience ownership
CREATE POLICY "Users manage own bullet versions" ON bullet_versions
    FOR ALL USING (
        experience_id IN (SELECT id FROM user_experiences WHERE user_id = auth.uid())
    );

-- approved_bullets: users manage their own
CREATE POLICY "Users manage own approved bullets" ON approved_bullets
    FOR ALL USING (auth.uid() = user_id);

-- section_versions: users manage their own
CREATE POLICY "Users manage own section versions" ON section_versions
    FOR ALL USING (auth.uid() = user_id);

-- bullet_generation_logs: users can view their own
CREATE POLICY "Users view own bullet logs" ON bullet_generation_logs
    FOR ALL USING (auth.uid() = user_id);

-- ============================================
-- TRIGGER: auto-update updated_at on user_experiences
-- ============================================

CREATE TRIGGER update_user_experiences_updated_at
    BEFORE UPDATE ON user_experiences
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- DONE!
-- ============================================
```

### `supabase/migrations/20260506000001_external_jobs_setup.sql`

```sql
-- Migration: Setup pra ingestão de vagas externas (Apify Gupy + Greenhouse + Lever)
--
-- Adiciona campos de sourcing em jobs/companies, cria tabela de mapeamento
-- de boards públicos (Greenhouse/Lever), e seed inicial das empresas.

BEGIN;

-- ============================================================================
-- 1. Campos de sourcing externo em jobs
-- ============================================================================

ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS source TEXT,
  ADD COLUMN IF NOT EXISTS external_id TEXT,
  ADD COLUMN IF NOT EXISTS external_url TEXT,
  ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS raw_payload JSONB;

-- Dedup: dois jobs com mesmo (source, external_id) é o mesmo job. Permite
-- mesmo external_id em fontes diferentes (ex: Gupy + Greenhouse).
CREATE UNIQUE INDEX IF NOT EXISTS jobs_source_external_id_uniq
  ON public.jobs (source, external_id)
  WHERE source IS NOT NULL;

-- Index pra otimizar query do "mark stale"
CREATE INDEX IF NOT EXISTS jobs_source_last_seen_idx
  ON public.jobs (source, last_seen_at)
  WHERE source IS NOT NULL;

-- ============================================================================
-- 2. Slug + source em companies (pra dedup entre múltiplos sources)
-- ============================================================================

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS slug TEXT,
  ADD COLUMN IF NOT EXISTS source TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS companies_slug_uniq
  ON public.companies (slug)
  WHERE slug IS NOT NULL;

-- ============================================================================
-- 3. Tabela de mapeamento de boards públicos (Greenhouse + Lever)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.external_job_sources (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ats          TEXT NOT NULL CHECK (ats IN ('greenhouse', 'lever')),
  company_slug TEXT NOT NULL,         -- slug que vai na URL (ex: 'inter', 'mercadolivre')
  display_name TEXT NOT NULL,         -- nome amigável pra UI ('Inter')
  is_active    BOOLEAN NOT NULL DEFAULT TRUE,
  last_synced_at TIMESTAMPTZ,
  last_sync_error TEXT,               -- nullable; preenche se sync falhou
  created_at   TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT external_job_sources_unique UNIQUE (ats, company_slug)
);

ALTER TABLE public.external_job_sources ENABLE ROW LEVEL SECURITY;

-- Service role only — tabela de configuração interna, usuários não precisam ler
CREATE POLICY "Service role only on external_job_sources"
  ON public.external_job_sources FOR ALL
  USING (false);

-- ============================================================================
-- 4. Seed das empresas Greenhouse com presença BR confirmada (testadas ao vivo)
-- ============================================================================

INSERT INTO public.external_job_sources (ats, company_slug, display_name) VALUES
  ('greenhouse', 'inter',       'Inter'),
  ('greenhouse', 'c6bank',      'C6 Bank'),
  ('greenhouse', 'stone',       'Stone'),
  ('greenhouse', 'nubank',      'Nubank'),
  ('greenhouse', 'quintoandar', 'QuintoAndar'),
  ('greenhouse', 'gympass',     'Wellhub (Gympass)'),
  ('greenhouse', 'vtex',        'VTEX'),
  ('greenhouse', 'ebanx',       'EBANX'),
  ('greenhouse', 'airbnb',      'Airbnb'),
  ('greenhouse', 'datadog',     'Datadog'),
  ('greenhouse', 'mongodb',     'MongoDB'),
  ('greenhouse', 'twilio',      'Twilio'),
  ('greenhouse', 'pinterest',   'Pinterest'),
  ('greenhouse', 'picpay',      'PicPay'),
  ('greenhouse', 'cloudflare',  'Cloudflare'),
  ('greenhouse', 'gitlab',      'GitLab'),
  ('greenhouse', 'asana',       'Asana'),
  ('greenhouse', 'dropbox',     'Dropbox'),
  ('greenhouse', 'anthropic',   'Anthropic'),
  ('greenhouse', 'stripe',      'Stripe')
ON CONFLICT (ats, company_slug) DO NOTHING;

COMMIT;
```

### `supabase/migrations/20260506000004_match_analyses.sql`

```sql
-- Match Score com IA: cache de análises por (user, vaga) + ampliação do
-- generation_type permitido em ai_generation_logs.

BEGIN;

-- ============================================================================
-- 1. Estender CHECK constraint de ai_generation_logs pra incluir 'match_analysis'
-- ============================================================================

ALTER TABLE public.ai_generation_logs
  DROP CONSTRAINT IF EXISTS ai_generation_logs_generation_type_check;

ALTER TABLE public.ai_generation_logs
  ADD CONSTRAINT ai_generation_logs_generation_type_check
  CHECK (generation_type IN (
    'profile',
    'resume',
    'interview',
    'bullets',
    'resume_evaluation',
    'resume_refine',
    'match_analysis'
  ));

-- ============================================================================
-- 2. Tabela de cache: uma entrada por (user, job)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.match_analyses (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  job_id          UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
  score           INT  NOT NULL CHECK (score BETWEEN 0 AND 100),
  reasons         JSONB NOT NULL DEFAULT '[]'::jsonb,
  model_used      TEXT NOT NULL,
  prompt_version  TEXT NOT NULL DEFAULT 'v1',
  -- SHA-256 hex das prefs+gamification_data relevantes. Quando muda, cache stale.
  profile_hash    TEXT NOT NULL,
  computed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT match_analyses_user_job_uniq UNIQUE (user_id, job_id)
);

CREATE INDEX IF NOT EXISTS idx_match_analyses_user
  ON public.match_analyses(user_id);

CREATE INDEX IF NOT EXISTS idx_match_analyses_user_hash
  ON public.match_analyses(user_id, profile_hash);

-- ============================================================================
-- 3. RLS: usuário só lê/escreve as próprias análises
-- ============================================================================

ALTER TABLE public.match_analyses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user reads own matches"
  ON public.match_analyses FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "user inserts own matches"
  ON public.match_analyses FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user updates own matches"
  ON public.match_analyses FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "user deletes own matches"
  ON public.match_analyses FOR DELETE
  USING (auth.uid() = user_id);

COMMIT;
```

### `supabase/migrations/20260507000001_swipe_applied.sql`

```sql
-- Adiciona controle de "vaga aplicada" em swipe_actions.
-- Usuário curte uma vaga via swipe → aparece na nova aba "Curtidas".
-- Lá ele marca quando aplicou no site da empresa (`applied = true`).

BEGIN;

ALTER TABLE public.swipe_actions
  ADD COLUMN IF NOT EXISTS applied BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS applied_at TIMESTAMPTZ;

-- Índice parcial pra buscar rapidamente "vagas curtidas e aplicadas/pendentes" do user
CREATE INDEX IF NOT EXISTS idx_swipe_actions_liked_user
  ON public.swipe_actions (user_id, applied)
  WHERE action = 'liked';

COMMIT;
```

### `supabase/migrations/20260507000002_adapted_resumes.sql`

```sql
-- Migration: adapted_resumes
--
-- Cache server-side da feature "adaptar currículo pra vaga".
-- Cada (user, job) tem no máximo 1 versão adaptada. Cache invalida quando o
-- usuário edita perfil ou currículo (via source_hash).
--
-- Custo: ~$0.001-0.003 por adaptação (gpt-4o-mini). Cache hit = 0.

BEGIN;

CREATE TABLE IF NOT EXISTS public.adapted_resumes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  job_id UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,

  -- Lista de mudanças explicáveis: [{field, label, before, after, reason}]
  changes JSONB NOT NULL,

  -- Currículo adaptado completo (mesmo schema que ResumeData no client).
  -- Nome/email/telefone/empresas/datas batem 100% com o input — validado
  -- server-side antes de salvar.
  resume_data JSONB NOT NULL,

  -- Score de match antes/depois da adaptação (motivacional pro user).
  match_score_before INT,
  match_score_after INT,

  -- SHA-256 dos dados de input do user (perfil + CV + dados imutáveis da
  -- vaga). Se mudar, regera. Mesma estratégia que match_analyses.
  source_hash TEXT NOT NULL,
  prompt_version TEXT NOT NULL,
  model_used TEXT NOT NULL,

  computed_at TIMESTAMPTZ DEFAULT now(),

  UNIQUE (user_id, job_id)
);

CREATE INDEX IF NOT EXISTS adapted_resumes_user_idx
  ON public.adapted_resumes (user_id, computed_at DESC);

ALTER TABLE public.adapted_resumes ENABLE ROW LEVEL SECURITY;

-- Users veem só os próprios.
CREATE POLICY "users_read_own_adapted_resumes"
  ON public.adapted_resumes FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Users podem deletar (caso queiram regenerar manualmente).
CREATE POLICY "users_delete_own_adapted_resumes"
  ON public.adapted_resumes FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- Insert/update: APENAS via service_role (edge function), pra garantir que
-- o validador anti-invenção sempre rode.
CREATE POLICY "service_role_writes_adapted_resumes"
  ON public.adapted_resumes FOR INSERT
  WITH CHECK (false);

CREATE POLICY "service_role_updates_adapted_resumes"
  ON public.adapted_resumes FOR UPDATE
  USING (false);

COMMIT;
```

### `supabase/migrations/20260512000000_app_config.sql`

```sql
-- Migration: tabela app_config para force-update gate
--
-- Singleton (id=1). O app lê min_supported_version no startup e bloqueia o
-- usuário se a versão instalada for menor. latest_version é informativo (pode
-- ser usado no futuro pra "soft prompt"). URLs ficam na config pra não precisar
-- rebuildar quando o link da loja mudar.
--
-- Versão segue o formato semver simples "MAJOR.MINOR.PATCH" (mesmo que o
-- pubspec.yaml, sem o build number depois do +). Comparação é numérica por
-- componente, feita no cliente.

BEGIN;

CREATE TABLE IF NOT EXISTS public.app_config (
  id INT PRIMARY KEY DEFAULT 1,
  min_supported_version TEXT NOT NULL DEFAULT '1.0.0',
  latest_version TEXT NOT NULL DEFAULT '1.0.0',
  update_message TEXT,
  ios_store_url TEXT,
  android_store_url TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT app_config_singleton CHECK (id = 1)
);

-- Seed row inicial. Ajustar min_supported_version manualmente no Supabase
-- quando subir build crítica que precisa de força.
INSERT INTO public.app_config (id, min_supported_version, latest_version, ios_store_url, android_store_url)
VALUES (
  1,
  '1.0.0',
  '1.1.0',
  'https://apps.apple.com/app/id0000000000',
  'https://play.google.com/store/apps/details?id=com.example.career_gamification'
)
ON CONFLICT (id) DO NOTHING;

-- RLS: leitura pública (qualquer um pode consultar a config), escrita só via
-- service_role (painel do Supabase).
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app_config read" ON public.app_config;
CREATE POLICY "app_config read"
  ON public.app_config
  FOR SELECT
  USING (true);

COMMIT;
```

### `supabase/migrations/20260516000000_jobs_skill_extraction.sql`

```sql
-- Migration: jobs_skill_extraction
--
-- Cache server-side da feature "confirmação de skills antes da adaptação".
-- Extração de skills atômicas é POR VAGA (não por user) — as skills que a vaga
-- pede são as mesmas pra qualquer candidato. Cruzamento contra CV (in_cv) e
-- contra confirmed_skills (pre_confirmed) é feito em runtime na Edge Function.
--
-- Custo extração: ~$0.0003/call (gpt-4o-mini). Cache hit = 0.

BEGIN;

CREATE TABLE IF NOT EXISTS public.jobs_skill_extraction (
  job_id          UUID PRIMARY KEY REFERENCES public.jobs(id) ON DELETE CASCADE,

  -- Skills extraídas: [{name: string, source: 'requirements'|'description'}]
  skills          JSONB NOT NULL,

  prompt_version  TEXT NOT NULL DEFAULT 'v1',
  model_used      TEXT NOT NULL,
  computed_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS jobs_skill_extraction_computed_idx
  ON public.jobs_skill_extraction (computed_at DESC);

ALTER TABLE public.jobs_skill_extraction ENABLE ROW LEVEL SECURITY;

-- Sem policy de SELECT pro user direto: acesso só via Edge Function
-- (service_role). User recebe o resultado já cruzado com o CV dele.

-- Estender CHECK de generation_type pra aceitar 'skill_extraction'
ALTER TABLE public.ai_generation_logs
  DROP CONSTRAINT IF EXISTS ai_generation_logs_generation_type_check;

ALTER TABLE public.ai_generation_logs
  ADD CONSTRAINT ai_generation_logs_generation_type_check
  CHECK (generation_type IN (
    'profile',
    'resume',
    'interview',
    'bullets',
    'resume_evaluation',
    'resume_refine',
    'match_analysis',
    'resume_adaptation',
    'skill_extraction'
  ));

COMMIT;
```

### `supabase/migrations/20260522000000_profile_personal.sql`

```sql
-- Migration: profile_personal
--
-- Semana 1 da migração profile-first. Tabela 1:1 com o usuário, sucessor
-- estruturado de user_profiles.gamification_data.imported_resume.parsed.
-- Hoje todo dado pessoal vive num JSONB aninhado; aqui vira coluna pra
-- permitir query direta, validação de schema e telemetria estruturada.
--
-- Convive com o JSONB legacy: a edge function extract-profile escreve
-- AMBOS (parsed JSONB + tabelas relacionais) durante a transição.
--
-- RLS policies vivem na migration 20260522000010_profile_rls_policies.sql,
-- agrupando todas as tabelas profile_* num só arquivo pra facilitar review.

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_personal (
  user_id                UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  first_name             TEXT,
  last_name              TEXT,
  email                  TEXT,
  phone_country_code     TEXT,
  phone_number           TEXT,
  headline               TEXT,
  summary                TEXT,
  gender                 TEXT CHECK (gender IN ('male','female','other','prefer_not_to_say')),
  age_range              TEXT CHECK (age_range IN ('under_18','18_24','25_34','35_44','45_54','55_64','65_plus')),
  location_country       TEXT,
  location_state         TEXT,
  location_city          TEXT,
  location_postal_code   TEXT,
  location_street_address TEXT,
  attribution_source     TEXT,
  profile_source         TEXT CHECK (profile_source IN ('imported','manual','mixed')),
  completeness_score     INTEGER NOT NULL DEFAULT 0 CHECK (completeness_score BETWEEN 0 AND 100),
  schema_version         INTEGER NOT NULL DEFAULT 1,
  profile_completed_at   TIMESTAMPTZ,
  last_extracted_at      TIMESTAMPTZ,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.profile_personal ENABLE ROW LEVEL SECURITY;

COMMIT;
```

### `supabase/migrations/20260522000001_profile_experiences.sql`

```sql
-- Migration: profile_experiences
--
-- Experiências profissionais + bullets categorizados por ângulo Harvard
-- (leadership / technical / impact). Hoje o imported_resume JSONB guarda
-- bullets como "description" string \n-separada; aqui cada bullet vira
-- linha própria pra permitir edição, regeneração e análise de força.
--
-- Bullets têm RLS via parent (profile_experiences.user_id) — policy
-- baseada em EXISTS fica na migration de policies (000010).
--
-- confidence (0-1) é setada pelo extrator IA; needs_review é flag manual
-- usada pela tela da Semana 2 pra destacar campos suspeitos.

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_experiences (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title         TEXT NOT NULL,
  company       TEXT NOT NULL,
  location      TEXT,
  start_date    DATE NOT NULL,
  end_date      DATE,
  is_current    BOOLEAN NOT NULL DEFAULT FALSE,
  order_index   INTEGER NOT NULL DEFAULT 0,
  confidence    NUMERIC(3,2) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  needs_review  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (is_current = TRUE OR end_date IS NOT NULL),
  CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_profile_experiences_user
  ON public.profile_experiences (user_id, order_index);

ALTER TABLE public.profile_experiences ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_bullets (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  experience_id   UUID NOT NULL REFERENCES public.profile_experiences(id) ON DELETE CASCADE,
  text            TEXT NOT NULL,
  angle           TEXT CHECK (angle IS NULL OR angle IN ('leadership','technical','impact')),
  strength_score  INTEGER CHECK (strength_score IS NULL OR strength_score BETWEEN 0 AND 100),
  verb            TEXT,
  order_index     INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profile_bullets_experience
  ON public.profile_bullets (experience_id, order_index);

ALTER TABLE public.profile_bullets ENABLE ROW LEVEL SECURITY;

COMMIT;
```

### `supabase/migrations/20260522000002_profile_education.sql`

```sql
-- Migration: profile_education
--
-- Formação acadêmica com tabelas filhas pra majors, minors e activities.
-- O modelo atual em imported_resume.parsed achata tudo num campo
-- "details" string-livre; aqui cada major/minor/atividade vira linha
-- separada pra permitir queries (ex: "todos os usuários que cursam
-- Engenharia de Computação"). gpa e max_gpa armazenados separadamente
-- pra suportar escalas diferentes (0-10 BR, 0-4.0 US).
--
-- RLS das filhas é via parent (profile_education.user_id) — EXISTS
-- na migration de policies (000010).

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_education (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  institution  TEXT NOT NULL,
  location     TEXT,
  degree       TEXT,
  start_date   DATE,
  end_date     DATE,
  gpa          NUMERIC(4,2),
  max_gpa      NUMERIC(4,2),
  order_index  INTEGER NOT NULL DEFAULT 0,
  confidence   NUMERIC(3,2) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_profile_education_user
  ON public.profile_education (user_id, order_index);

ALTER TABLE public.profile_education ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_education_majors (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  education_id  UUID NOT NULL REFERENCES public.profile_education(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  order_index   INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_profile_education_majors_edu
  ON public.profile_education_majors (education_id);

ALTER TABLE public.profile_education_majors ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_education_minors (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  education_id  UUID NOT NULL REFERENCES public.profile_education(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  order_index   INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_profile_education_minors_edu
  ON public.profile_education_minors (education_id);

ALTER TABLE public.profile_education_minors ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_education_activities (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  education_id  UUID NOT NULL REFERENCES public.profile_education(id) ON DELETE CASCADE,
  text          TEXT NOT NULL,
  order_index   INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_profile_education_activities_edu
  ON public.profile_education_activities (education_id);

ALTER TABLE public.profile_education_activities ENABLE ROW LEVEL SECURITY;

COMMIT;
```

### `supabase/migrations/20260522000003_profile_languages.sql`

```sql
-- Migration: profile_languages
--
-- Idiomas com proficiência normalizada em 5 níveis. O imported_resume
-- JSONB não tem campo dedicado pra idioma — vinha implícito em achievements
-- ou interests. Aqui ganha estrutura: o extrator IA mapeia textos livres
-- ("Avançado", "C1", "Fluente", "Inglês intermediário") pros 5 enums.

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_languages (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  proficiency  TEXT CHECK (proficiency IS NULL OR proficiency IN ('native','fluent','advanced','intermediate','basic')),
  order_index  INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profile_languages_user
  ON public.profile_languages (user_id, order_index);

ALTER TABLE public.profile_languages ENABLE ROW LEVEL SECURITY;

COMMIT;
```

### `supabase/migrations/20260522000004_profile_skills.sql`

```sql
-- Migration: profile_skills + profile_certifications
--
-- Skills explícitas (extraídas da seção "Habilidades" do CV) e
-- certificações. Skills têm índice único case-insensitive por user pra
-- evitar duplicatas tipo "Python" vs "python" vs "PYTHON". Categoria
-- é opcional e setada pela IA (ex: "Programming", "Soft Skills", "Tools").

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_skills (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  category     TEXT,
  order_index  INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_profile_skills_user_name
  ON public.profile_skills (user_id, LOWER(name));

CREATE INDEX IF NOT EXISTS idx_profile_skills_name
  ON public.profile_skills (LOWER(name));

ALTER TABLE public.profile_skills ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_certifications (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  issuer       TEXT,
  date         DATE,
  order_index  INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profile_certifications_user
  ON public.profile_certifications (user_id, order_index);

ALTER TABLE public.profile_certifications ENABLE ROW LEVEL SECURITY;

COMMIT;
```

### `supabase/migrations/20260522000005_profile_projects.sql`

```sql
-- Migration: profile_projects
--
-- Projetos pessoais ou freelances. Distinto de experiences (que são
-- empregos formais). Inclui website pra portfolio link, datas opcionais
-- (alguns projetos são pontuais sem data clara).

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_projects (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  website      TEXT,
  description  TEXT,
  start_date   DATE,
  end_date     DATE,
  is_current   BOOLEAN NOT NULL DEFAULT FALSE,
  order_index  INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profile_projects_user
  ON public.profile_projects (user_id, order_index);

ALTER TABLE public.profile_projects ENABLE ROW LEVEL SECURITY;

COMMIT;
```

### `supabase/migrations/20260522000006_profile_lists.sql`

```sql
-- Migration: profile_interests + profile_awards + profile_coursework
--
-- Três listas auxiliares. Interests tem índice único case-insensitive
-- pra evitar duplicatas; awards e coursework não — premiação pode ter
-- nome igual em anos diferentes, e cursos com mesmo nome também.

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_interests (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  order_index  INTEGER NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_profile_interests_user_name
  ON public.profile_interests (user_id, LOWER(name));

ALTER TABLE public.profile_interests ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_awards (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  date         DATE,
  order_index  INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_profile_awards_user
  ON public.profile_awards (user_id, order_index);

ALTER TABLE public.profile_awards ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_coursework (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  order_index  INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_profile_coursework_user
  ON public.profile_coursework (user_id, order_index);

ALTER TABLE public.profile_coursework ENABLE ROW LEVEL SECURITY;

COMMIT;
```

### `supabase/migrations/20260522000007_profile_job_preferences.sql`

```sql
-- Migration: profile_job_preferences + filhas
--
-- Preferências de vaga pro matching e feed personalizado. Estruturado em
-- 4 tabelas:
--   - profile_job_preferences (1:1): localização primária + arrays de
--     experience_level/work_mode/job_types
--   - profile_desired_titles: cargos desejados, com origem (user_added
--     vs from_resume) pra a Semana 2 distinguir o que veio da IA
--   - profile_application_countries: países onde aplica + status de
--     autorização de trabalho (pra futuras vagas internacionais)
--   - profile_other_locations: localizações secundárias (ex: trabalha
--     em SP mas considera RJ e remoto)
--
-- Hoje todas essas prefs vivem em JSONB em user_profiles.preferences.
-- A migração será dual-written na edge function extract-profile.

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_job_preferences (
  user_id                    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  primary_location_country   TEXT,
  primary_location_state     TEXT,
  primary_location_city      TEXT,
  primary_location_postal_code TEXT,
  primary_location_lat       NUMERIC,
  primary_location_lng       NUMERIC,
  primary_location_radius_km INTEGER DEFAULT 50,
  experience_level           TEXT[] CHECK (experience_level IS NULL OR experience_level <@ ARRAY['entry','mid','senior']::TEXT[]),
  work_mode                  TEXT[] CHECK (work_mode IS NULL OR work_mode <@ ARRAY['remote','hybrid','in_person']::TEXT[]),
  job_types                  TEXT[] CHECK (job_types IS NULL OR job_types <@ ARRAY['full_time','internship','contract','part_time']::TEXT[]),
  updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.profile_job_preferences ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_desired_titles (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title        TEXT NOT NULL,
  source       TEXT CHECK (source IS NULL OR source IN ('user_added','from_resume')),
  order_index  INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_profile_desired_titles_user
  ON public.profile_desired_titles (user_id, order_index);

ALTER TABLE public.profile_desired_titles ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_application_countries (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  country_code  TEXT NOT NULL,
  work_auth     TEXT CHECK (work_auth IS NULL OR work_auth IN ('citizen','authorized','sponsorship_needed')),
  UNIQUE (user_id, country_code)
);

CREATE INDEX IF NOT EXISTS idx_profile_application_countries_user
  ON public.profile_application_countries (user_id);

ALTER TABLE public.profile_application_countries ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.profile_other_locations (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  city        TEXT,
  state       TEXT,
  country     TEXT,
  radius_km   INTEGER DEFAULT 50
);

CREATE INDEX IF NOT EXISTS idx_profile_other_locations_user
  ON public.profile_other_locations (user_id);

ALTER TABLE public.profile_other_locations ENABLE ROW LEVEL SECURITY;

COMMIT;
```

### `supabase/migrations/20260522000009_profile_extraction_logs.sql`

```sql
-- Migration: profile_extraction_logs
--
-- Logs específicos da edge function extract-profile, complementando
-- ai_generation_logs (que tem o panorama de LLM observability — tokens,
-- modelo, custo). Aqui ficam só os campos próprios do extrator:
--   - raw_json_output: o JSON estruturado pra debug de regressão
--   - raw_text_input_hash: SHA-256 do raw_text pra detectar reprocessamento
--   - confidence_global + low_confidence_fields: qualidade da extração
--   - status: success / partial / failed (matriz de observabilidade no
--     docs/profile_architecture.md)
--
-- FK ai_generation_log_id liga ao log de LLM correspondente; ON DELETE
-- SET NULL pra preservar o histórico de extração mesmo se o log de LLM
-- for purgado (retenção pode divergir).
--
-- RLS habilitada SEM POLICIES DE SELECT — debug de extração contém PII
-- (raw_json_output). Acesso só via service_role (edge functions admin).

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_extraction_logs (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  ai_generation_log_id  UUID REFERENCES public.ai_generation_logs(id) ON DELETE SET NULL,
  confidence_global     NUMERIC(3,2) CHECK (confidence_global IS NULL OR confidence_global BETWEEN 0 AND 1),
  low_confidence_fields JSONB,
  raw_json_output       JSONB,
  raw_text_input_hash   TEXT,
  status                TEXT NOT NULL CHECK (status IN ('success','partial','failed')),
  error_message         TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profile_extraction_logs_user
  ON public.profile_extraction_logs (user_id, created_at DESC);

-- Índice parcial: queries operacionais filtram pra status != 'success'
-- ao monitorar saúde do extrator (raro = pequeno = rápido).
CREATE INDEX IF NOT EXISTS idx_profile_extraction_logs_status
  ON public.profile_extraction_logs (status)
  WHERE status != 'success';

-- Índice parcial: monitora extrações com baixa confiança pra ajustar
-- prompt (também raro = pequeno = rápido).
CREATE INDEX IF NOT EXISTS idx_profile_extraction_logs_low_confidence
  ON public.profile_extraction_logs (confidence_global)
  WHERE confidence_global IS NOT NULL AND confidence_global < 0.7;

ALTER TABLE public.profile_extraction_logs ENABLE ROW LEVEL SECURITY;

-- DELIBERADAMENTE SEM POLICIES — só service_role acessa.

COMMIT;
```

### `supabase/migrations/20260522000010_profile_rls_policies.sql`

```sql
-- Migration: profile_* RLS policies
--
-- 4 policies (SELECT/INSERT/UPDATE/DELETE) por tabela, expandidas
-- EXPLICITAMENTE (sem placeholder/loop). Política padrão: auth.uid() =
-- user_id pras tabelas com FK direta de user, e EXISTS via parent pras
-- tabelas filhas (bullets, education_majors/minors/activities).
--
-- DELIBERADAMENTE EXCLUÍDA: profile_extraction_logs. RLS habilitada na
-- migration anterior (000009) sem policies = só service_role acessa.
--
-- Naming: users_<op>_<table>. Compactos e descritivos.

BEGIN;

-- ────────────────────────────────────────────────────────────────────
-- profile_personal (1:1)
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_personal ON public.profile_personal
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_personal ON public.profile_personal
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_personal ON public.profile_personal
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_personal ON public.profile_personal
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_experiences
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_experiences ON public.profile_experiences
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_experiences ON public.profile_experiences
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_experiences ON public.profile_experiences
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_experiences ON public.profile_experiences
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- profile_bullets — acesso via parent (profile_experiences)
CREATE POLICY users_select_profile_bullets ON public.profile_bullets
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_experiences pe
            WHERE pe.id = profile_bullets.experience_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_insert_profile_bullets ON public.profile_bullets
  FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public.profile_experiences pe
            WHERE pe.id = profile_bullets.experience_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_update_profile_bullets ON public.profile_bullets
  FOR UPDATE TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_experiences pe
            WHERE pe.id = profile_bullets.experience_id AND pe.user_id = auth.uid())
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM public.profile_experiences pe
            WHERE pe.id = profile_bullets.experience_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_delete_profile_bullets ON public.profile_bullets
  FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_experiences pe
            WHERE pe.id = profile_bullets.experience_id AND pe.user_id = auth.uid())
  );

-- ────────────────────────────────────────────────────────────────────
-- profile_education
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_education ON public.profile_education
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_education ON public.profile_education
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_education ON public.profile_education
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_education ON public.profile_education
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- profile_education_majors — acesso via parent
CREATE POLICY users_select_profile_education_majors ON public.profile_education_majors
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_majors.education_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_insert_profile_education_majors ON public.profile_education_majors
  FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_majors.education_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_update_profile_education_majors ON public.profile_education_majors
  FOR UPDATE TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_majors.education_id AND pe.user_id = auth.uid())
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_majors.education_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_delete_profile_education_majors ON public.profile_education_majors
  FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_majors.education_id AND pe.user_id = auth.uid())
  );

-- profile_education_minors — acesso via parent
CREATE POLICY users_select_profile_education_minors ON public.profile_education_minors
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_minors.education_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_insert_profile_education_minors ON public.profile_education_minors
  FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_minors.education_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_update_profile_education_minors ON public.profile_education_minors
  FOR UPDATE TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_minors.education_id AND pe.user_id = auth.uid())
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_minors.education_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_delete_profile_education_minors ON public.profile_education_minors
  FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_minors.education_id AND pe.user_id = auth.uid())
  );

-- profile_education_activities — acesso via parent
CREATE POLICY users_select_profile_education_activities ON public.profile_education_activities
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_activities.education_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_insert_profile_education_activities ON public.profile_education_activities
  FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_activities.education_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_update_profile_education_activities ON public.profile_education_activities
  FOR UPDATE TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_activities.education_id AND pe.user_id = auth.uid())
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_activities.education_id AND pe.user_id = auth.uid())
  );
CREATE POLICY users_delete_profile_education_activities ON public.profile_education_activities
  FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM public.profile_education pe
            WHERE pe.id = profile_education_activities.education_id AND pe.user_id = auth.uid())
  );

-- ────────────────────────────────────────────────────────────────────
-- profile_languages
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_languages ON public.profile_languages
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_languages ON public.profile_languages
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_languages ON public.profile_languages
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_languages ON public.profile_languages
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_skills
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_skills ON public.profile_skills
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_skills ON public.profile_skills
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_skills ON public.profile_skills
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_skills ON public.profile_skills
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_certifications
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_certifications ON public.profile_certifications
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_certifications ON public.profile_certifications
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_certifications ON public.profile_certifications
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_certifications ON public.profile_certifications
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_projects
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_projects ON public.profile_projects
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_projects ON public.profile_projects
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_projects ON public.profile_projects
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_projects ON public.profile_projects
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_interests
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_interests ON public.profile_interests
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_interests ON public.profile_interests
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_interests ON public.profile_interests
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_interests ON public.profile_interests
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_awards
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_awards ON public.profile_awards
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_awards ON public.profile_awards
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_awards ON public.profile_awards
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_awards ON public.profile_awards
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_coursework
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_coursework ON public.profile_coursework
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_coursework ON public.profile_coursework
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_coursework ON public.profile_coursework
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_coursework ON public.profile_coursework
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_job_preferences (1:1)
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_job_preferences ON public.profile_job_preferences
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_job_preferences ON public.profile_job_preferences
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_job_preferences ON public.profile_job_preferences
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_job_preferences ON public.profile_job_preferences
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_desired_titles
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_desired_titles ON public.profile_desired_titles
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_desired_titles ON public.profile_desired_titles
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_desired_titles ON public.profile_desired_titles
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_desired_titles ON public.profile_desired_titles
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_application_countries
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_application_countries ON public.profile_application_countries
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_application_countries ON public.profile_application_countries
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_application_countries ON public.profile_application_countries
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_application_countries ON public.profile_application_countries
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────
-- profile_other_locations
-- ────────────────────────────────────────────────────────────────────
CREATE POLICY users_select_profile_other_locations ON public.profile_other_locations
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY users_insert_profile_other_locations ON public.profile_other_locations
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_profile_other_locations ON public.profile_other_locations
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_delete_profile_other_locations ON public.profile_other_locations
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

COMMIT;
```

### `supabase/migrations/20260523000002_app_feature_flags.sql`

```sql
-- Migration: app_feature_flags
--
-- Semana 3 — Bloco F.1: feature flags granulares pra rollout das versões v2
-- (templates v2, adapt v2, match v2).
--
-- Por que tabela própria e NÃO PostHog:
--   PostHog mostrou comportamento async-frágil na Semana 2 — flag
--   `new_onboarding_enabled` não retornava true confiavelmente por causa
--   do cache async, forçando bypass hardcoded. Pra controlar rollout de
--   features CRÍTICAS (PDF/adapt/match), o failure mode "flag não carregou
--   ainda → fica em v1" silenciosamente atrasa rollout e contamina
--   métricas de comparação v1 vs v2.
--
-- Resolução: tabela direta no Supabase + leitura síncrona pelo client
-- com cache cold-start. Hash determinístico de user_id pra rollout
-- percentual (consistente entre sessões).
--
-- RLS: leitura pública (qualquer authenticated). Escrita apenas via
-- service_role (admin/console).

BEGIN;

CREATE TABLE IF NOT EXISTS public.app_feature_flags (
  feature_key  TEXT PRIMARY KEY,
  enabled      BOOLEAN NOT NULL DEFAULT false,
  rollout_pct  INTEGER NOT NULL DEFAULT 0 CHECK (rollout_pct BETWEEN 0 AND 100),
  description  TEXT,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.app_feature_flags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "app_feature_flags read all" ON public.app_feature_flags;
CREATE POLICY "app_feature_flags read all"
  ON public.app_feature_flags
  FOR SELECT
  TO authenticated
  USING (true);

-- Seed dos 3 flags da Semana 3, todos OFF.
-- Founder ajusta via Supabase Studio quando decidir avançar rollout.
INSERT INTO public.app_feature_flags (feature_key, enabled, rollout_pct, description)
VALUES
  ('templates_v2_enabled', false, 0, 'PDF templates lêem schema profile_* relacional via JOIN. Fallback automático pro v1 se perfil vazio.'),
  ('adapt_v2_enabled',     false, 0, 'adapt-resume-to-job v2 recebe user_id + lê schema relacional. Output inclui _source_bullet_id + _action por bullet.'),
  ('match_v2_enabled',     false, 0, 'analyze-match v2 usa profile_skills/profile_personal.summary. Fallback raw_text só se skills+summary+experiences todos vazios.')
ON CONFLICT (feature_key) DO NOTHING;

-- Trigger pra manter updated_at em sync (manual UPDATE no Studio bate aqui).
CREATE OR REPLACE FUNCTION public.touch_app_feature_flags_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_app_feature_flags_updated_at ON public.app_feature_flags;
CREATE TRIGGER trg_app_feature_flags_updated_at
  BEFORE UPDATE ON public.app_feature_flags
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_app_feature_flags_updated_at();

COMMIT;
```

### `supabase/migrations/20260527000002_add_email_application_to_jobs.sql`

```sql
-- Adiciona suporte a vagas em que a candidatura é por email (não URL).
--
-- Contexto: começamos a ingerir vagas via mailing (ex: Polifinance) onde
-- o candidato envia o CV pra um endereço como "rpgm@empresa.com.br" com
-- um assunto específico — não há URL de ATS pra apontar.
--
-- Schema:
--   application_method = 'url'   → comportamento legacy (external_url aponta
--                                  pra Greenhouse/Lever/Gupy/site da empresa)
--   application_method = 'email' → app abre mailto:application_email com
--                                  application_subject pré-preenchido
--
-- Vagas existentes (todas com application_method NULL → fallback 'url').

ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS application_method TEXT
    DEFAULT 'url'
    CHECK (application_method IN ('url', 'email'));

ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS application_email TEXT;

ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS application_subject TEXT;

-- Quando method='email', application_email é obrigatório. Quando method='url',
-- application_email deve ser NULL pra não confundir o frontend.
ALTER TABLE public.jobs
  DROP CONSTRAINT IF EXISTS jobs_application_method_consistency;
ALTER TABLE public.jobs
  ADD CONSTRAINT jobs_application_method_consistency
  CHECK (
    (application_method = 'email' AND application_email IS NOT NULL AND application_email <> '')
    OR
    (application_method = 'url' AND application_email IS NULL)
  );

COMMENT ON COLUMN public.jobs.application_method IS
  'Como o candidato aplica: ''url'' (legacy, abre external_url no browser) ou ''email'' (abre mailto:application_email com application_subject).';

COMMENT ON COLUMN public.jobs.application_email IS
  'Email do recrutador pra envio de CV. Só preenchido quando application_method=''email''. Ex: rpgm@bbscp.com.br';

COMMENT ON COLUMN public.jobs.application_subject IS
  'Assunto recomendado pro email de candidatura. App substitui placeholders tipo [SEU NOME]. Ex: ''Vaga Investimentos Alternativos – [SEU NOME]''';
```

### `supabase/migrations/20260601010000_add_manual_education_fields.sql`

```sql
-- Manual onboarding education fields.
--
-- The profile-first schema already stores education as structured rows, but
-- the manual onboarding path needs two extra dimensions that do not belong in
-- free-text fields:
-- - education_level: distinguishes school from college/university rows.
-- - education_status/current_semester/current_school_year: captures the
--   student's current education state for onboarding and reporting.

ALTER TABLE public.profile_education
  ADD COLUMN IF NOT EXISTS education_level TEXT CHECK (
    education_level IS NULL OR education_level IN ('school', 'college', 'technical', 'other')
  ),
  ADD COLUMN IF NOT EXISTS education_status TEXT CHECK (
    education_status IS NULL OR education_status IN (
      'studying',
      'graduated',
      'paused',
      'not_started',
      'not_in_college',
      'not_studying'
    )
  ),
  ADD COLUMN IF NOT EXISTS current_semester SMALLINT CHECK (
    current_semester IS NULL OR current_semester BETWEEN 1 AND 12
  ),
  ADD COLUMN IF NOT EXISTS current_school_year SMALLINT CHECK (
    current_school_year IS NULL OR current_school_year BETWEEN 1 AND 3
  );

CREATE INDEX IF NOT EXISTS idx_profile_education_user_level
  ON public.profile_education (user_id, education_level, order_index);

COMMENT ON COLUMN public.profile_education.education_level IS
  'Education tier. Manual onboarding writes school and college separately.';

COMMENT ON COLUMN public.profile_education.education_status IS
  'Education status captured in manual onboarding: studying, graduated, paused, not_started, not_in_college, not_studying.';

COMMENT ON COLUMN public.profile_education.current_semester IS
  'Current or last college semester captured in manual onboarding.';

COMMENT ON COLUMN public.profile_education.current_school_year IS
  'Current school year captured in manual onboarding: 1, 2 or 3 for high school.';
```

### `supabase/migrations/20260601030000_admin_dashboard_b2b.sql`

```sql
-- Admin Dashboard B2B
--
-- Internal tables for the Stage admin dashboard. All tables are RLS-protected
-- and are intended to be accessed only through admin Edge Functions using the
-- service role key after validating the caller against public.admin_users.

BEGIN;

CREATE TABLE IF NOT EXISTS public.admin_users (
  email      TEXT PRIMARY KEY,
  role       TEXT NOT NULL CHECK (role IN ('owner', 'analyst')),
  is_active  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "No direct client access to admin_users" ON public.admin_users;
CREATE POLICY "No direct client access to admin_users"
  ON public.admin_users FOR ALL
  USING (false)
  WITH CHECK (false);

CREATE TABLE IF NOT EXISTS public.employer_clients (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  website       TEXT,
  contact_name  TEXT,
  contact_email TEXT,
  status        TEXT NOT NULL DEFAULT 'prospect'
    CHECK (status IN ('prospect', 'active', 'paused', 'archived')),
  notes         TEXT,
  created_by    TEXT REFERENCES public.admin_users(email) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_employer_clients_status
  ON public.employer_clients (status, created_at DESC);

ALTER TABLE public.employer_clients ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "No direct client access to employer_clients" ON public.employer_clients;
CREATE POLICY "No direct client access to employer_clients"
  ON public.employer_clients FOR ALL
  USING (false)
  WITH CHECK (false);

CREATE TABLE IF NOT EXISTS public.candidate_list_requests (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       UUID REFERENCES public.employer_clients(id) ON DELETE SET NULL,
  source_job_id   UUID REFERENCES public.jobs(id) ON DELETE SET NULL,
  title           TEXT NOT NULL,
  area            TEXT,
  description     TEXT,
  requirements    TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  location_city   TEXT,
  location_state  TEXT,
  work_model      TEXT CHECK (work_model IS NULL OR work_model IN ('presencial', 'hibrido', 'remoto')),
  job_type        TEXT CHECK (job_type IS NULL OR job_type IN ('estagio', 'trainee', 'clt_junior', 'temporario', 'full_time', 'internship', 'contract', 'part_time')),
  min_score       INTEGER NOT NULL DEFAULT 60 CHECK (min_score BETWEEN 0 AND 100),
  status          TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'ranking', 'review', 'exported', 'archived')),
  created_by      TEXT REFERENCES public.admin_users(email) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_candidate_list_requests_client
  ON public.candidate_list_requests (client_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_candidate_list_requests_status
  ON public.candidate_list_requests (status, created_at DESC);

ALTER TABLE public.candidate_list_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "No direct client access to candidate_list_requests" ON public.candidate_list_requests;
CREATE POLICY "No direct client access to candidate_list_requests"
  ON public.candidate_list_requests FOR ALL
  USING (false)
  WITH CHECK (false);

CREATE TABLE IF NOT EXISTS public.candidate_data_sharing_consents (
  user_id          UUID PRIMARY KEY REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  status           TEXT NOT NULL DEFAULT 'not_asked'
    CHECK (status IN ('not_asked', 'granted', 'denied', 'revoked')),
  status_reason    TEXT,
  granted_at       TIMESTAMPTZ,
  revoked_at       TIMESTAMPTZ,
  updated_by_admin TEXT REFERENCES public.admin_users(email) ON DELETE SET NULL,
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_candidate_data_sharing_consents_status
  ON public.candidate_data_sharing_consents (status, updated_at DESC);

ALTER TABLE public.candidate_data_sharing_consents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "No direct client access to candidate_data_sharing_consents" ON public.candidate_data_sharing_consents;
CREATE POLICY "No direct client access to candidate_data_sharing_consents"
  ON public.candidate_data_sharing_consents FOR ALL
  USING (false)
  WITH CHECK (false);

CREATE TABLE IF NOT EXISTS public.candidate_list_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id      UUID NOT NULL REFERENCES public.candidate_list_requests(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  score           INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100),
  rank            INTEGER NOT NULL,
  score_breakdown JSONB NOT NULL DEFAULT '[]'::jsonb,
  status          TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'exported')),
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (request_id, user_id),
  UNIQUE (request_id, rank)
);

CREATE INDEX IF NOT EXISTS idx_candidate_list_items_request_rank
  ON public.candidate_list_items (request_id, rank);

CREATE INDEX IF NOT EXISTS idx_candidate_list_items_user
  ON public.candidate_list_items (user_id);

ALTER TABLE public.candidate_list_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "No direct client access to candidate_list_items" ON public.candidate_list_items;
CREATE POLICY "No direct client access to candidate_list_items"
  ON public.candidate_list_items FOR ALL
  USING (false)
  WITH CHECK (false);

CREATE TABLE IF NOT EXISTS public.candidate_list_exports (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id      UUID NOT NULL REFERENCES public.candidate_list_requests(id) ON DELETE CASCADE,
  exported_by     TEXT REFERENCES public.admin_users(email) ON DELETE SET NULL,
  format          TEXT NOT NULL DEFAULT 'csv' CHECK (format IN ('csv')),
  exported_fields TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  candidate_count INTEGER NOT NULL DEFAULT 0 CHECK (candidate_count >= 0),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_candidate_list_exports_request
  ON public.candidate_list_exports (request_id, created_at DESC);

ALTER TABLE public.candidate_list_exports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "No direct client access to candidate_list_exports" ON public.candidate_list_exports;
CREATE POLICY "No direct client access to candidate_list_exports"
  ON public.candidate_list_exports FOR ALL
  USING (false)
  WITH CHECK (false);

CREATE TABLE IF NOT EXISTS public.admin_audit_log (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_email TEXT REFERENCES public.admin_users(email) ON DELETE SET NULL,
  action      TEXT NOT NULL,
  entity_type TEXT,
  entity_id   TEXT,
  metadata    JSONB NOT NULL DEFAULT '{}'::jsonb,
  ip_address  TEXT,
  user_agent  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_admin
  ON public.admin_audit_log (admin_email, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_action
  ON public.admin_audit_log (action, created_at DESC);

ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "No direct client access to admin_audit_log" ON public.admin_audit_log;
CREATE POLICY "No direct client access to admin_audit_log"
  ON public.admin_audit_log FOR ALL
  USING (false)
  WITH CHECK (false);

DROP TRIGGER IF EXISTS trg_employer_clients_updated_at ON public.employer_clients;
CREATE TRIGGER trg_employer_clients_updated_at
  BEFORE UPDATE ON public.employer_clients
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_candidate_list_requests_updated_at ON public.candidate_list_requests;
CREATE TRIGGER trg_candidate_list_requests_updated_at
  BEFORE UPDATE ON public.candidate_list_requests
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_candidate_data_sharing_consents_updated_at ON public.candidate_data_sharing_consents;
CREATE TRIGGER trg_candidate_data_sharing_consents_updated_at
  BEFORE UPDATE ON public.candidate_data_sharing_consents
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_candidate_list_items_updated_at ON public.candidate_list_items;
CREATE TRIGGER trg_candidate_list_items_updated_at
  BEFORE UPDATE ON public.candidate_list_items
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

COMMIT;
```

### `supabase/migrations/20260607000000_user_culture_fit_preferences.sql`

```sql
-- Coleta de preferências não técnicas para futuro fit score cultural.
-- A UI salva localmente primeiro e sincroniza aqui em best-effort.

CREATE TABLE IF NOT EXISTS public.user_culture_fit_preferences (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  work_style text,
  learning_style text,
  collaboration_style text,
  pace_style text,
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT user_culture_fit_work_style_check CHECK (
    work_style IS NULL OR work_style IN (
      'clear_scope',
      'autonomy',
      'guided_autonomy'
    )
  ),
  CONSTRAINT user_culture_fit_learning_style_check CHECK (
    learning_style IS NULL OR learning_style IN (
      'mentor',
      'docs',
      'hands_on'
    )
  ),
  CONSTRAINT user_culture_fit_collaboration_style_check CHECK (
    collaboration_style IS NULL OR collaboration_style IN (
      'high_collaboration',
      'async_focus',
      'balanced_rituals'
    )
  ),
  CONSTRAINT user_culture_fit_pace_style_check CHECK (
    pace_style IS NULL OR pace_style IN (
      'predictable',
      'dynamic',
      'seasonal_intensity'
    )
  )
);

ALTER TABLE public.user_culture_fit_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY users_select_own_culture_fit_preferences
ON public.user_culture_fit_preferences
FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY users_insert_own_culture_fit_preferences
ON public.user_culture_fit_preferences
FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY users_update_own_culture_fit_preferences
ON public.user_culture_fit_preferences
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY users_delete_own_culture_fit_preferences
ON public.user_culture_fit_preferences
FOR DELETE
USING (auth.uid() = user_id);
```

## Apêndice 3 — Edge Functions (resumo fiel; código-fonte em `supabase/functions/`)

Total: 31 diretórios no repo, 27 deployadas ACTIVE (verificado via API em 09/06). Todas envelopadas por `withEdgeAnalytics` (`_shared/posthog.ts`) que emite `edge_function_invoked` com latência/status. Linhas = `wc -l` do `index.ts`.

| Função (linhas) | Resumo fiel do comportamento |
|---|---|
| `adapt-resume-to-job` (2.947 + `v2.ts`) | Recebe `job_id` (+`user_id` no v2). v1 (PROMPT v14): lê `gamification_data`, adapta CV via gpt-4o-mini com refine opcional gpt-4o (`REFINEMENT_ENABLED`), validador semântico de nomes próprios (Jaro-Winkler), validador anti-invenção, quality_score 0-100, cache em `adapted_resumes` por (user, job, prompt_version). v2 (`v2.ts`, PROMPT v27-v2, flag `adapt_v2_enabled`=100%): lê schema relacional `profile_*`, output com `_source_bullet_id`+`_action` por bullet (diff explicável), tradução de extra_skills, i18n PT/EN do output. Telemetria `$ai_generation` + `ai_generation_logs`. |
| `analyze-match` (939) | Match user×vaga. Carrega prefs + perfil (pseudo-texto `profile_*` com fallback `whoIAm`/raw_text legacy), monta prompt v10 (Apêndice 4), gpt-4o-mini com timeout 8s, valida score = soma dos weights, cache `match_analyses` keyed (user, job, prompt_version, profile_hash). Cenário C (tudo vazio) → score 50 sem chamar IA quando detectável. |
| `extract-profile` (834) | Parse de CV: recebe PDF base64 + texto extraído client; GPT-4o (vision quando precisa); valida contra `PROFILE_JSON_SCHEMA` (`_shared/profile_schema.ts`); grava via RPC `save_profile_from_json` (transacional) + dual-write `imported_resume` legacy; loga em `profile_extraction_logs` com recovery_status. |
| `parse-cv` (523) / `parse-cv-pdf` (367) | Parsers legados (texto-only / PDF) — sem caller no app desde 26/05; mantidos como rollback. |
| `generate-bullets` (363) | 3 bullets (resultado/processo/habilidade) a partir de `raw_responses` da fase + contexto da campanha; suporta clarification loop; grava log em `bullet_generation_logs`. Prompt no Apêndice 4. |
| `generate-summary` (226) | Resumo profissional do CV a partir de bullets aprovados + formação + vaga-alvo. |
| `generate-resume` (509) | Monta o ResumeData final da trilha (bullets aprovados + dados) e salva; ⚠️ rate-limit `count >= N` comentado (linha 36, "TODO re-enable before launch"). |
| `generate-profile` (186) / `suggest-tools` (185) | Legacy da trilha: perfil/relatório e sugestão de ferramentas. |
| `extract-job-skills` (469) | Extrai até N skills atômicas da vaga (gpt-4o-mini), cache `jobs_skill_extraction` por (job, prompt_version). Usado pela skills-confirmation do adapt. |
| `sync-jobs-apify` (462) | Dispara actor Apify (Gupy), aguarda dataset, normaliza via `_shared/jobs.ts` (htmlToText, inferArea, inferJobType), upsert companies+jobs por (source, external_id), `markStaleJobsInactive('apify_gupy'?, 48h)`. Protegido por `x-cron-secret`. |
| `sync-jobs-ats` (176) | Itera `external_job_sources` ativas (Greenhouse/Lever API pública por slug), filtra vagas de estágio/junior BR, mesmo pipeline de normalização/upsert/stale(48h). |
| `sync-jobs-brazil` (414) | Scraper HTTP de boards BR (InfoJobs etc.), keyword "estagio", mesmo pipeline; sources prefixo `brz_%`. |
| `ingest-jobs-email` (634, verify_jwt=false) | Webhook Resend Inbound: valida secret + remetente em `POLIFINANCE_ALLOWED_SENDERS`; GPT-4o (texto+vision p/ imagem) extrai vagas do e-mail; cria jobs com `application_method='email'` + subject; source `polifinance`. |
| `notify-signup` (82, verify_jwt=false) | Recebe POST do trigger DB; manda ntfy ao fundador com nome/e-mail do novo user. |
| `notify-auto-apply-swipe` (147) | Auth via JWT do user; recebe `job_id`; manda ntfy (NTFY_TOPIC_AUTO_APPLY) avisando que o user deu swipe-right numa vaga de candidatura por e-mail — operação manual do fundador a partir daí. |
| `notifications-daily-digest` (301) | Cron: conta vagas novas do dia, monta push OneSignal (REST API) pra base; emite eventos de telemetria. |
| `notifications-broadcast` (235) | Push manual ad-hoc via OneSignal REST (chamado por script do fundador). |
| `daily-report` (311) | Cron 07h BRT: agrega KPIs do banco (users, swipes, applies, CVs), envia e-mail Resend (founder+sócio) + ntfy; semanal aos domingos. |
| `admin-me/-overview/-jobs/-users/-clients/-candidate-lists/-audit` (24-606) | API do dashboard B2B. Autenticação: JWT Supabase + verificação em `admin_users` (`_shared/admin.ts`); usam service role; `admin-candidate-lists` (606 l.) monta listas ranqueadas de candidatos com consentimento + export; `admin-audit` grava `admin_audit_log`. |

Módulos `_shared/`: `jobs.ts` (703 — normalização/inferArea/inferJobType/markStale), `posthog.ts` (454 — J3), `profile_schema.ts` (493 — JSON schema do perfil + PROFILE_SYSTEM_PROMPT + toLegacyResume), `cv_text.ts` (176), `cv_content_validator.ts` (120 — anti-invenção), `cv_schema.ts` (103), `admin.ts` (167).

## Apêndice 4 — Prompts literais de IA

### 4.1 `analyze-match` — SYSTEM_PROMPT (PROMPT_VERSION v10) — `supabase/functions/analyze-match/index.ts:356-481`

```text
const SYSTEM_PROMPT = `Você analisa fit entre estudantes/juniores brasileiros e vagas de estágio/junior.

═══════════════════════════════════════════════════════════════════
REGRA #1 (CRÍTICA) — O SCORE É MATEMÁTICA EXATA:
  score = soma dos "weight" onde matched=true.
  Exemplo: matched em Área (30) + Tipo (20) = score 50. NÃO é 70, NÃO é 85.
  NUNCA arredonde pra cima. NUNCA infle. Soma exata, sempre.

REGRA #2 (CRÍTICA) — NÃO INVENTE DADOS DO CANDIDATO:
  Se o candidato não declarou "Jurídico" como interesse, ele NÃO tem interesse em Jurídico.
  O título da vaga é INFORMAÇÃO DA VAGA, não do candidato.
  Você NÃO pode inferir interesse do candidato a partir do título/descrição da vaga.
  Se o candidato não tem skill X declarada, ele NÃO tem skill X.

═══════════════════════════════════════════════════════════════════
ESTRATÉGIA (escolha o cenário ANTES de pontuar):

CENÁRIO A — candidato TEM preferências declaradas (áreas/cidades/modelo/tipo/salário):
  Pesos: Área 30, Tipo 20, Localização 15, Modelo 15, Salário 10, Skills 10.
  Avalie SOMENTE contra os dados que o candidato declarou.

CENÁRIO B — candidato SEM preferências MAS COM perfil (CV importado, skills, sobre, interesses):
  Use APENAS o CV/perfil como fonte de verdade do candidato.
  Pesos: Área (afinidade CV↔vaga) 40, Skills (sobreposição com requisitos) 40, Tipo 10, Modelo/Local 10.
  Do CV você pode extrair área de formação, skills, cidade, nível — desde que ESTEJA EXPLÍCITO no texto.

CENÁRIO C — candidato SEM preferências E SEM perfil (cadastro incompleto):
  CRITÉRIO ESTRITO PARA ATIVAR:
    - TODAS as preferências estão vazias: areas=[], locations=[], work_models=[], job_types=[], min_salary=null
    - E TODO o perfil está vazio: sem skills, sem summary, sem interesses, sem CV importado, sem perfil estruturado.
  Se QUALQUER uma das prefs OU do perfil tem valor (mesmo que só "Modelos preferidos: ['remote']"
  ou só "Skills: ['excel']"), você JÁ TEM dado — use CENÁRIO A.

  PARE só quando TUDO está vazio. Retorne EXATAMENTE:
  {"score": 50, "reasons": [{"label":"Sem perfil","matched":false,"weight":0,"detail":"Configure suas preferências ou suba seu CV para um match preciso."}]}
  Não tente analisar. Não tente inferir do título da vaga. PARE.

═══════════════════════════════════════════════════════════════════
COMO AVALIAR cada dimensão (Cenário A/B):

- matched=true: o dado DO CANDIDATO bate com o requisito da vaga. Some o weight.
- matched=false, weight=0: o candidato NÃO declarou esse dado (não penalize, mas também não some).
- matched=false, weight>0: o candidato declarou MAS não bate (raro — só quando há conflito explícito).

REGRA CRÍTICA — LISTAS DE PREFERÊNCIAS (areas/locations/work_models/job_types):
Quando o candidato declarou MÚLTIPLOS valores numa lista (ex: work_models=["remoto", "presencial"]),
isso significa que QUALQUER UM desses valores serve pra ele. NÃO é "indeciso" — é "aceita várias".

  Se o atributo da vaga está NA lista do candidato → matched=true (some o weight inteiro).
  Se NÃO está → matched=false (mesmo que o candidato tenha outras opções listadas).

  Exemplo: candidato work_models=["remoto", "presencial"], vaga work_model="presencial"
    → matched=TRUE (presencial está na lista), weight=15 contribui pro score.

  Exemplo: candidato work_models=["remoto"], vaga work_model="presencial"
    → matched=FALSE (presencial NÃO está na lista), weight=15 não contribui.

Aplica-se identicamente pra areas, locations, job_types.

Seja generoso em afinidade SEMÂNTICA REAL (skills):
  "Marketing Digital" ↔ "Designer com Photoshop" = match (Adobe compartilhado)
  "Excel avançado" ↔ "análise de dados" = match
  "Photoshop" ≈ "Adobe Creative" = match

NUNCA seja generoso INVENTANDO dado. Se candidato diz "Direito" e vaga é "Marketing", NÃO é match só porque ambos existem.

═══════════════════════════════════════════════════════════════════
EXEMPLOS:

# Exemplo 1 — Cenário A, fit alto
INPUT: candidato declarou areas=["Tecnologia"], locations=["São Paulo"], work_models=["remoto"], job_types=["estagio"]
       vaga: "Estágio Dev Frontend", área="Tecnologia", cidade="São Paulo", modelo="remoto", tipo="estagio"
OUTPUT (correto):
{"score": 80, "reasons": [
  {"label":"Área","matched":true,"weight":30,"detail":"Tecnologia bate exatamente com seu interesse declarado."},
  {"label":"Tipo","matched":true,"weight":20,"detail":"Estágio é o tipo que você procura."},
  {"label":"Localização","matched":true,"weight":15,"detail":"São Paulo é a cidade que você prefere."},
  {"label":"Modelo","matched":true,"weight":15,"detail":"Remoto bate com sua preferência."},
  {"label":"Salário","matched":false,"weight":0,"detail":"Você não definiu mínimo de salário."},
  {"label":"Skills","matched":false,"weight":0,"detail":"Você não declarou skills específicas para comparar."}
]}
NOTA: 30+20+15+15 = 80. NÃO arredondar pra 85 ou 90.

# Exemplo 2 — Cenário A, fit médio (apenas algumas dimensões batem)
INPUT: candidato declarou areas=["Jurídico"], nada mais
       vaga: "Estagiário Jurídico Imobiliário", área="Jurídico", cidade="São Paulo", modelo="híbrido", tipo="estagio"
OUTPUT (correto):
{"score": 50, "reasons": [
  {"label":"Área","matched":true,"weight":30,"detail":"Jurídico bate exatamente com seu interesse declarado."},
  {"label":"Tipo","matched":true,"weight":20,"detail":"Estágio é compatível."},
  {"label":"Localização","matched":false,"weight":0,"detail":"Você não declarou cidade preferida."},
  {"label":"Modelo","matched":false,"weight":0,"detail":"Você não declarou modelo de trabalho preferido."},
  {"label":"Salário","matched":false,"weight":0,"detail":"Você não definiu mínimo de salário."},
  {"label":"Skills","matched":false,"weight":0,"detail":"Você não declarou skills para comparação."}
]}
NOTA: 30+20 = 50. NÃO inflar para 70, 85 ou 100 só porque a única dimensão que existe bateu.

# Exemplo 3 — Cenário C, sem dado (ATIVAR APENAS quando TUDO vazio)
INPUT: areas=[], locations=[], work_models=[], job_types=[], min_salary=null, sem whoIAm, sem skills, sem CV
       vaga: qualquer
OUTPUT (correto):
{"score": 50, "reasons": [
  {"label":"Sem perfil","matched":false,"weight":0,"detail":"Configure suas preferências ou suba seu CV para um match preciso."}
]}

# Exemplo 4 — Cenário A com SÓ 1 dimensão (NÃO é Cenário C!)
INPUT: areas=[], locations=[], work_models=["remoto"], job_types=[], min_salary=null
       perfil tem skills=["Excel"]
       vaga: "Estágio Marketing", modelo="presencial"
OUTPUT (correto — usa CENÁRIO A com SÓ as dimensões que existem):
{"score": 0, "reasons": [
  {"label":"Área","matched":false,"weight":0,"detail":"Você não declarou áreas de interesse."},
  {"label":"Tipo","matched":false,"weight":0,"detail":"Você não declarou tipo de vaga preferido."},
  {"label":"Localização","matched":false,"weight":0,"detail":"Você não declarou cidade preferida."},
  {"label":"Modelo","matched":false,"weight":15,"detail":"Você prefere remoto, mas a vaga é presencial."},
  {"label":"Salário","matched":false,"weight":0,"detail":"Você não definiu mínimo de salário."},
  {"label":"Skills","matched":false,"weight":10,"detail":"Excel não aparece nos requisitos desta vaga."}
]}
NOTA: 0 matched=true → score 0. NÃO retornar "Sem perfil" só porque a maioria está vazia — o user JÁ DECLAROU "remoto" e "Excel".

═══════════════════════════════════════════════════════════════════
OUTPUT JSON ESTRITO:
{"score": <int 0..100, soma EXATA dos weights matched>, "reasons": [{"label": "...", "matched": <bool>, "weight": <int>, "detail": "..."}, ...]}

CADA reason.detail: máximo 150 chars, PT-BR, segunda pessoa ("sua área", "você tem...").
NÃO inclua texto fora do JSON. NÃO adicione fences markdown.`
```

O user prompt é montado por `buildUserPrompt` (mesmo arquivo, linhas 483-580): seção CANDIDATO (prefs JSON + perfil estruturado das tabelas profile_* até 1500-3000 chars, com fallback whoIAm.derived e CV raw legacy) + seção VAGA (título, área, tipo, cidade sanitizada, modelo, salário, requisitos, descrição truncada).

### 4.2 `adapt-resume-to-job` v2 — SYSTEM_PROMPT_V2 (PROMPT_VERSION v27-v2, em produção a 100%) — `supabase/functions/adapt-resume-to-job/v2.ts:642-687`

```text
export const SYSTEM_PROMPT_V2 = `Você adapta currículos brasileiros pra vagas específicas. Sua tarefa: REORDENAR e REFORMULAR conteúdo destacando o que é relevante pra vaga. NUNCA adicione informação que não esteja no input.

REGRAS INVIOLÁVEIS:
1. NÃO INVENTE NADA. Se não está nos dados do candidato, NÃO existe.
2. Nome, email, telefone, LinkedIn, localização: copie EXATAMENTE.
3. Empresas, cargos, instituições, diplomas, períodos: copie EXATAMENTE.
4. Skills: pode REORDENAR e REMOVER. Não pode ADICIONAR skill fora do pool.
5. Resumo profissional: pode reescrever pra destacar fit, só com informação do input.
6. Cada substantivo concreto no resumo (área, tecnologia, ferramenta, indústria, idioma) precisa aparecer textualmente no input.
7. NÃO TRADUZA O CURRÍCULO. Output deve estar na MESMA LÍNGUA do input. CV em inglês → output em inglês ("Supported deal origination..."). CV em português → output em português ("Apoiei a originação..."). NUNCA traduza bullets, summary ou skills entre línguas.
7b. Stack tecnológico / área de formação: copie exato (não traduza nem reinterprete).

REGRA CRÍTICA DE CARDINALIDADE (NÃO VIOLE):
8. O número de experiences no OUTPUT precisa ser EXATAMENTE IGUAL ao número de experiences no INPUT. NUNCA adicione experience que não está listada. Se o input tem 1 experience, output TEM que ter 1. Se o input tem 3, output tem 3. NUNCA invente uma 2ª, 3ª ou 4ª experience pra "completar o CV" — currículo com 1 experience real é melhor que 3 inventadas.
9. O número de education no OUTPUT precisa ser EXATAMENTE IGUAL ao número de education no INPUT.
10. PRESERVE TODAS as experiences e education listadas — adapte cada uma, mas não remova nenhuma.

REGRA DE PRESERVAÇÃO INTEGRAL DE SEÇÕES (Tier 1):
11. PRESERVE TODAS as seções abaixo. Se input traz, output DEVE trazer:
    - Languages (lista de {name, proficiency}) — se input tem ["English: Native", "Portuguese: Native"], output DEVE conter os 2.
    - Tools (lista separada de skills técnicas) — MS Office, Power BI, etc. Se input tem 3 tools, output tem AS MESMAS 3 (pode reordenar).
    - Education details:
      • gpa: se input tem "8.9/10.0", output DEVE ter "8.9/10.0" (NÃO invente, NÃO mude).
      • majors: copie array IDÊNTICO (mesma ordem permitida).
      • minors: copie array IDÊNTICO.
      • activities: copie cada activity (pode reformular leve, mas o FATO de cada uma DEVE estar presente).
    - linkedin, streetAddress, headline: copie EXATAMENTE como vêm. Se input está vazio, output vazio. NUNCA invente URL/endereço/headline.
12. Esses campos NÃO são "decorativos" — são identidade do candidato. Currículo recrutador-friendly precisa de GPA, Minor, languages, etc. NUNCA dropa por achar que "não cabe" na vaga.

BULLETS — REGRA NOVA E CRÍTICA (V2):
Cada bullet adaptado precisa ter:
  - text: o bullet (pode ser reformulado em relação ao original)
  - _source_bullet_id: o uuid do bullet original cujo FATO está sendo descrito (ou null se for novo)
  - _action: 'kept' | 'rewritten' | 'synthesized'

REGRAS DE _action:
- 'kept'        : texto idêntico ao original (whitespace pode variar). _source_bullet_id é OBRIGATÓRIO.
- 'rewritten'   : reformula o MESMO fato do bullet original com palavras diferentes. _source_bullet_id é OBRIGATÓRIO. Não pode trocar fato; só verbo, ordem, ênfase.
- 'synthesized' : bullet completamente novo, sem fonte direta. PROIBIDO em V2 — só use se você está combinando dois fatos REAIS de bullets do MESMO experience_id. _source_bullet_id deve ser null.

LIMITES:
- Bullets por experience: NUNCA mais que o número original. Pode ter MENOS (omitir bullets fracos).
- Skills: máximo 12.
- Changes: máximo 6.

OUTPUT JSON ESTRITO conforme schema. Bullets na MESMA LÍNGUA do input (ver instrução de OUTPUT LANGUAGE no user prompt), método Harvard (verbo ação + impacto/contexto).`
```

(O v1 legacy tem SYSTEM_PROMPT próprio, v14, em `adapt-resume-to-job/index.ts:1074+` — não transcrito por estar desativado pela flag `adapt_v2_enabled=100%`.)

### 4.3 `generate-bullets` — buildSystemPrompt — `supabase/functions/generate-bullets/index.ts:262-325`

```text
    return `Você é um ghostwriter especializado em currículos para estudantes universitários brasileiros.

## CONTEXTO DA CAMPANHA
Vaga-alvo: ${targetJob?.title ?? 'Estágio ou Primeiro Emprego'}
Descrição da vaga: ${targetJob?.description_text ?? 'não fornecida'}
Área de foco do usuário: ${interestAreas || 'não informada'}
Norte profissional: ${visionText || 'não informado'}

## SUA TAREFA
Gere EXATAMENTE 3 versões de bullet point com ângulos narrativos distintos:

1. **RESULTADO**: Impacto quantificável. Verbo de ação + entrega mensurável.
2. **PROCESSO**: Foco no método/como o trabalho foi feito.
3. **HABILIDADE**: Competência demonstrada conectada a uma skill transferível.

As 3 versões usam as MESMAS informações mas com ênfase diferente — NÃO são paráfrases.

## REGRAS INVIOLÁVEIS
- Português brasileiro
- Verbo de ação forte no início (NUNCA "Responsável por", "Auxiliou em", "Participou de")
- USE: Liderei, Desenvolvi, Otimizei, Cresci, Implementei, Gerenciei, Criei, Estruturei, Conduzi
- Primeira pessoa implícita (não use "Eu" — comece direto com o verbo)
- 1-2 linhas por bullet, máximo ~180 caracteres
- NUNCA invente dados, números ou ferramentas não mencionados pelo usuário
- Se a informação for rasa demais, retorne needs_clarification MAS ainda gere os 3 bullets

## EXEMPLO
❌ RUIM: "Responsável por atividades de marketing digital"
✅ BOM (Liga de Marketing, cresceu Instagram de 800 → 2.400):
- RESULTADO: "Cresci o Instagram da Liga de Marketing de 800 para 2.400 seguidores em 4 meses, gerando 15 leads para eventos."
- PROCESSO: "Estruturei calendário editorial semanal com 3 formatos iterando com base em métricas de engajamento."
- HABILIDADE: "Apliquei gestão de mídias sociais e análise de dados para otimizar a estratégia de conteúdo digital."

## FORMATO DE RESPOSTA (JSON estrito)
{
  "bullets": [
    {"angle": "resultado", "content": "...", "confidence": 0.85},
    {"angle": "processo", "content": "...", "confidence": 0.90},
    {"angle": "habilidade", "content": "...", "confidence": 0.75}
  ],
  "needs_clarification": null
}

Se info for rasa:
{
  "bullets": [ ... os 3 bullets do jeito que conseguir ... ],
  "needs_clarification": {
    "question": "Pergunta específica...",
    "reason": "Por que isso tornaria o bullet mais impactante.",
    "target_angle": "resultado"
  }
}`
```

### 4.4 `extract-profile` — PROFILE_SYSTEM_PROMPT — `supabase/functions/_shared/profile_schema.ts:247-290`

```text
export const PROFILE_SYSTEM_PROMPT = `Você é um extrator de currículos brasileiros. Receba o texto do CV (e/ou imagem PDF) e retorne um JSON exato no schema fornecido.

PRINCÍPIOS DE LEITURA:
1. Currículos brasileiros frequentemente usam DUAS COLUNAS. Leia COLUNA POR COLUNA, esquerda antes da direita.
2. Cabeçalho (nome + contatos) é sempre lido primeiro.
3. Headers de seção marcam início de seção. Reconheça TODOS os equivalentes PT e EN:
   - EXPERIÊNCIA / EXPERIÊNCIA PROFISSIONAL / EXPERIENCE / PROFESSIONAL EXPERIENCE / WORK EXPERIENCE → experiences[]
   - FORMAÇÃO / FORMAÇÃO ACADÊMICA / EDUCAÇÃO / EDUCATION → education[]
   - HABILIDADES / COMPETÊNCIAS / SKILLS / TECHNICAL SKILLS → skills[] (category=null ou 'hard')
   - FERRAMENTAS / TOOLS / PROGRAMAS / SOFTWARE → skills[] com category='tool'
   - IDIOMAS / LANGUAGES → languages[]
   - ATIVIDADES EXTRACURRICULARES / EXTRACURRICULAR ACTIVITIES / ACTIVITIES / LIDERANÇA / LEADERSHIP / VOLUNTARIADO / VOLUNTEER → experiences[] (recrutador vê como experiência — title=cargo, company=nome do clube/org)
   - CERTIFICAÇÕES / CERTIFICATIONS → certifications[]
   - PROJETOS / PROJECTS → projects[]
   - INTERESSES / INTERESTS / HOBBIES → interests[]
4. Bullets de experiência preservam o TEXTO ORIGINAL — não traduza, não reescreva, não resuma.
5. Datas e localizações geralmente ficam à direita no mesmo bloco da empresa/instituição.

REGRAS DE EXTRAÇÃO (INVIOLÁVEIS):
1. EXTRAIA — não adapte, não reescreva, não corrija ortografia.
2. Se um campo não está no CV, use null (campos string-ou-null) ou array vazio (campos array). NÃO INVENTE dados.
3. Datas: SEMPRE no formato YYYY-MM-DD. Se só ano disponível, use YYYY-01-01. Se só mês/ano, use YYYY-MM-01.
4. Empregado atualmente: end_date = null e is_current = true.
5. first_name e last_name SEMPRE separados. Se o CV traz "João Silva Souza", first_name = "João", last_name = "Silva Souza".
6. Email: lowercase, trim.
7. Telefone: separar país (phone_country_code, ex "+55") do número (phone_number). PRESERVE A FORMATAÇÃO ORIGINAL do CV — se vem "(11) 98216-4700", retorna "(11) 98216-4700" (NÃO retire parênteses/hífen/espaço). Se vem "11987654321" raw, mantém raw. Os dígitos puros pra e164 são derivados automaticamente por trigger no DB. Se não houver código de país explícito no CV brasileiro, assuma "+55".
7b. LinkedIn URL: extraia LITERAL como aparece no CV. Aceita formatos "linkedin.com/in/usuario", "https://linkedin.com/in/usuario", "https://www.linkedin.com/in/usuario", "linkedin.com/in/usuario/" — copie como está, NÃO normalize. Se não houver, null.
7c. Website pessoal/portfólio: URL do site pessoal do candidato (NÃO LinkedIn, NÃO empresa do candidato). Aceita "github.com/usuario", "usuario.dev", "https://usuario.com", "behance.net/usuario". Copie literal. Se não houver, null.
8. Idiomas: mapear pra exatamente um dos níveis. "Nativo" → native; "Fluente"/"C2"/"C1" → fluent; "Avançado"/"B2" → advanced; "Intermediário"/"B1" → intermediate; "Básico"/"A1"/"A2" → basic.
9. Mantenha idioma original do CV (PT ou EN). Não traduza nada.
10. Skills: extrair só as habilidades explicitamente listadas em "Habilidades"/"Skills"/"Competências"/"Technical Skills"/"Tools"/"Ferramentas"/"Programas". Não inferir de bullets.
   - Items de "Tools"/"Ferramentas"/"Programas"/"Software" → category='tool' (ex: "Microsoft Office", "Power BI", "Figma").
   - Items de "Habilidades Técnicas"/"Technical Skills"/"Skills" → category=null (hard skills genéricas como "Accounting", "Corporate Finance").
   - Não duplique: se "Excel" aparece em Tools, NÃO repita em Skills.
10b. Education.activities: extrair CADA bullet/linha do bloco da educação (após o nome da instituição), incluindo Honors, Distinction, Class Rep, Awards, Coursework, Relevant Work. EXEMPLO: se o CV traz "Honors and Academic Distinction: Ranked among the top students (1st place, twice)" + "Class Representative: Elected to represent the class" → activities = ["Honors and Academic Distinction: Ranked among the top students (1st place, twice)", "Class Representative: Elected to represent the class"]. NÃO consolide múltiplos achievements em 1 activity só.
11. Bullets: cada item da lista vira um objeto {text: "..."}. NÃO categorize angle/strength_score/verb — esses serão preenchidos depois.
12. gender e age_range: só preencha se EXPLICITAMENTE declarados (raro). Caso contrário null.
13. headline e summary: distintos. Headline é o cargo/título no topo (ex: "Engenheiro de Software"). Summary é o parágrafo de resumo profissional (se houver).
14. Pra cada experiência e educação, atribua confidence 0..1 baseado em quão claro estava no CV:
    - 1.0 = título + empresa + datas completas + descrição clara
    - 0.7 = falta um detalhe menor (ex: location ausente)
    - 0.4 = ambiguidade importante (ex: datas incompletas, empresa indistinta)
    - 0.2 = quase só nome, sem contexto
`
```

### 4.5 `parse-cv` (legacy) — SYSTEM_PROMPT — `supabase/functions/parse-cv/index.ts:54-90`

```text
const SYSTEM_PROMPT = `Você é um extrator estrutural de currículos. Sua tarefa é receber o TEXTO BRUTO de um CV (extraído de PDF, com formatação parcial perdida) e retornar um JSON estruturado.

REGRAS INVIOLÁVEIS:
1. NÃO adapte, NÃO reescreva, NÃO melhore. Apenas EXTRAIA o que está escrito.
2. NÃO invente nada. Se um campo não está no CV, retorne string vazia ou array vazio.
3. Preserve nomes próprios EXATAMENTE como aparecem (mesma capitalização, mesmos espaços).
4. NÃO mude datas. Use o formato que está no CV ("Jan 2024 - Dez 2025", "01/2024", etc.).
5. PDFs frequentemente vêm com quebras de linha embaralhadas (cada palavra numa linha). Use contexto pra reconstruir frases coesas, mas SÓ a partir de palavras que estão no CV.
6. Para experiência profissional: extraia TODAS as posições do CV. Bullets/descrições preserve um por linha (separadas por \\n).
7. Para educação: extraia TODAS as formações. Se há GPA/honras/representação/coursework, coloque em "details".
8. Para skills: extraia palavras-chave da seção "Habilidades" / "Skills" / "Competências". NÃO inclua frases longas, só nomes de skills/tools.
9. Achievements: prêmios, distinções, projetos pessoais marcantes. Não duplique com bullets de experience.
10. Interests: hobbies, esportes, leituras — só se o CV tiver seção explícita.
11. Certifications: cursos extras + certificações profissionais (ex: "Modelagem Financeira - Wall Street Prep - 2025", "AWS Cloud Practitioner - 2024"). Formate cada item como string auto-contida: "Nome do curso/cert - Instituição - Ano" (omita partes que faltarem). Inclui qualquer seção do CV intitulada "CERTIFICAÇÕES", "CURSOS", "CURSOS E CERTIFICAÇÕES", "CERTIFICATIONS", "COURSES". NÃO repita aqui o que já está em achievements.
12. Language: detecte se o CV está em "pt" (português) ou "en" (inglês). Default "pt".
12. Para campos imutáveis (fullName, email, phone, linkedin, location), pegue do header do CV. Se incertos, deixe vazio em vez de chutar.

FORMATO DE BULLETS: cada bullet/responsabilidade deve ser uma linha do campo "description". Se o CV usa "•" ou "-", remova esses marcadores — só o texto da ação.

EXEMPLO de experience:
Input do CV:
  Stage  Londrina - PR
  CEO  Dez 2025 - Atual
  • Desenvolvi um aplicativo gamificado...
  • Fechei uma venda significativa...

Output:
  {"role":"CEO","company":"Stage","period":"Dez 2025 - Atual","location":"Londrina - PR","description":"Desenvolvi um aplicativo gamificado...\\nFechei uma venda significativa..."}`

function buildUserPrompt(rawText: string): string {
  return `EXTRAIA o currículo a seguir em JSON estruturado.

=== TEXTO BRUTO DO CV ===
${rawText.slice(0, 8000)}
=== FIM DO CV ===

Retorne o objeto { resume: {...} } seguindo o schema. Mantenha fidelidade absoluta ao que está no CV — não invente nada.`
```

### 4.6 `extract-job-skills` — SYSTEM_PROMPT (v1) — `supabase/functions/extract-job-skills/index.ts:166-187`

```text
const SYSTEM_PROMPT = `Você é um extrator de skills de vagas. Sua tarefa: dada a descrição de uma vaga (título + requisitos + descrição), extraia ATÉ ${MAX_SKILLS_OUT} skills/competências ATÔMICAS que o candidato precisa ter.

DEFINIÇÃO DE "ATÔMICA":
- Uma unidade indivisível de habilidade.
- "Excel e Power BI avançados" → ["Excel", "Power BI"] (2 skills atômicas)
- "Comunicação verbal e escrita" → ["Comunicação"] (1 skill — verbal e escrita são modalidades da mesma)
- "Inglês intermediário" → ["Inglês intermediário"] (nível faz parte da skill quando muda o significado)

REGRAS:
1. Cada skill em até 4 palavras (máximo). Prefira 1-2 palavras quando possível.
2. Use português (mesmo idioma da vaga). NÃO traduza.
3. Skills concretas e verificáveis. NÃO inclua "vontade de aprender", "atitude positiva", "dinamismo" etc — são qualidades subjetivas, não skills.
4. NÃO inclua área geral ("Marketing", "Vendas") — só ferramentas, técnicas, idiomas, conhecimentos específicos.
5. Ferramentas/softwares: nome canônico (ex: "Photoshop", "Figma", "SQL", "Excel").
6. Idiomas: incluir nível quando mencionado ("Inglês intermediário", "Espanhol fluente").
7. Para cada skill, indique a "source": "requirements" (veio da lista de requisitos) ou "description" (mencionada na descrição livre).
8. Ordene por relevância: as mais críticas primeiro.

OUTPUT JSON ESTRITO:
{"skills": [{"name": "...", "source": "requirements" | "description"}, ...]}

NÃO retorne nada fora do JSON. NÃO use fences markdown.`
```

### 4.7 `generate-summary` — buildSummarySystemPrompt — `supabase/functions/generate-summary/index.ts:185-214`

```text
function buildSummarySystemPrompt(
    targetJob: { title?: string; description_text?: string } | null,
    interestAreas: string,
    visionText: string,
    course: string,
    semester: string,
    institution: string,
): string {
    return `Você é um ghostwriter especializado em currículos para estudantes universitários brasileiros.

## TAREFA
Escreva UM resumo profissional sintético de 3-4 linhas (~60-80 palavras) para o candidato.
O resumo vai aparecer no topo do currículo como "Sobre mim" ou "Resumo Profissional".

## CONTEXTO DO CANDIDATO
Vaga-alvo: ${targetJob?.title ?? 'Estágio ou Primeiro Emprego'}
${targetJob?.description_text ? `Descrição da vaga: ${targetJob.description_text}` : ''}
Curso: ${course}${semester ? ` (${semester} semestre)` : ''}
${institution ? `Instituição: ${institution}` : ''}
Área de interesse: ${interestAreas || 'não informada'}
Norte profissional: ${visionText || 'não informado'}

## REGRAS
- Conecte o perfil do candidato com a vaga-alvo
- Mencione a formação, área de interesse e diferenciais que aparecem nos bullets
- Português brasileiro, tom profissional mas humano (não robótico)
- NÃO use clichês como "profissional proativo", "foco em resultados", "perfil inovador"
- NÃO invente informações não presentes nos bullets ou no contexto
- Primeira pessoa implícita (não use "Eu sou")
- Retorne APENAS o texto do resumo, sem formatação extra, sem aspas, sem título`
```

## Apêndice 5 — Comandos e queries executados durante a auditoria

Shell (read-only, executados em 2026-06-09):

```
flutter --version
flutter test                              # 6 testes, All tests passed (18s)
git rev-parse --show-toplevel
git log --oneline -15 / -20
git log --oneline --since="90 days ago" | wc -l   # 94
git log --format="%ad %s" --date=short --since="90 days ago"
git log --oneline --all -- .env           # vazio (nunca commitado)
git ls-files | grep -c "^\.env$"          # 0
ls / ls -la (raiz, supabase/, test/, admin_dashboard/, scripts/, tools/, ios/)
find lib -type d | sort
find lib -name "*.dart" | wc -l           # 208
find lib -name "*.dart" | xargs wc -l | sort -rn  # 79.429 total
wc -l supabase/functions/*/index.ts supabase/functions/_shared/*.ts
cat pubspec.yaml, CLAUDE.md, analysis_options.yaml, .gitignore,
    ios/Runner/Runner.entitlements
grep -o '^[A-Z_]*' .env .env.example      # só NOMES de chaves
grep -rn "IPHONEOS_DEPLOYMENT_TARGET" ios/Runner.xcodeproj/project.pbxproj
grep -n -A4 "CFBundleURLSchemes|associated-domains" ios/Runner/Info.plist
grep -rn "Analytics.shared\." lib          # inventário de call sites de eventos
grep -c "^const String ev" lib/services/analytics_events.dart   # 318
grep -rn "TODO|FIXME|HACK" lib supabase/functions
grep -rn "launchUrl|utm|ref=" lib/features/jobs
grep -rn "OPENAI_API_KEY" lib              # vazio
grep -rhn "Deno.env.get(" supabase/functions  # nomes de secrets
grep/sed/awk dirigidos nos arquivos citados no corpo (match_score.dart,
    job_repository.dart, swipe_repository.dart, jobs_viewmodel.dart,
    user_viewmodel.dart, analytics_service.dart, main.dart, splash_screen.dart,
    liked_jobs_screen.dart, job_card.dart, pdf_service.dart, resume_detail_screen.dart,
    trail_to_profile_bridge.dart, cv_import_service.dart, notifications_service.dart,
    culture_fit_repository.dart, telas de onboarding, edge functions)
```

Supabase (MCP read-only, projeto gaxfmniffjvwrwyunorl, 2026-06-09 ~20:45–21:30 BRT):

```
list_tables / list_migrations / list_edge_functions
SELECT ... FROM cron.job                                  -- 7 jobs
SELECT relname, n_live_tup, (count policies) FROM pg_stat_user_tables
SELECT count(*) reais: auth.users, user_profiles, profile_personal, swipe_actions,
    jobs, match_analyses, adapted_resumes, saved_resumes, campaigns, target_jobs,
    raw_responses, user_progress, user_answers, app_config, app_feature_flags,
    user_preferences, profile_extraction_logs, ai_generation_logs, admin_users,
    employer_clients, tracks, phases, questions, storage.objects(resumes),
    analytics_archive.posthog_events_archive
SELECT jobs por is_active/source/area; salary/cidade preenchidas; duplicatas
    (title, company_id) entre ativas                       -- 11 grupos
SELECT swipe_actions por action e applied
SELECT to_regclass('public.user_culture_fit_preferences')  -- NULL (drift)
SELECT pg_get_functiondef: handle_new_user, delete_user
SELECT * FROM pg_policies (12 tabelas-chave)
SELECT triggers FROM information_schema.triggers (public + auth)
SELECT colunas FROM information_schema.columns: jobs, profile_personal,
    external_job_sources
SELECT * FROM app_config; SELECT * FROM app_feature_flags
SELECT tabelas do schema analytics_archive; views do public (0)
SELECT id, name, public FROM storage.buckets               -- 1 (resumes, privado)
```

PostHog (MCP, projeto 419792, 2026-06-09):

```
dashboards-get-all (limit 30)   -- 23 dashboards, 10 pinned pós-cutover
```

Nenhum arquivo do projeto foi modificado além de `AUDITORIA-STAGE.md`. Nenhuma migration foi aplicada; nenhum UPDATE/INSERT/DELETE executado no banco.
