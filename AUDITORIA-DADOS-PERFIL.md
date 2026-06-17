# AUDITORIA — Cadeia de dados de perfil (busca da shortlist + match score)

**Data:** 2026-06-16 · **Modo:** somente leitura (auditoria, não implementação) · **Banco:** prod (medições via MCP Supabase, queries reais coladas)
**Pergunta:** a qualidade e a estrutura do dado de perfil são suficientes para (PRIMÁRIO) o admin montar shortlists eficazes e (SECUNDÁRIO) o match score ser confiável para a maioria?
**Regra de ouro:** o fato vence; verificado, não declarado — todo número abaixo vem de query colada. Não re-audita o que `AUDITORIA-STAGE.md` (§F, §G, §K) e `FASE-1/2-RELATORIO.md` já cobrem; mede o delta.

> **Convenção de universo.** A base buscável pelo admin e a base avaliável pelo match são a MESMA: `profile_personal` (**1.690 usuários**; é literalmente o `from` da edge `admin-candidates-search`). Quando relevante, recorto também os **ativos nos últimos 30 dias** (1.338). `user_profiles` (2.092) é o universo de cadastro bruto, maior porque inclui contas pré-perfil-relacional.

---

## Sumário executivo

| Função | Veredito | Número que sustenta |
|---|---|---|
| **Busca do admin (primário)** | **Comprometida** — acha gente, mas não pela dimensão que a empresa pede, e quase nada é entregável | A busca **não tem filtro de área de interesse nem de semestre**; o filtro de "completude" está **quebrado** (76% dos perfis têm `completeness_score = 0` apesar de 740 deles terem CV); e **só 2 candidatos em toda a base têm consent concedido** → numa shortlist real de 26, **1** é entregável a terceiro. |
| **Match score (secundário)** | **Comprometido para a maioria** — confiável só para o terço rico | Só **24,4%** dos usuários (412/1.690) têm confidence **high** (número exibido normal); **40,1%** caem em **low** ("Análise limitada"). E a dimensão **salário está morta por construção** (coluna inexistente; `minSalary` hardcoded `null`), rebaixando ~463 usuários que declararam 4/5 dimensões. |
| **Qualidade/estrutura do dado (causa-raiz)** | **A montante: o onboarding produz perfil oco** | Riqueza de perfil ≈ import de CV. Dos **795 usuários que não importaram CV**, só **9 têm ≥3 skills e 13 têm experiência**. No total, **29% da base é "shortlist-ready"** (CV + área + ≥3 skills) e **32% é totalmente oca** (sem CV, sem skill, sem experiência). |

**Uma frase:** as duas funções não estão quebradas no código — estão **famintas de dado**, e a fome nasce no onboarding, que coleta preferências (área/local) mas não coleta o conteúdo (skills/experiências) que só o CV importado traz.

---

## 1. Busca do admin (FOCO PRIMÁRIO)

Ferramenta: `admin_dashboard/src/features/candidates/CandidatesSearchPage.tsx` + edge `supabase/functions/admin-candidates-search/index.ts` (Fase 1 T1.8).

### 1.1 Filtros que existem hoje (lidos do código)

| Filtro | Como resolve (edge `resolveCandidateIds`) | Observação |
|---|---|---|
| Curso | `user_profiles.course ILIKE` ∪ `profile_education_majors.name ILIKE` | substring, texto livre |
| Instituição | `profile_education.institution_id =` **ou** `institution ILIKE` | texto livre + catálogo |
| Cidade | `profile_personal.location_city ILIKE` | **accent-sensitive** (ver 1.2) |
| Skills (vírgula = E) | 1 query por termo, `profile_skills.name ILIKE`, **interseção (AND)** | texto livre |
| Completude ≥ | `profile_personal.completeness_score >=` | **quebrado** (ver 1.3) |
| Ativo nos últimos N dias | proxy = `swipe_actions.created_at >=` | não é "último acesso" real |
| Tem CV/experiências | `saved_resumes` ∪ `profile_experiences` | OK |

