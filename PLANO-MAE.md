# PROMPT — Plano de Implementação Stage (Fases 0–6)
## Para o Claude Code, em resposta à AUDITORIA-STAGE.md

---

## Contexto e missão

A auditoria que você produziu (`AUDITORIA-STAGE.md`, 09/06) foi revisada pelo arquiteto externo e este documento é a resposta: o plano de implementação que transforma o app atual no produto especificado — feed em lista com ranking server-side, perfil estruturado como fonte única, candidatura nativa com máquina de estados e SLA, tracker, vaga própria fim-a-fim, console de ops e Android.

O plano está dividido em **7 fases (0–6)**. As fases 0 e 1 são sequenciais e obrigatórias antes de qualquer outra. A partir da Fase 2, frentes podem ser paralelizadas com aprovação explícita do fundador. Cada fase referencia os achados da auditoria pela seção (ex.: "O2 #1") — mantenha a auditoria aberta como contexto durante todo o trabalho.

**Princípio que governa tudo:** estamos construindo a espinha de dados de um marketplace (perfil → candidatura → colocação) por cima de um app vivo em produção com ~2.000 usuários. Toda mudança é aditiva, todo backfill é idempotente, toda transição tem janela de leitura dupla. Nada quebra o usuário de hoje para servir o de amanhã.

---

## Regras de trabalho (valem para todas as fases)

**R1 — Plano antes de código.** No início de cada fase, escreva `PLANO-FASE-N.md` na raiz: tarefas na sua ordem real de execução, migrations que vai criar (com DDL rascunhado), arquivos que vai tocar, riscos, e o que ficou de fora. **Pare e aguarde aprovação do fundador antes de implementar.** Ao final da fase, escreva `FASE-N-RELATORIO.md` (o que foi feito, desvios do plano, métricas de aceite medidas).

