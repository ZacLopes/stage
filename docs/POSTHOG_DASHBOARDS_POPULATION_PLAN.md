# PostHog — Plano de População dos 9 Dashboards (Sprint B)

> **Para o chat de execução:** este documento é self-contained. Leia tudo antes de começar. Use as ferramentas MCP do PostHog (`mcp__plugin_posthog_posthog__exec`) com os comandos `search`, `info`, `schema`, `call`. NÃO chute schemas — sempre rode `info <tool>` antes de `call <tool>`.

---

## 1. Contexto

Stage é um app Flutter (v1.5.3+1) de match de vagas com gamificação. Submit pra App Store em até 7 dias (Demo Day 10/06). Instrumentação PostHog foi reescrita no cutover de 2026-05/06 (Sprint A). Agora é Sprint B: popular 9 dashboards já criados com insights baseados nos eventos novos.

**Org/Project (já ativo na MCP):**
- Organization: `stage` (id: `019e19a8-67dc-0000-a220-9b1aad514657`)
- Project: `Default project` (id: `419792`)
- Timezone: `America/Sao_Paulo`
- POE mode ativo — propriedades de pessoa em events são frozen no momento de ingest.

**Cutover date:** `2026-05-06`. Use isso pra filtrar eventos legados ("Pre-cutover") vs novos ("Post-cutover"). Cohort property: `flow_version` (`profile_first` = novo, ausente/outro = legado).

---

## 2. Tooling Guide (ordem obrigatória)

Para cada insight:

```
1. search/info — descobrir e validar o tool a chamar
2. read-data-schema — confirmar event_name + properties existem
   (call read-data-schema {"query": {"kind": "events"}})
   (call read-data-schema {"query": {"kind": "event_properties", "event_name": "<event>"}})
3. schema query-trends series / schema query-funnel series — drill nas estruturas
4. call query-trends/query-funnel/query-retention {...} — testar shape
5. call insight-create {"name": "...", "dashboards": [<id>], "query": {...}}
```

**HARD RULE:** rodar `read-data-schema` antes de cada `query-*` é OBRIGATÓRIO. Nomes canônicos ($pageview, etc.) variam por projeto.

**Pra adicionar insight a dashboard existente:** `insight-create` aceita `dashboards: [<id>]` direto. Não precisa de step separado.

---

## 3. Filtros Globais (aplicar em TODOS insights)

```jsonc
"filters": {
  "properties": {
    "type": "AND",
    "values": [
      {
        "type": "event",
        "key": "is_internal",
        "operator": "exact",
        "value": ["false", false],   // exclui founder/team
        "value_filters": []
      }
    ]
  }
}
```

Exceções (onde `is_internal=true` deve estar incluído):
- Health Check Diário (id 1641528) — quer ver TODOS eventos pra validar instrumentação
- Pipeline B2B — não filtrar (poucos dados)

**Date range padrão**: últimos 30 dias (`-30d`), exceto retention (D1/D3/D7) que usa janela própria.

---

## 4. Schema Verification Checklist

Antes de criar insights, validar que estes events existem (rodar `read-data-schema` events):

### Auth & Onboarding
- `auth_signup_landing_shown`
- `auth_signup_method_chosen` (property: `method` = phone/google/apple/email)
- `auth_login_attempt`
- `auth_signup_started`
- `auth_signup_completed` (property: `method`)
- `auth_login_succeeded` (property: `method` — pode vir "email" em phone signup synthetic)
- `auth_logout`
- `onboarding_step_reached` (property: `step` numeric)
- `onboarding_two_doors_shown`
- `onboarding_started`
- `onboarding_door_chosen` (property: `door` = `upload` | `from_scratch`)
- `onboarding_masking_question_answered`
- `onboarding_pref_step_shown` (property: `step`)
- `onboarding_pref_step_answered` (property: `step`)
- `onboarding_completed`

