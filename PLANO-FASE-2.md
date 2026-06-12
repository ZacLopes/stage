# PLANO-FASE-2 — Feed server-side, modo lista e holdout do score

**Branch:** `fase-2-feed-server` · **Client:** release 2.4.0 · **Refs:** PLANO-MAE F2 (T2.1–T2.5 + T2.0 novo), AUDITORIA E1/E2/E4, F1–F5, O1 #2, espec. 3.2–3.5/4.3
**Status:** aprovado pelo fundador em 12/06 via ExitPlanMode, com a revisão do arquiteto externo incorporada (REV-1 abaixo). A implementação segue a ordem da seção 6.

> **REV-1 (12/06) — Revisão do arquiteto incorporada.** Trechos tocados marcados com `(REV-1)`:
> 1. **Keyset corrigido** — `ORDER BY rank_score DESC, id DESC` alinhado ao predicado `ROW(…) < ROW(…)` (o desenho anterior tinha `id ASC` no ORDER BY e `id DESC` implícito no predicado → loop infinito de duplicatas para os 52% sem prefs, onde tudo empatava em rank 0). Teste **all-ties** adicionado ao T2.1.
> 2. **Ranking re-especificado** — decay com piso `score × (0.6 + 0.4·exp(−dias/14))` (correção de especificação do PRÓPRIO arquiteto: o "desempate multiplicativo" original não desempatava, dominava — match 100 de 10 dias perdia pra match 50 de hoje) + **jitter determinístico** por (user, vaga, dia) que repõe a FUNÇÃO do `shuffle` para os 52% sem prefs. Paridade D2 intocada: piso e jitter mudam ORDEM, não CONJUNTO — os 7/7 md5 (comparação de conjuntos) permanecem válidos sem re-execução.
> 3. **Medição miúda** — prop `feed_source: 'rpc'|'legacy'` em `feed_loaded` (sem ela o aceite P50 não filtra rota nova×antiga); `total_available` retornado pelo RPC na 1ª página (estado B da exaustão); clamp `p_frozen_at := least(p_frozen_at, now())`.
> Pacote menor (decisões registradas): caso sintético com `p_min_salary` no teste SQL (fecha buraco de cobertura — nenhum dos 7 perfis exercitava salário); migration de dados normalizando títulos legacy mortos (~25 rows, só os não-ambíguos); checklist do fundador atualizado (F0/F1 mergeadas, 2.2.0 em prod, 2.3.0 em revisão).

## Contexto

O feed hoje é `JobRepository.fetchJobsWithDiagnostics` baixando TODAS as vagas ativas (469), filtrando em Dart e embaralhando com `Random()` sem seed — P50 real de 2.229ms. Não há onde plugar ranking nem paginação. A Fase 2 constrói a camada server-side (RPC `get_feed_page` com ranking determinístico v1), entrega a UI de lista atrás de flag, estados de exaustão honestos + `company_requests`, score em bandas e o holdout que responde "o match do pitch é verdade?". **Paridade de conjunto com o caminho atual é princípio de aceite** — e foi provada em plan mode (seção D2: 7/7 usuários, md5 idênticos). Rollback = flag off; o caminho antigo fica 100% intacto até a flag chegar a 100%.

**Decisões do fundador (12/06, AskUserQuestion):** rollout 10→50→100% com 3-4 dias por degrau (gatilho: zero regressão crash/`feed_load_failed` + save-rate estável); **modo padrão continua SWIPE, lista é opt-in via toggle** (conservador — a tese da lista será lida pela adoção do toggle e save-rate por modo, prop `feed_mode`); holdout em 20% dos elegíveis confirmado.

---

## 1. Verificações de plan mode (fatos numerados, medidos em prod 12/06)

**B1 — EXPLAIN ANALYZE da query candidata** (rodado em prod como service role, `user_id` parametrizado; query = espelho exato dos filtros client + ranking, ver D1):

| Perfil | user | Exec | Planning | Buffers | Resultado |
|---|---|---|---|---|---|
| (a) heavy swiper | `b7226e54` (569 swipes, prefs parciais) | **20,7ms** | 4,4ms | 1.969 hits | **0 vagas** (prefs dele zeram o catálogo) |
| (b) prefs vazias | `456ea636` (416 swipes, zero prefs) | **4,9ms** | 4,6ms | 1.841 hits | 322 candidatas → 20 retornadas |
| (c) prefs completas | `a91e0ed2` (3 áreas+2 cidades+3 modelos+2 tipos) | **74,0ms** | 14,7ms | 521 hits | **2 vagas** |

- Nota técnica do (c): rodou na variante SEM `MATERIALIZED` no CTE de prefs — o planner re-avaliou os InitPlans por referência (74ms). Com `prefs AS MATERIALIZED` (variantes a/b) o custo cai pra ~5-21ms; **o RPC final computa prefs UMA vez em variáveis plpgsql**, então o perfil real é o de (a)/(b).
- Índices que o planner usou: `idx_jobs_active_published_at` (Index Cond `is_active=true`; deadline + prefs como Filter — removeu 8 vencidas + N por prefs) e `swipe_actions_user_id_job_id_key` (**Index Only Scan no anti-join**, ~0,002ms/probe, Heap Fetches 82-190). Sort: quicksort/top-N 25-29kB em memória.
- Por que o planner escolheu isso: 469 vagas ativas cabem numa passada do índice parcial composto; o anti-join por unique index é O(1) por vaga; o Sort vê só o conjunto pós-filtro (2–322 rows).
- **Fato extra que muda o produto:** os perfis (a) e (c) mostram que filtros estritos zeram ou quase-zeram o feed de usuários reais HOJE (paridade D2 prova que o app atual se comporta igual). Isso reforça T2.3 (exaustão honesta + expansão) como parte essencial, não cosmética.

**B2 — Índices existentes** (`pg_indexes`):
- `jobs`: pk, `(source, external_id)` unique, `(source, last_seen_at) WHERE source IS NOT NULL`, **`(is_active, published_at DESC)`** ✓
- `swipe_actions`: pk, **`(user_id, job_id)` unique** ✓, `(job_id)`, `(user_id, applied) WHERE action='liked'`
- `profile_desired_titles (user_id, order_index)`, `profile_other_locations (user_id)`, `profile_job_preferences pk(user_id)` ✓
- **Decisão (fato vence o plano-mãe):** NENHUM índice novo no v1. O `jobs(is_active, area, published_at)` sugerido no plano-mãe não seria usado — o filtro de área é por expressão (`lower(btrim(unaccent(area)))` + sinônimos), btree em `area` cru não serve; e a 469–5.000 rows o scan do índice existente é o plano certo. Reavaliar em >10k vagas.

**B3 — Baseline de latência atual:** `feed_loaded` JÁ carrega `load_duration_ms` em prod (emitido em `jobs_viewmodel.dart:275` com `cache_hit:false`). PostHog, últimos 7 dias, loads frios: **n=556, P50 = 2.228,5ms, P95 = 4.605,8ms**. Nenhuma instrumentação nova é pré-requisito; a comparação será pelo MESMO evento com prop nova `feed_mode`. Meta P50<800ms = melhora de ~3× sobre a baseline.