**R2 — Disciplina de migration (resposta direta ao drift C6/O1 #4).** Toda mudança de schema nasce como arquivo em `supabase/migrations/` e é aplicada via CLI (`supabase db push`). Proibido alterar schema pelo dashboard/MCP. Antes de cada PR: `supabase migration list` precisa estar limpo (local = remoto). Se encontrar drift novo, pare e reporte antes de prosseguir.

**R3 — Testes acompanham o código novo.** Cada fase entrega testes para o que criou: mínimo de testes de unidade para lógica de domínio (ranking, máquina de estados, merges de backfill) e 1 widget test por tela nova crítica. Não é meta de cobertura retroativa dos 79k LOC — é regra de "código novo não nasce nu" (O1 #6).

**R4 — Flags para tudo que muda comportamento visível.** Use a infra existente: `app_feature_flags` (Supabase, F5) para ligar/desligar estrutural; PostHog flags para experimento/rollout gradual. Toda UI nova relevante entra atrás de flag com rollout 10% → 50% → 100%.

**R5 — Não tocar sem rede:** qualquer mudança que encoste no pipeline de adaptação de CV (adapt v2) exige rodar o harness `golden_set/` antes e depois, com diff de qualidade no relatório da fase. Mudança de prompt = bump de `PROMPT_VERSION` (disciplina já existente, manter).

**R6 — Fora de escopo permanente (não fazer):** migrar para Riverpod/go_router/get_it ou qualquer reescrita arquitetural (consistência > pureza — o padrão Provider+MVVM atual fica); deletar tabelas/functions legacy (congelar, não apagar); redesenhar o design system; criar telas além das especificadas; "aproveitar para refatorar" deus-classes fora do caminho crítico da tarefa.

**R7 — Eventos:** todo evento novo entra no catálogo `analytics_events.dart` E ganha emissor no mesmo PR (nunca mais catálogo morto — J5 #7). Transições de estado executadas server-side (edge functions admin) emitem via `_shared/posthog.ts` (`captureEvent`), que já existe (J3).

**R8 — Commits e branches:** uma branch por fase (`fase-0-seguranca`, ...), conventional commits, PRs pequenos por frente de trabalho dentro da fase.

---

# FASE 0 — Segurança, drift e fundação de release
*Objetivo: parar os vazamentos, restabelecer a confiança no processo de schema e publicar a régua de medição. Sem isso, as fases seguintes constroem no escuro e por cima de risco. Refs: M1, M4, C6, L3 #1, O2 #4, O2 #5, J5 #1.*

**T0.1 — Chave OpenAI fora do bundle (M1).**
(a) Remover a linha `OPENAI_API_KEY` do `.env` local e do `.env.example` se houver; (b) o fundador rotaciona a chave no painel OpenAI e atualiza APENAS o secret do Supabase (`supabase secrets set`) — deixe essa instrução destacada no PLANO; (c) adicionar guarda permanente: script `scripts/check_env_safety.sh` que falha se `.env` contiver `OPENAI|SERVICE_ROLE|SECRET|RESEND|APIFY` (roda no CI e em pre-commit); (d) avaliar e documentar no relatório: o `.env` continua como asset (`pubspec.yaml:133`) contendo somente chaves públicas-by-design (SUPABASE_URL/ANON_KEY, POSTHOG, ONESIGNAL_APP_ID) — aceitável; alternativa dart-define fica anotada como melhoria futura, não bloqueia.

**T0.2 — Reativar o rate limit de `generate-resume`** (`index.ts:36`, L3 #1). Restaurar o check `count >= N`, com N conservador (sugestão: 10/dia/usuário) e evento `rate_limit_hit` já suportado pelo `_shared/posthog.ts`.

**T0.3 — Minimizar PII no ntfy (M4).** `notify-signup`: trocar payload nome+e-mail por contagem do dia + user_id truncado (8 chars). `notify-auto-apply-swipe`: job_id + user_id truncado, sem dados pessoais. O detalhe completo o fundador vê no dashboard admin, não no push.

**T0.4 — Resolver o drift de `user_culture_fit_preferences` (C6, achado #4 do TL;DR).** Decisão default: **aplicar** a migration `20260607000000` via CLI (a tabela é benigna e o código em main já depende dela). Em seguida, remover o fallback silencioso de `culture_fit_repository.dart:36-41` — falha de save remoto agora loga `$exception` com contexto em vez de degradar mudo. Registrar no relatório a verificação `to_regclass` pós-aplicação.

**T0.5 — CI mínimo (O2 #4).** GitHub Actions com 4 jobs: `flutter analyze` (zero erros), `flutter test`, `check_env_safety.sh`, e checagem de migrations (falha se `supabase migration list` indicar drift — pode ser via diff de arquivos contra um manifest commitado se o CLI não rodar no CI sem secrets). Build iOS sem assinatura fica como job opcional/noturno.

**T0.6 — Publicar a build-régua (J5 #1, O2 #5).** Subir 2.2.x para a App Store contendo o fix `a72dedb` (is_pre_cutover_user, feed_exhausted) e as mudanças desta fase. Anotar o deploy no PostHog com o script existente (`scripts/posthog_annotate_deploy.sh`). Esta build é a baseline de TODAS as comparações futuras.

**T0.7 — Higiene leve (L4).** Deletar `world_screen.dart`; adicionar comentário-cabeçalho `DEPRECATED — sem caller desde 26/05, manter para rollback até Fase 2` em `parse-cv`/`parse-cv-pdf`/`generate-profile`. Nada mais de limpeza nesta fase.

**Critérios de aceite F0:** chave antiga revogada e IPA novo verificado sem a chave (extrair o asset e confirmar); rate limit ativo com evento; ntfy sem PII; `migration list` limpo; CI verde no PR da fase; build na revisão da App Store; relatório com o diff golden_set NÃO requerido (nada de adapt foi tocado).

---

# FASE 1 — A espinha de dados: candidatura, preferências, instituições, busca de candidatos
*Objetivo: criar a entidade que todo o resto pendura (`applications`), eleger fontes únicas de verdade, e destravar a operação concierge de shortlists. É a fase que o O2 #2 e #3 mandam fazer "agora, mesmo que mínima". Refs: O1 #1, O1 #5, O1 #10, O4, E3, E5, G2, G7, C1.*

**T1.1 — Migration `applications`.** Campos: `id uuid pk`, `user_id fk auth.users not null`, `job_id fk jobs not null`, `type text check in ('stage','external_confirmed','manual')`, `status text check in ('submitted','in_review','shortlisted','interview','offer','hired','rejected','withdrawn','expired') default 'submitted'`, `application_method text`, `adapted_resume_id fk adapted_resumes null`, `sla_deadline timestamptz null`, `rejection_category text null check in ('perfil_distante','requisito_especifico','vaga_preenchida','outro_candidato', null)`, `notes text null`, `external_company text null` + `external_title text null` (para type=manual sem job_id — nesse caso `job_id` nullable; ajustar o NOT NULL para `check (job_id is not null or type = 'manual')`), `created_at`, `updated_at`. Tabela irmã `application_events (id, application_id fk, from_status, to_status, actor text check in ('user','admin','system'), created_at)` — o histórico NÃO vive em jsonb, vive em linhas (auditável, consultável). RLS: own CRUD para o usuário em `applications` (UPDATE restrito a colunas próprias — status só avança por ele em types manual/external); `application_events` INSERT via trigger + SELECT own. Índices: `(user_id, status)`, `(job_id)`, `(sla_deadline) where sla_deadline is not null`.

**T1.2 — Trigger de transição.** `AFTER UPDATE OF status ON applications` → insere em `application_events`. Emissão analítica da transição: client emite `application_state_changed` quando a ação é do usuário; as edges `admin-*` (Fase 4) emitem server-side via `captureEvent`.

**T1.3 — Backfill dos 493 (O4).** Migration de dados idempotente: `INSERT INTO applications (user_id, job_id, type, status, application_method, created_at) SELECT user_id, job_id, 'external_confirmed', 'submitted', j.application_method, COALESCE(applied_at, sa.created_at) FROM swipe_actions sa JOIN jobs j ON ... WHERE applied = true ON CONFLICT DO NOTHING` (criar unique parcial `(user_id, job_id)` para types stage/external antes). Verificação no relatório: count = 493.

**T1.4 — Reescrever a leitura/escrita da aba Curtidas (`liked_jobs_screen.dart`, E5/O4).** "Marcar como aplicada" passa a criar/atualizar `applications` (type external_confirmed); o estado exibido vem de `applications`, não de `swipe_actions.applied`. `swipe_actions.applied/applied_at` entram em modo legacy: **parar de escrever** (manter colunas; comentário SQL `-- DEPRECATED desde Fase 1`). Bônus obrigatório do E5: vaga curtida com `is_active=false` ganha badge "Expirada" e ação de arquivar (em vez de card com link morto).

**T1.5 — Unificar preferências (O1 #10, L4).** Eleger `profile_job_preferences` como fonte única. Migration de merge `user_preferences` → `profile_job_preferences` (regra: registro mais recentemente atualizado vence campo a campo; documentar mapeamento de colunas no PLANO). Apontar `preferences_repository.dart` para a tabela vencedora; congelar `user_preferences` (revogar INSERT/UPDATE por RLS); remover a sincronização client-side dupla. Atenção: o filtro do feed (`jobs_viewmodel.dart:477`) e o match determinístico (F1) leem prefs — ajustar os dois call sites e testar.

**T1.6 — Tabela `institutions` + autocomplete (G7).** Migration: `institutions (id, name, normalized_name unique, type, city, state)` com seed das ~25 instituições dominantes da base (USP, UNICAMP, UFMG, Anhanguera, Estácio, Uninove, UNIP, Cruzeiro do Sul, Mackenzie, PUC-SP, PUC-Campinas, FGV, Insper, Link, FIAP, Senac, Anhembi, São Judas, Metodista, FMU + ajustar pela query real de `user_profiles.university`). `profile_education.institution_id fk null` (manter o texto raw na coluna atual). No app: typeahead no `EducationScreen` (campo atual em `education_screen.dart:680-693`) consultando a tabela, com opção "outra" que grava só texto. Backfill best-effort: match por `lower(unaccent(...))` das strings existentes → institution_id; relatório informa % casado.

**T1.7 — Aposentar o gate `hasCampaign` (O4, G1).** Nova coluna `profile_personal.onboarding_completed_at timestamptz`; backfill: usuários com campaign existente recebem o `created_at` da campaign. `AuthGate` (`splash_screen.dart:492-547`) passa a decidir por essa coluna. `campaigns`/`target_jobs` congeladas (revogar INSERT via RLS) — nenhuma escrita nova; o nome "campaign" fica livre para o futuro conceito de vaga-empresa.

**T1.8 — Busca de candidatos no console (destrava a operação comercial; usa o esqueleto B2B de C1/O4).** Nova edge `admin-candidates-search` (padrão das `admin-*`: auth por `admin_users`, service role, audit log): filtros curso (ilike em `user_profiles.course` + `profile_education`), instituição (id ou texto), cidade (`profile_personal.location_city`), skills (`profile_skills.name ilike any`), `completeness_score >=`, atividade recente (last event ou `updated_at`), tem CV (`saved_resumes` ou `profile_experiences > 0`). Página nova no `admin_dashboard/` (React existente) com a busca + seleção de candidatos + **salvar como `candidate_list`** (tabelas `candidate_list_requests/items` já existem vazias — usá-las como foram desenhadas) + export CSV (fluxo `candidate_list_exports` já previsto). PDF de shortlist fica para a Fase 4; CSV + dashboard resolve o concierge agora.

**Critérios de aceite F1:** backfill 493 confirmado; aba Curtidas funcionando via `applications` com badge de expirada; uma única tabela de preferências escrita pelo app (provado por grep + teste); autocomplete de instituição no ar com ≥70% das strings históricas casadas; AuthGate sem `hasCampaign`; busca de candidatos usada pelo fundador para montar 1 shortlist real de teste em <5 minutos; testes de unidade da máquina de estados + merge de prefs verdes.

---

# FASE 2 — Feed server-side + modo lista + holdout do score
*Objetivo: tirar o feed do client (O2 #1), substituir `shuffle(Random())` por ranking explicável, desacelerar a exaustão do catálogo e medir a validade real do match score. Refs: E1, E2, D4, F1-F5, O1 #2.*

**T2.1 — RPC `get_feed_page`.** Function SQL `get_feed_page(p_limit int default 20, p_cursor_score numeric default null, p_cursor_id uuid default null)` rodando como o usuário autenticado (`auth.uid()`): exclui swipadas (`NOT EXISTS swipe_actions`), `is_active = true`, `deadline` válido; junta `profile_job_preferences`; calcula **ranking heurístico v1 determinístico** com os mesmos pesos do match client (F1a — manter coerência: área 30, tipo 20, cidade 15 com remoto passa, modelo 15, salário 10, freshness como desempate multiplicativo `exp(-dias_desde_published/14)`); retorna página keyset `(score, id)` com as razões em colunas (`reason_area bool, reason_city bool...`) para os chips. **Não chama IA** — o match IA por card continua no client com sliding window e cache `match_analyses`, inalterado. Índices novos: `jobs(is_active, area, published_at desc)`. Teste de unidade SQL (pgTAP ou teste de integração via service role) para o ranking.

**T2.2 — UI lista como modo padrão, swipe preservado.** Nova `jobs_list_screen.dart` atrás da flag `feed_list_v1` (`app_feature_flags`): células com card compacto (empresa, título, chips de razão vindas do RPC, bolsa quando houver — 10% têm, D7 —, distância textual, badge de frescor), gesto de swipe na célula (direita salva / esquerda descarta → mesma `swipe_actions`), pull-to-refresh, paginação infinita pelo cursor. Toggle no topo abre o **modo swipe**: `CardSwiper` atual recebe um snapshot imutável da página corrente (resolve a restrição documentada em `job_repository.dart:30-34` sem refatorar o plugin). `JobRepository.fetchJobsWithDiagnostics` permanece apenas como fallback do modo swipe legado até a flag chegar a 100%; depois, deletar.

**T2.3 — Estados de exaustão honestos + pedido de empresa (E4).** Ao fim da página final: variante A "fim das relevantes desta semana" com CTA de alerta (liga push de vagas novas — digest existente) e expansão de raio/remoto (ajusta prefs); variante B mantém limpar filtros. Novo: botão "Pedir uma empresa" → migration `company_requests (id, user_id, company_name, note, created_at)` RLS own-insert + leitura no admin dashboard (vira lead comercial). Evento `company_requested`.

**T2.4 — Score em bandas + holdout (F3, F4, F5).** (a) Trocar a exibição do número 0-100 por 3 bandas (Alta ≥70 / Média 40-69 / Baixa <40) mantendo as `reasons` como chips — o número completo permanece no detalhe da vaga. (b) **Holdout:** usar a flag PostHog existente `match_score_visibility_v1` com variante `hidden_pre_swipe` para ~20% dos usuários *elegíveis* (confidence high/medium — a randomização é SÓ entre quem veria o score; F3 mostrou que os 28% sem score são selecionados por completude, não aleatórios — randomizar sobre todos contaminaria o teste): ocultar banda e chips pré-swipe, revelar no detalhe. (c) Adicionar prop `score_visible: bool` em `job_card_shown` e `job_swiped`. (d) Análise após ≥2 semanas: gap de save-rate por banda, com × sem exibição. O relatório da fase define o critério: se o gap colapsar >60% no grupo oculto, a exibição pré-swipe é ancoragem e sai do padrão até o match v2.

**T2.5 — Detalhe da vaga:** mover as razões para o topo, e nas agregadas exibir a fonte com selo discreto ("via Gupy") — preparação visual para a classe "Vaga Stage" da Fase 4.

**Critérios de aceite F2:** RPC servindo 100% do feed lista com P50 < 800ms na página de 20; flag a 100% após rollout sem regressão de `feed_loaded`/crash; `jobs.shuffle(Random())` deletado do repositório; holdout coletando com `score_visible` nos eventos; taxa de exaustão semanal medida no novo fluxo (baseline para comparar com os 19%); ≥1 `company_request` real registrado.

---

# FASE 3 — Tracker de candidaturas + prompt de retorno + saída instrumentada
*Objetivo: virar o sistema-de-registro da busca do usuário e iluminar o funil externo. Refs: H1-H3, E5, O1 #1, espec. seções 6.2 e 7.*

**T3.1 — Aba Candidaturas.** Renomear a aba Curtidas → **Candidaturas**, com segmentos: Salvas (liked sem application) / Enviadas / Em processo (in_review, shortlisted, interview) / Finalizadas (hired, rejected, withdrawn, expired). Fonte: `applications` + join de salvas. Célula com status, data, e menu de atualização manual de status para types `manual`/`external_confirmed` (usuário move o próprio pipeline; type `stage` é read-only para o usuário — quem move é a empresa/ops na Fase 4).

**T3.2 — Prompt de retorno (H3).** No `job_details_apply_clicked` (`liked_jobs_screen.dart:119-124` e `job_details_sheet.dart`), gravar `pending_apply {job_id, ts}` no `JobSwipeContext` (SharedPreferences). No `app_foregrounded` (observer já existente em `analytics_service.dart:211-292`): se `pending_apply` < 30 min → bottom sheet "Você se candidatou para {título}?" — **Sim** → application `external_confirmed` (`submitted`); **Não** → chips de motivo (`processo_longo`,`vaga_fechada`,`pediram_demais`,`so_olhando`) + evento `apply_abandon_reason` (ouro estratégico: fricção por fonte); **Depois** → re-pergunta única em 24h. Eventos novos no catálogo com emissor no mesmo PR (R7).

**T3.3 — Adição manual.** FAB na aba: empresa + título + link opcional + status inicial → application `type='manual'`. Meta de UX: 10 segundos.

**T3.4 — UTM na saída (H2).** Para links http(s) externos, anexar `utm_source=stage&utm_medium=app&utm_campaign=job_apply` preservando query existente (nunca em `mailto:`). Registrar o clique também em banco: tabela leve `outbound_clicks (id, user_id, job_id, created_at)` RLS own-insert — o funil externo deixa de viver só no PostHog (H2).

**T3.5 — Digest com prazos.** Estender `notifications-daily-digest` para incluir vagas salvas com `deadline` ≤ 48h ("2 vagas salvas fecham amanhã"). Sem novos tipos de push além disso nesta fase.

**Critérios de aceite F3:** ≥30% dos apply-clicks respondendo ao prompt em 2 semanas; tracker exibindo os 3 types; primeira análise de `apply_abandon_reason` por fonte no relatório; `outbound_clicks` populando; zero push novo fora do digest.

---

# FASE 4 — Vaga Stage fim-a-fim + console operacional
*Objetivo: a primeira vaga própria com candidatura 1-toque, timeline real e SLA operado — o produto que a empresa compra. Corrige também a promessa falsa de "candidatura automatizada" (achado #4 do TL;DR). Refs: O4, C1 (B2B skeleton), N1, espec. seções 6.1 e 9-10.*

**T4.1 — Migrations de vaga própria.** `jobs.status text check in ('draft','active','paused','filled','expired')` com backfill `is_active→status` e trigger transitório mantendo `is_active` em sync (todo código legado continua lendo `is_active` até a Fase 6 de limpeza); `jobs.employer_client_id fk employer_clients null`; `jobs.soft_close_threshold int default 25`; `application_method` ganha valor `'stage'`. Vaga com `source='stage_direct'` + employer vinculado = **Vaga Stage**.

**T4.2 — Candidatura 1-toque.** No detalhe de Vaga Stage: botão "Candidatar com meu perfil" → bottom sheet com preview do perfil (dados `profile_*`), opção "anexar CV adaptado para esta vaga" (reusa o pipeline adapt v2 inteiro — `adapted_resumes` vira o anexo via `adapted_resume_id`), confirmar → application `type='stage'`, `status='submitted'`, `sla_deadline = now() + interval '7 days'`. Soft close: trigger ou check no RPC de apply que pausa novas candidaturas quando `count(applications where job_id=X and status not in (rejected,withdrawn)) >= soft_close_threshold` → vaga vai a `paused` com motivo. Card e detalhe ganham o selo "Vaga Stage · resposta em até 7 dias".

**T4.3 — Timeline do candidato.** No detalhe da candidatura (aba Candidaturas): timeline vertical dos estados com timestamps de `application_events`, push OneSignal a cada transição (novo template no `notifications-*` ou direto da edge admin), e copy de recusa mapeada por `rejection_category` (4 textos gentis e acionáveis — escrever no PLANO para aprovação).

**T4.4 — Console: as 3 ferramentas da operação.** No `admin_dashboard/` + edges `admin-*` (padrão existente, audit log obrigatório em `admin_audit_log`):
(a) **Editor de estados** — `admin-applications` (GET lista por vaga/status, PATCH transição com `rejection_category` opcional) + UI kanban simples por vaga; toda transição server-side emite `application_state_changed` via `captureEvent` (R7) e dispara o push de T4.3.
(b) **Fila de SLA** — view/query: applications `type='stage'` com `status in (submitted,in_review)` e `sla_deadline < now() + 48h`, ordenada; ações de 1 clique (mover estado / recusar com motivo). Evento `sla_breached` emitido por cron diário (nova scheduled edge `sla-monitor`) quando estourar.
(c) **Shortlist builder v2** — da busca de candidatos (T1.8), gerar shortlist vinculada a uma vaga (reusar `candidate_list_requests` com `job_id`) e exportar **PDF padronizado** (server-side na edge, HTML→PDF simples — não reusar o pipeline client do app) para a fase WhatsApp do comercial.

**T4.5 — Corrigir a promessa de "candidatura automatizada" (achado #4, O1 #1).** O fluxo atual (swipe-right em vaga `application_method='email'` → ntfy → fundador envia e-mail) passa a CRIAR uma application real (`type='stage'`, method `email`) no momento do swipe-confirmação, e a UI muda a copy de "automática" para "assistida — você acompanha o status aqui". O ntfy continua como alerta operacional (payload mínimo, T0.3), mas o usuário ganha rastro e timeline de verdade. Nenhuma promessa de automação que é uma pessoa (regra da especificação: prometer o resultado, não o mecanismo).

**Critérios de aceite F4:** 1 Vaga Stage publicada (via SQL/console), ≥5 candidaturas 1-toque reais fim-a-fim com push de transição recebido; fila de SLA exibindo deadlines e zero violação no piloto; recusa categorizada chegando ao candidato com copy aprovada; PDF de shortlist gerado pelo console; promessa de automação corrigida na UI (screenshot no relatório).

---

# FASE 5 — Android beta
*Objetivo: ler o iceberg do ICP. Greenfield confirmado (A8): é projeto a criar, não configuração. Estimativa O3: 3-6 semanas, sem paralelizar com frente grande. Refs: A8, O3, O1 #8.*

**T5.1 — Mecânico (semanas 1-2):** `flutter create --platforms=android .`; ícones (`flutter_launcher_icons` ganhar `android: true`) e splash Android 12+ (config já preparada, `pubspec.yaml:114`); AndroidManifest com permissões (localização), schemes (`io.supabase.stage`, `stage`, `fb1268158548810380` meta-data), intent-filters de deep link; FCM + OneSignal (google-services.json, key no painel); Google OAuth redirect; keystore + Play Console (faixa interna); `app_config.android_store_url` populado (hoje null — A8).

**T5.2 — Os 5 riscos do O3, atacados cedo e nesta ordem:** (1) **Export PDF** — testar os 5 templates do `pdf_service.dart` no Android no PRIMEIRO dia do port (engine de render diferente; é o maior risco técnico); divergência visual = ajustar CSS por plataforma ou aceitar diff documentado; (2) Sign in with Apple via web flow (service ID + redirect — manter o botão exige isso; alternativa aprovável: ocultar botão Apple no Android no beta); (3) session replay PostHog Android + máscaras `PiiMask` re-validadas tela a tela; (4) QA de gestos: CardSwiper + os 40 widgets da trilha em 3 devices físicos (1 low-end); (5) ATT é iOS-only — confirmar no-op limpo e gating do Facebook SDK no Android.

**T5.3 — QA manual roteirizado** (sem suíte automatizada para herdar — L1): roteiro escrito em `QA-ANDROID.md` cobrindo auth (Google/telefone), onboarding completo, feed lista+swipe, apply externo + prompt de retorno, candidatura Stage, tracker, export PDF, push. Beta fechado na faixa interna com ~20 usuários convidados.

**Critérios de aceite F5:** APK/AAB na faixa interna; roteiro QA 100% executado e verde nos 3 devices; crash-free sessions >99% na primeira semana de beta; comparação iOS×Android de signups/semana no relatório (a leitura do iceberg).

---

# FASE 6 — Onboarding enxuto
*Objetivo: dos atuais 16-18 telas / 28-43 taps / 3-6 min (K2) para ≤8 telas / ≤90s, sem perder os dados que o TCE e o match exigem. Executar SÓ depois da baseline (T0.6) estar há ≥3 semanas em produção, para medir o impacto de verdade. Refs: K1-K3, G6, B7, espec. seção 2.*

**T6.1 — Comprimir as masking questions:** First/Last name + e-mail + telefone → 1 tela única; **data de nascimento entra como campo obrigatório nessa tela** (coluna já existe — B7; menores de 18 caem em experiência limitada: flag `is_minor`, sem compartilhamento com empresas, banner explicativo — primeira camada LGPD); Gender e AgeRange saem do fluxo (viram opcionais no Perfil; `age_range` é redundante com DOB).

**T6.2 — Formação com autocomplete** (T1.6 já entregou a infra) + semestre/previsão de formatura como passo único.

**T6.3 — Preferências de 6 telas → 2:** tela A (áreas máx. 3 + modalidade + tipo, em chips na mesma tela), tela B (cidade+raio + disponibilidade). `DesiredTitlesScreen` sai do onboarding (K3 provou: coletado e não usado no feed — vira refinamento opcional no Perfil).

**T6.4 — CV como acelerador pós-feed:** as Two Doors deixam de bloquear o caminho — o fluxo padrão leva ao feed após T6.3, com banner persistente "Importe seu currículo e a gente preenche seu perfil" disparando o fluxo de import existente (G6) a qualquer momento. A porta-trilha vira entrada da aba Currículo, não gate.

**T6.5 — Medição:** funil `onboarding_step_reached` re-mapeado para os passos novos (manter nomes antigos emitindo em paralelo por 2 semanas para comparação), meta: `onboarding_completed` ≥70% dos signups (vs. baseline), tempo mediano ≤90s via `onboarding_duration_ms`.

**Critérios de aceite F6:** fluxo novo atrás de flag `new_onboarding_v2`, A/B 50/50 por 2 semanas, decisão por dados no relatório; nenhum campo exigido pelo TCE perdido (nome completo, DOB, instituição, curso — checklist no PLANO); fluxo de menor de idade implementado e testado.

---

## Mapa de dependências e paralelização

```
F0 ─→ F1 ─→ F2 ─→ F3 ─→ F4
              └──────────→ F5 (Android: pode iniciar após F2, em janela dedicada — O3 pede não-paralelismo com frente grande)
F6: após T0.6 + 3 semanas de baseline; idealmente após F3
```

Ordem recomendada com 1 dev + Claude Code: F0 (3-5 dias) → F1 (1,5-2 semanas) → F2 (2 semanas) → F3 (1 semana) → F4 (2 semanas) → F5 (janela dedicada 3-6 semanas) → F6 (1 semana + 2 de medição). O fundador pode antecipar F5 se a leitura do iceberg Android virar prioridade comercial.

## O que este plano deliberadamente NÃO inclui (não implementar sem novo prompt)

Esteira TCE/e-sign/seguro (Step 2 do plano de negócio — depende dos primeiros pilotos pagos); portal self-service da empresa (o console admin cobre a fase concierge); páginas web públicas de vaga + universal links (B6 — exige AASA e domínio, fase própria); match v2 treinado em outcomes (precisa dos dados que F3/F4 começam a gerar); WhatsApp transacional; migração para dart-define; qualquer refactor dos arquivos de 2k+ linhas fora do caminho das tarefas.

---

*Documento pareado com: AUDITORIA-STAGE.md (estado atual), Especificação de Produto Stage (alvo) e Stage Business Plan Phase 1 (estratégia). Em caso de conflito entre este plano e a auditoria sobre um fato do código, a auditoria vence e o desvio é reportado no PLANO-FASE-N.md.*