### Trilha (granular)
- `phase_started` (props: `phase_id`, `phase_title`, `track_id`, `track_title`, `phase_order_index`)
- `phase_step_shown` (props: `phase_id`, `step_id`, `step_index`, `step_type`)
- `phase_step_completed` (props: `phase_id`, `step_id`, `duration_ms`)
- `phase_step_abandoned` (props: `phase_id`, `step_id`, `last_pct`, `duration_ms`)
- `phase_quiz_answered` (props: `phase_id`, `quiz_id`, `q_index`, `correct`, `attempt`)
- `phase_completed` (props: TODAS de phase_started + `time_spent_ms`, `questions_total`, `questions_answered`)
- `trilha_map_shown` (props: `phases_completed`, `phases_total`)
- `trilha_phase_locked_tapped` (prop: `phase_id`)
- `trilha_completed` (props: `total_days`, `phases_count`)
- `trilha_cv_final_downloaded` (props: `template`, `completeness_score`)

### Feed & Jobs
- `feed_opened` (props: `sub_tab` = `para_voce`|`curtidas`, `jobs_in_buffer`)
- `feed_loaded` (props: `sub_tab`, `jobs_count`, `load_duration_ms`, `cache_hit`)
- `feed_load_failed` (props: `sub_tab`, error)
- `job_card_shown`
- `job_swiped` (props: `direction`, `match_score`, `job_id`)
- `job_details_opened` (props: `match_score`, `job_id`)
- `job_details_apply_clicked` (props: `match_score`, `used_adapted_cv`, `job_id`)
- `job_apply_clicked` (props: `match_score`, `used_adapted_cv`, `time_from_download_to_apply_ms`, `job_id`)

### CV Adaptação
- `adapt_intent_clicked`
- `adapt_skills_confirmation_shown`
- `adapt_started`
- `adapt_succeeded` (props: `cached`, `score_before`, `score_after`, `changes_count`, `extra_skills_used`)
- `adapt_failed` (props: `code`, `field`)
- `adapt_pdf_downloaded`
- `cv_adaptation_validator_retry` (prop: `retries`)
- `cv_adaptation_quality_score`

### IA & Cost
- `$ai_generation` (props: `$ai_total_cost_usd`, `$ai_latency`, `$ai_input_tokens`, `$ai_output_tokens`, `$ai_model`)

### Activation milestones
- `activation_milestone_hit` (prop: `milestone` = `first_phase`, `first_swipe`, `first_apply`, etc.)

### Founders contact (Fluxo 9)
- `founders_contact_opened` (prop: `channel` = `whatsapp|phone|email`)

### Push & Notifications
- `push_permission_requested`
- `push_send_initiated`
- `push_send_completed`

### Backend health
- `edge_function_invoked` (props: `function_name`, `status` = `ok|error`, `latency_ms`)
- `llm_call_failed`
- `$exception` (props: `$exception_type`, `$device_model`)

### Acquisition
- `qr_code_scanned` (prop: `source_label`)
- `deep_link_opened` (prop: `source_app`)
- `invite_link_generated`
- `invite_link_opened_inbound`

### Tutorial
- `tutorial_started`
- `tutorial_step_shown` (prop: `step`)
- `tutorial_step_dismissed` (prop: `step`)
- `tutorial_skipped`

### Person/Super Properties (POE mode — frozen no event)
- `flow_version` (`profile_first` = novo)
- `is_internal` (founder/team)
- `is_testflight`
- `app_version`, `app_build`
- `$os_name`, `$os_version`, `$device_model`
- `acquisition_source` (set_once)
- `first_install_source` (set_once)
- `acquisition_channel_first_touch` (set_once)

---

## 5. Dashboards — Lista Completa com IDs

