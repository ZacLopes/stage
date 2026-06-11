# PLANO-FASE-1: A espinha de dados (applications, preferências, instituições, busca de candidatos)

**Status:** aprovado pelo fundador em 2026-06-10 (revisão com arquiteto externo; 3 correções obrigatórias da lupa + ajustes menores, todos incorporados).
**Branch:** `fase-1-espinha-de-dados` (empilhada sobre `fase-0-seguranca` — F0 ainda não mergeada; rebase em main após o merge da F0).

## Contexto

A Fase 1 cria a entidade que todas as frentes seguintes penduram (`applications` + `application_events` com máquina de estados), elege fontes únicas de verdade (preferências, gate de onboarding), normaliza instituições e destrava a operação comercial (busca de candidatos + shortlists). Executa T1.0–T1.8 do plano-mãe com os ajustes A1–A4 do arquiteto pós-Fase 0. Princípio: tudo aditivo, backfills idempotentes, **nenhuma revogação de escrita nas legacy nesta fase** — a 2.0.0/2.1.0 continuam funcionando.

---

## V — Verificações de plan mode (fatos, executados em 2026-06-10 ~10:00–10:40 BRT)

**V1 — Drift de functions (B1):** baixadas as 27 deployadas (`supabase functions download` em /tmp, isoladas por bundle) e difadas contra o repo. Resultado:

| Grupo | Functions | Natureza do diff | Resolução T1.0 |
|---|---|---|---|
| Iguais (13) | adapt-resume-to-job, analyze-match, admin-* (7), sync-jobs-apify, sync-jobs-brazil, generate-resume, notify-signup, notify-auto-apply-swipe | — | nada |
| Repo à frente: wrapper `withEdgeAnalytics` nunca deployado (6) | extract-job-skills (6 l.), generate-bullets (4), generate-summary (4), suggest-tools (6), notifications-daily-digest (6), extract-profile (31 — wrapper + instrumentação de 30/05) | **`edge_function_invoked` NÃO é emitido por elas em prod** (auditoria J3 descrevia o repo, não o deployado) | revisar diff + **deployar repo** (consciente) |
| Repo à frente: conteúdo real (2) | daily-report (105 l. — queries.ts com education majors de 01/06), notifications-broadcast (70 l. — eventos push_send_*) | deploys atrasados vs commits de 30/05–01/06 | revisar diff + **deployar repo** |
| Deprecated, header-only (3) | parse-cv (26), parse-cv-pdf (13), generate-profile (7) — diffs = headers DEPRECATED da F0 + wrapper | sem valor comportamental | **não redeployar** (allowlist do script) |
| Falso drift (docs não-bundladas) | README.md (daily-report), SETUP.md (ingest-jobs-email), sources/types.ts (sync-jobs-ats) | artefatos do repo que o bundler não embarca | allowlist do script |

**Direção:** em TODOS os casos reais o deployado está ATRÁS do repo (deploys atrasados; não houve edição via dashboard). A regra do arquiteto ("deployado = verdade comportamental") se resolve aqui como: revisar cada diff e deployar o repo conscientemente — o repo é o estado desejado documentado em commits.

**V2 — Schemas lado a lado (B2):**
- `user_preferences`: id, user_id, `areas text[]`, `locations text[]` (cidades soltas: "São Paulo" 178, "Rio de Janeiro" 29...), `work_models text[]` **em PT** (remoto/hibrido/presencial), `job_types text[]`, `min_salary int`, `min_match_score int`, updated_at.
- `profile_job_preferences` (PK user_id): primary_location_{country,state,city,postal,lat,lng,radius_km}, `experience_level text[]`, `work_mode text[]` **em EN** (remote/hybrid/in_person), `job_types text[]`, updated_at. **Não tem** areas/min_salary/min_match_score.
- **Fato que muda o D2:** o app já materializa a fonte nova assim (`jobs_viewmodel.dart:477-575`): `areas` ← **`profile_desired_titles.title`** (que contém ÁREAS: "Tecnologia" 537, "Administrativo" 437... — desvio da auditoria K3, que dizia que desired_titles não alimentava o feed); `locations` ← primary_location_city + `profile_other_locations.city`; `work_mode` EN→PT já traduzido no client (linhas 528-540); **min_salary deliberadamente fora da identidade** (comentário no código, decisão do fundador 2026-05-27 — filtros viraram temporários/locais).

**V3 — Escrita legacy de prefs está MORTA (mata a ponte da A2.1):** `savePreferences` é local-only desde 27/05 (`jobs_viewmodel.dart:855-877`, comentário explícito "NÃO escreve no Supabase"); banco confirma: **`user_preferences` = 0 escritas em 7 dias** (as 469 "em 30d" são um touch coletivo antigo, não tráfego). `PreferencesRepository` é injetado (`main.dart:265`) mas sem caller de escrita. → **T1.5 vira merge one-shot + remoção de código morto; SEM trigger-ponte de prefs** (monitoramento semanal via query cobre o risco residual de builds 1.x).