**Ordenação:** **nenhuma.** A edge faz interseção de `Set`s e devolve `[...result].slice(offset, limit)` — a ordem é a ordem física do `select` base em `profile_personal` (sem `ORDER BY`). Não há ranking por completude, relevância ou recência.

**O que a célula de resultado mostra ao fundador** (`CandidatesSearchPage.tsx` linhas 216-249): nome/email, curso, instituição, cidade, até 6 skills, **`completeness` (o número quebrado)** e o status de consent. **Não há** indicador de "tem CV", "tem experiência" ou "área de interesse" — exatamente os sinais que distinguem perfil sério de cadastro vazio. O fundador olha um `completeness` que é 0 para 76% e não consegue separar "perfil oco" de "perfil rico nunca pontuado".

### 1.2 O gap vs. o que uma empresa real pede

| Empresa pede… | Filtrável hoje? | Evidência |
|---|---|---|
| Curso / formação | ✅ | filtro `course` |
| Instituição | ✅ (parcial) | 50% do dado não está no catálogo — ver 3.3 |
| **Área de interesse** | ❌ **NÃO EXISTE** | a edge não toca `profile_desired_titles`; a área (vocabulário controlado de 59 valores que o feed da F2 já usa) **não é filtrável na busca** |
| Localização | ✅ (com ressalva de acento) | filtro `city` |
| **Semestre / previsão de formatura** | ❌ **NÃO EXISTE** | `profile_education.current_semester` está preenchido para **1.020 usuários**, mas não é exposto |
| Nível (superior × médio) | ❌ **NÃO EXISTE** | `education_level` existe (1.038 college / 105 school) e é relevante para LGPD/estágio, mas não filtra |
| "Perfil sério/completo" | ⚠️ quebrado | `minCompleteness` (ver 1.3); só `hasCv` funciona |

O maior buraco do primário: **a dimensão central do produto — área de interesse — não é um filtro da ferramenta de shortlist**, embora seja dado limpo e pronto. O fundador tem que garimpar área na mão (lendo skills/curso).

### 1.3 Qualidade do que a busca devolve — medido

**Exemplo pedido: "estudantes de Administração em São Paulo"**, replicando exatamente a lógica da edge:

```sql
with course_set as (
  select id as user_id from user_profiles where course ilike '%administ%'
  union
  select e.user_id from profile_education e join profile_education_majors m on m.education_id=e.id
   where m.name ilike '%administ%'),
city_accent as (select user_id from profile_personal where location_city ilike '%São Paulo%'),
city_unaccent as (select user_id from profile_personal where unaccent(location_city) ilike unaccent('%São Paulo%')),
shortlist as (select c.user_id from city_accent c join course_set cs on cs.user_id=c.user_id)
select (select count(*) from course_set) course_administ,
       (select count(*) from city_accent) city_accent,
       (select count(*) from city_unaccent) city_unaccent,
       (select count(*) from shortlist) shortlist_total,
       (select count(*) from shortlist s where exists(select 1 from saved_resumes r where r.user_id=s.user_id) or exists(select 1 from profile_experiences x where x.user_id=s.user_id)) with_cv,
       (select count(*) from shortlist s where (select count(*) from profile_skills k where k.user_id=s.user_id)>=3) with_skills3,
       (select count(*) from shortlist s where exists(select 1 from profile_desired_titles t where t.user_id=s.user_id)) with_areas,
       (select count(*) from shortlist s where (select completeness_score from profile_personal pp where pp.user_id=s.user_id)>=40) with_compl_ge40,
       (select count(*) from shortlist s where exists(select 1 from candidate_data_sharing_consents cc where cc.user_id=s.user_id and cc.status='granted')) with_consent;
```
```
course_administ=172 | city_accent=243 | city_unaccent=243 | shortlist_total=26
with_cv=21 | with_skills3=19 | with_areas=18 | with_compl_ge40=11 | with_consent=1
```

