# QA de Instrumentação — pré-build release

> Versão: pós-cutover 2026-05/06. Executar em **device físico** com o app
> de debug rodando contra o ambiente de produção PostHog.
> Status atual da auditoria de código: ✅ 113 callers `Analytics.shared.*`
> em 65 métodos tipados distintos, zero strings cruas em `track()`, zero
> warnings novos no `flutter analyze`.

## Pré-requisitos antes de começar

1. `flutter run` em release build no device físico (debug builds
   filtram alguns eventos via `kDebugMode` paths).
2. PostHog → Live Events tab aberta no navegador
   ([projeto 419792](http://posthog-web-django.posthog.svc.cluster.local:8000/project/419792/activity/explore)).
3. **Liga `is_internal=true`** em Settings → tap 7× em "Configurações" →
   toggle "Marcar device como interno" → ON. Assim eventos do teste
   ficam fora do cohort produto e podem ser filtrados separadamente.
4. Confirmar `cohort_calculate_done` pra cohort 303703 (`Internal users`).

## Como ler cada item

| Símbolo | Significado |
|---|---|
| ✅ Esperado | O evento DEVE aparecer no Live Events em até 30s |
| 🟡 Verificar | Propriedade específica que precisa estar correta |
| ⚠️ Anti-pattern | NÃO deve aparecer (filtragem ou catálogo bloqueando) |

---

## 1. Boot, identidade & sessão

### 1.1 Cold start (app fechado → abre)
- ✅ `app_cold_start` com `duration_ms` numérico > 0
- ✅ `app_opened` com `cold_vs_warm: "cold"` (se já dentro do warm window) OR sem
- ✅ `session_started` com `cold_vs_warm: "cold"` e `time_since_last_session_ms` (se houve sessão anterior)
- 🟡 Super properties em **todos** os eventos: `is_internal: true`, `app_version`, `app_build_number`, `flow_version: "profile_first"`, `session_id` (uuid-like)

### 1.2 Usuário pre-cutover (já tinha conta antes da build)
Cenário: tinha conta na build antiga, atualiza pra nova.
- ✅ `$alias` (ou alias na pessoa visível em Live Events) ligando distinct_id antigo pro user.id Supabase
- 🟡 Pessoa no PostHog (Persons tab) tem **`is_pre_cutover_user: true`** (via `$set_once`) + **`cutover_alias_at: <ISO timestamp>`**
- ⚠️ NÃO deve emitir alias 2x se você reabrir o app — flag `analytics_cutover_alias_done_v1` em SharedPrefs previne

### 1.3 Usuário novo (signup pós-cutover)
- ✅ `auth_signup_started` com `method: "apple"|"email"|"phone"`
- ✅ `auth_signup_completed` com `method`
- ✅ Pessoa NÃO tem `is_pre_cutover_user` ou tem `false`
- 🟡 Cohort `Post-cutover users` (333197) inclui essa pessoa

### 1.4 Background / foreground curto (<5min)
- ✅ `app_backgrounded` com `duration_in_foreground_ms`
- ✅ `app_foregrounded` com `duration_in_background_ms`
- ⚠️ NÃO deve emitir `session_started` (mesma sessão)
- 🟡 `session_id` permanece igual nos eventos seguintes

### 1.5 Background longo (>5min) e volta
- ✅ `app_backgrounded`
- ✅ `app_foregrounded`
- ✅ `session_ended` com `exit_type: "session_timeout"` e `duration_ms`
- ✅ `session_started` com `cold_vs_warm: "warm"` e novo `session_id`
- 🟡 `session_id` MUDA — eventos pré-timeout têm um id, eventos pós têm outro

### 1.6 Force kill (swipe up no app)
- ⚠️ Pode NÃO emitir `session_ended` (iOS não garante detached callback)
- ✅ No próximo cold start, `session_started` calcula `time_since_last_session_ms` baseado em `analytics_last_session_ended_at` em SharedPrefs

---

## 2. Onboarding (fluxo profile-first)

### 2.1 Welcome → escolha de porta
- ✅ `onboarding_started` com `flow_version: "profile_first"`
- ✅ `onboarding_two_doors_shown`
- ✅ `onboarding_door_chosen` com `door: "upload_cv"|"from_scratch"` e `time_to_decide_ms`

### 2.2 Upload de CV (porta A)
- ✅ `onboarding_cv_upload_started` com `file_size_kb`
- ✅ `onboarding_cv_upload_completed` com `upload_duration_ms`
- 🟡 `onboarding_profile_extraction_started` (server-side, vem de edge function parse-cv)
- 🟡 `onboarding_profile_extraction_succeeded` com `model`, `latency_ms`, `fields_filled`, `anti_invention_flagged`
- 🟡 `edge_function_invoked` com `function: "parse-cv"`, `status: "ok"|"error"`, `duration_ms`

### 2.3 7 perguntas (porta B from_scratch)
- ✅ Para cada pergunta: `onboarding_cv_question_shown` com `question_id`, `question_index`, `prefill_present`
- ✅ `onboarding_cv_question_answered` com `time_ms`, `char_count`
- ✅ Skip: `onboarding_cv_question_skipped`

### 2.4 Revisão pessoal + CV
- ✅ `onboarding_personal_review_shown`
- ✅ Edit em campo: `onboarding_personal_field_edited` com `field`, `char_delta`
- ✅ Confirmação: `onboarding_personal_review_confirmed` com `edits_count`, `time_on_screen_ms`
- ✅ Mesma seq pra CV: `onboarding_cv_review_*`

### 2.5 Preferências (7 telas)
- ✅ `onboarding_pref_step_shown` com `step` (1-7), `step_name`
- ✅ `onboarding_pref_step_answered` com `values_count`, `time_ms`
- ✅ Skip: `onboarding_pref_step_skipped`

### 2.6 Conclusão
- ✅ `onboarding_all_set_shown` com `total_duration_ms`, `steps_skipped`
- ✅ `onboarding_completed` com `door`, `flow_version`, `edits_total`
- ✅ `activation_milestone_hit` com `milestone: "first_swipe"` (ou similar, $set_once)

### 2.7 Abandono mid-flow
Cenário: bg/kill durante onboarding.
- ✅ Próximo boot deve emitir `onboarding_abandoned` com `last_step`, `time_in_flow_ms`, `exit_type`

---

## 3. Auth (login/signup/logout)

### 3.1 Apple Sign-In
- ✅ Toca botão: `auth_login_attempt` com `method: "apple"`
- ✅ Sucesso signup novo: `auth_signup_completed` com `method: "apple"`
- ✅ Sucesso login existente: `auth_login_succeeded` com `method: "apple"`
- ⚠️ Cancela no diálogo iOS: `auth_login_failed` com `method: "apple"`, `error_code: "cancelled"`

### 3.2 Logout
- ✅ `auth_logout` com `source: "settings"`
- 🟡 Após logout, próximos eventos viram anônimos (Posthog `reset()`)

### 3.3 Mudança de senha (settings)
- ✅ Sucesso: `auth_password_changed`
- ⚠️ Senha errada: `auth_password_change_failed` com `reason: "wrong_current"`
- ⚠️ Fraca: `reason: "weak"`
- ⚠️ Mesma senha: `reason: "same"`
- ⚠️ Erro rede: `reason: "reauth_network"`

---

## 4. Feed & Swipe (B.14, B.17)

### 4.1 Abrir aba Vagas
- ✅ `feed_opened` com `sub_tab: "para_voce"`, `jobs_in_buffer`
- ✅ `feed_loaded` (cold) com `jobs_count`, `load_duration_ms`, `cache_hit: false`
- ✅ Re-abrir aba: `feed_loaded` com `cache_hit: true` (sem `load_duration_ms`)

### 4.2 Pull-to-refresh
- ✅ `feed_refresh_pulled` com `time_since_last_load_ms`
- ✅ Seguido de novo `feed_loaded`

### 4.3 Swipe direita (curtir)
- ✅ `job_swiped` com TODAS estas props (**audit critical**):
  - `job_id`, `direction: "like"`, `match_score`, `match_source: "ai"|"deterministic_v1"|"fallback_deterministic"|"unknown"`
  - `position_in_feed` (índice no swiper)
  - `company_id` (pode ser null pra alguns)
  - `modality` ("presencial"|"hibrido"|"remoto"|"clt"|...)
  - `salary_bucket` ("lt_2k"|"2k_4k"|"4k_6k"|"6k_10k"|"gte_10k"|null)
  - `location_bucket` ("sp_capital"|"rj_capital"|"bh_capital"|"poa_capital"|"sp_interior"|"br_other_<uf>"|null)
- ✅ Primeira save: `first_save_celebration_shown` → toca "Ver salvas" → `first_save_celebration_continued`

### 4.4 Swipe esquerda (rejeitar)
- ✅ `job_swiped` com `direction: "reject"` + mesmo set de props

### 4.5 Acabaram as vagas
- ✅ `feed_exhausted` com `sub_tab: "para_voce"`, `jobs_seen_in_session`, `jobs_swiped_in_session`

### 4.6 Abrir detalhes (tap em card)
- ✅ `job_details_opened` com `job_id`, `match_score` (audit critical)
- 🟡 Tap em candidatar-se: `job_details_apply_clicked` com `job_id`, `match_score`, `used_adapted_cv: bool` — **CRÍTICO**, sustenta tese B2B
- ✅ Tap em compartilhar: `job_details_share_clicked` com `job_id`, `method`

### 4.7 Aba Curtidas
- ✅ `feed_opened` com `sub_tab: "curtidas"`
- ✅ Tap em vaga: `job_details_opened` com `match_score` enriquecido
- ✅ Tap candidatar: `job_details_apply_clicked` com `match_score` (não usa adapt = `used_adapted_cv` null)
- ✅ Unsave: `job_unsaved`

---

## 5. Adaptação de CV (B.15)

### 5.1 Fluxo completo
- ✅ Toca "Adaptar CV pra essa vaga": `adapt_intent_clicked` com `match_score`
- ✅ Edge function: `adapt_started` (sem skills)
- 🟡 Edge function executando: aparece `edge_function_invoked` com `function: "adapt-resume-to-job"`, `status: "ok"`, `duration_ms`, `prompt_version`
- 🟡 LLM call: `$ai_generation` (até 3 calls — `model_used`, `cost_usd_sum`, tokens)
- ✅ Sucesso: `adapt_succeeded` com `model`, `latency_ms`, `prompt_version`, `score_before`, `score_after`, `bullets_changed_count`, `cached`, `anti_invention_flagged`

### 5.2 Skills confirmation (se houver gap)
- ✅ `adapt_skills_confirmation_shown` com `suggestions_count`
- ✅ Toca skill aceitar: `adapt_skill_accepted` com `skill_name`
- ✅ Toca skill rejeitar: `adapt_skill_rejected` com `skill_name`
- ⚠️ Auto-skip (no_cv): `adapt_skills_confirmation_auto_skipped` com `reason`

### 5.3 Diff
- ✅ Diff renderizado: `adapt_diff_shown` com `bullets_changed_count`
- ⚠️ Scroll: `adapt_diff_scroll_progress` (não wired ainda — pendência)

### 5.4 Edit manual de bullet
- ✅ `adapt_section_edited_manually` com `field`, `edit_type` ("replace"|"clear"|"restore_original"), `char_diff`

### 5.5 Download PDF
- ✅ `adapt_pdf_downloaded` com `template`
- ✅ Apply após download: `adapt_apply_used` com `time_from_download_to_apply_ms`

### 5.6 Falha
- ⚠️ `adapt_failed` com `error_code` ("openai_timeout"|"openai_500"|etc)

---

## 6. Trilha (B.16 — granular novo)

### 6.1 Abrir trilha (mapa)
- ✅ `trilha_map_shown` com `phases_completed`, `phases_total`
- ✅ Toca fase bloqueada: `trilha_phase_locked_tapped` com `phase_id`

### 6.2 Iniciar fase
- ✅ `phase_started` com `phase_id`
- ✅ Após carregar questions: `phase_step_shown` com `phase_id`, `step_id`, `step_index`

### 6.3 Responder questions (granular novo)
Para cada question:
- ✅ Submit: `phase_step_completed` com `duration_ms` (tempo desde shown)
- ✅ Próxima: `phase_step_shown` com `step_index + 1`
- 🟡 Pares `_shown` ↔ `_completed` devem balancear 1:1

### 6.4 D6 / Bullet review interceptado
Cenário: D6 question é respondida → pendingBullet ativado.
- ✅ `phase_step_completed` pra D6
- ⚠️ NÃO emite `phase_step_shown` da próxima ainda (resume vem do BulletReviewScreen)
- ✅ Após `resumeAfterBullet`: `phase_step_shown` pra próxima

### 6.5 Abandono mid-step (bg ou back)
- ⚠️ `phase_step_abandoned` NÃO está wired ainda (pendência) — vai precisar instrumentar no `dispose()` ou via WidgetsBindingObserver

### 6.6 Completar fase
- ✅ `phase_completed` com `phase_id` (sem `xp_earned` — anti-padrão #2 corrigido)
- ✅ Última fase: `trilha_completed` com `phases_count`, `total_days`
- ✅ CV final disponível: `trilha_cv_final_downloaded` com `template`

---

## 7. Push notifications (B.10)

### 7.1 Permission flow
- ✅ Primeira vez (home ou pós-swipe): `push_permission_requested` com `source_screen: "first_session"`
- ✅ Aceita: `push_permission_granted`
- ⚠️ Nega: `push_permission_denied` com `ask_count`
- ✅ Reactivate via Settings: `push_reactivate_tapped` → `push_permission_requested` (`source: "settings_reactivate"`) → `push_reactivate_completed` com `granted`, `new_status`

### 7.2 Push foreground delivery (app aberto recebe push)
- ✅ `push_displayed` com `campaign_id`, `type`
- ⚠️ Tap na notificação: `push_opened` com `campaign_id`, `type`, `time_from_send_ms` (se sent_at vier no payload)

### 7.3 Push background (app fechado, tap no banner)
- ✅ Ao abrir via push: `push_opened` com `campaign_id`, `type`
- 🟡 Pode emitir `app_cold_start` + `session_started` cold

### 7.4 Revoke via Settings.app
- Cenário: vai em Settings iOS, desliga notificações, volta pro app.
- ✅ `push_permission_revoked_detected` com `days_since_grant`

---

## 8. Tutorial (B.11)

### 8.1 Primeira vez na home (tutorial roda)
- ✅ `tutorial_started` com `flow: "home_main"`
- ✅ Para cada step: `tutorial_step_shown` com `step` (0-N)
- ✅ Tap "Ver vagas" no último step: `tutorial_completed` com `flow`, `duration_ms`, `next_action: "jobs"`
- ✅ Ou "Cuidar do CV": `tutorial_completed` com `next_action: "resume"`

### 8.2 Skip
- ✅ `tutorial_step_dismissed` com step atual
- ✅ `tutorial_skipped` com `flow`

### 8.3 Re-run via Settings → Tutorial
- ✅ Mesmo fluxo do 8.1, mas seq na mesma sessão

---

## 9. Navegação & Settings (B.13, B.19)

### 9.1 Tab switch (bottom nav)
- ✅ `nav_tab_switched` com `from_tab`, `to_tab` ("jobs_swipe"|"jobs_liked"|"resume_tab"|"profile"), `duration_on_from_ms`
- ⚠️ Re-tap mesma tab: NÃO emite

### 9.2 Profile sub-tabs (Informações/Preferências/Currículos)
- ✅ `profile_tab_changed` com `tab: "info"|"preferences"|"resumes"`

### 9.3 Settings
- ✅ Toca botão Configurações: nada específico (cobre $screen com `settings`)
- ✅ Toggle Marcar device como interno (devmode): `setInternalUser` muda — verificar Person properties tem `is_internal: true`

### 9.4 Founders contact
- ✅ Toca botão: `founders_contact_opened` com `channel: "whatsapp"|"email"|"phone"`

---

## 10. Sinais qualitativos críticos pro pitch

Esses são os eventos cujo dado vai pro slide. Conferir manualmente que disparam corretamente em fluxos representativos:

| Evento | Pra que slide |
|---|---|
| `job_details_apply_clicked` com `match_score` | "Match IA prediz interesse" |
| `adapt_apply_used` com `time_from_download_to_apply_ms` | "Adapt fecha o loop" |
| `phase_step_completed` count + `duration_ms` | "Trilha educa" |
| `feedback_submitted` com `rating` | NPS proxy |
| `founders_contact_opened` | Power users pra ligar |

---

## 11. Anti-padrões a confirmar (NÃO devem aparecer)

- ⚠️ `Application Opened` / `Application Backgrounded` / `Application Installed` / `Application Updated` (autocapture mobile do SDK — DESLIGADA)
- ⚠️ `$screen` com `screen_name: "root('/')"` (PosthogObserver removido — não deve mais aparecer)
- ⚠️ `phase_completed` com property `xp_earned` (zumbi anti-pattern #2 — removido)
- ⚠️ `cv_adapted` (legacy event — substituído por `cv_adaptation_succeeded`)
- ⚠️ `job_sync_completed` em nova ingestão (substituído por `apify_sync_completed` em sync-jobs-apify)
- ⚠️ `tutorial_completed` com props `{next_action: ...}` mas sem `flow`/`duration_ms` (substituído por `finishWithChoice`)
- ⚠️ Eventos sem `is_internal`/`app_version`/`flow_version`/`session_id` em super properties

---

## 12. Comandos pra debug rápido

```bash
# Re-run com PostHog debug ligado pra ver eventos no console
flutter run --dart-define=POSTHOG_DEBUG=true

# Forçar nova sessão (limpa SharedPrefs)
flutter run --dart-define=CLEAR_PREFS=true   # ainda não implementado, ver TODO

# Validar análise estática
flutter analyze

# Conferir nomes em uso vs catálogo (em outro terminal)
grep -r "Analytics.shared.track(['\"]" lib  # deve retornar VAZIO
```

---

## 13. Checklist final pré-build

- [ ] Cohort `Internal users` (303703) populada com Zac (e Pedro quando ele ativar devmode)
- [ ] Cohort `Pre-cutover users` (333195) e `Post-cutover users` (333197) criadas
- [ ] 5 flags DRAFT criadas (`match_score_visibility_v1`, `adapt_diff_mode_v1`, `push_reactivate_tone_v1`, `card_design_v1`, `empty_state_cta_v1`)
- [ ] 5 dashboards criados (Health Check, Ativação, Swipe & Match, Trilha, Retenção)
- [ ] 6 dashboards legacy arquivados com tag `legacy-pre-cutover`
- [ ] `autocapture_opt_out: true` no projeto
- [ ] `heatmaps_opt_in: false` no projeto
- [ ] `test_account_filters_default_checked: true` no projeto
- [ ] `captureApplicationLifecycleEvents = false` em main.dart (Posthog config)
- [ ] PosthogObserver removido de MaterialApp
- [ ] 4 edge functions instrumentadas: adapt-resume-to-job, analyze-match, parse-cv, sync-jobs-apify, notifications-broadcast
- [ ] **Rodar este QA inteiro em device** — todos os ✅ confirmados

> Última atualização: 2026-05-28 (Sprint A Dia 6 finalizado).