**V4 — Campaigns e applied estão VIVOS (pontes obrigatórias):** `campaigns` 387 criadas/7d (todo onboarding atual cria — `onboarding_complete_screen.dart:46`); `swipe_actions.applied` 81 sets/7d. Pontes A2.2/A3 confirmadas necessárias.

**V5 — Estado dos applied (B4):** 493 applied=true; `applied_at` null = 0; **343 (69%) apontam pra jobs `is_active=false`** (badge "Expirada" é urgente); 0 jobs deletados; por método: 484 url / 9 email.

**V6 — Dry-run do merge (B3):** 470 users em `user_preferences`, 1.112 em `profile_job_preferences`, 378 em ambas, 92 só legacy, 734 só nova. Conflitos: job_types **0** (vocabulário compartilhado); "work" 186 — mas é majoritariamente tradução PT↔EN, não conflito real; up mais novo que pjp: só 3 users. **Ganho real do merge (one-shot):** 19 users ganham áreas, 33 ganham localização, 27 ganham work_mode, 21 ganham job_types. min_salary (80 users) e min_match_score (34) **morrem conscientemente** (decisão de 27/05 já tomada).

**V7 — Builds em produção (A2.2/B):** últimos 7d no PostHog: **2.1.0 = 1.092 users (97% dos eventos)** — houve release 2.1.0 não registrada nos relatórios ("prod = 2.0.0+2" está desatualizado; corrigir em FASE-0-RELATORIO na implementação); 2.0.0 = 41 users; 2.2.0 = 7 (devs). Builds 1.x: sem eventos da taxonomia nova.

**V8 — Instituições (B6):** `user_profiles` **não tem coluna university** (desvio da auditoria G7) — instituição vive em `profile_education.institution` (texto livre, **2.288 rows reais**; estimativa da auditoria, 135, era n_live_tup defasado). Top: USP 65, Anhanguera 53, "Ensino Médio*" ~95 (nível, não instituição — distinguível por `education_level`), UNICAMP 28, Estácio 25+8, fragmentação de variantes (UNIP 15+11+8; Cruzeiro do Sul 13+12; SENAI 15+12). **`unaccent` NÃO instalada** → migration cria. Match estimado do seed (32 nomes, containment cru): 34% global, **50,4% nas rows `education_level='college'`** (522/1.035; null=1.150 com 22%; school=103 com 0 por design). → Critério do plano-mãe ("≥70% das strings históricas") revisado com evidência: **meta ≥70% das rows `college`** via aliases + passada no top-100 de valores distintos; % global reportado no relatório.

**V9 — Esqueleto B2B (B7):** `candidate_list_requests` (client_id, source_job_id, title, area, requirements[], location, work_model, job_type, min_score, status, created_by) + `candidate_list_items` (request_id, user_id, score, rank, score_breakdown, status, notes) + `candidate_list_exports` (request_id, exported_by, format, exported_fields[], candidate_count) — **servem à T1.8 sem alteração**. `candidate_data_sharing_consents` (user_id, status, status_reason, granted_at, revoked_at, updated_by_admin) **não tem `granted_via` nem escopo** → migration adiciona (decisão do fundador, V12). Padrão admin confirmado (`_shared/admin.ts`): `requireAdmin` (JWT + `admin_users`, roles owner/analyst), `jsonResponse/errorResponse`, service role.

**V10 — Admin dashboard (B8):** Vite + React, roda local com `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY` (`admin_dashboard/src/lib/supabase.ts:3-4`), `npm run dev`. Nav hardcoded em `src/app/Layout.tsx:5`; páginas em `src/features/{overview,users,jobs,clients,candidate-lists}/`; API helper em `src/lib/api.ts`. Página nova: `src/features/candidates/CandidatesSearchPage.tsx` + entrada no nav.

**V11 — Testes (B9):** **Docker NÃO instalado** → sem `supabase start`/shadow DB local. Testes de banco (matriz de transições — incluindo retrocesso-por-design e o caminho service-role da Bridge 1 —, imutabilidade de colunas, pontes com INSERT mínimo em profile_personal, idempotência dos backfills) viram **script SQL transacional `BEGIN…ROLLBACK`** com asserts (`DO $$ ... RAISE EXCEPTION`), executado contra prod na implementação (rollback = zero efeito), colado no relatório. Disciplina dos testes: **transações curtas** e **nunca tocar `user_profiles` dentro deles** (trigger de http `notify_new_signup` dispararia webhook real); sequences avançadas pelo rollback são inofensivas. Lógica client: testes Dart normais.