Leitura:
- A busca devolve **26** candidatos. Desses, **21 (81%) têm CV** e 19 têm ≥3 skills — para *este* recorte a qualidade do conteúdo é **boa**.
- Mas se o fundador usar o filtro "Completude ≥ 40" para achar "perfis sérios", a lista **cai de 26 → 11** — **descartando 10 candidatos que têm CV**. O filtro de qualidade poda os perfis bons.
- **Consent: 1 de 26.** A shortlist é montável, mas **não é entregável** (ver 1.4).
- Acento: aqui `accent` = `unaccent` = 243 (o dado de "São Paulo" está consistente). O `ILIKE` da edge é **accent-sensitive por construção** (ao contrário do feed, que usa `unaccent`), mas a fragmentação de acento na base de cidades é mínima (só **2** cidades têm grafias variantes) — risco **latente, baixo impacto hoje**.

**Quadro geral da base (não só o exemplo):**

```sql
with f as (
  select pp.user_id,
    exists(select 1 from swipe_actions s where s.user_id=pp.user_id and s.created_at>=now()-interval '30 days') active30,
    (exists(select 1 from saved_resumes r where r.user_id=pp.user_id) or exists(select 1 from profile_experiences x where x.user_id=pp.user_id)) has_cv,
    exists(select 1 from profile_desired_titles t where t.user_id=pp.user_id) has_areas,
    (select count(*) from profile_skills s where s.user_id=pp.user_id) n_skills,
    exists(select 1 from profile_experiences x where x.user_id=pp.user_id) has_exp
  from profile_personal pp)
select count(*) total,
  count(*) filter (where has_cv and has_areas and n_skills>=3) shortlist_ready,
  count(*) filter (where not has_cv and n_skills=0 and not has_exp) hollow,
  count(*) filter (where active30) active30,
  count(*) filter (where active30 and has_cv and has_areas and n_skills>=3) active30_ready,
  count(*) filter (where active30 and not has_cv and n_skills=0 and not has_exp) active30_hollow
from f;
```
```
total=1690 | shortlist_ready=491 | hollow=540 | active30=1338 | active30_ready=458 | active30_hollow=342
```

- **Shortlist-ready** (CV + área + ≥3 skills): **491/1.690 = 29,1%** (34,2% entre os ativos).
- **Oco total** (sem CV, sem skill, sem experiência): **540/1.690 = 32,0%** (25,6% entre os ativos).
- Tradução: para cada perfil que valeria uma indicação, há aproximadamente um que **poluiria** a shortlist — e a ferramenta não tem como o fundador separar os dois de relance (a célula mostra o `completeness` quebrado).

### 1.4 Consentimento e elegibilidade — quem é "entregável"

```sql
select status, count(*) from candidate_data_sharing_consents group by status;
-- granted = 2   (e mais nada)
select count(*) from candidate_list_items;     -- 101
select count(*) from candidate_list_exports;   -- 5
```

A F1 criou o consent por candidato (`granted_via`/`scope`) e o export é consent-gated (`admin-candidate-lists`). Estado real: **2 candidatos com consent concedido em toda a base de 1.690.** A busca não distingue, na hora de montar, quem é "buscável" de quem é "entregável" — o status aparece na célula, mas a coleta de consent é manual, um a um, via prompt de WhatsApp (`markConsent` → `granted_via:'whatsapp'`). Resultado: **praticamente toda shortlist gerada hoje esbarra no gate de export.** O gargalo do primário não é achar o candidato; é ter direito de mandá-lo.

---

## 2. Match score (FOCO SECUNDÁRIO)

### 2.1 O que o match consome (confirmado contra o código atual)

`MatchScoreCalculator.calculate` (`lib/features/jobs/utils/match_score.dart:162-287`) — pesos confirmados **Área 30 · Tipo 20 · Cidade 15 · Modelo 15 · Salário 10 · Skills 10**. De onde cada dimensão é carregada (`jobs_viewmodel.dart::_loadProfilePrefs`, linhas 844-933):