**B4 — Restrição do CardSwiper:** confirmada — comentário em `job_repository.dart:30-34` ("CardSwiper exige array imutável durante a sessão; mexer dessincroniza current-index") + `jobs_swipe_screen.dart` (`cardsCount: vm.jobs.length`, linha ~1316; comentário linha 56 sobre reinício perder posição). Solução desenhada: snapshot imutável por página (T2.2).

**B5 — Distribuição de prefs nulas** (2.014 usuários com sign-in ≤30d, de 2.074 totais): sem áreas **1.045 (52%)** · sem work_mode **1.050 (52%)** · sem localização **951 (47%)** · sem job_types **1.128 (56%)**. ~Metade da base depende da null-permissividade — o RPC trata array NULL = "sem filtro, tudo passa", exatamente como `FilterHelpers` (provado em D2 com os perfis vazios/parciais).

**B6 — Vocabulário e normalização:**
- `jobs.area` é canônico e NOT NULL (12 valores: Tecnologia 66, Finanças 58, Geral 52, Saúde 42, Operações 37, Produto 37, Engenharia 33, Jurídico 32, Marketing 32, RH 32, Vendas 24, Administrativo 24). `work_model`/`job_type` NOT NULL com vocabulário fechado PT (`presencial/hibrido/remoto`; `estagio/clt_junior/trainee/temporario`). 0 vagas sem cidade+estado.
- `profile_desired_titles.title` tem cauda legacy do merge F1: "administração" (12), "Tecnologia & Programação" (5), "Administração & Processos" (5), "programação" (3)… que **não casam** no client (nem match direto nem sinônimos) — o SQL espelha o mesmo miss (provado: usuário `c5bdb3ac` com "Finanças | administração" → 0 vagas em AMBOS os lados).
- Espelho SQL: `lower(btrim(unaccent(x)))` ↔ `FilterHelpers.normalize` (lowercase+trim+mapa de acentos PT-BR). Divergência teórica: `unaccent` remove diacríticos de qualquer língua, o mapa Dart só PT-BR (ex.: "ý", "ø") — nos dados reais não ocorre (paridade 7/7); listado como risco residual monitorado pelo harness.
- Sinônimos de área (13 chaves) e cidade→UF (28 entradas) replicados literalmente de `filter_helpers.dart` como `VALUES` na migration, com comentário de espelhamento + harness de paridade commitado pra re-verificação.

**B7 — Flag PostHog `match_score_visibility_v1`:** existe (id 693925), **inativa (`active:false`), `last_called_at: null`** (nunca avaliada por nenhum client), multivariate `percent` 50 / `hidden` 50, exclui cohort "Internal users" (303703), bucketing por distinct_id. Client lê via `Analytics.getFlag(key)` (`analytics_service.dart:437` — `Posthog().getFeatureFlag`, cache do SDK, async). **Fato vence o prompt:** as variantes são `percent`/`hidden` (não `hidden_pre_swipe`) — reusamos a flag e as variantes existentes, só mudando o split pra 80/20 e ativando (seguro: nunca foi chamada).

**B8 — Mecânica do `app_feature_flags`:** **suporta percentual nativamente** — `rollout_pct` 0-100 + bucket determinístico `userId.hashCode.abs() % 100` (`feature_flags_service.dart:74-100`). 3 flags em prod (`adapt_v2_enabled` 100%, `match_v2_enabled` 0, `templates_v2_enabled` 0). **Fato vence o doc-comment do service:** `refresh()` é chamado SÓ no boot (`main.dart:151`) — não há refresh on-foreground apesar do comentário. Consequência: mudança de rollout pega no próximo cold start; com degraus de 3-4 dias isso é aceitável. **Decisão: `feed_list_v1` vive no `app_feature_flags`** (estrutural, kill switch síncrono e failure-safe→false; R4) — a flag PostHog fica só pro holdout (experimento, que é o caso dela).

**B9 — Pesos exatos do match determinístico** (`match_score.dart:162-287`):

| Dimensão | Peso | Entra no denominador quando | Matched quando |
|---|---|---|---|
| Área | 30 | `prefs.areas` não-vazio | `isAreaMatch` (sinônimos, acento-insens., estrito no null da vaga) |
| Tipo de vaga | 20 | `prefs.jobTypes` não-vazio | `jobTypes.contains(jobTypeRaw)` |
| Localização | 15 | `prefs.locations` não-vazio | `isLocationMatch` (remoto sempre passa; cidade substring 2-vias; cidade→UF) |
| Modelo | 15 | `prefs.workModels` não-vazio | `workModels.contains(workModelRaw)` |
| Salário | 10 | `minSalary > 0` declarado | `salary_min >= minSalary` (vaga sem salário NÃO pontua) |
| Skills | 10 | userPool não-vazio | proporcional: `(overlap_ratio × 2.5).clamp(0,1) × 10` |

Normalização: `score/totalWeight×100` (só dimensões declaradas no denominador). Sem prefs → `unknown`. **Fatos relevantes:** (i) prefs relacionais NÃO têm salário (coluna não existe em `profile_job_preferences` — min_salary morreu no merge F1); salário só chega via filtro local explícito; (ii) skills depende de tokenizador Dart com stop-words e cap — impossível espelhar bit a bit em SQL (ver decisão D-2).

**B10 — Nulls do ranking** (469 ativas): sem salário **390 (83%)**, sem deadline **226 (48%)**, deadline vencido-mas-ativa 8 (filtradas), sem `published_at` 0. **Colunas lat/long NÃO EXISTEM em `jobs`** — proximidade geográfica confirmada FORA (D7). Regras de null no ranking v1: salário-null não pontua (e a dimensão nem entra sem filtro do user), deadline-null não afeta score (só filtro de vencida), freshness usa `published_at` (0 nulls).

**B11 — Conta interna (T2.0):** `internal-fase0-test@stage.app` = user `3eaf8faa-a905-4d80-aced-40be7781f623`, identity `email`, senha conhecida da F0, 1 área semeada ("Tecnologia"), sem row em `profile_job_preferences`. Formato sintético confirmado (`phone_auth_helpers.dart:16-22`): `phone_<cc-dígitos><fone-dígitos>@stage.app`; `parseSyntheticEmail` exige prefixo de país ∈ {351,55,44,1}. **Caminho de login confirmado no código:** `PhoneSignupScreen._handleSignup` → `vm.signUp(email: sintético)` → erro "already registered" → **fallback automático `signIn(email, password)`** (`user_viewmodel.dart:580-585`) — ou seja, o fundador digita telefone+senha no fluxo normal e entra. Conversão preserva `user_id` (FKs intactas — referenciam id, não email). **Gap encontrado:** `profile_personal.onboarding_completed_at` é NULL → cairia no onboarding (e poderia sobrescrever a área semeada); T2.0 inclui semear o gate.

---

## 2. Decisões explícitas (adotadas/derivadas — cada uma com o fato que a sustenta)