**V12 — RLS/triggers reutilizáveis (B10):** padrão own-CRUD 4-policies confirmado (auditoria C2, `pg_policies`); `update_updated_at_column()` reutilizável (já usada por 6 tabelas). Conta interna de teste: `internal-fase0-test@stage.app` (user `3eaf8faa-…`), instrumento dos e2e.

### Desvios registrados (auditoria/plano-mãe × fato — "o fato vence")
1. A2.1 (ponte de prefs) **desnecessária** — escrita legacy morta desde 27/05 (V3).
2. Auditoria K3: desired_titles **alimenta sim** o feed (são as áreas) (V2).
3. Auditoria G7: `user_profiles.university` não existe; fonte é `profile_education.institution` (V8).
4. "Prod = 2.0.0+2" desatualizado: dominante é 2.1.0 (V7).
5. Critério "≥70% das strings" da T1.6 recalibrado para rows `college` (V8).
6. Auditoria J3: wrapper `withEdgeAnalytics` está no repo, mas 8 functions ativas rodam SEM ele em prod (V1).
7. min_salary não migra para a fonte nova — decisão pré-existente do fundador (27/05) registrada no código (V2/V6).

### Decisões do fundador (AskUserQuestion, 10/06)
1. **Force-update: só monitorar** nesta fase.
2. **Critério de revogação (diferido):** builds antigas <5% dos eventos semanais por 2 semanas **E zero escritas via pontes na mesma janela** → as pontes ganham log de atividade (`bridge_activity`).
3. **Seed institutions:** lista aprovada + **UNESP, FATEC (Centro Paula Souza), UFABC, ESPM, FEI** (= 32; FATEC com aliases agressivos — variantes fragmentadas). "Ensino Médio*" fica fora (nível, não instituição).
4. **CSV shortlist: completo (com contato), gated por consent POR CANDIDATO** — ops registra em `candidate_data_sharing_consents` quando o candidato confirma (WhatsApp), com `granted_via`/escopo; o export só aceita candidatos com consent `granted`; log por export em `candidate_list_exports` permanece.

---

## Camadas (A3) — o que vale quando

| Camada | Vale a partir de | Tarefas |
|---|---|---|
| **Server-imediato** (todas as builds) | deploy/db push | T1.0, migrations T1.1/T1.2, backfill T1.3, pontes (campaigns→onboarding_completed_at; applied→applications), merge T1.5, institutions T1.6 (tabela+backfill), T1.8 |
| **Client (release 2.3.0)** | liberação na App Store | T1.4 rewire Curtidas + badge Expirada, T1.7 AuthGate novo + fim do createCampaign, T1.6 typeahead, T1.5 remoção de código morto, eventos client novos |
| **Intervalo entre os dois:** builds 2.0/2.1 seguem togglando `applied` e criando `campaigns` — as pontes convertem essas escritas para o modelo novo em tempo real. Nada quebra; nada se perde. |

---

## Tarefas

### T1.0 — Reconciliação do drift de functions (BLOQUEANTE para qualquer deploy)
1. Criar `scripts/check_functions_drift.sh`: baixa as functions ativas para dir temporário (`supabase functions download --project-ref`), difa contra `supabase/functions/`, com allowlist de (a) arquivos não-bundlados (README.md, SETUP.md, sources/types.ts) e (b) functions deprecated (parse-cv, parse-cv-pdf, generate-profile). Entra no checklist local de release ao lado do `migration list` (sem secrets no GitHub).
2. Para as 8 divergentes ativas (V1): revisar o diff um a um (eyeball, está mapeado) e **deployar o repo**. Ordem: as 6 wrapper-only primeiro (risco ~zero), depois daily-report e notifications-broadcast (diffs maiores — smoke após deploy: invocar daily-report manualmente 1x e conferir e-mail/ntfy; broadcast NÃO smoke-testar em massa — revisão de código basta).
3. Verificação de aceite: `check_functions_drift.sh` → 0 divergências em functions ativas.

### T1.1/T1.2 — `applications` + `application_events` (D1 — DDL completo)

**Matriz de transições** (validada por trigger `BEFORE UPDATE OF status`; actor derivado: GUC `app.actor` se setado pelas edges admin (Fase 4) → senão `auth.uid() IS NOT NULL` → 'user' → senão 'system'):

| Actor | Type | Transições permitidas |
|---|---|---|
| user | manual, external_confirmed | de qualquer não-terminal para qualquer estado de pipeline (in_review/shortlisted/interview/offer/hired) — **inclui retrocesso (ex.: offer→in_review), por design**: o usuário corrige erro no próprio tracker; qualquer não-terminal→rejected\|withdrawn; **reabertura** rejected\|withdrawn→submitted |
| user | stage | apenas não-terminal→withdrawn |
| admin | qualquer | qualquer estado de pipeline (inclui retrocesso); não-terminal→rejected (com `rejection_category`); reabertura em stage |
| system | qualquer | não-terminal→expired\|**withdrawn** (withdrawn cobre a Bridge 1 no caminho service-role/Studio — ver nota da bridge); (INSERT inicial do backfill/pontes) |