| Dimensão | Fonte real | Estado |
|---|---|---|
| Área (30) | `profile_desired_titles.title` | vocabulário controlado (ver 3.1) |
| Tipo (20) | `profile_job_preferences.job_types[]` | OK |
| Cidade (15) | `profile_job_preferences.primary_location_city` + `profile_other_locations.city` | OK |
| Modelo (15) | `profile_job_preferences.work_mode[]` (normalizado EN→PT) | OK |
| **Salário (10)** | — | **MORTO**: não existe coluna de salário em `profile_job_preferences`; `jobs_viewmodel.dart:931` passa `minSalary: null` fixo |
| Skills (10) | pseudo-texto agregado de `profile_*` (keyword overlap) | depende de skills/CV |

`computeConfidence` (`match_score.dart:307-366`): 6 dimensões declaráveis (as acima); **≥5 = high** (número normal), **3-4 = medium** ("estimativa parcial"), **<3 = low** ("Análise limitada", esconde número + CTA). Como **salário nunca preenche**, o teto efetivo é 5 dimensões vivas → **"high" exige as 5 restantes todas presentes**.

### 2.2 A completude que sustenta o match — medido

```sql
with f as (
  select pp.user_id,
    (exists(select 1 from profile_desired_titles t where t.user_id=pp.user_id))::int d_areas,
    (exists(select 1 from profile_job_preferences jp where jp.user_id=pp.user_id and coalesce(array_length(jp.job_types,1),0)>0))::int d_jt,
    (exists(select 1 from profile_job_preferences jp where jp.user_id=pp.user_id and coalesce(array_length(jp.work_mode,1),0)>0))::int d_wm,
    (((pp.location_city is not null and pp.location_city<>'') or exists(select 1 from profile_job_preferences jp where jp.user_id=pp.user_id and jp.primary_location_city is not null and jp.primary_location_city<>'') or exists(select 1 from profile_other_locations ol where ol.user_id=pp.user_id and ol.city is not null and ol.city<>'')))::int d_loc,
    ((select count(*) from profile_skills s where s.user_id=pp.user_id)>=3)::int d_sk
  from profile_personal pp),
g as (select (d_areas+d_jt+d_wm+d_loc+d_sk) filled from f)
select filled, count(*) users,
  case when filled>=5 then 'high' when filled>=3 then 'medium' else 'low' end confidence
from g group by filled order by filled;
```
```
filled=0 → 328 (low) | =1 → 150 (low) | =2 → 200 (low)
filled=3 → 137 (medium) | =4 → 463 (medium) | =5 → 412 (high)
```

| Confidence | Usuários | % da base | O que o usuário VÊ |
|---|---|---|---|
| **low** (0-2 dim) | **678** | **40,1%** | número escondido, "Análise limitada" + CTA |
| medium (3-4 dim) | 600 | 35,5% | número + "estimativa parcial" |
| **high** (5 dim) | **412** | **24,4%** | número normal |

**Veredito:** o match é confiável (high) para **~1 em cada 4** usuários. Para 40% ele se recusa a mostrar número (correto — é honesto sobre a falta de dado, conforme o desenho do Passo 5). O lembrete do prompt confirma-se: perfil pobre → score pobre/escondido, não enganoso. O design protege contra "Alta em tudo", mas ao custo de cobertura baixa.

**Custo da dimensão morta (salário):** os **463 usuários em `filled=4`** declararam 4 das 5 dimensões vivas e estão presos em "medium" — não há como chegar a "high" porque a 6ª dimensão (salário) é inalcançável. Se o denominador de confidence fosse recalibrado para as 5 dimensões vivas (ou salário recoletado), até **875** usuários (412+463) poderiam ser "high". É uma decisão de calibragem barata com efeito grande na cobertura — **sinalizada, fora de escopo** (tocar o cálculo do match é fora do escopo desta auditoria).

---

## 3. Qualidade e estrutura do dado de perfil (CAUSA-RAIZ)

### 3.1 Onde o perfil mora e em que formato

Tabelas relacionais (`profile_*`, Semana 1) + JSONB legacy (`user_profiles.gamification_data`) + artefatos (`saved_resumes`). Inventário de schema confirmado via `information_schema`. Estrutura por dimensão, medida:

**Áreas — `profile_desired_titles` (BOM, vocabulário controlado):**
```sql
select count(*) rows, count(distinct title) distinct_title, count(distinct lower(btrim(title))) norm, count(distinct user_id) users
from profile_desired_titles;
-- rows=3440 | distinct_title=66 | norm=59 | users=998
select source, count(*) from profile_desired_titles group by source;  -- user_added=3411 | legacy_merge=29
select title, count(*) from profile_desired_titles where unaccent(lower(title)) like '%administ%' group by title order by 2 desc;
-- Administrativo=469 | "administracao e processos"=1 | "administração e processos"=1
```
A "cauda legacy de títulos" que a F2 flagrou **já foi normalizada** (D-11): 66 valores brutos → 59 normalizados, só **2 rows** soltas de texto livre. É um **vocabulário controlado** (top: Tecnologia 580, Administrativo 469, Geral 357, Vendas 325, Marketing 306…). **Não é o problema de estrutura.** Ressalva menor: **"Geral" (357 usuários)** é uma escolha de baixo sinal — equivale a "sem área" para fins de shortlist.

**Skills — `profile_skills` (RUIM, texto livre sem taxonomia):**
```sql
select count(*) total, count(distinct name) distinct_name, count(distinct lower(btrim(name))) norm, count(distinct user_id) users from profile_skills;
-- total=5351 | distinct_name=2745 | norm=2591 | users=763
```
**2.591 strings de skill distintas** para 763 usuários. Fragmentação de grafia confirmada (mesma skill em 3-4 grafias):
```
trabalho em equipe → 4 variantes / 195 rows | pacote office → 4 / 80 | javascript → 3 / 53 | python → 3 / 68 | html → 3 / 38 …
```
Top skills são majoritariamente **soft skills de baixo sinal** (Trabalho em equipe 173, Organização 87, Boa comunicação 85, Proatividade 80) misturadas com hard skills (Python 66, Excel 64, SQL 37). Sem taxonomia nem mapa de sinônimos (JS↔JavaScript, Excel↔Pacote Office). Impacto: (a) a busca de skills do admin não pode oferecer faceta/dropdown (só substring frágil); (b) o keyword-overlap do match (10 pts) recebe ruído de soft skill.

**Curso — texto livre fragmentado:**
```sql
select 'majors' src, count(*) total, count(distinct name) dist, count(distinct lower(btrim(name))) norm from profile_education_majors
union all select 'up.course', count(*), count(distinct course), count(distinct lower(btrim(course))) from user_profiles where course is not null and course<>'';
-- majors:   total=1359 dist=468 norm=348
-- up.course: total=1076 dist=343 norm=247
```
~248-348 grafias distintas de curso, sem catálogo canônico. O filtro de curso por substring (`ILIKE '%administ%'`) mitiga em parte, mas "ADM" ou "Gestão" não casam com "Administração" → **risco de recall** na busca.

**Instituição — metade fora do catálogo + poluição de ensino médio:**
```sql
select count(*) edu_rows, count(*) filter (where institution_id is not null) linked, count(*) filter (where institution_id is null) free_text,
  count(distinct lower(btrim(institution))) distinct_strings,
  count(*) filter (where unaccent(lower(institution)) ~ 'ensino medio|ensino fundamental|colegio|escola estadual|e\.e\.|em ') school_like
from profile_education;
-- edu_rows=2339 | linked=1168 | free_text=1171 | distinct_strings=1313 | school_like=367
```
**50% das rows de educação não estão ligadas ao catálogo `institutions`** (`institution_id` null) — o filtro por catálogo perde metade; o filtro por texto pega, mas com 1.313 grafias. **367 rows parecem escola, não faculdade** — confirma que o problema "Ensino Médio no campo universidade" (spec §2.2, audit G7) **persiste** apesar do typeahead da F1 (que cobre os 1.168 ligados). Relevante para LGPD (menores).

**Cidade — BOM:** só **2** cidades têm grafias variantes na base; o dado de localização é limpo.