- **D-1 · Zero índices novos no v1.** Fato: planner usa `idx_jobs_active_published_at` + unique de swipe; projeção 5k com folga (D1). Desvio consciente do plano-mãe (pedia `jobs(is_active, area, published_at)`); reavaliar >10k vagas.
- **D-2 · Skills (peso 10) FORA do ranking v1 SQL.** Fatos: (i) tokenizador Dart (regex+stop-words+cap 1500 chars+ratio×2.5) não tem espelho exato em SQL — qualquer aproximação viola "coerência client-server"; (ii) custo: tokenizar `description` de 469→5k vagas por request inviabiliza o orçamento de latência. A normalização por `totalWeight` já renormaliza os 90 pontos restantes ao declarado. O score DO CARD (IA + fallback determinístico com skills) continua client-side inalterado — ranking ordena, card explica.
- **D-3 · `feed_list_v1` no `app_feature_flags`** (suporta %, kill switch síncrono failure-safe). PostHog flag não participa do rollout do feed. Fato: B8.
- **D-4 · Salário no ranking só quando `p_min_salary` (filtro local) vier declarado.** Fato: prefs relacionais não têm salário (B9).
- **D-5 · Holdout reusa a flag e as variantes existentes** (`percent`/`hidden`), split alterado pra 80/20, ativação na release 2.4.0. Fato: B7 (flag inativa e nunca chamada — reconfigurar é seguro e evita flag duplicada).
- **D-6 · Modo padrão = swipe; lista opt-in com toggle persistido** (decisão do fundador 12/06). Com a flag ON, **ambos os modos consomem o RPC** (lista = scroll infinito por cursor; swipe = snapshot imutável da página corrente, auto-busca da próxima página ao esgotar o snapshot). `jobs.shuffle(Random())` e o fetch-tudo morrem SÓ quando a flag chegar a 100%.
- **D-7 · Cursor keyset estável via `p_frozen_at`:** freshness e jitter dependem do tempo — entre páginas, o drift de `now()` mudaria `rank_score` e quebraria o cursor. O client envia o timestamp da 1ª página em todas as páginas da mesma sessão de paginação; `(rank_score, id)` vira determinístico (o jitter usa `date_trunc('day', p_frozen_at)` no seed — estável na sessão, rotaciona por dia). Comparação por `ROW(rank_score, id) < ROW(p_cursor_rank, p_cursor_id)` com **`ORDER BY rank_score DESC, id DESC`** (REV-1: ASC no id contradizia o predicado e travava a paginação dos 52% sem prefs em loop de duplicatas). Clamp server-side `p_frozen_at := least(p_frozen_at, now())`.
- **D-10 (REV-1) · Ranking com piso + jitter:** `rank = score × (0.6 + 0.4·exp(−dias/14)) + jitter(user, vaga, dia)`, jitter `(abs(hashtext(…)) % 1000)/250.0` ≈ 0–4 pontos. Origem: correção de especificação do arquiteto (o "desempate multiplicativo" original dominava em vez de desempatar) + reposição da função do `shuffle` (fato E1: ordem fixa matou engajamento; os 52% sem prefs teriam feed em ordem de id fixa). Muda ORDEM, não CONJUNTO — paridade D2 intocada.
- **D-11 (REV-1) · Normalização dos títulos legacy mortos** (pacote menor, adotado): migration de dados idempotente convertendo só os mapeamentos NÃO-ambíguos (~25 rows: "administração"/"Administração"/"Administração & Processos"→"Administrativo"; "Tecnologia & Programação" (variações de caixa)/"programação"→"Tecnologia"; "marketing"→"Marketing"; "Marketing & Branding"→"Marketing"; "vendas"→"Vendas"; "finanças & Controladoria"→"Finanças"). "processos" fica de fora (ambíguo — registrado). Parity-safe: ambos os caminhos leem a mesma fonte; harness re-rodado após a migration. Padrão anti-duplicata: `UPDATE … WHERE NOT EXISTS (mesmo user_id + título-alvo)` seguido de `DELETE` dos remanescentes legacy.
- **D-8 · Paridade by construction:** os FILTROS chegam como argumentos do RPC (o client resolve "filtros locais SE existem, senão prefs do Perfil" — exatamente o `_performFetch` de hoje, `jobs_viewmodel.dart:290-310`; SharedPreferences é invisível ao servidor). As prefs de RANKING são lidas server-side via `auth.uid()` (identidade relacional — espelho de `_loadProfilePrefs`). `min_match_score` (filtro por score IA) permanece client-side por página, como hoje (depende do par user×vaga + cache `match_analyses`); página pode encolher — documentado na UI de lista como hoje no swipe.
- **D-9 · RPC `SECURITY INVOKER`** — roda como o usuário, RLS vale, `auth.uid()` resolve swipes e prefs. `GRANT EXECUTE TO authenticated`, revoke de `anon`.

---

## 3. D1 — SQL completo do RPC + projeção a 5k

### 3.1 Migration `2026xxxx_get_feed_page.sql` (DDL íntegra)