| # | Nome | ID | Prioridade | URL |
|---|---|---|---|---|
| 1 | Ativação (Post-cutover) | 1641531 | 🔴 P0 | [/dashboard/1641531](https://us.posthog.com/project/419792/dashboard/1641531) |
| 2 | Trilha (granular pós-cutover) | 1641534 | 🔴 P0 | [/dashboard/1641534](https://us.posthog.com/project/419792/dashboard/1641534) |
| 3 | CV Adaptado (qualidade IA) | 1641642 | 🔴 P0 | [/dashboard/1641642](https://us.posthog.com/project/419792/dashboard/1641642) |
| 4 | Swipe & Match | 1641532 | 🟡 P1 | [/dashboard/1641532](https://us.posthog.com/project/419792/dashboard/1641532) |
| 5 | Retenção & Cohorts (Post-cutover) | 1641535 | 🟡 P1 | [/dashboard/1641535](https://us.posthog.com/project/419792/dashboard/1641535) |
| 6 | Health Check Diário | 1641528 | 🟢 P2 | [/dashboard/1641528](https://us.posthog.com/project/419792/dashboard/1641528) |
| 7 | Operação (custos, latência, erros) | 1641645 | 🟢 P2 | [/dashboard/1641645](https://us.posthog.com/project/419792/dashboard/1641645) |
| 8 | Canal & Aquisição | 1641646 | 🟢 P2 | [/dashboard/1641646](https://us.posthog.com/project/419792/dashboard/1641646) |
| 9 | Pipeline B2B (proto) | 1641647 | ⚫ P3 | [/dashboard/1641647](https://us.posthog.com/project/419792/dashboard/1641647) |

**Ordem recomendada de execução:** 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9. Após P0+P1, parar pra confirmar com o user antes de seguir P2/P3.

---

## 6. Plano por Dashboard

### 🔴 P0 — Dashboard 1: Ativação (Post-cutover) `id: 1641531`

**Tags:** `pitch`, `ativacao`, `cutover-2026-05`

**Insights a criar:**

1. **Funil macro — Ativação completa**
   - Tipo: `query-funnel`
   - Steps: `auth_signup_completed` → `onboarding_completed` → `job_swiped` (1x) → `job_details_apply_clicked` (1x)
   - Breakdown: `acquisition_source` (set_once)
   - Conversion window: 7 days
   - Date range: `-30d`
   - Display: funnel chart

2. **Cohort funil — Ativação por door**
   - Tipo: `query-funnel`
   - Steps: `auth_signup_completed` → `onboarding_door_chosen` → `onboarding_completed` → `job_swiped` (1x)
   - Breakdown: event property `door` (`upload` vs `from_scratch`)
   - Hipótese: `upload` deve ter conversão maior porque já tem CV, vai direto pra match.

3. **Dropout por step do onboarding**
   - Tipo: `query-trends`
   - Event: `onboarding_step_reached`
   - Breakdown: property `step`
   - Math: `unique_users`
   - Display: `ActionsBar`
   - Date range: `-14d`
   - Pra identificar onde quebra mais.

4. **Edit rate profile_review (qualidade IA)**
   - Tipo: `query-trends`
   - Events: `profile_review_field_edited` / `profile_review_shown`
   - Formula: `A / B * 100` (% de campos editados sobre total review)
   - Display: `BoldNumber` ou `ActionsLineGraph`
   - **CAVEAT:** verificar se esses events existem; se não, criar TODO no doc.

5. **CV completeness score distribuição**
   - Tipo: `query-trends`
   - Event: `cv_completeness_calculated` (ou similar)
   - Property: `completeness_score`
   - Math: `unique_users` por bucket
   - Display: `ActionsBar`
   - **CAVEAT:** verificar event name; pode estar como property em outro event.

6. **Time-from-signup-to-first-swipe (mediana)**
   - Tipo: SQL via `execute-sql`
   - Query: tempo entre `auth_signup_completed` e primeiro `job_swiped` por user
   - Agregação: `quantile(0.5)(diff)` (p50) e p90
   - Display: `BoldNumber` (2 valores: p50 + p90)
   - Date range: `-30d`

---

### 🔴 P0 — Dashboard 2: Trilha (granular pós-cutover) `id: 1641534`

**Tags:** `trilha`, `cutover-2026-05`, `pitch`

**Insights a criar:**

1. **Funil completo da trilha (1 fase como exemplo)**
   - Tipo: `query-funnel`
   - Steps: `phase_started` → `phase_step_shown` → `phase_step_completed` → `phase_completed`
   - Breakdown: `phase_title` (recente — props enriquecidas em 2026-05-28)
   - Conversion window: 1 hour
   - Filtra fases t1_p1 a t5_p10 (ou usa todas).

2. **Time per step (p50/p90) — gargalo de tempo**
   - Tipo: `query-trends`
   - Event: `phase_step_completed`
   - Property: `duration_ms`
   - Math: `median(duration_ms)` e `p90(duration_ms)`
   - Breakdown: `phase_id`
   - Display: `ActionsTable`
   - Slide do pitch: "Trilha educa em X minutos"

3. **Abandonment heat map por step**
   - Tipo: `query-funnel` ou `TwoDimensionalHeatmap`
   - Events: `phase_step_shown` vs `phase_step_completed` por `phase_id` + `step_index`
   - Display: `TwoDimensionalHeatmap` (eixo X = step_index, eixo Y = phase_id, cor = % abandono)
   - Gap caixa-preta pré-cutover — primeira vez visível.

4. **Trilha completion rate (5 trilhas)**
   - Tipo: `query-trends`
   - Event: `trilha_completed`
   - Breakdown: `track_id` ou `track_title`
   - Math: `unique_users`
   - Display: `ActionsBar`
   - Comparar com `auth_signup_completed` no mesmo período pra %.

5. **Days from phase_start to phase_complete (p50)**
   - Tipo: `execute-sql`
   - Query: tempo entre `phase_started` e `phase_completed` matched por user+phase_id
   - Agregação: `quantile(0.5)`
   - Display: `ActionsTable` por phase_title

6. **Quiz pass rate (acertou na 1ª tentativa)**
   - Tipo: `query-trends`
   - Event: `phase_quiz_answered`
   - Filter: `correct=true AND attempt=1`
   - Math: `unique_users` / total `phase_quiz_answered`
   - Formula: A / B * 100
   - Display: `BoldNumber`

7. **Slide pitch — Trilha completa em X min (BoldNumber)**
   - Tipo: `execute-sql`
   - Query: SUM(time_spent_ms) por user que completou T1 (track_id='track_1')
   - Agregação: mediana
   - Display: `BoldNumber` em minutos

---

### 🔴 P0 — Dashboard 3: CV Adaptado (qualidade IA) `id: 1641642`

**Tags:** `cv-adaptado`, `pitch`, `cutover-2026-05`

**Insights a criar:**

1. **Funil CV adaptado**
   - Tipo: `query-funnel`
   - Steps: `adapt_intent_clicked` → `adapt_started` → `adapt_succeeded` → `adapt_pdf_downloaded` → `job_apply_clicked` (filtrado por `used_adapted_cv=true`)
   - Conversion window: 30 min
   - Pitch: "X% dos que adaptam baixam, Y% candidatam"

2. **Anti-invention rate (% adapt_succeeded com retries > 0)**
   - Tipo: `query-trends`
   - Event: `cv_adaptation_validator_retry`
   - Filter: `retries > 0`
   - Math: count / count(`adapt_succeeded`) * 100
   - Display: `BoldNumber` ou `ActionsLineGraph` (queda esperada após bump 2→4 de 2026-05-28)
   - **IMPORTANTE:** Pós-deploy do fix, esperar % cair drasticamente.

3. **Edit rate por seção (proxy qualidade IA)**
   - Tipo: `query-trends`
   - Event: `adapt_section_edited_manually`
   - Breakdown: property `field` (`summary`, `bullets`, `skills`, etc.)
   - Display: `ActionsBar`
   - Quanto maior o edit_rate, pior a qualidade IA naquela seção.

4. **Skill rejected rate**
   - Tipo: SQL
   - Query: count(`adapt_skill_rejected`) / (count(`adapt_skill_rejected`) + count(`adapt_skill_accepted`)) * 100
   - Display: `BoldNumber`
   - Meta: < 10%

5. **Latência adapt p50/p90/p99**
   - Tipo: `query-trends`
   - Event: `$ai_generation` (filter `generationType=cv_adaptation`)
   - Property: `$ai_latency`
   - Math: p50, p90, p99 (3 séries)
   - Display: `ActionsLineGraph`

6. **Custo USD/adapt**
   - Tipo: SQL
   - Query: `sum($ai_total_cost_usd) / count(distinct distinct_id)` por dia (events com `generationType=cv_adaptation`)
   - Display: `ActionsLineGraph`

7. **Score after − Score before distribuição**
   - Tipo: `query-trends`
   - Event: `adapt_succeeded`
   - Compute property: `score_after - score_before`
   - Math: distribution buckets
   - Display: `ActionsBar`
   - Pitch: "Match score sobe em média X pontos"

8. **Adapt-to-apply 24h conversion**
   - Tipo: `query-funnel`
   - Steps: `adapt_pdf_downloaded` → `job_apply_clicked` (mesmo job_id, com `used_adapted_cv=true`)
   - Conversion window: 24 hours
   - Display: funnel chart

---

### 🟡 P1 — Dashboard 4: Swipe & Match `id: 1641532`

**Tags:** `swipe`, `pitch`, `cutover-2026-05`

**Insights a criar:**

1. **Distribuição match_score nos swipes (histograma)**
   - Tipo: `query-trends`
   - Event: `job_swiped`
   - Property: `match_score` em buckets (0-25, 26-50, 51-75, 76-100)
   - Display: `ActionsBar`

2. **Swipe right rate por bucket de match** (AUDIT CRÍTICO — sustenta tese B2B)
   - Tipo: SQL
   - Query: count(`job_swiped` where `direction='right'`) / count(`job_swiped`) por bucket de `match_score`
   - Display: `ActionsBar`
   - Hipótese: users tendem a dar right em jobs com match alto. Se não, modelo de match está quebrado.

3. **Apply rate por bucket de match**
   - Tipo: SQL
   - Query: count(`job_details_apply_clicked`) / count(`job_card_shown`) por bucket
   - Display: `ActionsBar`
   - Mesma hipótese.

4. **Time on card por bucket**
   - Tipo: SQL
   - Query: median(time between `job_card_shown` e próximo `job_swiped`) por bucket
   - Display: `ActionsBar`
   - Hipótese: cards com match alto recebem mais tempo de leitura.

5. **Bursts de swipe (esmagador detection)**
   - Tipo: `query-trends`
   - Event: `job_swiped`
   - Math: count por minuto por user
   - Filter: count > 5 por minuto
   - Display: `ActionsLineGraph`
   - Detecta usuários "esmagando" sem ler.

6. **Revisited rate (curtidas → ver de novo)**
   - Tipo: SQL
   - Query: count(`job_details_opened` from sub_tab='curtidas') / count(`job_swiped` direction='right') 
   - Display: `BoldNumber`

7. **Feed loaded p50/p90 load_duration_ms**
   - Tipo: `query-trends`
   - Event: `feed_loaded`
   - Property: `load_duration_ms`
   - Math: p50, p90
   - Display: `ActionsLineGraph`
   - Meta: p50 < 2s, p90 < 5s

8. **Feed exhausted rate**
   - Tipo: `query-trends`
   - Event: `feed_exhausted` ou `feed_loaded` com `jobs_count=0`
   - Math: unique_users
   - Display: `BoldNumber`

9. **Funil feed → apply com match_score**
   - Tipo: `query-funnel`
   - Steps: `feed_opened` → `job_card_shown` → `job_details_opened` → `job_details_apply_clicked`
   - Breakdown: bucket de `match_score`
   - Conversion window: 1 day

---

### 🟡 P1 — Dashboard 5: Retenção & Cohorts (Post-cutover) `id: 1641535`

**Tags:** `pitch`, `retencao`, `cutover-2026-05`

**Insights a criar:**

1. **D1 retention pós-cutover**
   - Tipo: `query-retention`
   - Cohortizing event: `auth_signup_completed`
   - Returning event: `app_opened`
   - Period: 1 day
   - Total periods: 30
   - Display: retention grid

2. **D3 retention**
   - Como D1 mas period=3 days

3. **D7 retention**
   - Como D1 mas period=7 days

4. **Stickiness DAU/MAU**
   - Tipo: `query-stickiness`
   - Event: `app_opened`
   - Period: 30 days
   - Display: stickiness bars

5. **Active days last 7 distribution**
   - Tipo: `query-stickiness`
   - Event: `app_opened`
   - Period: 7 days
   - Compute: histogram of users by # of active days

6. **Dormant cohort growth**
   - Tipo: `query-trends`
   - Event: `app_opened`
   - Filter: NOT seen in last 14 days
   - Math: unique_users
   - Display: `ActionsLineGraph`

7. **Resurrected após push**
   - Tipo: `query-funnel`
   - Steps: `push_send_completed` → `app_opened` (mesmo distinct_id, dentro de 4h)
   - Display: funnel
   - Conversion window: 4 hours

8. **Sessão média p50/p90**
   - Tipo: SQL ou `query-trends` com event session-level
   - Query: median e p90 de `session_duration_ms`
   - Display: `BoldNumber`

9. **Sessions antes vs depois de push**
   - Tipo: SQL
   - Query: contar sessões/user nas 24h antes vs nas 24h depois de `push_send_completed`
   - Display: `ActionsTable`

---

### 🟢 P2 — Dashboard 6: Health Check Diário `id: 1641528`

**Tags:** `cutover-2026-05`, `ops`

**Insights a criar:**

1. **Eventos emitidos/hora (todos)**
   - Tipo: `query-trends`
   - All events
   - Math: `total_count`
   - Interval: hour
   - Display: `ActionsLineGraph`
   - Detecta queda anômala.

2. **% users com `is_internal=true`**
   - Tipo: SQL
   - Query: count(distinct_id where is_internal=true) / count(distinct_id total)
   - Display: `BoldNumber`
   - Sanity check do filtro.

3. **Pre-cutover vs Post-cutover growth**
   - Tipo: `query-trends`
   - Event: `auth_signup_completed`
   - Breakdown: `flow_version`
   - Display: `ActionsAreaGraph`

4. **Edge function error rates**
   - Tipo: `query-trends`
   - Event: `edge_function_invoked`
   - Filter: `status=error`
   - Breakdown: `function_name`
   - Display: `ActionsLineGraph`

5. **Crash rates ($exception)**
   - Tipo: `query-trends`
   - Event: `$exception`
   - Math: unique_users
   - Breakdown: `$device_model`
   - Display: `ActionsLineGraph`

6. **Permission denied rates**
   - Tipo: `query-trends`
   - Event: `push_permission_requested` filtrar resposta=denied
   - Math: unique_users
   - Display: `BoldNumber`

---

### 🟢 P2 — Dashboard 7: Operação (custos, latência, erros) `id: 1641645`

**Tags:** `ops`, `cutover-2026-05`

**Insights a criar:**

1. **Custo OpenAI por DAU**
   - Tipo: SQL
   - Query: `sum($ai_total_cost_usd) / count(distinct distinct_id where event='app_opened')` por dia
   - Display: `ActionsLineGraph`

2. **Latência edge_function_invoked p50/p90**
   - Tipo: `query-trends`
   - Event: `edge_function_invoked`
   - Property: `latency_ms`
   - Math: p50 + p90 (2 séries)
   - Breakdown: `function_name`
   - Display: `ActionsLineGraph`

3. **Taxa de erro edge_function por dia**
   - Tipo: `query-trends`
   - Event: `edge_function_invoked`
   - Filter: `status=error`
   - Breakdown: `function_name`
   - Display: `ActionsLineGraph`

4. **LLM error rate**
   - Tipo: `query-trends`
   - Event: `llm_call_failed`
   - Math: total_count
   - Display: `ActionsLineGraph`

5. **$exception rate por device_model**
   - Tipo: `query-trends`
   - Event: `$exception`
   - Breakdown: `$device_model`
   - Math: unique_users
   - Display: `ActionsBar`

6. **Apify sync success rate**
   - Tipo: SQL
   - Query: count(`apify_sync_completed`) / count(`apify_sync_started`) * 100
   - Display: `BoldNumber`

7. **Push send rate**
   - Tipo: SQL
   - Query: count(`push_send_completed`) / count(`push_send_initiated`) * 100
   - Display: `BoldNumber`

8. **Daily report sent count**
   - Tipo: `query-trends`
   - Event: `daily_report_sent` (verificar nome exato)
   - Math: total_count
   - Display: `ActionsLineGraph`

---

### 🟢 P2 — Dashboard 8: Canal & Aquisição `id: 1641646`

**Tags:** `cutover-2026-05`, `growth`

**Insights a criar:**

1. **Installs por acquisition_source**
   - Tipo: `query-trends`
   - Event: `app_opened` filter primeira sessão
   - Breakdown: person.properties.`first_install_source`
   - Display: `ActionsBar`

2. **Funil ativação por canal**
   - Tipo: `query-funnel`
   - Steps: `auth_signup_completed` → `onboarding_completed` → `job_swiped` → `job_details_apply_clicked`
   - Breakdown: person.`acquisition_channel_first_touch`
   - Conversion window: 7 days

3. **Retention curve D1/D3/D7 por canal**
   - Tipo: `query-retention`
   - Cohort: `auth_signup_completed`
   - Returning: `app_opened`
   - Breakdown: `acquisition_source`

4. **QR code scanned por source_label**
   - Tipo: `query-trends`
   - Event: `qr_code_scanned`
   - Breakdown: `source_label`
   - Math: total_count
   - Display: `ActionsBar`

5. **Deep link opened por source_app**
   - Tipo: `query-trends`
   - Event: `deep_link_opened`
   - Breakdown: `source_app`
   - Display: `ActionsBar`

6. **First session attribution**
   - Tipo: SQL
   - Query: count(distinct distinct_id) por person.`acquisition_source` first_touch
   - Display: `ActionsTable`

7. **K-factor proxy (invite_link)**
   - Tipo: SQL
   - Query: count(`invite_link_opened_inbound`) / count(`invite_link_generated`)
   - Display: `BoldNumber`

8. **Custo CPI Meta (anotação manual)**
   - Tipo: text tile via `dashboard-create-text-tile`
   - Conteúdo: link pra planilha de spend + tabela manual

---

### ⚫ P3 — Dashboard 9: Pipeline B2B (proto) `id: 1641647`

**Tags:** `cutover-2026-05`, `b2b`, `pitch`

**⚠️ DEPENDÊNCIA:** Esses insights dependem de `group=company` estar wired no PostHog. **Verificar primeiro** se `b2b_candidate_viewed` e companies como groups estão emitindo. Se não, marcar dashboard como "Aguardando emissão de groups" e adicionar text tile explicando.

**Se groups OK, criar:**

1. **Top 10 empresas com candidato match > 70 que aplicaram últimos 30d**
   - Tipo: SQL
   - Query: GROUP BY company, COUNT(distinct user where match_score>70 and applied)
   - LIMIT 10
   - Display: `ActionsTable`

2. **Vagas com 0 swipes em 7d**
   - Tipo: SQL
   - Display: `BoldNumber`

3. **Apply rate por empresa (top 50)**
   - Tipo: SQL
   - Display: `ActionsTable`

4. **Distribuição candidatos por bucket de match dentro de cada empresa (top 20)**
   - Tipo: SQL / heatmap
   - Display: `TwoDimensionalHeatmap`

5. **Cidades com maior concentração**
   - Tipo: SQL
   - Display: `ActionsTable`

6. **Tempo médio apply → empresa visualizar** (precisa `b2b_candidate_viewed`)
   - Tipo: SQL
   - Display: `BoldNumber`

**Se groups NÃO estiver emitindo:**
- Criar text tile no dashboard explicando: "Aguardando emissão de groups company — ver pendência em [[ARQUIVO]]"
- Pular dashboard, reportar ao user.

---

## 7. Checkpoints & Reportes

**Após cada dashboard P0 (3 primeiros):** parar, reportar ao user via mensagem curta (qual dashboard, quantos insights criados, links de cada). Aguardar OK pra seguir.

**Após P1 (mais 2):** mesma coisa.

**P2/P3:** só executar se user pedir explicitamente após P0+P1.

**Format de report sugerido:**
```
✅ Dashboard X (id: Y) populado:
- Insight A (id: short_id) — descrição curta
- Insight B (id: short_id) — descrição curta
...
URL: /dashboard/Y
Próximo: Dashboard Z
```

---

## 8. Caveats Conhecidos

1. **POE mode**: ao filtrar por `person.properties.*`, valores são do momento de ingest, não atuais. Pra cohort signup, prefira `set_once` properties (first_*).
2. **Synthetic email no phone signup**: `method=email` em `auth_login_succeeded` quando origem é phone. Documentado em memória `[[phone_signup_synthetic]]`.
3. **flow_version "profile_first"**: marca o cutover. Use pra cortar pre vs post.
4. **`is_internal=true`**: filtros do founder (zac) e team — sempre excluir EXCETO no Health Check.
5. **Eventos que podem não existir ainda** (verificar com `read-data-schema` antes):
   - `profile_review_field_edited` / `profile_review_shown` (Ativação #4)
   - `cv_completeness_calculated` (Ativação #5)
   - `adapt_section_edited_manually` (CV Adaptado #3)
   - `adapt_skill_rejected` / `adapt_skill_accepted` (CV Adaptado #4)
   - `feed_exhausted` (Swipe #8)
   - `b2b_candidate_viewed` (Pipeline B2B)
   - `daily_report_sent` (Operação #8)
   - Groups `company` (Pipeline B2B)
   
   Se não existirem, criar TODO list ao final do report.

6. **Phone signup synthetic email** já tratado — não tratar como bug, só documentar nos insights de método.

7. **Cohort "Post-cutover"**: pode ser definida como `flow_version = 'profile_first'` OR `timestamp >= '2026-05-06'`. Criar cohort dinâmica antes de começar P0 se ainda não existe.

---

## 9. Ordem de Execução Resumida

```
PHASE 1 (P0 — Demo Day pitch críticos):
[ ] Verificar schema de todos events listados na seção 4
[ ] Criar cohort "Post-cutover" se necessário
[ ] Dashboard 1: Ativação — 6 insights
[ ] CHECKPOINT 1 (reportar)
[ ] Dashboard 2: Trilha — 7 insights
[ ] CHECKPOINT 2 (reportar)
[ ] Dashboard 3: CV Adaptado — 8 insights
[ ] CHECKPOINT 3 (reportar)

PHASE 2 (P1 — pitch secundário):
[ ] Dashboard 4: Swipe & Match — 9 insights
[ ] Dashboard 5: Retenção & Cohorts — 9 insights
[ ] CHECKPOINT 4 (reportar)
[ ] AGUARDAR aprovação pra P2/P3

PHASE 3 (P2 — ops):
[ ] Dashboard 6: Health Check — 6 insights
[ ] Dashboard 7: Operação — 8 insights
[ ] Dashboard 8: Canal & Aquisição — 8 insights

PHASE 4 (P3 — depende de groups):
[ ] Verificar groups company
[ ] Dashboard 9: Pipeline B2B — 6 insights (se groups OK)
```

**Total estimado:** ~67 insights, 5-8h de trabalho focado, ~5-10 chamadas MCP por insight.

---

**Fim do plano.** Boa execução.
