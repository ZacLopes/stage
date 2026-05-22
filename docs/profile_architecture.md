# Profile-First Architecture

Versão: Semana 1 (2026-05-22)

## Por que existe

Até a Semana 1, todo dado pessoal do usuário vivia em
`user_profiles.gamification_data.imported_resume.parsed` — um JSONB
aninhado. Isso barateou a iteração inicial mas trouxe limitações:

- **Sem queries diretas**: filtrar "usuários com experiência em fintech" exige
  varrer JSONBs em runtime, sem índices.
- **Edição granular complicada**: a Semana 2 vai trazer telas de revisão
  por campo. Editar um bullet num JSONB aninhado vs um campo em tabela
  relacional é cirurgia vs cinto de utilidades.
- **Schema implícito**: campos novos (gender, age_range, phone country code,
  confidence per-item) não tinham lugar consistente, gerando drift entre
  uploads.

A migração profile-first cria 18 tabelas relacionais que armazenam o
mesmo conteúdo, com schema explícito + RLS + índices. Durante a Semana 1
o JSONB legacy continua sendo escrito em paralelo (dual-write) pra preservar
`adapt-resume-to-job`, `generate-resume` e o cliente Flutter.

## Diagrama (ASCII)

```
┌─────────────────────────────────────────────────────────────────────┐
│  auth.users (Supabase)                                              │
└────┬────────────────────────────────────────────────────────────────┘
     │
     │ user_id (PK em personal/preferences, FK nas demais)
     │
     ├──→ profile_personal              (1:1)
     │
     ├──→ profile_experiences (1:N) ──→ profile_bullets (1:N)
     │
     ├──→ profile_education   (1:N) ──┬─→ profile_education_majors    (1:N)
     │                                 ├─→ profile_education_minors    (1:N)
     │                                 └─→ profile_education_activities (1:N)
     │
     ├──→ profile_languages         (1:N)
     ├──→ profile_skills            (1:N) — UNIQUE (user_id, LOWER(name))
     ├──→ profile_certifications    (1:N)
     ├──→ profile_projects          (1:N)
     ├──→ profile_interests         (1:N) — UNIQUE (user_id, LOWER(name))
     ├──→ profile_awards            (1:N)
     ├──→ profile_coursework        (1:N)
     │
     ├──→ profile_job_preferences          (1:1)
     ├──→ profile_desired_titles           (1:N)
     ├──→ profile_application_countries    (1:N) — UNIQUE (user_id, country_code)
     ├──→ profile_other_locations          (1:N)
     │
     └──→ profile_extraction_logs   (1:N) ──→ ai_generation_logs (FK opcional)
              [SEM RLS POLICIES — service-role apenas]
```

Total: 18 tabelas (15 com policies, 3 com policies via parent: bullets +
education_majors/minors/activities, 1 sem policy: extraction_logs).

## Fluxo upload → extract → save