```sql
-- FASE 2 (T2.1): feed server-side com ranking determinístico v1.
-- ESPELHO de lib/features/jobs/utils/filter_helpers.dart e dos pesos de
-- match_score.dart (30/20/15/15/10; skills fora — decisão D-2 do PLANO-FASE-2).
-- Mudou lá → muda aqui → roda tools/feed_parity/ antes do merge.

create or replace function public.get_feed_page(
  p_limit              int          default 20,
  p_cursor_rank        numeric      default null,
  p_cursor_id          uuid         default null,
  p_filter_areas       text[]       default null,  -- null = sem filtro (permissivo)
  p_filter_locations   text[]       default null,
  p_filter_work_models text[]       default null,  -- vocabulário PT do client
  p_filter_job_types   text[]       default null,
  p_min_salary         int          default null,  -- centavos; só de filtro local
  p_frozen_at          timestamptz  default now()  -- D-7: cursor estável
) returns table (
  job_id uuid, score int, rank_score numeric,
  reason_area boolean, reason_location boolean, reason_work_model boolean,
  reason_job_type boolean, reason_salary boolean,
  total_after_filters bigint, -- só na 1ª página (cursor null); senão null
  total_available bigint      -- (REV-1) idem: pós exclusões básicas, PRÉ filtros de args
)
language plpgsql stable security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  -- prefs de RANKING (identidade relacional — espelho de _loadProfilePrefs)
  r_areas text[]; r_locations text[]; r_work_models text[]; r_job_types text[];
begin
  if v_uid is null then
    raise exception 'get_feed_page requer usuário autenticado';
  end if;
  -- (REV-1) clamp defensivo: client bugado/malicioso não viaja no futuro pra inflar freshness
  p_frozen_at := least(coalesce(p_frozen_at, now()), now());

  select array_agg(lower(btrim(unaccent(title))))
    into r_areas from profile_desired_titles where user_id = v_uid;

  select nullif(array_remove(array[
           (select lower(btrim(unaccent(primary_location_city)))
              from profile_job_preferences
             where user_id = v_uid
               and coalesce(btrim(primary_location_city),'') <> '')
         ] || coalesce((select array_agg(lower(btrim(unaccent(city))))
                          from profile_other_locations
                         where user_id = v_uid
                           and coalesce(btrim(city),'') <> ''), '{}'), null), '{}')
    into r_locations;

  select array_agg(case wm when 'remote' then 'remoto'
                           when 'hybrid' then 'hibrido'
                           when 'in_person' then 'presencial' else wm end)
    into r_work_models
    from profile_job_preferences jp, unnest(coalesce(jp.work_mode,'{}'::text[])) wm
   where jp.user_id = v_uid;

  select case when jp.job_types is null or array_length(jp.job_types,1) is null
              then null else jp.job_types end
    into r_job_types from profile_job_preferences jp where jp.user_id = v_uid;

  return query
  with syn(canonical, synonym) as (values
    -- ESPELHO LITERAL de FilterHelpers._areaSynonyms (13 chaves)
    ('rh','rh'),('rh','recursos humanos'),('rh','gente'),('rh','gente e gestao'),('rh','people'),
    ('recursos humanos','rh'),('recursos humanos','recursos humanos'),('recursos humanos','gente'),
    ('recursos humanos','gente e gestao'),('recursos humanos','people'),
    ('tecnologia','tecnologia'),('tecnologia','ti'),('tecnologia','tech'),
    ('tecnologia','engenharia de software'),('tecnologia','desenvolvimento'),('tecnologia','software'),
    ('engenharia','engenharia'),('engenharia','engenharia de software'),('engenharia','engineering'),
    ('design','design'),('design','produto'),('design','ux'),('design','ui'),
    ('design','product design'),('design','experiencia do usuario'),
    ('produto','produto'),('produto','design'),('produto','product'),('produto','ux'),('produto','ui'),
    ('marketing','marketing'),('marketing','growth'),('marketing','comunicacao'),
    ('marketing','crm'),('marketing','brand'),
    ('vendas','vendas'),('vendas','comercial'),('vendas','sales'),('vendas','business development'),
    ('financas','financas'),('financas','finance'),('financas','controladoria'),('financas','contabilidade'),
    ('operacoes','operacoes'),('operacoes','operations'),('operacoes','logistica'),
    ('operacoes','supply chain'),('operacoes','cs'),('operacoes','customer success'),
    ('operacoes','atendimento'),('operacoes','suporte'),
    ('juridico','juridico'),('juridico','legal'),('juridico','compliance'),
    ('administrativo','administrativo'),('administrativo','admin'),
    ('geral','geral'),('geral','general')
  ),
  city_state(city, uf) as (values
    -- ESPELHO LITERAL de FilterHelpers._cityToState (28 entradas)
    ('sao paulo','sp'),('campinas','sp'),('santos','sp'),('sao bernardo do campo','sp'),
    ('guarulhos','sp'),('osasco','sp'),('sao jose dos campos','sp'),('ribeirao preto','sp'),('sorocaba','sp'),
    ('rio de janeiro','rj'),('niteroi','rj'),
    ('belo horizonte','mg'),('uberlandia','mg'),('contagem','mg'),
    ('curitiba','pr'),('londrina','pr'),('porto alegre','rs'),('caxias do sul','rs'),
    ('brasilia','df'),('salvador','ba'),('recife','pe'),('fortaleza','ce'),('manaus','am'),
    ('florianopolis','sc'),('joinville','sc'),('goiania','go'),('vitoria','es'),('belem','pa')
  ),
  -- filtros efetivos normalizados (args crus do client, mesma normalização)
  f as (
    select (select array_agg(lower(btrim(unaccent(a)))) from unnest(p_filter_areas) a)       as areas,
           (select array_agg(lower(btrim(unaccent(l)))) from unnest(p_filter_locations) l)    as locations,
           p_filter_work_models                                                               as work_models,
           p_filter_job_types                                                                 as job_types
  ),
  scored as (
    select j.id,
      -- matched do FILTRO (args) — paridade com _applyPreferenceFilters
      (f.areas is null or exists (
         select 1 from unnest(f.areas) ua
         where ua = lower(btrim(unaccent(j.area)))
            or exists (select 1 from syn s where s.canonical = lower(btrim(unaccent(j.area))) and s.synonym = ua)
            or exists (select 1 from syn s where s.canonical = ua and s.synonym = lower(btrim(unaccent(j.area))))
      )) as pass_area,
      (f.work_models is null or j.work_model = any(f.work_models)) as pass_model,
      (f.job_types  is null or j.job_type  = any(f.job_types))   as pass_type,
      (f.locations is null or j.work_model = 'remoto' or (
         (coalesce(btrim(j.location_city),'') <> '' or coalesce(btrim(j.location_state),'') <> '')
         and exists (
           select 1 from unnest(f.locations) ul
           left join city_state cs_u on cs_u.city = ul
           left join city_state cs_j on cs_j.city = lower(btrim(unaccent(coalesce(j.location_city,''))))
           where (coalesce(btrim(j.location_city),'') <> ''
                  and (lower(btrim(unaccent(j.location_city))) like '%'||ul||'%'
                       or ul like '%'||lower(btrim(unaccent(j.location_city)))||'%'))
              or (cs_u.uf is not null and lower(btrim(unaccent(coalesce(j.location_state,'')))) = cs_u.uf)
              or (cs_j.uf is not null and cs_u.uf is not null and cs_j.uf = cs_u.uf)
              or (ul = lower(btrim(unaccent(coalesce(j.location_state,'')))))
         )
      )) as pass_loc,
      (p_min_salary is null or p_min_salary <= 0
        or j.salary_min is null or j.salary_min >= p_min_salary) as pass_salary,
      -- matched do RANKING (prefs relacionais r_*) — mesmos predicados
      (r_areas is not null and exists (
         select 1 from unnest(r_areas) ua
         where ua = lower(btrim(unaccent(j.area)))
            or exists (select 1 from syn s where s.canonical = lower(btrim(unaccent(j.area))) and s.synonym = ua)
            or exists (select 1 from syn s where s.canonical = ua and s.synonym = lower(btrim(unaccent(j.area))))
      )) as m_area,
      (r_job_types is not null and j.job_type = any(r_job_types)) as m_type,
      (j.work_model = 'remoto' or (
         (coalesce(btrim(j.location_city),'') <> '' or coalesce(btrim(j.location_state),'') <> '')
         and r_locations is not null and exists (
           select 1 from unnest(r_locations) ul
           left join city_state cs_u on cs_u.city = ul
           left join city_state cs_j on cs_j.city = lower(btrim(unaccent(coalesce(j.location_city,''))))
           where (coalesce(btrim(j.location_city),'') <> ''
                  and (lower(btrim(unaccent(j.location_city))) like '%'||ul||'%'
                       or ul like '%'||lower(btrim(unaccent(j.location_city)))||'%'))
              or (cs_u.uf is not null and lower(btrim(unaccent(coalesce(j.location_state,'')))) = cs_u.uf)
              or (cs_j.uf is not null and cs_u.uf is not null and cs_j.uf = cs_u.uf)
              or (ul = lower(btrim(unaccent(coalesce(j.location_state,'')))))
         )
      )) as m_loc,
      (r_work_models is not null and j.work_model = any(r_work_models)) as m_model,
      (p_min_salary is not null and p_min_salary > 0
       and j.salary_min is not null and j.salary_min >= p_min_salary) as m_salary,
      j.published_at
    from jobs j
    where j.is_active = true
      and (j.deadline is null or j.deadline >= now())
      and not exists (select 1 from swipe_actions sa
                      where sa.user_id = v_uid and sa.job_id = j.id)
  ),
  ranked as (
    select s.id,
      case when w.total > 0 then round(
        (30*s.m_area::int + 20*s.m_type::int + 15*s.m_loc::int
         + 15*s.m_model::int + 10*s.m_salary::int)::numeric / w.total * 100)
      else 0 end as score,
      s.m_area, s.m_loc, s.m_model, s.m_type, s.m_salary
    from scored s
    cross join lateral (select
        (case when r_areas       is not null then 30 else 0 end)
      + (case when r_job_types   is not null then 20 else 0 end)
      + (case when r_locations   is not null then 15 else 0 end)
      + (case when r_work_models is not null then 15 else 0 end)
      + (case when p_min_salary is not null and p_min_salary > 0 then 10 else 0 end)
      as total) w
    where s.pass_area and s.pass_model and s.pass_type and s.pass_loc and s.pass_salary
  ),
  -- (REV-1) rank_score = score × (0.6 + 0.4·exp(−dias/14)) + jitter
  --   · piso 0.6: frescor custa NO MÁXIMO 40% do score — relevância domina
  --     (correção de especificação do arquiteto: o multiplicador puro fazia
  --     match 100 de 10 dias perder pra match 50 de hoje; crossover ~9,7 dias).
  --   · jitter determinístico 0..~4 pontos, seed (user, vaga, dia da sessão):
  --     repõe a FUNÇÃO do shuffle pros 52% sem prefs (rank base 0 → feed
  --     rotaciona por dia, não por id fixo — fato E1: ordem fixa matou
  --     engajamento) e desempata scores quantizados sem reordenar bandas.
  --     Determinístico dentro da sessão (p_frozen_at truncado) → keyset estável (D-7).
  rank_calc as (
    select r.id, r.score,
      (r.score * (0.6 + 0.4 * exp(-extract(epoch from (p_frozen_at - s2.published_at)) / 86400.0 / 14.0))
       + (abs(hashtext(v_uid::text || r.id::text || date_trunc('day', p_frozen_at)::text)) % 1000) / 250.0
      )::numeric as rank_score,
      r.m_area, r.m_loc, r.m_model, r.m_type, r.m_salary
    from ranked r join scored s2 on s2.id = r.id
  )
  select rc.id, rc.score::int, rc.rank_score,
    rc.m_area, rc.m_loc, rc.m_model, rc.m_type, rc.m_salary,
    case when p_cursor_id is null then (select count(*) from ranked) else null end as total_after_filters,
    case when p_cursor_id is null then (select count(*) from scored) else null end as total_available
  from rank_calc rc
  where p_cursor_id is null
     or row(rc.rank_score, rc.id) < row(p_cursor_rank, p_cursor_id)
  -- (REV-1) id DESC: ORDER BY alinhado ao predicado ROW(…) < ROW(…) — com
  -- id ASC, empates de rank (52% da base com tudo em rank≈jitter) entravam
  -- em loop de duplicatas na página 2.
  order by rc.rank_score desc, rc.id desc
  limit greatest(1, least(p_limit, 50));
end $$;

revoke all on function public.get_feed_page from public, anon;
grant execute on function public.get_feed_page to authenticated;
```