Terminais: hired, rejected, withdrawn, expired (rejected/withdrawn reabríveis conforme acima; hired/expired finais). Assert explícito nos testes: retrocesso user em manual/external é permitido **por design**.

**Guarda de imutabilidade (correção da lupa #2):** a RLS de UPDATE own não restringe colunas — sem guarda, um user via PostgREST fliparia `type` stage→manual e se moveria livre até hired (poluindo métricas, labels do match v2 e o SLA da F4). O trigger de validação roda em TODO update (não só `OF status`) e trava, para actor `user`: `user_id`, `job_id`, `type` imutáveis; `rejection_category` e `sla_deadline` só admin/system.

```sql
-- 2026061XXXXXXX_applications.sql (Fase 1 T1.1/T1.2 — plano-mãe C/D1)

CREATE TABLE public.applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- RESTRICT (correção da lupa #1): SET NULL violaria o CHECK job_or_manual em
  -- applications stage/external. Applications são trilha de auditoria e futuro
  -- objeto de receita — vaga com candidatura não se deleta, se desativa.
  -- CONSEQUÊNCIA DESEJADA: scripts de limpeza que deletem jobs com candidatura
  -- passarão a FALHAR (o histórico tem ~12 migrations de cleanup — N1).
  job_id uuid REFERENCES public.jobs(id) ON DELETE RESTRICT,
  type text NOT NULL CHECK (type IN ('stage','external_confirmed','manual')),
  status text NOT NULL DEFAULT 'submitted' CHECK (status IN
    ('submitted','in_review','shortlisted','interview','offer','hired',
     'rejected','withdrawn','expired')),
  application_method text,
  adapted_resume_id uuid REFERENCES public.adapted_resumes(id) ON DELETE SET NULL,
  sla_deadline timestamptz,
  rejection_category text CHECK (rejection_category IS NULL OR rejection_category IN
    ('perfil_distante','requisito_especifico','vaga_preenchida','outro_candidato','outro')),
  notes text,
  external_company text,
  external_title text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT applications_job_or_manual CHECK (job_id IS NOT NULL OR type = 'manual'),
  CONSTRAINT applications_manual_fields CHECK
    (type <> 'manual' OR (external_company IS NOT NULL AND external_title IS NOT NULL))
);
CREATE UNIQUE INDEX applications_user_job_uniq ON public.applications (user_id, job_id)
  WHERE job_id IS NOT NULL;                       -- re-candidatura = reabertura, nunca 2ª row
CREATE INDEX applications_user_status_idx ON public.applications (user_id, status);
CREATE INDEX applications_job_idx ON public.applications (job_id);
CREATE INDEX applications_sla_idx ON public.applications (sla_deadline)
  WHERE sla_deadline IS NOT NULL;

CREATE TRIGGER trg_applications_updated_at BEFORE UPDATE ON public.applications
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();  -- reuso (V12)

CREATE TABLE public.application_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES public.applications(id) ON DELETE CASCADE,
  from_status text,                                -- null = evento de criação
  to_status text NOT NULL,
  actor text NOT NULL CHECK (actor IN ('user','admin','system')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX application_events_app_idx ON public.application_events (application_id, created_at);

-- Actor da operação corrente: GUC > JWT > system.
CREATE FUNCTION public._application_actor() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT COALESCE(NULLIF(current_setting('app.actor', true), ''),
                  CASE WHEN auth.uid() IS NOT NULL THEN 'user' ELSE 'system' END);
$$;

-- Matriz de transições (SECURITY DEFINER não necessário — pura).
CREATE FUNCTION public._application_transition_allowed(
  p_actor text, p_type text, p_from text, p_to text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_from = p_to THEN true                                   -- no-op idempotente
    WHEN p_actor = 'system' THEN
         p_to IN ('expired','withdrawn') AND p_from NOT IN ('hired','expired')
    WHEN p_actor = 'admin' THEN
         (p_from NOT IN ('hired','expired')
          AND p_to IN ('in_review','shortlisted','interview','offer','hired','rejected','withdrawn'))
         OR (p_type = 'stage' AND p_from IN ('rejected','withdrawn') AND p_to = 'submitted')
    WHEN p_actor = 'user' AND p_type = 'stage' THEN
         p_from NOT IN ('hired','expired','rejected','withdrawn') AND p_to = 'withdrawn'
    WHEN p_actor = 'user' THEN                                     -- manual / external_confirmed
         (p_from IN ('rejected','withdrawn') AND p_to = 'submitted')                -- reabertura
         OR (p_from NOT IN ('hired','expired','rejected','withdrawn')
             AND p_to IN ('in_review','shortlisted','interview','offer','hired',
                          'rejected','withdrawn'))
    ELSE false END;
$$;

CREATE FUNCTION public._applications_validate_update() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_actor text := public._application_actor();
BEGIN
  -- Imutabilidade por actor (lupa #2): RLS não restringe colunas.
  IF v_actor = 'user' THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.job_id IS DISTINCT FROM OLD.job_id
       OR NEW.type   IS DISTINCT FROM OLD.type THEN
      RAISE EXCEPTION 'user_id/job_id/type são imutáveis para actor user'
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.rejection_category IS DISTINCT FROM OLD.rejection_category
       OR NEW.sla_deadline IS DISTINCT FROM OLD.sla_deadline THEN
      RAISE EXCEPTION 'rejection_category/sla_deadline só podem ser alterados por admin/system'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  -- Máquina de estados.
  IF OLD.status IS DISTINCT FROM NEW.status
     AND NOT public._application_transition_allowed(v_actor, NEW.type, OLD.status, NEW.status) THEN
    RAISE EXCEPTION 'transição % → % não permitida para actor % em type %',
      OLD.status, NEW.status, v_actor, NEW.type
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER trg_applications_validate BEFORE UPDATE ON public.applications
  FOR EACH ROW EXECUTE FUNCTION public._applications_validate_update();

-- Histórico em linhas, desde o nascimento (SECURITY DEFINER pra atravessar RLS).
CREATE FUNCTION public._applications_log_event() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO application_events (application_id, from_status, to_status, actor)
    VALUES (NEW.id, NULL, NEW.status, public._application_actor());
  ELSIF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO application_events (application_id, from_status, to_status, actor)
    VALUES (NEW.id, OLD.status, NEW.status, public._application_actor());
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER trg_applications_event_insert AFTER INSERT ON public.applications
  FOR EACH ROW EXECUTE FUNCTION public._applications_log_event();
CREATE TRIGGER trg_applications_event_update AFTER UPDATE OF status ON public.applications
  FOR EACH ROW EXECUTE FUNCTION public._applications_log_event();

-- RLS: own SELECT/INSERT/UPDATE; sem DELETE (histórico não se apaga — withdrawn é o caminho).
ALTER TABLE public.applications ENABLE ROW LEVEL SECURITY;
CREATE POLICY applications_select_own ON public.applications FOR SELECT
  USING (auth.uid() = user_id);
CREATE POLICY applications_insert_own ON public.applications FOR INSERT
  WITH CHECK (auth.uid() = user_id AND type IN ('external_confirmed','manual'));
CREATE POLICY applications_update_own ON public.applications FOR UPDATE
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

ALTER TABLE public.application_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY application_events_select_own ON public.application_events FOR SELECT
  USING (EXISTS (SELECT 1 FROM applications a
                 WHERE a.id = application_id AND a.user_id = auth.uid()));
-- INSERT client-side: nenhum (só via trigger SECURITY DEFINER).
```

(`type='stage'` no INSERT client fica de fora por RLS até a Fase 4 — criação stage será pelo fluxo 1-toque.)

### T1.3 — Backfill dos applied (D3 — SQL + prova de idempotência)

```sql
-- 2026061XXXXXXX_backfill_applications_from_applied.sql (idempotente)
INSERT INTO public.applications
  (user_id, job_id, type, status, application_method, created_at)
SELECT sa.user_id, sa.job_id, 'external_confirmed', 'submitted',
       COALESCE(j.application_method, 'url'),
       COALESCE(sa.applied_at, sa.created_at)
FROM public.swipe_actions sa
JOIN public.jobs j ON j.id = sa.job_id
WHERE sa.applied = true
ON CONFLICT (user_id, job_id) WHERE job_id IS NOT NULL DO NOTHING;
```
- Eventos iniciais saem do trigger de INSERT com actor `system` (sem JWT no contexto da migration).
- **Prova de idempotência (aceite):** executar 2x literalmente; 1ª execução = 493 rows (V5; ±deltas do dia), 2ª = **0 rows**; counts `select count(*) from applications` idênticos antes/depois da 2ª. Executado também dentro do script de testes (V11) contra dados sintéticos.

### Pontes (BRIDGES — nascem na F1, morrem juntas na revogação futura)

```sql
-- bridge_activity: observabilidade exigida pelo critério de revogação (decisão #2).
CREATE TABLE public.bridge_activity (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  bridge text NOT NULL, occurred_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE public.bridge_activity ENABLE ROW LEVEL SECURITY;  -- deny-all client

-- BRIDGE 1 — remover quando build antiga < limiar: applied → applications.
CREATE FUNCTION public._bridge_swipe_applied() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.applied = true AND COALESCE(OLD.applied, false) = false THEN
    INSERT INTO applications (user_id, job_id, type, status, application_method, created_at)
    SELECT NEW.user_id, NEW.job_id, 'external_confirmed', 'submitted',
           COALESCE(j.application_method,'url'), COALESCE(NEW.applied_at, now())
    FROM jobs j WHERE j.id = NEW.job_id
    ON CONFLICT (user_id, job_id) WHERE job_id IS NOT NULL DO NOTHING;
    INSERT INTO bridge_activity (bridge) VALUES ('swipe_applied');
  ELSIF NEW.applied = false AND OLD.applied = true THEN
    UPDATE applications SET status = 'withdrawn'
    WHERE user_id = NEW.user_id AND job_id = NEW.job_id
      AND type = 'external_confirmed' AND status = 'submitted';  -- não clobbera estado movido
    INSERT INTO bridge_activity (bridge) VALUES ('swipe_applied_undo');
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER trg_bridge_swipe_applied
  AFTER INSERT OR UPDATE OF applied ON public.swipe_actions
  FOR EACH ROW EXECUTE FUNCTION public._bridge_swipe_applied();

-- BRIDGE 2 — remover quando build antiga < limiar: campaigns → onboarding_completed_at.
CREATE FUNCTION public._bridge_campaign_onboarding() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO profile_personal (user_id, onboarding_completed_at)
  VALUES (NEW.user_id, NEW.created_at)
  ON CONFLICT (user_id) DO UPDATE
    SET onboarding_completed_at =
        COALESCE(profile_personal.onboarding_completed_at, EXCLUDED.onboarding_completed_at);
  INSERT INTO bridge_activity (bridge) VALUES ('campaign_onboarding');
  RETURN NEW;
END; $$;
CREATE TRIGGER trg_bridge_campaign_onboarding AFTER INSERT ON public.campaigns
  FOR EACH ROW EXECUTE FUNCTION public._bridge_campaign_onboarding();
```
**Nota da Bridge 1 (justificativa corrigida pela revisão):** no caminho normal o trigger roda DENTRO da sessão JWT do usuário da build antiga — `SECURITY DEFINER` muda privilégios, não `auth.uid()` — então o actor é `user` e submitted→withdrawn já é permitido. O `system→withdrawn` na matriz é necessário mesmo assim, para o caminho **service-role/Studio** (ops editando `applied=false` direto no banco), que sem ele abortaria o UPDATE em `swipe_actions`. Assert do caminho service-role incluído nos testes.

**Bridge 2 — risco de NOT NULL verificado em plan mode (lupa #3):** os únicos NOT NULL de `profile_personal` são `user_id` e 4 colunas com default (`completeness_score=0`, `schema_version=1`, `created_at`, `updated_at`) — `first_name`/`email` são NULLABLE (information_schema, 10/06). O INSERT mínimo é seguro HOJE; o assert do INSERT mínimo entra no script de testes mesmo assim (protege contra NOT NULL futuro), porque uma falha aqui abortaria o INSERT de campaigns das builds antigas = onboarding quebrado em produção.

### T1.4 — Rewire da aba Curtidas (CLIENT 2.3.0)
- Novo `lib/features/jobs/data/applications_repository.dart` + model `Application` (status enum espelho).
- `liked_jobs_screen.dart`: estado "Aplicada" vem de `applications` (fetch por user, map por job_id); toggle → cria application (`external_confirmed/submitted`) ou move pra `withdrawn`; **para de escrever `swipe_actions.applied`** (colunas ficam; comentário `-- DEPRECATED desde Fase 1` via migration comment).
- **Badge "Expirada"** quando `job.is_active == false` (69% dos applied — V5) + ação "Arquivar" reusando `removeLikedJob` existente (vaga inativa não volta ao feed).
- Eventos (R7, catálogo + emissor no mesmo PR): `application_created`, `application_state_changed` (props: application_id, type, from_status, to_status, job_id?), `application_reopened`.
- Testes Dart: unit do mapper/serialização do `Application` + espelho client da matriz (helper `canTransition`) + widget test da célula com badge Expirada.

### T1.5 — Unificação de preferências (revisada — SEM ponte, V3)
- **Merge one-shot idempotente (D2)** — só preenche onde a fonte nova está vazia (regra: escolha nova do usuário vence; legacy só resgata quem nunca preencheu a nova):

| Origem (`user_preferences`) | Destino | Transformação | Ganho medido (V6) |
|---|---|---|---|
| `areas[]` | `profile_desired_titles (user_id, title, source='legacy_merge')` | INSERT por elemento; só users sem NENHUM desired_title. Coluna `source` **existe** (verificado em V2: id, user_id, title, source, order_index) | 19 users |
| `locations[1]` | `profile_job_preferences.primary_location_city` | 1º elemento; só se primary null e sem other_locations | 33 users |
| `locations[2..]` | `profile_other_locations (user_id, city)` | demais elementos | (mesmos 33) |
| `work_models[]` PT | `profile_job_preferences.work_mode` EN | remoto→remote, hibrido→hybrid, presencial→in_person | 27 users |
| `job_types[]` | `profile_job_preferences.job_types` | direto (vocabulário idêntico, 0 conflitos) | 21 users |
| `min_salary`, `min_match_score` | — | **morrem** (decisão fundador 27/05: salário fora da identidade; filtros são locais) | 80/34 users, documentado |

  SQL: upsert em `profile_job_preferences` com `ON CONFLICT (user_id) DO UPDATE SET work_mode = COALESCE(NULLIF(pjp.work_mode,'{}'), EXCLUDED.work_mode), ...` + INSERTs com `NOT EXISTS`. Idempotente (re-execução = 0 mudanças). Dry-run de aceite com counts antes/depois.
- **Client (2.3.0):** remover `PreferencesRepository` morto + injeção (`main.dart:265`, ctor do `JobsViewModel`). `user_preferences` fica como fóssil legível; **sem revogação** (decisão diferida #2). Monitoramento: a query semanal de `updated_at > now()-7d` entra no checklist de release junto do `bridge_activity`.

### T1.6 — `institutions` + autocomplete + backfill
- Migration: `CREATE EXTENSION IF NOT EXISTS unaccent;` + `institutions (id, name, normalized_name unique, aliases text[], type, city, state)` + seed das **32** (decisão #3: lista aprovada + UNESP, FATEC/Centro Paula Souza, UFABC, ESPM, FEI), com aliases pré-povoados pras variantes conhecidas (FATEC agressivo: "fatec sp", "fatec zona leste", "centro paula souza"...; Cruzeiro do Sul/Universidade Cruzeiro do Sul; Mackenzie/Universidade Presbiteriana Mackenzie; São Judas/Universidade São Judas Tadeu; Estácio/Estácio de Sá; UNIP/Universidade Paulista).
- `profile_education.institution_id uuid NULL REFERENCES institutions(id)` (texto raw permanece).
- Backfill best-effort em 2 passadas (exact normalized equality → word-boundary containment p/ nomes ≥4 chars, sempre `lower(unaccent(...))`) + passada no **top-100 valores distintos** para estender aliases. **Meta: ≥70% das rows `education_level='college'`** (cru já dá 50,4% — V8); % global e % college reportados.
- Client (2.3.0): typeahead no `EducationScreen` (campo livre atual em `education_screen.dart:680-693`) e no `AddEditEducationModal` (perfil), consultando `institutions` (ilike em name+aliases, limit 8), opção "outra" mantém só texto. Grava `institution_id` quando escolhido.
- RLS: `institutions` SELECT para authenticated (catálogo).

### T1.7 — Aposentar o gate `hasCampaign`
- Migration: `profile_personal.onboarding_completed_at timestamptz` + **backfill**: `UPDATE profile_personal pp SET onboarding_completed_at = c.first_at FROM (SELECT user_id, min(created_at) first_at FROM campaigns GROUP BY 1) c WHERE c.user_id = pp.user_id AND pp.onboarding_completed_at IS NULL` + INSERT de linhas mínimas pra users com campaign e sem profile_personal (existem: fluxo legacy).
- Bridge 2 cobre builds antigas (387 campaigns/7d — V4).
- Client (2.3.0): `UserViewModel.hasCompletedOnboarding` lê `onboarding_completed_at` (via `ProfileRepositorySupabase`); `AuthGate` (`splash_screen.dart:530`) troca `hasCampaign` → `hasCompletedOnboarding`; `OnboardingCompleteScreen`/`CompletionScreen` param de chamar `createCampaign` e setam `onboarding_completed_at` direto. Leitura de campaigns permanece (`add_experience_wizard.dart:288` usa contexto da campanha pros bullets — 99% skipped, degradação nula pra users novos; registrado).
- `campaigns`/`target_jobs`: **sem revogação nesta fase** (decisão diferida).

### T1.8 — Busca de candidatos no console
- Migration: `candidate_data_sharing_consents` + colunas `granted_via text` (whatsapp/email/in_app) e `scope text[]` (default `{contact_info}`) — decisão #4.
- Edge nova `admin-candidates-search` (padrão `_shared/admin.ts`; audit em `admin_audit_log`): filtros curso (`user_profiles.course` ilike + `profile_education.degree`), instituição (institution_id ou texto), cidade (`profile_personal.location_city`), skills (`profile_skills.name ilike any`), `completeness_score >=`, atividade (exists `swipe_actions` recente — proxy), tem CV (exists `saved_resumes` OU `profile_experiences`>0); paginação; POST salva como `candidate_list_requests`+`items` (estruturas servem sem alteração — V9). PATCH de consent registra granted/revoked com `granted_via`/`scope`/`updated_by_admin` e usa **`status_reason` como nota de evidência** ("confirmou por WhatsApp em DD/MM" — coluna já existe, vira o rastro humano do consent).
- Export CSV: estender `admin-candidate-lists` com export server-side: **filtra itens para `consents.status='granted'`**, gera CSV (nome, contato, cidade, curso, instituição, semestre, skills, completeness), loga `candidate_list_exports` (exported_fields, count, exported_by). Candidatos sem consent saem da lista exportada com aviso na UI.
- Dashboard: `src/features/candidates/CandidatesSearchPage.tsx` (busca + seleção + salvar lista + marcar consent + export) + entrada no nav (`Layout.tsx:5`); padrão `lib/api.ts`.
- Eventos server-side (R7): `candidate_search_performed` (filtros usados, result_count), `candidate_list_created` (request_id, size) via `captureEvent`.

---

## Ordem de execução e PRs (branch `fase-1-espinha-de-dados`)

1. **PR1 — T1.0** (bloqueante): script de drift + 8 redeploys conscientes. Sem schema.
2. **PR2 — migrations core (server-imediato):** applications + events + matriz + bridges + bridge_activity + backfill applied + onboarding_completed_at + backfill campaigns. Manifest atualizado; script de testes SQL executado (rollback) e colado.
3. **PR3 — migrations de dados:** merge de preferências (D2) + institutions/seed/backfill + consents columns.
4. **PR4 — client 2.3.0:** T1.4 + T1.7 + typeahead T1.6 + remoção PreferencesRepository + eventos novos no catálogo (R7).
5. **PR5 — T1.8:** edge + dashboard + export gated por consent + eventos server.
Cada PR roda o CI da F0; PRs 2–3 incluem `migration list` limpo no checklist.

## Reuso (não reinventar)
`update_updated_at_column()` (triggers); padrão RLS own-CRUD (C2); `_shared/admin.ts` (requireAdmin/jsonResponse/audit); `_shared/posthog.ts captureEvent` (eventos server); `removeLikedJob`/`restoreLikedJob` (arquivar); tradução EN↔PT de work_mode já existente (`jobs_viewmodel.dart:528-540` — extrair pra helper compartilhado); `analytics_events.dart` (catálogo R7); conta interna `internal-fase0-test@stage.app`.

## Verificação fim-a-fim (aceites — verificado, não declarado)
1. **T1.0:** `check_functions_drift.sh` → 0 divergências ativas; daily-report smoke (1 invocação manual → e-mail/ntfy ok).
2. **Backfill:** 493 applications criadas (±delta do dia); **re-execução literal = 0 rows**; cada application com 1 evento inicial actor=system.
3. **Matriz + guardas:** script SQL transacional (BEGIN…ROLLBACK, transações curtas, sem tocar `user_profiles`) com asserts cobrindo: user move manual→hired; **retrocesso offer→in_review permitido por design**; user NÃO move stage→in_review; user stage→withdrawn ok; reabertura; system→expired; **imutabilidade: user não flipa type/job_id/user_id nem seta rejection_category/sla_deadline**; **Bridge 1 via service-role (applied=false → withdrawn, actor system)**; **Bridge 2 com INSERT mínimo em profile_personal**; `ON DELETE RESTRICT` (delete de job com candidatura falha). Output colado no relatório.
4. **Pontes:** com a conta interna num device com build atual (2.1.0 ou simulando o write): toggle `applied` em `swipe_actions` → application aparece + `bridge_activity` registra; INSERT de campaign sintética → `onboarding_completed_at` setado.
5. **Merge prefs:** counts antes/depois batem com V6 (19/33/27/21); re-execução = 0 mudanças; feed da conta interna continua filtrando igual (smoke no app).
6. **Institutions:** % match reportado, ≥70% em `college`; typeahead funcionando no device (2.3.0 build local).
7. **Curtidas 2.3.0 (build local):** marcar aplicada → row em applications + evento `application_created` no PostHog; badge Expirada visível numa vaga inativa; `swipe_actions.applied` sem escrita nova (grep + observação).
8. **T1.8:** fundador monta 1 shortlist real em <5 min; export CSV bloqueia candidato sem consent e exporta com consent; `candidate_list_exports` logado; eventos server no PostHog.
9. `flutter test` verde (novos testes incluídos); CI verde nos 5 PRs; `migration list` e manifest limpos ao final.
10. `FASE-1-RELATORIO.md` com: drift table final, números de backfill/merge/instituições, correção do registro "prod=2.0.0+2"→2.1.0, pendências.

## Fora de escopo (reafirmado)
Fases 2–6; revogação de escrita nas legacy (diferida — critério registrado: <5% eventos semanais por 2 semanas E zero `bridge_activity` na janela); portal de empresa; prompt de retorno pós-apply (F3); criação de application no clique de apply (F3); qualquer mudança no pipeline adapt (R5 — se encostar, parar e reportar); force-update (só monitorar).