```
Flutter (cv_import_service.dart)
    │
    │ supabase.functions.invoke('extract-profile', {pdf_base64, raw_text_fallback})
    ▼
┌────────────────────────────────────────────────────────────────┐
│ extract-profile (edge function)                                │
│                                                                │
│  1. cache check (parser_source === CURRENT_EXTRACTOR_VERSION) │
│  2. detect non-CV (rejeita extratos, docs governamentais)      │
│  3. GPT-4o + PROFILE_JSON_SCHEMA (Structured Outputs)         │
│  4. pós-processamento determinístico                           │
│  5. anti-invenção (flatten + isInCv)                           │
│  6. computa confidence_global + completeness_score             │
│  7. log em ai_generation_logs                                  │
│  8. toLegacyResume(profile_data) → subset compatível           │
│  9. update user_profiles.gamification_data.imported_resume      │
│     (JSONB legacy — mantém adapt-resume-to-job/generate-resume)│
│ 10. invoke('save-profile', {profile_data, user_id})  ◄─SÍNCRONO│
│ 11. log em profile_extraction_logs (FK ai_generation_log_id)   │
│ 12. captureEvent (profile_extraction_completed)                │
│ 13. trackAIGeneration ($ai_generation)                         │
│                                                                │
└────────────────────────────────────────────────────────────────┘
            │
            │ POST /functions/v1/save-profile
            ▼
┌────────────────────────────────────────────────────────────────┐
│ save-profile (edge function)                                   │
│                                                                │
│  1. auth (service-role ou JWT)                                 │
│  2. supabaseAdmin.rpc('save_profile_from_json',                │
│         {p_user_id, p_data})                                   │
│                                                                │
└────────────────────────────────────────────────────────────────┘
            │
            │ RPC PL/pgSQL (transactional)
            ▼
┌────────────────────────────────────────────────────────────────┐
│ save_profile_from_json (SECURITY DEFINER, GRANT service_role) │
│                                                                │
│  upsert profile_personal                                       │
│  DELETE+INSERT (modo replace):                                 │
│    profile_experiences (+ profile_bullets)                     │
│    profile_education (+ majors/minors/activities)              │
│    profile_languages, profile_skills, profile_certifications   │
│    profile_projects, profile_interests, profile_awards         │
│    profile_coursework                                          │
│  upsert profile_job_preferences (+ titles/countries/locations) │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

## Observabilidade — matriz de estados de falha

Implementada literalmente no try/catch de
[supabase/functions/extract-profile/index.ts](../supabase/functions/extract-profile/index.ts).

| Cenário | `ai_generation_logs` | `profile_extraction_logs` | `imported_resume.parsed` | Tabelas relacionais | HTTP |
|---|---|---|---|---|---|
| OpenAI falha (network/timeout/non-2xx) | — | `status='failed'`, `error_message`, FK NULL | inalterado | inalteradas | 502/504 |
| OpenAI retorna mas JSON inválido | linha completa | `status='failed'`, `raw_json_output=<raw>`, `error_message='json_parse'`, FK preenchida | inalterado | inalteradas | 502 |
| Validação anti-invenção crítica (≥3 fails) | linha completa | `status='partial'`, `raw_json_output`, `error_message`, FK preenchida | inalterado | inalteradas | 422 |
| Tudo OK até save-profile, save-profile falha | linha completa | `status='success'`, `raw_json_output`, FK preenchida | **atualizado** | **ausentes (alarme via PostHog)** | dev: 500 / prod: 200 |
| Tudo OK end-to-end | linha completa | `status='success'`, `raw_json_output`, FK preenchida | atualizado | populadas | 200 |

Eventos PostHog emitidos:
- `$ai_generation` (via `trackAIGeneration`) — sempre
- `profile_extraction_attempted` — antes de chamar OpenAI
- `profile_extraction_completed` — sucesso
- `profile_extraction_failed` — falha (com `error_stage` ∈ {openai, json_parse, validation})
- `save_profile_failed` — quando save-profile retorna erro mas JSONB foi gravado

### Queries operacionais úteis

```sql
-- Saúde geral: últimas 20 extrações
SELECT pel.created_at, pel.status, pel.confidence_global,
       array_length(pel.low_confidence_fields::text[]::text[], 1) AS low_conf_count,
       agl.input_tokens, agl.output_tokens
FROM profile_extraction_logs pel
LEFT JOIN ai_generation_logs agl ON agl.id = pel.ai_generation_log_id
ORDER BY pel.created_at DESC LIMIT 20;

-- Falhas recentes — usa índice parcial idx_profile_extraction_logs_status
SELECT created_at, status, error_message, user_id
FROM profile_extraction_logs
WHERE status != 'success'
ORDER BY created_at DESC LIMIT 30;

-- Extrações de baixa confiança — usa índice parcial idx_..._low_confidence
SELECT created_at, confidence_global, low_confidence_fields, user_id
FROM profile_extraction_logs
WHERE confidence_global IS NOT NULL AND confidence_global < 0.7
ORDER BY confidence_global ASC LIMIT 30;

-- Dual-write desincronizado: usuários com JSONB legacy mas sem profile_personal
-- (sinaliza save-profile falhando em produção)
SELECT up.id, (up.gamification_data->'imported_resume'->>'parsed_at')::timestamptz
FROM user_profiles up
LEFT JOIN profile_personal pp ON pp.user_id = up.id
WHERE up.gamification_data->'imported_resume' ? 'parsed'
  AND pp.user_id IS NULL;