Notas de implementação: (i) a forma final em plpgsql computa as prefs UMA vez (variáveis), eliminando os InitPlans repetidos do perfil (c) do B1; (ii) `unaccent` é STABLE — ok dentro da função STABLE, sem índice de expressão; (iii) `p_limit` clampado 1..50; (iv) o JOIN `ranked×scored` da versão final será colapsado num único SELECT na migration real (escrito aqui em CTEs pra legibilidade — a query do EXPLAIN B1 é a forma colapsada e é a que foi medida); (v) RLS: `jobs` tem SELECT pra authenticated, `swipe_actions`/`profile_*` own-select — invoker funciona (validado: a mesma lógica roda hoje no client com anon key + RLS).

### 3.2 EXPLAIN ANALYZE colados (resumo dos planos reais — íntegra no relatório da fase)

Perfil (a) heavy swiper — plano com prefs MATERIALIZED (espelho da forma final):
```
Limit (actual time=18.988..19.009 rows=0)  Buffers: shared hit=1969
 └─ Sort top-N (Memory: 25kB)
     └─ Nested Loop (Join Filter: prefs; Rows Removed: 271)
         └─ Nested Loop Anti Join (actual 0.045..2.320 rows=271)
             ├─ Index Scan idx_jobs_active_published_at (rows=461; deadline Filter removed 8)
             └─ Index Only Scan swipe_actions_user_id_job_id_key (0.002ms/probe, Heap Fetches: 190)
Planning 4.397ms · Execution 20.672ms
```
Perfil (b) prefs vazias: mesmo shape, filtros viram no-op (`pr.* IS NULL` curto-circuita; subplans de área/cidade "never executed"), 322 rows → top-N 20. Execution **4.919ms**. Perfil (c) prefs completas: 74.005ms na variante sem MATERIALIZED (InitPlans re-avaliados — eliminado na forma final), 2 rows.

*(REV-1)* Os EXPLAIN acima mediram a forma pré-revisão do rank (multiplicador puro, `id ASC`). As mudanças da REV-1 (piso+jitter, `id DESC`, clamp, 2 counts na 1ª página) alteram só expressões escalares e a direção do tie-break — **zero impacto no shape do plano** (mesmos scans, mesmo anti-join, mesmo top-N). O EXPLAIN do RPC final em prod (verificação do T2.1) confirma com números.

### 3.3 Projeção a 5k vagas (raciocinada termo a termo)

| Termo do plano | Escala | 469 ativas (medido) | 5.000 (projetado) |
|---|---|---|---|
| Index Scan jobs + filtros | linear em vagas ativas | ~1,0ms (461 rows) + Join Filter ~2,3ms total | ~25-35ms |
| Anti-join swipe_actions | linear × O(1) por probe | 461 probes ≈ 1,0ms | ~10ms (5k probes) |
| Subplans área/cidade | linear no conjunto pós-modelo/tipo | 213 avaliações ≈ 10ms | ~100ms pior caso (sem pré-filtro de modelo/tipo) |
| Sort top-N | n log k, k=20 | <1ms | ~5ms |
| **Total estimado** | | **5-21ms** | **~50-150ms** |

Folga ≥5× sobre o aceite de 800ms — que inclui rede + PostgREST (não medidos pelo EXPLAIN; a medição de aceite é fim-a-fim no evento `feed_loaded`, e o T2.0 existe pra validar no device antes do rollout). O termo que pior escala é o subplan de cidade (LIKE 2-vias por localização×vaga); se a 5k ele estourar, a saída registrada é pré-computar `lower(btrim(unaccent(location_city)))` como coluna gerada + índice — adiado por D-1 (sem necessidade hoje).

---

## 4. D2 — Prova de paridade (executada em plan mode, 12/06)

**Metodologia (sem reimplementação):** o conjunto-client foi produzido rodando o **código Dart real** — `filter_helpers.dart` copiado byte-idêntico (sha256 `7c2a33c4…49fea` conferido) e importado por um harness que espelha literalmente `fetchJobsWithDiagnostics` (exclusão de swipadas + deadline) → `_loadProfilePrefs` (mapeamento relacional→prefs, EN→PT) → `_applyPreferenceFilters` — sobre snapshot de prod (469 vagas ativas + prefs + swipes por usuário). O conjunto-RPC veio da query candidata (forma colapsada do 3.1) no mesmo snapshot. Comparação: count + md5 dos ids ordenados (uuid em PG ordena como o sort lexicográfico do hex — mesma ordem nos dois lados).