**`completeness_score` — QUEBRADO como sinal (achado central das duas pontas):**
```sql
select round(avg(completeness_score),1) avg, percentile_cont(0.5) within group (order by completeness_score) median,
  count(*) filter (where completeness_score=0) eq0, count(*) filter (where completeness_score>=80) ge80 from profile_personal;
-- avg=19.3 | median=0 | eq0=1286 | ge80=248
-- cross-tab: dos 1286 com score=0 → 740 TÊM CV, 841 têm área, 384 têm ≥3 skills
```
**76% da base tem `completeness_score = 0`** e, desses, **740 têm CV**. O campo não mede riqueza de perfil — mede "a extração de CV rodou e computou um score" (só importadores recebem). Por isso o filtro "Completude ≥" do admin e o número na célula são enganosos: **excluem perfis reais e não distinguem oco de rico.**

### 3.2 A origem do dado — a causa-raiz a montante

```sql
select coalesce(profile_source,'(null)') src, count(*) users, round(avg(completeness_score),1) avg_compl,
  count(*) filter (where exists(select 1 from profile_desired_titles t where t.user_id=pp.user_id)) areas,
  count(*) filter (where (select count(*) from profile_skills s where s.user_id=pp.user_id)>=3) skills3,
  count(*) filter (where exists(select 1 from profile_experiences x where x.user_id=pp.user_id)) exp
from profile_personal pp group by profile_source order by users desc;
```
```
imported : users=895 | avg_compl=36.4 | areas=629 | skills3=680 | exp=742
(null)   : users=795 | avg_compl=0.0  | areas=369 | skills3=9   | exp=13
```

**Este é o achado-raiz.** Os **795 usuários que NÃO importaram CV** (`profile_source` null = caminho onboarding/trilha manual) têm:
- **≥3 skills: 9 (1,1%)** · **experiência: 13 (1,6%)** · área: 369 (46%, vinda do seletor de área do onboarding).

Ou seja: **skills, experiências e bullets vêm quase inteiramente do import de CV.** O onboarding manual coleta preferências (área, local, tipo, modelo) mas **não coleta conteúdo** — as "perguntas dirigidas + bullets incrementais" prometidas na spec §5.3 não chegam a esses usuários. Como **47% da base nunca importou** (795/1.690), quase metade dos perfis é estruturalmente fina.

**O pipeline de extração em si é saudável** (não é aqui que se perde dado):
```sql
select status, count(*) from profile_extraction_logs group by status;
-- success=1151 | log_only=141 | recovered=31 | failed=1
```
O problema não é a extração falhar; é a **cobertura** (só ~895 importaram). Cross-checks: `saved_resumes` exato = **1.261** (1.132 usuários distintos); `imported_resume` JSONB = **896** ≈ `profile_source='imported'` 895.

### 3.3 Dado que existe mas não é usado (oportunidade barata)

- **Semestre:** `current_semester` preenchido para **1.020** usuários (college) — **não é filtro da busca**.
- **Nível de educação:** 1.038 college / 105 school / 720 sem nível — **não é filtro** (LGPD-relevante).
- **Área de interesse:** vocabulário limpo de 59 valores, **já consumido pelo feed (F2)** — **não é filtro da busca**.

---

## 4. Diagnóstico priorizado (recomendação — NÃO implementar)

Ordenado por impacto sobre as duas funções. Cada item: (a) problema medido · (b) o que consertar · (c) trade-off/custo · (d) tipo = **dado** (backfill/normalização) / **estrutura** (schema/UI) / **origem** (onboarding).

**P1 — Onboarding produz perfil oco (causa-raiz comum das DUAS pontas).**
(a) 795 não-importadores → 9 com ≥3 skills, 13 com experiência; 32% da base totalmente oca; só 29% shortlist-ready. (b) Coletar no onboarding o conteúdo, não só as preferências: ≥3 skills (de uma lista) e ≥1 experiência com as perguntas dirigidas da spec §5.3, **ou** elevar drasticamente a taxa de import de CV. (c) Conflita com a meta "feed em <90s" da spec §2.2 — alongar o onboarding derruba ativação; a saída é coleta *em contexto* pós-feed, que é justamente o que ainda não existe. (d) **origem** → conecta direto com a **F6**. **É a maior alavanca; sem ela, P3/P5 só polem dado que continua faltando.**