```

## Versionamento do extrator

`CURRENT_EXTRACTOR_VERSION` é uma constante no topo de
[extract-profile/index.ts](../supabase/functions/extract-profile/index.ts).
Quando o `PROFILE_SYSTEM_PROMPT` ou o `PROFILE_JSON_SCHEMA` mudam de forma
não-trivial, bumpe a versão (`v1.0` → `v1.1`). Isso:

1. Invalida automaticamente o cache (usuários que re-uploadarem o mesmo CV
   passarão pela nova extração).
2. Marca o `parser_source` do `imported_resume` com a versão usada, dando
   rastreabilidade.

Critérios de bump:
- **Patch (v1.0.x)**: ajuste cosmético no prompt (reformulação, exemplo
  novo) sem alterar campos extraídos.
- **Minor (v1.x.0)**: nova categoria adicionada ao schema (ex: salário
  esperado), ou regra de extração alterada (ex: agora separar middle_name).
- **Major (vx.0.0)**: refator estrutural do schema.

Não usar SemVer real (com `.`) — só bump linear pra simplificar comparação
de string.

## Como ajustar o prompt

1. Edite `PROFILE_SYSTEM_PROMPT` em
   [_shared/profile_schema.ts](../supabase/functions/_shared/profile_schema.ts).
2. Bumpe `CURRENT_EXTRACTOR_VERSION` em `extract-profile/index.ts`.
3. Rode o golden set:
   ```bash
   cd career_gamification/golden_set
   deno run --allow-env --allow-net --allow-read --allow-write scripts/run_extraction.ts
   deno run --allow-read scripts/compare.ts
   ```
4. Verifique:
   - **CVs adversariais 100% pass** (bloqueante, `compare.ts` retorna exit 1 se não)
   - Confidence_global médio > 0.7
   - % campos corretos por seção > 70%
5. Se OK, deploy:
   ```bash
   supabase functions deploy extract-profile
   ```

## Como adicionar uma nova categoria ao perfil

Exemplo: adicionar "Voluntariado".

1. **Migration**: criar `20YYMMDDhhmmss_profile_volunteering.sql` com a
   tabela `profile_volunteering` (RLS habilitada).
2. **Migration de policies**: adicionar as 4 policies à `profile_rls_policies`
   ou criar uma migration nova de policies.
3. **Schema rico**: adicionar `volunteering` ao `PROFILE_JSON_SCHEMA` em
   [_shared/profile_schema.ts](../supabase/functions/_shared/profile_schema.ts).
4. **save_profile_from_json**: adicionar o loop de INSERT na função
   PL/pgSQL (migration nova com `CREATE OR REPLACE FUNCTION`).
5. **`toLegacyResume`**: decidir se a nova categoria entra no JSONB legacy
   ou não. Se sim, mapear.
6. **Cliente Flutter**: na Semana 2, adicionar widget na tela de revisão.
7. **Bump `CURRENT_EXTRACTOR_VERSION`**.
8. **Golden set**: adicionar 2-3 CVs que exercitam o campo novo.

## Operações

### Setup inicial

```bash
# Aplicar migrations (em staging primeiro)
supabase db push --linked

# Setar env var pra failure handling
supabase secrets set ENVIRONMENT=production

# Deploy edge functions
supabase functions deploy extract-profile save-profile
```

Verifique que os secrets a seguir já estão presentes (devem estar — vêm
das outras edge functions):
- `OPENAI_API_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `POSTHOG_API_KEY`

### PostHog LLM Analytics evaluation (manual, pós-deploy)

Configure no UI:
1. PostHog → LLM Analytics → Evaluations → Create
2. Type: `llm_judge`
3. Filter: `event = '$ai_generation' AND generation_type = 'profile_extraction'`
4. Model: `gpt-4o-mini`
5. Prompt do juiz (cole no UI):
   ```
   Você está avaliando uma extração de CV em JSON.

   Input do CV (raw_text): {raw_text}
   Output gerado (JSON): {json_output}

   Pontue de 0 a 100 considerando:
   1. Todos os campos importantes do CV foram extraídos? (40 pontos)
   2. Datas estão no formato YYYY-MM-DD correto? (15 pontos)
   3. Bullets preservam texto original? (15 pontos)
   4. Nada foi inventado? (15 pontos)
   5. Confidence_global parece adequado ao quão claro o CV estava? (15 pontos)

   Retorne só um número.
   ```

### Rotação de SUPABASE_SERVICE_ROLE_KEY

**Pendência da Semana 1**: ao fim da semana, rotacionar a service-role key.
Razão: durante o desenvolvimento e setup do golden set, a chave passou por
`.env` local e potencialmente pelo histórico do shell.

Procedimento:
1. Dashboard Supabase → Project Settings → API → Reset service-role key
2. Atualizar `SUPABASE_SERVICE_ROLE_KEY` em todos os secrets de edge
   functions: `supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<nova>`
3. Atualizar `.env` local
4. Atualizar `.env` do golden_set (se separado)
5. Verificar que `pg_cron` jobs ainda funcionam (alguns usam a key via
   Vault `cron_secret_*`)

### Rollback de extract-profile

Se a nova função quebrar produção:

1. **Reverter cliente Flutter**: trocar `'extract-profile'` por `'parse-cv-pdf'`
   em [cv_import_service.dart](../lib/services/cv_import_service.dart) e
   publicar versão do app.
2. **OU manter `extract-profile` deployada mas degradada**: substituir
   o corpo de `extract-profile/index.ts` por um proxy que chama
   `parse-cv-pdf` internamente.

O segundo é mais rápido pra reverter em produção (sem release de app).

## Tech debt registrada

- **Modo replace** em `save_profile_from_json`: deleta tudo e re-insere.
  OK na Semana 1 (sem edição manual). **Semana 2**: trocar pra merge
  inteligente (preservar campos editados manualmente).
- **`parse-cv` text-only** ainda popula só JSONB legacy quando rasterização
  PDF falha no Flutter. Idealmente migrar ele também ou descontinuar quando
  todos os uploads forem garantidos como PDF.
- **`parse-cv-pdf` deprecated**: manter até confirmar 2-3 semanas de
  estabilidade em produção, então deletar a função e a pasta.
- **Adversariais do golden set**: começar com 5-10 e expandir conforme
  bugs em produção forem detectados via `profile_extraction_logs`.