| Usuário | Perfil | n client (Dart real) | n RPC (SQL) | md5 client | md5 RPC | Veredito |
|---|---|---|---|---|---|---|
| `a91e0ed2` | prefs cheias + título legacy "Tecnologia & Programação" | 2 | 2 | `9ea9150d…` | `9ea9150d…` | ✅ idêntico |
| `b7226e54` | heavy swiper (569 swipes), prefs parciais | 0 | 0 | `d41d8cd9…` (vazio) | `d41d8cd9…` | ✅ idêntico |
| `456ea636` | prefs vazias, 416 swipes | 322 | 322 | `26f4a54a…` | `26f4a54a…` | ✅ idêntico |
| `1d052e97` | só cidade primária "São Paulo" | 155 | 155 | `1c5f5076…` | `1c5f5076…` | ✅ idêntico |
| `16835f3d` | 7 áreas + 3 modelos + 3 tipos, SEM cidade | 159 | 159 | `c4abf1e3…` | `c4abf1e3…` | ✅ idêntico |
| `d466f487` | conta nova (criada 12/06, 0 swipes, 0 prefs) | 461 | 461 | `892ccde4…` | `892ccde4…` | ✅ idêntico |
| `c5bdb3ac` | títulos legacy "Finanças \| administração" | 0 | 0 | `d41d8cd9…` | `d41d8cd9…` | ✅ idêntico |

**Divergências: ZERO (7/7).** Os dois conjuntos-vazios são paridade legítima, explicada linha a linha:
- `b7226e54`: área "Administrativo" (24 vagas) ∩ `presencial` ∩ `estagio` ∩ localização "Novo Gama" (GO; não está no mapa cidade→UF, nenhum substring casa, nenhuma vaga lá) → 0 nos DOIS lados. Esse usuário vê feed vazio no app HOJE.
- `c5bdb3ac`: "administração" não casa "Administrativo" (sem sinônimo no Dart — miss espelhado), "Finanças" casa 58 vagas, mas ∩ "Mogi das Cruzes" (fora do mapa; só substring) → 0 nos dois lados.

**Harness commitado** em `tools/feed_parity/` (script Dart + SQL + README) para re-execução: (i) pós-implementação do RPC real em prod, (ii) sempre que `filter_helpers.dart` ou a migration mudarem, (iii) após a migration de títulos legacy (D-11).

*(REV-1)* As mudanças de ranking da revisão (piso + jitter + `id DESC`) alteram ORDEM, não CONJUNTO — a paridade acima (md5 de ids **ordenados por id**, comparação de conjuntos) permanece válida sem re-execução por essa causa. Buraco de cobertura registrado e fechado: nenhum dos 7 perfis exercita `p_min_salary` (a dimensão morreu no merge F1; só filtro local a seta) — o teste SQL do T2.1 ganha caso sintético com `p_min_salary` setado (vaga sem salário passa permissiva; vaga abaixo do mínimo cai; vaga acima passa e pontua +10).

---

## 5. D3 — Desenho completo do holdout (T2.4)

**Flag:** `match_score_visibility_v1` (PostHog id 693925, hoje inativa/nunca chamada). Reconfigurar: variantes `percent` **80** / `hidden` **20**, manter exclusão do cohort interno (303703), ativar junto com a release 2.4.0 aprovada. Bucketing por distinct_id (estável entre sessões; users são identified — sem necessidade de experience continuity).

**Elegibilidade (quem entra no experimento):** `confidence ∈ {high, medium}` — calculada client-side por `MatchScoreCalculator.computeConfidence` (≥3 dimensões declaradas), que é EXATAMENTE o gate que decide se o número aparece hoje (`job_card_shown` F3). Randomizar sobre todos contaminaria: os 28% sem score são selecionados por completude de perfil, não aleatórios.

**Ponto exato de avaliação no client:** no `JobsViewModel`, junto do cálculo de confidence da sessão (1× por sessão, após `ensureProfilePrefsLoaded`): se `confidence == low` → usuário NÃO-elegível, comportamento atual ("Análise limitada"), `score_visible` reflete o que de fato apareceu. Se elegível → `await Analytics.getFlag('match_score_visibility_v1')`; `'hidden'` → ocultar banda E chips pré-swipe (card e célula da lista), revelar no detalhe da vaga; `'percent'`/null/erro → exibir normal (failure-safe = controle). Resultado cacheado na sessão (sem flicker por card).

**Instrumentação (R7 — catálogo + emissor no MESMO PR):** prop nova `score_visible: bool` (o que o usuário VIU de fato, pós-flag e pós-confidence) em `job_card_shown` e `job_swiped`; prop `holdout_variant: 'percent'|'hidden'|null` (null = não-elegível) nos mesmos eventos para cortar a análise por atribuição e detectar contaminação.

**Plano de análise pós-≥2-semanas (escrito agora, executado no relatório):**
- População: eventos `job_swiped` com `holdout_variant` não-nulo, janela ≥14 dias da ativação, excluindo cohort interno.
- Métrica primária: **save-rate por banda** = `job_swiped[action=liked] / job_card_shown`, agrupado por banda do `match_score` do próprio evento (Alta ≥70 / Média 40-69 / Baixa <40) × `score_visible`.
- HogQL (esqueleto, rodável no relatório):
```sql
SELECT properties.score_visible AS visible,
  multiIf(toFloat(properties.match_score) >= 70, 'alta',
          toFloat(properties.match_score) >= 40, 'media', 'baixa') AS banda,
  countIf(event = 'job_swiped' AND properties.action = 'liked') /
  nullif(countIf(event = 'job_card_shown'), 0) AS save_rate
FROM events
WHERE event IN ('job_card_shown','job_swiped')
  AND properties.holdout_variant IS NOT NULL
  AND timestamp > toDateTime('<data_ativacao>')
GROUP BY visible, banda ORDER BY visible, banda
```
- Critério (plano-mãe F2): gap de save-rate (alta − baixa) no grupo `hidden` **colapsando >60%** vs o gap no grupo `percent` → exibição pré-swipe é ancoragem → banda/chips pré-swipe saem do padrão até o match v2. Gap persistindo (≥40% do gap do controle) → há sinal preditivo real; v1 pode ser calibrado em cima.
- Sanidade: verificar n por célula (≥~300 impressões/célula para ler direção; base elegível estimada em algumas centenas de usuários ativos — se subamostrado em 14 dias, estender a janela em vez de inflar o %).

---

## 6. Escopo, tarefas e PRs (ordem real de execução)

Camadas declaradas por tarefa: **[SERVER-IMEDIATO]** = vale assim que deployado (migration/SQL/flag/admin); **[CLIENT-2.4.0]** = só vale na release, atrás de flag.