**P2 — Busca sem filtro de área de interesse (nem semestre/nível).**
(a) Empresa pede área e semestre; a edge não toca `profile_desired_titles`; área é vocabulário limpo de 59 valores e semestre está em 1.020 usuários. (b) Adicionar filtros de área (join em `profile_desired_titles`), faixa de semestre e `education_level` à edge + UI. (c) Baixo: o dado já existe e está limpo; é só expor. (d) **estrutura** (edge/UI). **Maior ganho/custo do primário.**

**P3 — `completeness_score` quebrado como filtro e como sinal de célula.**
(a) 76% da base = 0; 740 desses têm CV; o filtro "≥40" derrubou a shortlist de exemplo de 26→11 podando perfis com CV. (b) Recomputar completude para TODOS (não só importadores) por uma fórmula baseada em presença real de campos, **ou** trocar o filtro/célula por sinais reais (badges `tem CV` / `nº skills` / `tem área`). (c) Médio (backfill + recompute on-write); decidir a fórmula (a da spec §5.4 existe). (d) **dado** + **estrutura**. **É o que permite o fundador distinguir oco de rico.**

**P4 — Consent: 2 concedidos em toda a base → shortlists não entregáveis.**
(a) 1 de 26 no exemplo; export é consent-gated. (b) Coletar consent dentro do produto (prompt in-app no candidato / no fluxo de candidatura), não um-a-um por WhatsApp manual. (c) Médio; toca LGPD e UX do app, não só o admin. (d) **origem/estrutura**. **Sem isso, a busca entrega valor zero a terceiros, por melhor que fique.**

**P5 — Skills sem taxonomia.**
(a) 2.591 strings para 763 usuários; fragmentação de grafia + sinônimos; soft skills dominam. (b) Normalizar para uma taxonomia + mapa de sinônimos; separar hard/soft. (c) Médio (precisa de taxonomia + reprocesso); melhora busca (faceta) e o overlap do match. (d) **dado** + **estrutura**. Depende de P1 para ter volume que valha normalizar.

**P6 — Instituição 50% fora do catálogo + 367 rows de ensino médio.**
(a) 1.171/2.339 rows sem `institution_id`; 367 parecem escola; 105 `education_level='school'`. (b) Backfill de `institution_id` por matching de texto contra `institutions`; flag de menores/ensino médio. (c) Baixo-médio; LGPD-relevante (menores, spec §13). (d) **dado**.

**P7 — Salário morto rebaixa a confidence do match.**
(a) Coluna inexistente; `minSalary` null fixo; 463 usuários presos em "medium" por uma 6ª dimensão inalcançável. (b) Recalibrar o denominador de confidence para 5 dimensões vivas, **ou** recoletar salário. (c) Baixo, mas **toca o cálculo do match — fora do escopo desta auditoria**; só sinalizado. (d) **estrutura**.

**P8 — Busca sem ordenação + célula sem indicador de riqueza.**
(a) Resultados em ordem física arbitrária; célula mostra só o `completeness` quebrado. (b) Ordenar por um score de riqueza real; adicionar badges de CV/skills/área. (c) Baixo (casa com P3). (d) **estrutura**.

---

### Conexão com a próxima fase
A causa-raiz das duas funções é **origem** (P1): o onboarding não materializa o conteúdo do perfil. Isso aponta para **F6 (onboarding)** como a fase de maior alavancagem. **P2 e P3** (estrutura/dado da busca) são ganhos rápidos e independentes que melhoram o primário **já com o dado atual** — bons candidatos a uma fase curta antes da F6. **Decisão de sequência fica para o fundador e o arquiteto** — esta auditoria é o diagnóstico, não a fase.

---

*Medições: MCP Supabase (prod), 2026-06-16. Nenhuma escrita, migration ou deploy executados. Leituras de código: `admin-candidates-search/index.ts`, `CandidatesSearchPage.tsx`, `match_score.dart`, `jobs_viewmodel.dart`. Baseline documental: `AUDITORIA-STAGE.md` §F/§G/§K, `FASE-1/2-RELATORIO.md`, `docs/ESPECIFICACAO-PRODUTO.md` §2/§4/§5/§10.*