### T2.0 — Conta interna logável num device [SERVER-IMEDIATO]
1. Fundador escolhe um número sintético claramente-fake iniciando com código 55 (sugestão: `+55 (00) 90000-0001` → `phone_5500900000001@stage.app`; `parseSyntheticEmail` exige prefixo ∈ {351,55,44,1} — ok).
2. Script `scripts/convert_internal_account.sh` (curl Admin API, `SERVICE_ROLE` via env do shell — NUNCA em arquivo): `PUT /auth/v1/admin/users/3eaf8faa-…` com `{email: <sintético>, password: <nova-senha-forte>, email_confirm: true}`. `user_id` preservado → FKs e dados semeados intactos.
3. Semear o gate: `UPDATE profile_personal SET onboarding_completed_at = now() WHERE user_id = '3eaf8faa-…'` (B11: está NULL; sem isso cai no onboarding e poderia sobrescrever a área semeada). Não toca `user_profiles` (trigger de webhook é em INSERT lá — não disparamos).
4. **Verificação:** (i) `signInWithPassword` via curl com anon key + email sintético → 200 com access_token; (ii) fundador loga no device digitando telefone+senha no fluxo normal (caminho confirmado em B11: signup → "already registered" → fallback signIn) e cai na Home com feed da área "Tecnologia".

### T2.1 — RPC `get_feed_page` + testes [SERVER-IMEDIATO]
- Migration do §3.1 (forma colapsada) via CLI (R2); `supabase migration list` limpo antes do PR; manifest atualizado.
- *(REV-1)* Migration de dados D-11 (títulos legacy mortos, ~25 rows, idempotente, anti-duplicata) — arquivo separado; verificação: query de contagem dos títulos legacy = 0 pós-aplicação + harness de paridade re-rodado.
- Teste SQL `supabase/scripts/test_fase2_feed_rpc.sql` (`BEGIN…ROLLBACK`, DO block terminando em `RAISE EXCEPTION 'FASE2_TESTS_OK'`, sem tocar `user_profiles`): vagas sintéticas inativas/ativas + swipe sintético + `set_config('request.jwt.claims', …)` com role authenticated pra simular `auth.uid()`; asserts:
  - exclusão de swipada; null-permissividade (args null = tudo passa); limit clampado;
  - score exato de vaga construída (área+tipo casados, cidade não → score = (30+20)/80×100 = 63 com 4 dims declaradas s/ salário);
  - *(REV-1)* **caso all-ties**: usuário sintético SEM prefs (rank = só jitter) paginando ≥3 páginas com `p_frozen_at` fixo → **zero overlap e zero gap** (união das páginas = conjunto completo, sem repetição). É o caso que detecta o bug de keyset — o teste com prefs (scores contínuos) passaria com o bug dentro;
  - *(REV-1)* **determinismo/rotação do jitter**: duas chamadas com o MESMO `p_frozen_at` → ordem idêntica; `p_frozen_at` de dias diferentes → ordem distinta pro usuário sem prefs;
  - *(REV-1)* **salário**: usuário/args com `p_min_salary` setado → vaga sem salário passa (permissiva), vaga abaixo cai, vaga acima passa e pontua +10 no numerador/denominador.
- Harness de paridade `tools/feed_parity/` commitado + **re-execução contra o RPC real em prod** (mesmos 7 usuários) colada no relatório.
- **Verificação de performance:** `EXPLAIN (ANALYZE, BUFFERS)` do RPC real em prod pros 3 perfis do B1 — números no relatório (regressão vs plan mode = parar e investigar).

### T2.2 — UI lista atrás de `feed_list_v1` + modo swipe por snapshot [CLIENT-2.4.0 + seed da flag SERVER-IMEDIATO]
- Migration: seed `feed_list_v1` em `app_feature_flags` (`enabled=false, rollout_pct=0` — comportamento zero até a release E a decisão de ligar).
- `JobsViewModel`: caminho novo (flag ON) chama `get_feed_page` via `supabase.rpc` com filtros efetivos resolvidos como hoje (local-else-profile, D-8) + `p_frozen_at` da sessão; cursor `(rank_score, id)` da última row; pull-to-refresh reinicia sessão de paginação. Caminho antigo (flag OFF) **intocado byte a byte** — é o rollback.
- `jobs_list_screen.dart` (novo): células compactas — empresa, título, chips de razão (`reason_*` do RPC), bolsa quando houver (e "a combinar" quando não — 83% não têm, B10), badge de frescor, banda de match (T2.4); gesto na célula: direita salva / esquerda descarta → mesma `swipe_actions` + `job_swiped` com `feed_mode:'list'`; paginação infinita; estados de exaustão do T2.3 ao fim.
- **Modo padrão = swipe (D-6):** toggle no topo da aba alterna lista↔swipe (persistido em SharedPreferences; evento novo `feed_mode_toggled`). Com flag ON, o swipe consome **snapshot imutável da página corrente** do RPC (resolve B4 sem refatorar o plugin); ao esgotar o snapshot, busca a próxima página e recria o CardSwiper (reinício coincide com array esgotado — sem dessincronização possível).
- Eventos (R7, mesmo PR): prop `feed_mode: 'list'|'swipe'` em `feed_loaded`/`feed_exhausted`/`job_swiped`/`job_card_shown`; *(REV-1)* prop **`feed_source: 'rpc'|'legacy'`** em `feed_loaded` (sem ela o aceite P50 não filtra rota nova×antiga — `feed_mode` distingue lista×swipe, e o swipe ON também usa RPC); evento `feed_mode_toggled` no catálogo + emissor.
- *(REV-1)* Estado B da exaustão usa os DOIS counts do RPC (1ª página): `total_after_filters=0` com `total_available>0` = "filtros zeraram" (CTA limpar filtros); `total_available=0` = catálogo esgotado de verdade (estado A).
- Testes (R3): unit do cursor/paginação do ViewModel (mock do rpc), unit do snapshot do swipe, 1 widget test da `jobs_list_screen`.
- `JobRepository.fetchJobsWithDiagnostics` + `jobs.shuffle(Random())` permanecem como caminho da flag OFF; **deleção só quando a flag chegar a 100%** (fase de fechamento, commit separado).

### T2.3 — Exaustão honesta + pedido de empresa [CLIENT-2.4.0 + migration SERVER-IMEDIATO]
- Migration: `company_requests (id uuid pk default gen_random_uuid(), user_id uuid not null references auth.users, company_name text not null, note text, created_at timestamptz default now())` + RLS own-insert/own-select + GRANT pro service role (leitura admin).
- Fim da página final (lista) e fim do snapshot sem próxima página (swipe): estado A "fim das relevantes desta semana" com CTA de alerta (digest existente) + CTA de expansão (raio/remoto → ajusta filtros locais); estado B (filtros zerando tudo — `total_after_filters=0` com `total_available>0`) mantém "limpar filtros". B1/D2 mostram que feeds-zero EXISTEM hoje (2 dos 7 perfis) — esses estados são o produto, não edge case.
- Botão "Pedir uma empresa" → insert em `company_requests` + evento `company_requested` (catálogo + emissor, R7).
- Admin dashboard: leitura simples de `company_requests` (lista com user, empresa, nota, data) — página nova mínima no `admin_dashboard/` + extensão de edge `admin-*` existente ou query direta no padrão atual do dashboard (auth `admin_users`, audit log).

### T2.4 — Bandas + holdout [CLIENT-2.4.0 + reconfig flag PostHog]
- Exibição: número 0-100 → 3 bandas (Alta ≥70 / Média 40-69 / Baixa <40) no card do swipe E na célula da lista, chips de razões mantidos; número completo só no detalhe da vaga. Mexe em UI de match — **R5 não dispara** (pipeline adapt intocado; se qualquer ajuste encostar em adapt, parar e reportar).
- Holdout: tudo do §5 (D3) — reconfig da flag (80/20), gate de elegibilidade, `score_visible` + `holdout_variant` em `job_card_shown`/`job_swiped` (R7), ativação da flag na liberação da release.
- Testes: unit das bandas (limiares), unit do gate de elegibilidade (low → não avalia flag).

### T2.5 — Detalhe da vaga: razões no topo + selo de fonte [CLIENT-2.4.0]
- Razões/chips movidos pro topo do detalhe; vagas agregadas ganham selo discreto "via Gupy"/"via {source}" (`jobs.source` existe e é populado) — preparação visual pra classe "Vaga Stage" da F4. Sem mudança de dados.

### Agrupamento em PRs (pequenos, por frente — R8)
1. **PR1 [server]:** T2.0 (script) + T2.1 (migration RPC + teste SQL + harness) + seed `feed_list_v1` OFF + migration `company_requests`. Sem efeito visível (flag off, RPC sem caller). Checklist: `migration list` limpo, manifest, `check_functions_drift.sh` (não toca functions — confirmação de não-regressão).
2. **PR2 [client]:** T2.2 completo (lista + snapshot swipe + eventos + testes).
3. **PR3 [client+admin]:** T2.3 (estados + pedido de empresa + admin page).
4. **PR4 [client+PostHog]:** T2.4 + T2.5 (bandas, holdout, detalhe).
Ordem de merge = numérica; release 2.4.0 = PR2+3+4; bump + archive no fechamento, `posthog_annotate_deploy.sh` na liberação aos usuários.

---

## 7. Rollout & rollback

- **Rollout `feed_list_v1`** (decisão do fundador): 10% por 3-4 dias → 50% por 3-4 dias → 100%. Gatilho de avanço: zero regressão em crash e `feed_load_failed`, save-rate estável. Mudança de % pega em cold start (B8) — janelas de dias absorvem isso.
- **Rollback = `enabled=false`** (1 UPDATE; kill switch global, leitura failure-safe→false). Nenhuma migration desta fase altera comportamento do caminho antigo: o RPC é função nova sem caller no caminho OFF; `company_requests` é tabela nova; a flag nasce OFF. Provado por construção + diff do PR2 (caminho OFF sem mudanças).
- **Holdout:** flag PostHog ativada na liberação da 2.4.0; rollback do holdout = desativar a flag (client failure-safe → controle).
- **Fechamento da fase** (flag a 100% + janela estável): deletar `jobs.shuffle(Random())` + fetch-tudo (commit dedicado), critério de aceite #4.

## 8. Aceites medíveis (verificado, não declarado)

1. **Paridade:** harness `tools/feed_parity/` contra o RPC real em prod, mesmos 7 usuários → 7/7 md5 idênticos (qualquer divergência explicada linha a linha ou bug).
2. **P50 < 800ms na página de 20:** PostHog, `feed_loaded` com **`feed_source='rpc'`** (REV-1), `cache_hit=false`, P50 de ≥7 dias com flag ≥50% — query colada no relatório. Baseline pré (rota legacy): **2.228ms** (B3). EXPLAIN do RPC real também colado (servidor <150ms projetado).
3. **Flag a 100% sem regressão:** crash-free e taxa de `feed_load_failed` ≤ baseline da janela pré-rollout; save-rate (liked/card_shown) estável (±20%) — números no relatório.
4. **`jobs.shuffle(Random())` deletado** do repositório no fechamento (commit referenciado).
5. **Holdout coletando:** ≥14 dias de `job_card_shown`/`job_swiped` com `score_visible` e `holdout_variant` nas duas variantes; contagens por célula + análise do §5 no relatório.
6. **Exaustão semanal medida no novo fluxo** (`feed_exhausted` por `feed_mode`) — baseline pra comparar com os 19%.
7. **≥1 `company_request` real** registrado (row em prod).
8. **Testes:** `flutter test` verde com os novos (unit cursor/snapshot/bandas/elegibilidade + widget lista); `test_fase2_feed_rpc.sql` = `FASE2_TESTS_OK` em prod (rollback limpo), **incluindo all-ties + determinismo do jitter + salário** (REV-1); CI verde.
9. *(REV-1)* **Títulos legacy zerados:** query de contagem dos mapeamentos D-11 = 0 pós-migration; harness de paridade re-rodado verde.

## 9. Riscos & mitigações

- **Latência fim-a-fim ≠ EXPLAIN** (rede + PostgREST + cold connection): medição no device com a conta interna (T2.0) ANTES do rollout; aceite é pelo evento, não pelo EXPLAIN.
- **Cursor com numeric float:** client repassa `rank_score` como string exata recebida (sem reparse float) — igualdade binária garantida; `ROW(…) < ROW(…)` cobre empates via id.
- **Drift Dart↔SQL futuro** (sinônimos/cidades editados só de um lado): comentário-espelho nas duas pontas + harness de paridade no checklist de qualquer PR que toque `filter_helpers.dart` ou a migration.
- **Swipes concorrentes entre páginas:** vaga swipada some das páginas seguintes (NOT EXISTS por request) — comportamento desejado; snapshot do swipe não muda no meio (B4 respeitado).
- **`min_match_score` client-side encolhe páginas:** comportamento atual preservado; UI da lista busca próxima página quando a corrente render <N células (mesma UX de hoje no swipe).
- **Subplan de cidade a 5k vagas:** plano B registrado (coluna gerada normalizada + índice) — não implementar agora (D-1).

## 10. Fora de escopo (reafirmado)

Fases 3-6; match v2/IA no ranking server; proximidade geográfica (sem lat/long em `jobs` — fato B10); busca textual; revogação das legacy (critério diferido segue: monitorar `bridge_activity` + builds antigas no checklist semanal); portal de empresa; mudanças de onboarding; `responsividade_da_fonte` do ranking da espec (sem dado de resposta por fonte ainda — entra com F3/F4); seções do feed ("Novas para você" etc.) — pós-v1.

## 11. Checklist do fundador

1. Aprovar este plano (ExitPlanMode) — arquiteto externo revisa.
2. Escolher o telefone sintético + nova senha da conta interna (T2.0) e rodar o script (SERVICE_ROLE no shell).
3. Validar no device: login da conta interna, feed lista (toggle), P50 percebido.
4. Decidir o momento de ligar `feed_list_v1` 10% (pós-aceitação da 2.4.0 na App Store — review ≠ produção).
5. Ativar `match_score_visibility_v1` no PostHog na liberação (ou aprovar que eu reconfigure/ative via MCP na execução).
6. *(REV-1, atualizado)* Pendências herdadas que CONTINUAM: validação device da 2.3.0 quando sair da revisão da App Store; assinar tópicos ntfy; shortlist real em <5min (dashboard → Busca). Fechadas e fora do checklist: F0/F1 mergeadas, 2.2.0 em produção desde ~09/06 com baseline anotada, 2.3.0 submetida. Ao gravar `PLANO-FASE-2.md` no repo, atualizar a seção "Estado atual" do `CLAUDE.md` (escrita antes desses fechamentos).
