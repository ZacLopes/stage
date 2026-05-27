# Relatório: Melhoria do Cálculo do Match Score

> Foco: melhorar o cálculo dentro da estrutura atual (0-100, 6 dimensões ponderadas). Sem redesenho conceitual. Princípio: realismo calibrado — não inflar, não punir incompletude além do necessário, comunicar incerteza.

Data: 2026-05-27
Base: produção (1.039 users, 468 vagas ativas, 21.222 rows em `match_analyses`).

---

## Parte 1 — Auditoria do cálculo atual

### A. Inputs do candidato

#### A.1 Tabelas `profile_*` (relacional)

**Funcionando:**
- 18 tabelas modulares, populadas via `extract-profile` (PDF → estruturado).
- `ProfileSnapshot.toPseudoText()` agrega tudo em string única (`lib/services/profile_snapshot_service.dart:110-176`). 289 users com `profile_skills`, 279 com `profile_experiences`.

**Duvidoso:**
- `profile_personal.summary` populado em só 255/451 users com CV importado (56%). Dos 5 amostrados, summary é null e headline é null para users que TÊM 10+ skills e 2-3 experiences — sinal de que `extract-profile` está deixando dimensões importantes vazias.
- `buildProfileText` (`supabase/functions/analyze-match/index.ts:257-342`) concatena com `\n` mas não rotula seções. A IA recebe blob de texto onde "Marketing Digital" pode ser uma skill OU um nome de empresa OU um interesse — sem marcação.

**Faltando ser usado:**
- `profile_skills.proficiency_level` se existir (não consta no schema mostrado, mas pode haver). Não consultado pelo cálculo.
- `profile_education.gpa`, `profile_education.degree`: nunca lidos pelo match. Pra vagas trainee/CLT júnior, GPA pode ser sinal forte.
- `profile_certifications.issuer`: usado no pseudo-texto, mas não como dimensão própria. Certificação match (ex: AWS para vaga AWS) vira keyword overlap fraco.

#### A.2 `user_preferences` (legacy) vs `profile_job_preferences` (relacional)

**Divergência crítica entre cliente e servidor:**

| Fonte | Cliente Flutter | Servidor `analyze-match` |
|---|---|---|
| Prefs | SÓ `user_preferences` (`preferences_repository.dart:10-13`) | Relacional PRIMEIRO, fallback legacy (`analyze-match/index.ts:176-245`) |
| Áreas (titles) | `user_preferences.areas` | `profile_desired_titles.title[]` + fallback |
| Locations | `user_preferences.locations` | `profile_other_locations.city[]` + `primary_location_*` + fallback |

**Dados:**
```
profile_job_preferences populado: 1 user
profile_desired_titles populado: 0 users
user_preferences populado: 358 users (de 404 rows)
```

Hoje a divergência tem impacto mínimo (relacional vazio). Mas qualquer feature que comece a popular o relacional vai criar dissociação imediata: filtro do feed mostra todas as vagas (cliente vê prefs vazias), match score mostra valores (servidor lê prefs do relacional).

#### A.3 `gamification_data.whoIAm.derived` — caminho QUEBRADO, não morto

**Status:** caminho quebrado. Há sinal valioso sendo gerado pela trilha 1, mas descartado antes de chegar no match.

**Dados:**
```
user_profiles com whoIAm:         0  ← deveria ter ~196 (users que completaram t1_p3)
user_profiles com module1:        0
user_profiles com module2:      160  ← branch t2 funciona
user_profiles com module3:       74  ← branch t3 funciona
user_profiles com imported_resume: 457
```

Tracks no banco hoje:
```
track_1 "Direção":                1 fase (t1_p3) — "tirei subfases e coloquei na tela da trilha"
track_2 "Minha Base":             3 fases (t2_p1, p2, p3)
track_3 "Minhas Experiências":    1 fase (t3_p1)
track_4 "Hard Skills & Idiomas":  2 fases (t4_p1, p2)
track_5 "Links & Logística":      2 fases (t5_p1, p2)
```

**A trilha 1 ainda é completada:**
- 99 users completaram t1_p3 nos últimos 7 dias.
- 196 users completaram nos últimos 30 dias.
- Última conclusão: hoje.

**As respostas têm conteúdo MUITO valioso pro match.** Exemplo real (anonimizado, user completou hoje):
```
M1_3_1_Q2  (interesse de área): "Ainda estou explorando / Aberto a oportunidades, Administração & Processos"
M1_3_1_Q25 (tipo de vaga):       "Estágio"
M1_3_1_Q3  (futuro):             "Quero me formar em Direito, e seguir carreira como policial Federal"
```

Isso é exatamente o que o match precisa: área declarada, tipo declarado, narrativa. Mas é descartado.

**Onde o sinal se perde:** `gamification_viewmodel.dart:702-711` tem branch que escreve em `whoIAm.derived` quando t1_p3 completa. Mas em produção, 0/196 users têm o campo populado. Os módulos t2 e t3 (mesma função `saveProgress`, mesmo arquivo) escrevem normalmente. Algo específico ao branch t1 está falhando.

**Hipóteses (não confirmadas):**
- Bug no guard `if (module1Data['traits'].isNotEmpty)` ([gamification_viewmodel.dart:705](career_gamification/lib/features/gamification/gamification_viewmodel.dart#L705)) — único guard que existe no branch t1. Os branches t2/t3 não têm.
- UI nova da trilha pode ter caminho que chama `markPhaseCompleted` direto (registrando em `user_progress`) sem passar por `saveProgress` (que escreve `gamification_data`). Mas o grep só achou 1 chamador de `markPhaseCompleted`.
- Race condition com outra escrita em `gamification_data`.

**Bug secundário — chaves desalinhadas mesmo se o write funcionasse.** O escritor (`processModule1Answers` em `gamification_logic.dart`) produz:
```
{
  'soft_skills': [...],
  'traits': {
    'interest_areas': [...],
    'opportunity_types': [...],
    'future_vision_text': '...'
  }
}
```

Os 3 leitores leem chaves diferentes:
- `match_score.dart:293-295`
- `analyze-match/index.ts:536-538`
- `adapt-resume-to-job/index.ts:918-961`

Todos esperam `whoIAm.derived.{skills, summary, interests}`. **Essas chaves NUNCA existiram no escritor.** Mesmo se o write funcionasse hoje, os leitores voltariam null.

Resumo: dois bugs combinados (write não acontece + chaves não batem) fazem o sinal mais rico declarado pelo user (interest_areas direto, tipo declarado, narrativa de futuro) ser jogado no lixo. Cobre potencialmente os 327 users (70% dos com likes) que curtem vagas sem ter declarado prefs ([Observação A.4](#a4-comportamento-implícito-swipes)).

#### A.4 Comportamento implícito (swipes)

**Coletado:** `swipe_actions` tem ~14k registros nos últimos 14 dias. Volume suficiente pra ser sinal.

**Usado no cálculo:** NÃO. Nenhum trecho de `match_score.dart` ou `analyze-match/index.ts` lê `swipe_actions`.

**Evidência de valor desperdiçado:**
- 327/465 users (70%) com likes NÃO declararam prefs de área. Eles estão "votando" via swipe mas o cálculo não enxerga.
- 69/465 users (15%) com prefs declaradas curtem vagas FORA das áreas que declararam.
- Diferença de score médio entre liked e rejected: 6 pontos (37 vs 31) — sinal fraco, possivelmente porque o cálculo não usa o que o user revela.

### B. Inputs da vaga

#### B.1 `area` — granularidade insuficiente + classificação errada

11 categorias totais em vagas ativas:
```
Tecnologia       98
Produto          83
Recursos Humanos 79
Operações        44
Jurídico         43
Marketing        35
Finanças         26
Geral            26  ← catch-all com classificação errada
Vendas           25
Engenharia        8
Administrativo    1
```

**Problemas:**
- "Geral" (26 vagas, 5.5%) é catch-all. Amostra mostra vagas claramente em outras áreas: "Cyber Security Analyst | Red Team" (Tech), "Performance Analyst E-commerce" (Marketing/Analytics), "Commercial Analyst" (Vendas), "Customer Advisor" (Atendimento), "Fixed Income Backoffice" (Finanças). Todas Banco Inter — possível bug no `inferArea` da sync function pra esse ATS.
- "Produto" e "Design" não estão diferenciadas no banco (área é só "Produto"), mas o filtro front-end as oferece como áreas separadas (via `_areaSynonyms` em `filter_helpers.dart:41-55`).
- "Administrativo" tem 1 vaga — granularidade desperdiçada.

#### B.2 `requirements` (array)

```
6+ items:    173 vagas (37%)
3-5 items:   147 vagas (31%)
1-2 items:   129 vagas (28%)
empty:       19 vagas (4%)
```

277/468 vagas (59%) têm ≤ 5 requirements. `_computeOverlap` (`match_score.dart:308-336`) faz keyword overlap entre user pool e `requirements + description (cap 1500)`. Em vagas com requirements rasos, o overlap vira dominado por keywords da description (1500 chars de boilerplate "Sobre a empresa") — diluído.

#### B.3 `jobs_skill_extraction` — tabela existe, está vazia

```
SELECT COUNT(*) FROM jobs_skill_extraction;
-- 0 rows
```

A função `extract-job-skills` foi feita pra extrair skills atomizadas de cada vaga (`supabase/functions/extract-job-skills/`) e armazenar em `jobs_skill_extraction`. Hoje ela só roda **on-demand** quando o user abre `SkillsConfirmationSheet` pra adaptar CV (`ai_service.dart:225-240`). Score nunca lê dessa tabela.

Skills do user (top 30, ordenados): "trabalho em equipe" (74), "boa comunicação" (38), "python" (38), "organização" (31), "javascript" (29), "proatividade" (28), "pacote office" (27), "git" (23), "excel" (23), "html" (22), "sql" (20). Mix de soft skills + técnicas. O keyword overlap atual não distingue entre essas categorias — match em "comunicação" vale tanto quanto match em "python".

#### B.4 `description` — texto livre não estruturado

Description média 2.694 chars (3-5 items) a 3.483 chars (6+ items). Em vagas com area="Geral" do Banco Inter, descrições contêm 600+ chars de boilerplate corporativo antes de chegar nas responsabilidades. `extractRelevantCvSection` (`analyze-match/index.ts:69-83`) faz isso pro CV, mas não há equivalente pro description da vaga.

### C. Mecânica do cálculo

#### C.1 Pesos por dimensão

Atuais: **Área 30, Tipo 20, Cidade 15, Modelo 15, Salário 10, Skills 10** (total 100).

**Taxa de match real (v10, 309 análises):**
```
Tipo         66% bate     (peso 20)  → contribui em média ~13 pontos
Área         27% bate     (peso 30)  → ~8 pontos
Localização  28% bate     (peso 15)  → ~4 pontos
Modelo        7% bate     (peso 15)  → ~1 ponto
Skills        2% bate     (peso 10)  → ~0 ponto
Salário       0% bate     (peso 10)  → 0 ponto
```

**Problemas estruturais:**
- **Tipo (20 pts) é trivialmente alto** porque só há 3 opções (estágio 66%, trainee 15%, CLT júnior 19%). Probabilidade de match aleatória ≈ 33-66%. A dimensão contribui ~13 pontos pra qualquer vaga, inflando scores sem agregar sinal.
- **Salário (10 pts) é deadweight**: 89% das vagas (417/468) não têm `salary_min`. Mesmo quando user seta `min_salary`, regra "permissiva no null" (`filter_helpers.dart:199-203`) garante matched=true só quando AMBOS existem E user ≤ vaga. Em v10, taxa de match = 0%.
- **Skills (10 pts) é o sinal mais rico mas com peso mais baixo**: pareado com Salário no fundo do ranking. Match rate 2-7% reflete tanto dificuldade do cálculo (keyword overlap raso) quanto baixo peso atribuído.
- **Área (30 pts) é o maior peso mas tem 11 categorias muito grossas**: vaga "Cyber Security Engineer" e "Front-end Developer" estão ambas em "Tecnologia" — granularidade insuficiente pra discriminar.

#### C.2 Função de agregação

Soma simples: `score = Σ (weight_i × matched_i)`. Servidor segue (`analyze-match/index.ts:659-663`). Cliente NORMALIZA por `totalWeight` (`match_score.dart:226-229`):

```dart
final normalized = totalWeight > 0
    ? (score / totalWeight * 100).round()
    : 0;
```

**Resultado:** mesmo input, escalas diferentes.
- User só declarou `areas=['Marketing']`. Vaga é Marketing.
  - IA: matched Área 30, outras 0 → score `30`.
  - Determinístico: matched Área 30 / totalWeight=30 → score `100`.
- Quando IA falha (25% das chamadas — 504 timeouts) e cai pro determinístico, score muda 3× sem indicação ao user.

#### C.3 Tratamento de dimensão não-declarada

Hoje: `weight=0` (não pune, não contribui). Resultado: user que declara só 2 dimensões e ambas batem tem score 30+20=50 (servidor) ou 100 (cliente normalizado). Sem critério intermediário.

A dimensão não-declarada produz reasons na UI como "Você não declarou cidade preferida" (weight 0, matched false) — visualmente equivalente a "Cidade não bate" (weight 15, matched false). User não distingue.

#### C.4 Gatilho "Cenário C"

Definido no prompt como ESTRITO (`analyze-match/index.ts:374-383`): TODAS as 5 prefs vazias E perfil sem dados.

Resultado real:
```
v10: 226/309 = 73% caem no Cenário C
v4:  7693/19123 = 40% caem no Cenário C
```

**Divergência observada/esperada:** o critério estrito do prompt prevê <20% (a maioria dos users tem AO MENOS 1 sinal — skills, location, work_model). Que 73% caia indica que a IA está sendo permissiva: dispara Cenário C com qualquer perfil parcial.

Isso é amplificado pelo prompt v10 que reforçou regras de "PARE se vazio" (`analyze-match/index.ts:381-383`) — talvez tão forte que a IA passou a interpretar dados parciais como vazios.

### D. Uso de IA

#### D.1 Bug crítico: prompt_version desalinhado

```
Cliente: _matchPromptVersion = 'v4'  (ai_service.dart:53)
Servidor: PROMPT_VERSION = 'v10'     (analyze-match/index.ts:24)
```

`fetchCachedMatches` filtra por `eq('prompt_version', _matchPromptVersion)` (`ai_service.dart:71`). Resultado:
- 309 rows v10 (mais recentes, regras atuais) → cliente NÃO VÊ no batch hydration.
- 19.123 rows v4 (legacy, regras antigas) → cliente vê.

Como tabela tem UNIQUE em `(user_id, job_id)`, pares re-calculados sobrescrevem. Então:
- Users novos / recalculados → cliente filtra fora todos os caches recentes.
- Users antigos (não tocados desde 2026-05-14) → cliente puxa caches v4 com regras antigas.

#### D.2 IA erra aritmética básica

`parseAndValidate` (`analyze-match/index.ts:644-674`) DESCARTA o `score` retornado pela IA e re-deriva da soma dos weights. Comentário in-code: "GPT-4o-mini erra a aritmética básica algumas vezes". Há `console.warn` quando diverge — não medi frequência. Defesa é boa, custo é manter prompt longo só pra ter consistência aritmética (a IA não está adicionando valor nessa parte).

#### D.3 Labels não-canônicos

A IA esporadicamente cria labels fora do canônico ({Área, Tipo, Localização, Modelo, Salário, Skills}). Cache v4:
```
"Modelo/Local"      109 reasons (label do Cenário B)
"Área de Formação"    5
"Área de formação"    3  ← capitalização diferente
"Experiência"         4
"Sem Tipo"            1
```

Servidor não normaliza esses labels — passa pra UI cru.

#### D.4 Detail invade contexto da vaga

Padrão na amostra v10 de score=0:
```
"Você não declarou áreas de interesse."           ← canônico (esperado)
"Você não declarou interesse em Engenharia."      ← inventado: Engenharia é da VAGA
"Você não possui skills relacionadas..."          ← inferindo do contexto da vaga
```

Detail "Você não declarou interesse em Engenharia" viola REGRA #2 do system prompt ("O título da vaga é INFORMAÇÃO DA VAGA, não do candidato"). O detail está usando atributos da vaga como se fossem do candidato — exatamente o que o prompt proíbe.

#### D.5 25% timeouts

Amostra de ~200 logs recentes do edge function: ~25% retornam 504 com `execution_time_ms ≈ 8200-9600`. `OPENAI_TIMEOUT_MS=8000` no servidor + overhead da gateway. Cliente trata 504 como "cai pro determinístico" — sem indicação ao user que viu score calculado por sistema diferente.

#### D.6 Custo divergente da estimativa

Tokens 14d: 47M. gpt-4o-mini ≈ $0.15/M input + $0.60/M output. Estimativa: $7-10 em 14d → ~$15-20/mês. Memory `match_ai.md` documenta "~$1/mês". Ordem de grandeza divergente.

### E. Calibração e validação

#### E.1 Ausência de ground truth

Nenhum mecanismo formal pra responder "o score 65 dessa vaga estava certo?". Apenas like rate por bucket — sinal indireto e enviesado pelo próprio score (user pode estar swipando influenciado pelo número que vê).

#### E.2 Sinais comportamentais não usados como validação

`swipe_actions` existe há meses, com 14k swipes/14d. Dashboard de match_score em PostHog poderia mostrar like rate por bucket E correlação com swipes históricos do mesmo user. Não medi se existe — não vi nada no código que renderize isso.

#### E.3 Telemetria `matchSource` errada

```dart
if (cached == null) {
  matchSource = 'fallback_deterministic';
  matchScore = null;
}
```

`jobs_swipe_screen.dart:386-388`. Mas quando `cached == null`, `_resolveMatch` retorna `MatchResult.pending()` — o user viu placeholder de dots, NÃO o determinístico. Telemetria reporta categoria errada.

#### E.4 prompt_version bumps invalidam baseline

7 bumps em 14 dias (v3→v10). Cada bump invalida cache e muda distribuição de scores. Impossível comparar "score médio do user X em 2026-05-15" com "score médio do user X em 2026-05-27" — são prompts diferentes.

### F. Resumo das divergências cliente vs servidor

| Aspecto | Cliente | Servidor |
|---|---|---|
| Fonte de prefs | `user_preferences` apenas | Relacional + fallback legacy |
| Fórmula | Normalizada por totalWeight | Soma absoluta |
| prompt_version (cache) | Hard-coded 'v4' | 'v10' |
| Tratamento Cenário C | Converte `score=50 + "Sem perfil"` em `MatchResult.unknown` | Retorna score=50 |
| Sanitização pseudo-city | Não filtra "Brasil" | Filtra "Remoto/Brasil/Brazil/Home Office" |
| Sinal mais rico de match | Skills via keyword overlap × 2.5 (constante mágica) | Skills via IA semântica |

---

## Parte 2 — Propostas de melhoria

### Grupo 1 — Dados do candidato

#### M1.1 Unificar leitura de prefs (cliente lê do mesmo lugar que servidor)
- **O que muda:** `PreferencesRepository.getPreferences` busca PRIMEIRO do relacional, fallback legacy. Espelha a lógica de `loadPrefs` do servidor (`analyze-match/index.ts:176-245`).
- **Por que melhora a precisão:** elimina cenário em que user salva prefs via aba Perfil → relacional, mas filtro client-side e MatchScoreCalculator não enxergam. Pré-requisito pra qualquer feature que vá popular o relacional.
- **Como verificar:** rodar query antes/depois mostrando %users com prefs detectadas pelo cliente; criar user de teste que escreve no relacional e validar que filtro do feed funciona.
- **Custo:** baixo (1 PR, espelhar função TS em Dart, ~50 linhas).
- **Dependências:** nenhuma.

#### M1.2 Capturar áreas implícitas a partir de likes
- **O que muda:** novo campo derivado `implicit_areas` = lista de áreas (`jobs.area`) das últimas 20 vagas curtidas. Quando user não declarou áreas, usa `implicit_areas` como fallback (em vez de cair em Cenário C).
- **Por que melhora:** 70% dos users com likes (327/465) não declararam prefs de área. Esses caem em Cenário C hoje. Likes revelam preferência.
- **Como verificar:** %users com Cenário C deve cair; like rate em bucket 50→61-74 deve aumentar (vagas que antes eram "Sem perfil" agora têm fit calculado).
- **Custo:** médio (1 query incremental computando implicit_areas; integração no prompt + MatchScoreCalculator). Implicit_areas pode ser computado uma vez por sessão.
- **Dependências:** decisão de produto: implicit_areas é EXIBIDO no app como "Áreas inferidas do seu comportamento" ou usado silenciosamente? Honestidade vs UX.

#### M1.3 Reativar trilha 1 como fonte de sinal pro match (revisada — versão anterior estava errada)

> **Versão anterior dizia "apagar caminho morto whoIAm.derived". Errado.** Auditoria revelou que a trilha 1 é completada por 99 users/semana com respostas valiosas (área de interesse declarada, tipo de vaga, narrativa de futuro), mas o sinal é descartado por dois bugs combinados. Vide [A.3 revisado](#a3-gamification_datawhoiamderived--caminho-quebrado-não-morto). Apagar a leitura agora maskara o bug e perde sinal estratégico.

- **O que muda:** dois fixes em sequência.
  1. **Investigar e consertar a falha de write do branch t1** em [`gamification_viewmodel.dart:702-711`](career_gamification/lib/features/gamification/gamification_viewmodel.dart#L702-L711). Suspeita primária: guard `if (module1Data['traits'].isNotEmpty)` falhando por motivo desconhecido. Reproduzir localmente completando t1_p3 com logs em volta do branch, observar onde o flow aborta.
  2. **Alinhar chaves entre escritor e leitores.** Decidir uma das duas direções:
     - (a) Escritor passa a produzir `{skills, summary, interests}` no formato esperado pelos leitores. Exige refator de `GamificationLogic.processModule1Answers`.
     - (b) Leitores (`match_score.dart`, `analyze-match`, `adapt-resume-to-job`) passam a ler `{soft_skills, traits.interest_areas, traits.opportunity_types, traits.future_vision_text}` no formato produzido pelo escritor. Toca 3 arquivos.

- **Por que melhora a precisão:** desbloqueia sinal forte que hoje vai pro lixo. `traits.interest_areas` é literalmente declaração de áreas de interesse — alimenta diretamente a dimensão Área (peso 30 no match). `traits.future_vision_text` ("Quero me formar em Direito") é narrativa que ancora a IA semanticamente. Cobre potencialmente os 327 users (70% dos com likes) que curtem vagas sem ter declarado prefs explícitas via aba Vagas — eles JÁ declararam via trilha.

- **Como verificar:**
  - Após fix do write: query `SELECT COUNT(*) FROM user_profiles WHERE gamification_data ? 'whoIAm'` deve subir de 0 pra ≥ 196 nos próximos dias (conforme users completam t1_p3).
  - Após alinhamento de chaves: amostrar 20 cálculos de match em users com whoIAm populado. Reasons devem mostrar Área matched=true quando `traits.interest_areas` bate com `jobs.area`.
  - Métrica de produto: %users em Cenário C (50/0 score genérico) deve cair entre os users que completaram trilha 1.

- **Custo:** médio. Investigação 1-2h (logs + repro local). Fix do write provavelmente trivial (1 linha do guard, ou ajuste do flow). Alinhamento de chaves ~1-2h (refator pequeno).

- **Dependências:**
  - Decisão de produto: trilha 1 é fonte canônica de prefs declaradas, ou aba Vagas → Filtros é? Hoje há divergência: user pode declarar área via trilha 1 ("Administração & Processos") E via aba Vagas (`user_preferences.areas`). Quem ganha? Sugestão default: merge (união), com trilha 1 como fonte primária se aba Vagas vazia.
  - Ground truth (M5.1) ajuda a validar se reativar trilha 1 melhora correlação like rate × score.

#### M1.4 Garantir que `extract-profile` popula summary/headline
- **O que muda:** prompt do `extract-profile` exige campo `headline` (cargo + área inferidos) E `summary` (1-2 frases derivadas do CV inteiro). Cobre os 196 users (44%) com CV importado mas sem summary.
- **Por que melhora:** summary/headline é insumo do `buildProfileText` (primeiras 2 linhas). Sem isso, IA recebe só lista de skills + bullets — sem contexto narrativo.
- **Como verificar:** %users com `profile_personal.summary IS NOT NULL` vai de 25% pra >50%. Score médio de users CV-importados deve subir.
- **Custo:** baixo (alteração de prompt do extract-profile). Re-extrair PDFs existentes em background.
- **Dependências:** `extract-profile` v[atual] deve ter idempotência ou flag de force.

### Grupo 2 — Dados da vaga

#### M2.1 Re-classificar área das 26 vagas "Geral"
- **O que muda:** rodar IA (1× one-shot) sobre as 26 vagas com `area='Geral'`. Reclassificar baseado no título + descrição. Atualizar no banco. Ajustar `inferArea` no sync function pra reduzir taxa de "Geral" em novos imports do Banco Inter.
- **Por que melhora:** vagas "Geral" hoje são misclassificadas (amostra mostrou Cyber Security, Marketing, Vendas, Atendimento). User que setou `areas=['Tecnologia']` filtra essas vagas fora — não vê Cyber Security.
- **Como verificar:** após re-classificação, validar amostra de 10 vagas manualmente; medir aumento no número de vagas elegíveis pra users com prefs declaradas.
- **Custo:** trivial (1 script + 26 chamadas IA = ~$0.01). Sync function precisa de fix permanente.
- **Dependências:** nenhuma.

#### M2.2 Pré-computar `jobs_skill_extraction` para todas vagas ativas
- **O que muda:** cron noturno chamando `extract-job-skills` pra cada vaga ativa sem extração. Skills atomizadas vão pra `jobs_skill_extraction.skills` (jsonb). `analyze-match` lê dessa tabela em vez de fazer keyword overlap com requirements+description.
- **Por que melhora:** dimensão Skills (peso 10) hoje bate 2-7%. Com skills extraídas, match passa a ser "user.skill ∈ job.extracted_skills" — mais preciso que substring de description ruidoso.
- **Como verificar:** Skills matched=true rate sobe de 2% pra estimativa 15-25%. Score médio em vagas com requirements rasos sobe.
- **Custo:** médio. 468 vagas × ~$0.001 = ~$0.50 backfill inicial. Cron diário pra novas vagas: ~30 vagas/dia × $0.001 = $0.03/dia.
- **Dependências:** `extract-job-skills` já existe (`supabase/functions/extract-job-skills/`) e foi feita pra esse propósito. Só precisa ser orquestrada.

#### M2.3 Cap mais agressivo + extração de seção "requisitos" no description
- **O que muda:** detectar marcador "Requisitos" / "Obrigatório" / "What we look for" no description e usar APENAS a seção (~500 chars) em vez do description inteiro (1500 chars com boilerplate corporativo).
- **Por que melhora:** description médio de vagas Banco Inter tem 600-1000 chars de "Sobre a empresa" antes dos requisitos. Keyword overlap atual dilui sinal entre boilerplate e requisitos.
- **Como verificar:** amostrar 20 vagas, comparar score IA antes/depois.
- **Custo:** baixo (~30 linhas regex no `extract-job-skills` ou no `analyze-match`).
- **Dependências:** preferencialmente após M2.2 (skills extraídas tornam essa etapa redundante).

#### M2.4 Sanitizar pseudo-cities no cliente também
- **O que muda:** `FilterHelpers.isLocationMatch` (`filter_helpers.dart:136-177`) detecta city="Remoto/Brasil/Brazil/Home Office" e trata como wildcard (passa qualquer user_location). Espelha lógica do servidor (`analyze-match/index.ts:552-557`).
- **Por que melhora:** 23 vagas (5%) com pseudo-city hoje. No determinístico (fallback quando IA falha), elas marcam Cidade=mismatch falsamente, derrubando score em ~15 pontos.
- **Como verificar:** amostrar 10 vagas com pseudo-city + user com São Paulo declarado. Score determinístico antes/depois.
- **Custo:** baixo (~10 linhas).
- **Dependências:** nenhuma.

### Grupo 3 — Mecânica do cálculo

#### M3.1 Alinhar fórmula cliente e servidor (eliminar normalização)
- **O que muda:** cliente passa a usar soma absoluta (não normalizar por totalWeight). OU servidor passa a normalizar. **Decisão recomendada: servidor permanece autoritativo (soma absoluta), cliente reproduz fielmente quando rodar como fallback.**
- **Por que melhora:** elimina cenário em que IA falha e user vê score 3× diferente sem aviso (vide H6 do diagnóstico). Consistência > qualquer interpretação.
- **Como verificar:** amostrar 20 pares com IA falha, comparar scores antes/depois — devem ser idênticos ou explicáveis (diferença vem só de IA semântica vs keyword overlap, não da fórmula).
- **Custo:** trivial (10 linhas em `MatchScoreCalculator.calculate`).
- **Dependências:** decisão sobre qual é a fórmula canônica. Soma absoluta tem mérito (não infla pra users com poucas prefs declaradas), mas exige comunicar incerteza separadamente (vide M3.4).

#### M3.2 Re-balancear pesos: subir Skills, baixar Tipo e Salário
- **O que muda:** proposta como ponto de partida (a calibrar com dado):
  ```
  Área:   30 → 25     (granularidade ruim limita teto)
  Tipo:   20 → 15     (3 opções; pouco discriminativo)
  Cidade: 15 → 15     (mantém)
  Modelo: 15 → 15     (mantém)
  Salário: 10 → 5     (89% vagas missing — peso simbólico)
  Skills:  10 → 25    (sinal mais rico; com M2.2, fica utilizável)
  ```
- **Por que melhora:** distribui peso conforme sinal real. Hoje Tipo contribui ~13 pts em média (66% de match × 20 pts), Skills contribui ~0.2 pts. Inversão.
- **Como verificar:** A/B test com cohort. Métricas: like rate por bucket, %users com score≥60 em vagas que historicamente curtiram.
- **Custo:** trivial mudar os números. ALTO calibrar honestamente (requer ground truth — vide M5.1).
- **Dependências:** M2.2 (Skills extraction) tem que estar pronta antes — subir peso de Skills sem melhorar o cálculo apenas concentra erro.

#### M3.3 Repensar política de "não-declarado"
- **O que muda:** dimensão não-declarada não some — ela ENTRA NO CÁLCULO com weight reduzido e matched determinístico (ex: usa default da maioria — work_model='presencial' se user não declarou). OU declara explicitamente que aquela dimensão "não conta" e ajusta o denominator quando user não tem dados.
- **Por que melhora:** hoje user que só declarou área tem score máximo 30 (servidor) ou 100 (cliente). Os dois ruins. Solução intermediária: tratamento explícito.
- **Como verificar:** distribuição de scores em users com prefs parciais. Hoje concentra em 0, 30 ou 50 (Cenário C). Deveria espalhar.
- **Custo:** médio. Implica decidir política (qual é o "default" pra cada dimensão).
- **Dependências:** alinhar fórmula primeiro (M3.1).

#### M3.4 Endurecer gatilho do Cenário C
- **O que muda:** Cenário C SÓ dispara se servidor pré-validar que TODAS as condições são vazias (ANTES de chamar a IA). Server retorna direto `score=50 + reason="Sem perfil"` sem invocar gpt-4o-mini. IA nunca decide sozinha que é Cenário C.
- **Por que melhora:** hoje IA dispara Cenário C em 73% dos casos v10. Critério estrito do prompt prevê <20%. Tirar essa decisão da IA elimina o gap.
- **Como verificar:** %scores=50 com reason "Sem perfil" cai pra <20%. Distribuição de scores se espalha pelos buckets intermediários.
- **Custo:** baixo (~50 linhas; nova função `isScenarioCStrict(prefs, profile, gamificationData)`).
- **Dependências:** nenhuma. Pode shipar em isolado.

#### M3.5 ~~Adicionar dimensão "Senioridade"~~ — DESCARTADO

> Founder optou por NÃO adicionar essa dimensão (decisão 2026-05-27). Razão registrada: a estrutura atual de Tipo (estágio/trainee/CLT júnior) já segmenta nível básico; adicionar "Senioridade" como dimensão separada complicaria o cálculo sem ganho proporcional pro estágio do produto.
>
> Se voltar à mesa no futuro, considerar: vagas "CLT júnior + 2 anos exp" misturadas com "estágio sem requisito de experiência" criam mismatch que hoje passa batido. Pode virar refinamento dentro de Tipo em vez de dimensão nova.

### Grupo 4 — Uso de IA

#### M4.1 Alinhar `prompt_version` cliente=servidor
- **O que muda:** `_matchPromptVersion` em `ai_service.dart:53` passa a ler de uma constante compartilhada com o servidor (build-time injection ou config remoto). Imediato: trocar `'v4'` por `'v10'`.
- **Por que melhora:** batch hydration hoje retorna scores legados (v4) ou vazio (pares atualizados pra v10). Cliente vai parar de "ressuscitar" rows v4 obsoletas em sessões e o cache começa a funcionar.
- **Como verificar:** após release, %hit do batch hydration sobe; %chamadas IA "frescas" (cache miss) cai. Métrica PostHog: `analyze-match.cached=true` deve subir.
- **Custo:** trivial (1 linha). ALTO custo de manutenção contínua se PROMPT_VERSION continuar bumpando 1×/dia.
- **Dependências:** decidir como manter sincronizado. Opções: feature flag remoto, constante na resposta da edge function que cliente lê e usa pra próximo batch.

#### M4.2 Bypass IA quando Cenário C é estritamente óbvio
- **O que muda:** servidor antes de chamar OpenAI faz `isScenarioCStrict(prefs, profile, gamificationData, profileText)`. Se true, retorna direto sem invocar IA.
- **Por que melhora:** 73% dos cálculos v10 são Cenário C. Cada chamada custa ~$0.0003 + 2-3s. Eliminar 70% das chamadas = redução de custo + latência. Mais: IA hoje gera 6 reasons "Você não declarou" mesmo nesse caso — texto desperdiçado.
- **Como verificar:** custo OpenAI cai >50% sem mudança de comportamento perceptível pro user. Latência média p50 cai.
- **Custo:** baixo. Função de detecção é determinística.
- **Dependências:** combinar com M3.4 (mesma lógica, ponto único de implementação).

#### M4.3 Subir `OPENAI_TIMEOUT_MS` 8000 → 12000 (e cliente 12 → 15s)
- **O que muda:** dá mais tempo pra OpenAI responder antes de 504.
- **Por que melhora:** 25% das chamadas hoje retornam 504 com execution_time 8200-9600. Quando isso acontece, cliente cai pro determinístico — escala diferente, sinal diferente. Reduzir 504 garante mais cards mostram score IA real.
- **Como verificar:** taxa de 504 deve cair pra <5%. Latência média sobe um pouco (efeito esperado).
- **Custo:** trivial.
- **Dependências:** verificar que Supabase Gateway aceita 15s (timeout dela é 30s padrão — ok).

#### M4.4 Usar IA SÓ pra Skills semânticas, determinístico pro resto
- **O que muda:** novo edge function `match-skills-semantic` que recebe `(user_pool, job_skills)` e retorna `score 0-1`. Dimensões hard (área, cidade, modelo, tipo, salário) são determinísticas (sem IA). Score final = soma weights determinísticos + (IA_skills_score × peso_skills).
- **Por que melhora:** hoje IA processa dimensões em que ela não agrega (Cidade é comparação string, Modelo é enum, Salário é >=). Aritmética e comparações exatas são onde gpt-4o-mini erra (D.2 da auditoria). Concentrar IA no que ela faz bem (semântica de skills) reduz superfície de erro.
- **Como verificar:** comparar score em 50 pares com cálculo atual vs novo. Determinístico vai bater na maioria (área/cidade/modelo/tipo são sempre iguais entre IA e determinístico hoje). Skills muda — comparar manualmente.
- **Custo:** alto. Re-arquitetura do edge function. Mas a maior parte do código atual fica.
- **Dependências:** M2.2 (skills extraction). M4.3 (timeout) deixa de ser tão crítico porque IA roda só sobre skills (chamada mais curta).

#### M4.5 Cache server-side por evento (em vez de só TTL)
- **O que muda:** invalida cache de `match_analyses` quando: (a) user_preferences muda; (b) profile_* relevantes mudam; (c) job relevante muda; (d) prompt_version bumpa. Sem TTL 30d.
- **Por que melhora:** TTL 30d é arbitrário. Hash do `profile_hash` já invalida quando inputs mudam — então TTL é redundante. Removê-lo reduz cache miss desnecessário e custo de IA.
- **Como verificar:** %cache hit do `analyze-match` sobe (ainda mais com M4.1).
- **Custo:** baixo. Mudar `cacheCutoff` pra `'1900-01-01'` (efetivamente sem TTL) é 1 linha.
- **Dependências:** nenhuma, mas só faz sentido após M4.1 (alinhamento de prompt_version).

### Grupo 5 — Calibração e validação

#### M5.1 Ground truth via cohort interno
- **O que muda:** founder + time avaliam manualmente 100 pares (user, vaga) e classificam como "match real", "match parcial", "não-match". Vira benchmark pra validar qualquer mudança no cálculo.
- **Por que melhora:** hoje NÃO HÁ ground truth. Toda decisão de calibração é chutômetro. 100 pares é suficiente pra detectar mudanças significativas.
- **Como verificar:** sistema aceito é o que tem maior concordância com o ground truth (e.g., precisão@bucket).
- **Custo:** ~10h de trabalho humano (founder + 2 pessoas × 3h amostrando + 1h decidindo critérios).
- **Dependências:** consenso sobre critérios de "match real". Não precisa ser ML — só categorias humanas + algumas notas.

#### M5.2 Telemetria correta de `matchSource`
- **O que muda:** corrigir `jobs_swipe_screen.dart:386-388`: quando `cached == null`, `matchSource='pending'` (não `fallback_deterministic`). Quando cache hit com IA = `ai`. Quando cache hit com determinístico = `deterministic`. Adicionar source no resultado de cache pra distinguir.
- **Por que melhora:** dashboard PostHog hoje reporta `fallback_deterministic` pra casos em que UI mostrou pending — métricas de comparação IA vs determinístico estão contaminadas.
- **Como verificar:** baixar export PostHog antes/depois — distribuição de matchSource muda.
- **Custo:** baixo (~30 linhas).
- **Dependências:** nenhuma.

#### M5.3 Dashboard "calibração de score" no PostHog
- **O que muda:** insight novo: like rate por bucket de score, agrupado por matchSource e por prompt_version. Atualiza diariamente.
- **Por que melhora:** sem isso, impossível responder "o bump v9→v10 melhorou?". Métrica histórica permite verificar regressões.
- **Como verificar:** dashboard existe e é consultável.
- **Custo:** ~2h pra montar com queries que o relatório anterior já mostrou.
- **Dependências:** M5.2 primeiro (matchSource correto). M4.1 primeiro (prompt_version sincronizado).

#### M5.4 Snapshot do prompt_version no `swipe_actions`
- **O que muda:** ao registrar swipe, gravar `prompt_version` e `match_score` no momento. Hoje match_score aparece no PostHog mas swipe_actions não tem.
- **Por que melhora:** permite reconstruir "que score o user viu quando swipou X" mesmo após cache invalidar. Hoje, se prompt bumpa, cache fica inacessível e correlação swipe↔score quebra.
- **Como verificar:** coluna nova populada; queries históricas viáveis.
- **Custo:** baixo (1 migration + ajuste em `recordSwipe`).
- **Dependências:** nenhuma.

#### M5.5 Stage gating de prompt_version bumps
- **O que muda:** bump de prompt vai pra X% dos users via feature flag. Compara métricas (like rate, %Cenário C, latência) com cohort anterior antes de rollout 100%.
- **Por que melhora:** 7 bumps em 14 dias é taxa alta. Sem gating, qualquer regressão fica invisível até telemetria detectar.
- **Como verificar:** processo escrito (RFC). Nenhum bump em produção sem dashboard antes/depois.
- **Custo:** baixo (processo) + médio (infra de feature flag pra prompt_version já existe via PostHog).
- **Dependências:** M5.3 (dashboard).

---

## Parte 3 — Sequência sugerida por ROI

### Priorização: 1 (mais impacto rápido, mais barato) → 21 (mais ambicioso)

| # | Melhoria | Esforço | Impacto na precisão | Senso preciso pro user? |
|---|---|---|---|---|
| 1 | **M4.1** Alinhar `prompt_version` cliente=servidor | Trivial | Alto | Sim — para de mostrar scores v4 obsoletos |
| 2 | **M3.4 + M4.2** Bypass IA no Cenário C estrito | Baixo | Alto | Sim — score 50 só quando realmente vazio; resto se espalha |
| 3 | **M5.2** Corrigir telemetria `matchSource` | Baixo | Indireto | Não direto. Mas pré-req pra calibração. |
| 4 | **M3.1** Alinhar fórmula cliente/servidor | Trivial | Médio | Sim — quando IA falha, score não muda 3× |
| 5 | **M2.4** Sanitizar pseudo-cities no cliente | Baixo | Médio (em 5% vagas) | Sim — não derruba score em vaga remota |
| 6 | **M4.3** Subir `OPENAI_TIMEOUT_MS` 8→12s | Trivial | Médio | Sim — 25%→<5% das vagas mostram fallback |
| 7 | **M2.1** Reclassificar 26 vagas "Geral" | Trivial | Médio (em 5% vagas) | Sim — filtros funcionam, score reflete área certa |
| 8 | **M2.2** Backfill + cron `jobs_skill_extraction` | Médio | Alto (dimensão Skills) | Sim — sinal Skills passa de inútil a útil |
| 9 | **M4.5** Cache server por evento, remove TTL | Baixo | Baixo (só custo) | Indireto |
| 10 | **M1.1** Unificar leitura prefs cliente/servidor | Baixo | Alto se relacional crescer | Pré-emptive (relacional vazio hoje) |
| 11 | **M5.4** Snapshot prompt_version em swipes | Baixo | Indireto (calibração) | Indireto |
| 12 | **M5.3** Dashboard de calibração | Médio | Indireto (visibilidade) | Indireto |
| **8b** | **M1.3 revisado** Reativar trilha 1 como fonte de sinal (fix write + alinhar chaves) | Médio | Alto (cobre 327 users sem prefs declaradas via aba Vagas) | Sim — diretamente |
| 14 | **M1.4** `extract-profile` garante summary/headline | Médio | Médio | Indireto (melhora insumo, não score direto) |
| 15 | **M2.3** Cap descrição em seção "requisitos" | Baixo | Médio (com M2.2 pode ser redundante) | Sim |
| 16 | **M5.1** Ground truth via cohort interno | Médio (10h humanas) | Alto (validação) | Indireto |
| 17 | **M3.2** Re-balancear pesos | Alto | Potencialmente muito alto | Sim, depois de validar |
| 18 | **M1.2** Capturar áreas implícitas via swipes | Médio | Médio-alto (cobre 327/465 users) | Sim |
| 19 | **M3.3** Política nova pra dimensão não-declarada | Médio | Alto | Sim |
| 20 | **M4.4** IA só pra Skills, determinístico pro resto | Alto | Médio (consistência) | Indireto |
| 21 | **M5.5** Gating de prompt_version bumps | Baixo (processo) | Alto longo prazo | Não |

### Como "senso preciso pro user rápido" cai

As 7 primeiras (M4.1, M3.4+M4.2, M3.1, M2.4, M4.3, M2.1, M2.2) entregam ganho perceptível ao user em ~2 semanas de trabalho, todas baratas. Lógica:
- **#1-3**: corrigem bugs que estão ATIVAMENTE dando scores errados (cache mismatch, Cenário C inflado, telemetria errada que esconde o problema).
- **#4-7**: estancam inconsistências (fórmula cliente/servidor, pseudo-city, timeouts, vagas "Geral") que produzem scores discrepantes pro mesmo par.
- **#8 (M2.2 skills extraction)**: primeiro item que de fato melhora o SINAL — não só corrige erro. É o salto de qualidade.
- **#8b (M1.3 revisado — reativar trilha 1)**: segundo salto de qualidade. Não corrige score, RECUPERA SINAL hoje descartado. Cobre 70% dos users que curtem vagas sem ter declarado prefs explicitamente. Pareado com #8 (skills) entrega quase todo o ganho fácil disponível.

Depois disso (#9-21), trabalho passa a ser estrutural: calibração honesta requer ground truth (M5.1) que requer dashboards e telemetria correta (M5.2-5.4). Sem isso, mexer em pesos (M3.2) é chute.

### Mudança de priorização do M1.3 (errata)

A versão original do relatório classificou M1.3 como "baixo impacto, manutenção" no item #13. **Estava errado.** A auditoria mais profunda revelou que `whoIAm.derived` não é caminho morto — é caminho QUEBRADO descartando sinal valioso (99 users/semana respondendo a trilha 1 com declarações úteis pro match). Re-priorizei pra #8b, logo após o outro salto de qualidade (M2.2 skills extraction). Detalhe completo em [A.3 revisado](#a3-gamification_datawhoiamderived--caminho-quebrado-não-morto) e [M1.3 revisado](#m13-reativar-trilha-1-como-fonte-de-sinal-pro-match-revisada--versão-anterior-estava-errada).

### Razão de excluir certas variações do topo

- **M5.1 (ground truth) NÃO está no topo** apesar de fundamental, porque exige 10h humanas e os 7 primeiros itens podem ser shipados em ~1 semana sem precisar disso. Ground truth fica em paralelo, não bloqueia.
- **M3.2 (re-balancear pesos) NÃO está no topo** porque tunar pesos sem ground truth é viés — pode parecer melhor mas não é.
- **M1.2 (áreas implícitas) NÃO está no topo** porque exige decisão de produto (mostra/esconde?) e tem risco real de surpreender users. Pode esperar.

---

## Parte 4 — O que NÃO mexer agora

### 4.1 Estrutura conceitual do score (0-100 com 6 dimensões)
**Não mexer:** discussão sobre fragmentar em fit+confiança, virar categorias, ranking relativo, ML comportamental. Já foi exaustivamente discutida no relatório de redesenho.
**Por que separar:** este round é incrementar dentro da estrutura. Mudança conceitual exige reaprendizado pelo user (ver Parte 2 do redesenho), e qualquer melhoria do cálculo atual prepara terreno (calibração, ground truth) pra qualquer redesenho futuro.

### 4.2 Apresentação visual do score no card
**Não mexer:** ring colorido, "X% match", animação. Mudança visual = redesenho.
**Por que separar:** UX precisa de teste qualitativo com user. Score-feed-side melhora cálculo, não apresentação. Mexer nos dois ao mesmo tempo confunde sinal de mudança.

### 4.3 Substituir GPT-4o-mini por outro modelo
**Não mexer:** trocar pra gpt-4o ($0.15+$0.60 → $2.50+$10/M, ~16× caro), Claude, ou self-hosted.
**Por que separar:** custo atual ~$20/mês — não é gargalo. Modelo maior pode melhorar qualidade de Skills semânticas, mas só vale a pena testar APÓS skills extraction estar online (M2.2). Hoje mudar modelo apenas amplifica problemas estruturais.

### 4.4 ML treinado em swipes
**Não mexer:** modelo gradient boosting / two-tower / collaborative filtering pra predizer P(like) ou ranking.
**Por que separar:** volume insuficiente (14k swipes/14d), cold start crítico (70 users novos/semana), nenhuma loop de feedback da empresa (que vai filtrar candidatos). Fica pra quando Stage tiver 50k+ users.

### 4.5 Adicionar dimensão de "empresa" / "fit cultural"
**Não mexer:** comparar tamanho/setor/maturidade da empresa com preferência do user.
**Por que separar:** schema atual de `companies` não tem fields ricos (tamanho, setor). Adicionar essa dimensão exige extração nova de cada empresa + UX nova de declaração de preferência de empresa. Trabalho de mês.

### 4.6 Onboarding/UI pra preencher prefs faltantes
**Não mexer:** banner "Preencha suas prefs pra ter matches melhores", trilha de completar perfil.
**Por que separar:** já existe em paralelo (memory `profile_first_ui.md`). Cálculo é uma coisa, preenchimento é outra. Separar evita duplicar trabalho com o time de onboarding.

### 4.7 Mudanças no `inferArea` da sync function
**Não mexer:** lógica que classifica vagas durante sync (Apify/ATS/Brazil scraper).
**Por que separar:** M2.1 propõe corrigir o backfill (one-shot) e o inferArea (estrutural). O backfill é simples. O inferArea é compartilhado entre 3 sync functions — mudanças têm risco maior, custo maior, pertence ao time de sync. Backfill agora; inferArea fix em sprint separado.

### 4.8 Re-fetch de `analyze-match` quando user toca no card
**Não mexer:** invalidar cache mais agressivamente em interação.
**Por que separar:** explora cache-warming preditivo, prefetch, etc. Não muda precisão do cálculo, muda latência. Ortogonal.

---

## Notas finais

- Toda a Parte 2 foi escrita assumindo "realismo calibrado": nenhuma proposta infla score artificialmente. Onde score sobe (M2.2 Skills extraction), sobe porque o sinal está mais alinhado com a realidade. Onde score cai (M2.1 reclassificação de vagas Geral, M3.4 Cenário C estrito), cai porque o sinal anterior estava errado.
- Princípio "user, empresa, Stage": melhorias 1-8 ajudam principalmente USER (vê score mais consistente) e STAGE (reduz custo IA, reduz suporte por "match estranho"). Empresa só entra a partir de M5.1 (ground truth — começa a definir o que a empresa considera fit).
- Dependência crítica oculta: SEM ground truth (M5.1), qualquer ajuste de peso (M3.2) é tuning cego. Recomendo M5.1 começar em PARALELO com #1-8, mesmo que conclusão venha depois. A medida que ground truth fica disponível, valida-se o que foi feito retrospectivamente.

---

## Parte 5 — Plano consolidado pré-release (decidido 2026-05-27)

> Plano definitivo construído em conversa com o founder após auditoria. Substitui qualquer ordem de execução anterior pra os itens cobertos abaixo. Itens 9-21 da tabela de priorização ficam pra depois do release.

### Decisões tomadas

| Decisão | Escolha |
|---|---|
| Política pra dimensão não-declarada (M3.3) | Honestidade radical: < 3 dimensões → "Análise limitada" + CTA. Score interno continua sendo calculado pra ordenar feed (escondido). |
| Níveis de confiança | 3 níveis: Alta (≥ 5 dimensões), Média (3-4), Baixa (< 3). User vê transparência via labels; empresa (futuro) filtra por tier. |
| CTA quando Baixa | Card mostra "Análise limitada — falta declarar [X, Y]" indicando especificamente quais dimensões faltam. Não bloqueia interação (user ainda pode swipar, curtir, adaptar CV). |
| Fonte de verdade pra identidade do user | Tabelas relacionais `profile_*` APENAS. Legacy `user_preferences` JSONB e `gamification_data.whoIAm` ficam só pra leitura temporária durante backfill. |
| Separação Filtros vs Preferências | Universos independentes. Filtros (aba Vagas) viram TEMPORÁRIOS (memória/local storage, não persistem no match). Preferências (tab Perfil) são identidade permanente. |
| Como filtro temporário se comporta | Opção A: filtro só esconde/mostra vagas no feed. Score continua refletindo identidade do Perfil mesmo quando filtro contradiz. |
| Pré-marcação de filtros | Filtros pré-marcam com base no Perfil, mas user pode mexer livremente sem afetar identidade. |

### Desenho final

```
┌─────────────────────────────────────────────────────────┐
│  TAB PERFIL                                              │
│  Seção de Preferências (já existe)                       │
│  → Escreve nas tabelas relacionais (profile_*)           │
│  → ÚNICA fonte que alimenta match e confidence           │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Cálculo do Match Score + Confidence                     │
│  → Lê SÓ das tabelas relacionais                         │
│  → < 3 dimensões: "Análise limitada" + CTA               │
│  → 3-4: score + "estimativa parcial"                     │
│  → ≥ 5: score normal                                     │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  ABA VAGAS → ÍCONE FILTRO                                │
│  → Temporário (memória/local storage)                    │
│  → Só esconde/mostra vagas no feed                       │
│  → NÃO afeta match nem confidence                        │
│  → Pré-marca com base no Perfil (mas user pode override) │
└─────────────────────────────────────────────────────────┘
```

### Definição operacional de "dimensão preenchida"

Lendo SOMENTE das tabelas relacionais:

| Dimensão | Conta como "preenchida" quando |
|---|---|
| **Área** | `profile_desired_titles` tem ≥ 1 entrada |
| **Tipo** | `profile_job_preferences.job_types` não vazio |
| **Cidade** | `profile_job_preferences.primary_location_city` populado OU `profile_other_locations` tem entrada |
| **Modelo** | `profile_job_preferences.work_mode` não vazio |
| **Salário** | `profile_job_preferences.min_salary > 0` (pode requerer nova coluna — conferir schema atual) |
| **Skills** | `profile_skills` tem ≥ 3 entradas |

### Plano de execução em ordem

**Passo 1 — Auditar a seção de Preferências do Perfil (destino do write + emissão de evento)**
Founder confirmou que a seção existe na tab Perfil. Mas o banco mostra 0 users com `profile_job_preferences` e `profile_desired_titles` (porque build não saiu na App Store ainda). Conferir 2 coisas:

1. **Destino do write.** A tela escreve no relacional ou no legacy `user_preferences`?
   - Se já escreve no relacional → ok, seguir.
   - Se ainda escreve no legacy → redirecionar pro relacional.

2. **Emissão de `ProfileEvents.changes` ao salvar.** O cache em memória do match (`JobsSwipeScreen._matchCache`) é invalidado por 3 eventos, sendo um deles `ProfileEvents.changes` ([jobs_swipe_screen.dart:639-657](career_gamification/lib/features/jobs/screens/jobs_swipe_screen.dart#L639-L657)). Quando o user salva mudança no Perfil, a aba Vagas precisa saber pra re-hidratar os scores.
   - Se a seção de Preferências já emite `ProfileEvents.instance.notify()` ao salvar → ok.
   - Se NÃO emite → adicionar a emissão (1 linha). Sem isso, user adiciona área no Perfil, volta pra Vagas e vê os mesmos cards "Análise limitada" até hot-restart.

Esforço: 30min auditar + (se precisar) 2h corrigir destino do write + 5min adicionar `ProfileEvents.notify()`.

**Passo 2 — Backfill `user_preferences` → relacional**
Script idempotente que migra os 364 users com prefs legacy pras tabelas relacionais (`profile_job_preferences` + `profile_desired_titles` + `profile_other_locations`). Resolve regressão pra users existentes na próxima atualização do app.

Esforço: 1h.

**Passo 3 — Filtros da aba Vagas viram temporários**
Hoje `JobsViewModel.savePreferences` escreve no banco via `PreferencesRepository`. Muda pra:
- Estado vive em memória do `JobsViewModel` + persiste em `SharedPreferences` local (não no Supabase).
- Não chama mais `PreferencesRepository.savePreferences`.
- Pré-marca com base no Perfil ao abrir o sheet de filtros (lê identidade do relacional).
- User pode desmarcar/marcar livremente sem afetar Perfil.
- Feed filtrado client-side aplica os filtros temporários sobre as vagas vindas do servidor.

Esforço: 3-4h.

**Passo 4 — Trilha escreve direto nas tabelas relacionais (bypass do `whoIAm`)**
Resolve o bug do M1.3 de vez. Em vez de consertar o write quebrado do `whoIAm`, faz a trilha 1 escrever direto onde precisa:

| Pergunta da trilha 1 | Onde escrever |
|---|---|
| "Qual área te interessa?" (M1_3_1_Q2) | `profile_desired_titles` (1 linha por área selecionada) |
| "Que tipo de vaga você quer?" (M1_3_1_Q25) | `profile_job_preferences.job_types` |
| "Qual seu futuro profissional?" (M1_3_1_Q3) | `profile_personal.summary` se vazio (não sobrescreve se user já tem CV importado com summary) |

Pode ser implementado via `trail_to_profile_bridge.dart` (que já existe e popula outras tabelas relacionais).

Esforço: 3h.

**Passo 5 — Implementar confidence + UI "Análise limitada" + bypass de IA (M3.4 integrado)**

UI e regra de confidence:
- Servidor `analyze-match` passa a calcular `confidence_level` baseado na contagem de dimensões preenchidas no relacional.
- Cliente `JobCard` trata `isUnknown` (já existe) renderizando label "Análise limitada" no lugar do `X% match`.
- CTA dinâmico mostra exatamente quais dimensões faltam (ex: "Falta declarar cidade e tipo de vaga").
- Score interno continua calculado e usado pra ordenar feed (não desaparece — só esconde do user).
- Feature flag pra rollout gradual.

Sub-passo M3.4 — bypass de IA pra user fantasma (otimização):
- Antes de chamar OpenAI, servidor roda `isScenarioCStrict(user)` que retorna `true` quando TODAS as fontes do user estão vazias (nenhuma `profile_*` populada E `imported_resume.raw_text` vazio).
- Se `true` → servidor retorna direto `{score: 50, reasons: [{label: "Sem perfil", ...}]}` sem invocar gpt-4o-mini. Cliente já mapeia esse retorno pra `MatchResult.unknown()` ([ai_service.dart:289-294](career_gamification/lib/services/ai_service.dart#L289-L294)) — exatamente o que aciona "Análise limitada".
- Se `false` → fluxo normal: IA é chamada e tem que calcular score real (sem usar Cenário C como escape).
- Sob feature flag separada da confidence (`bypass_scenario_c_v1`) pra poder ligar/desligar independente.
- Economiza ~5-15% das chamadas de IA (users fantasmas no primeiro uso) sem afetar UX — o que o user vê é idêntico (já é "Análise limitada" pela regra de confidence).

Esforço: 5-7h (confidence + UI) + 1h (M3.4 bypass).

**Passo 6 (depois do release) — Apagar leituras do legacy**
Sem pressa. Quando ninguém escrever mais em `user_preferences` E no `gamification_data.whoIAm`, remover as branches lógicas que leem desses lugares (cliente Dart e servidor). Cache hash de match_analyses simplifica.

Esforço: 2h.

### Comportamento por tipo de user no release

| Tipo de user | O que ele vê |
|---|---|
| **User antigo com prefs legacy** | Backfill (Passo 2) garante que prefs continuem ativas. Vê scores normais. |
| **User antigo que fez trilha 1** | Backfill da trilha (parte do Passo 4) garante que prefs declaradas via trilha alimentem o match. Vê scores melhores que hoje. |
| **User novo no primeiro abrir** | Feed com cards "Análise limitada — falta declarar [X, Y]". Toca em "Completar" → vai pro Perfil → preenche → cards passam a ter score. CTA vira motor de preenchimento. |
| **User novo que só dá uma olhada** | Mesma coisa. Mas feed segue ordenado por score interno (escondido), então as vagas mais relevantes pra ele aparecem em cima mesmo sem ver número. |

### Total estimado

~2 semanas focado, em PRs pequenos:
- Semana 1: Passos 1, 2, 3, 4 (preparar terreno + reativar sinal da trilha).
- Semana 2: Passo 5 (confidence + UI).
- Passo 6 fica de babá pra pós-release.

### Checklist de validação antes do release

Antes de ligar a feature flag pra 100% dos users, validar manualmente esses cenários. Cada um confirma que a invalidação de cache (server + cliente) e o estado visual estão conversando direito.

| # | Cenário | Comportamento esperado |
|---|---|---|
| 1 | User novo cria conta, abre aba Vagas direto | Cards mostram "Análise limitada — preencha seu perfil". Servidor NÃO chama IA (M3.4 economiza). Verificar `analyze-match` logs: deve ter 0 chamadas pra esse user. |
| 2 | User vai pra Perfil → adiciona área "Marketing" → volta pra Vagas | Cards animam dots (estado pending) brevemente, depois mostram scores reais. Vagas de Marketing aparecem em cima da lista. |
| 3 | User adiciona 5 dimensões → volta pra Vagas | Cards mostram scores numéricos (confidence Alta — sem label "Estimativa parcial"). |
| 4 | User com perfil cheio remove tudo do Perfil | Cards voltam pra "Análise limitada". M3.4 reativa: servidor para de chamar IA pra esse user. |
| 5 | User entra na aba Vagas com perfil cheio, IA retorna score, depois user vai pro Perfil e adiciona 1 skill nova | Cards atualizam ao voltar pra Vagas. `profile_hash` mudou (`profile_text_hash` inclui skills) → cache server invalidou → IA é chamada de novo → novo score. |
| 6 | User mexe nos Filtros (aba Vagas) | Feed esconde/mostra vagas conforme filtros. Mas o score de cada vaga NÃO MUDA (continua refletindo identidade do Perfil). Verificar que `_matchCache` em memória não é invalidado por mudança de filtro. |
| 7 | User no nível "Média" (3-4 dimensões) | Card mostra score numérico + label discreto "Estimativa parcial". CTA opcional pra completar perfil. |
| 8 | User completa trilha 1 (área + tipo) | Após terminar a fase, ao voltar pra Vagas, scores refletem o novo perfil. Confirma que Passo 4 (trilha → relacional) funcionou e que cache invalida. |
| 9 | User abre aba Vagas, então outro device do mesmo user altera perfil | Cards do device atual NÃO atualizam até o user trocar de tab ou fazer pull-to-refresh. (Aceitável — é caso edge, mas vale documentar.) |
| 10 | Toggle a feature flag de bypass M3.4 OFF | Comportamento volta ao anterior (IA é chamada pra todos os casos, mesmo fantasmas). Nada quebra visualmente. |
| 11 | Toggle a feature flag de confidence OFF | Comportamento volta ao anterior (todos os scores aparecem como número, nenhum "Análise limitada"). Nada quebra. |

Os cenários 10 e 11 validam que a reversão funciona — crítico pra rollback de emergência.

### O que NÃO entra nessa rodada (volta pra Parte 4)

Continua não-mexer:
- Estrutura conceitual do score (continua 0-100 com dimensões).
- Apresentação visual além do que muda no card (sem redesign do ring).
- Trocar modelo de IA.
- ML treinado em swipes.
- Re-balancear pesos (M3.2) sem ground truth (M5.1) — segue sendo chute.

### Próxima ação concreta

**Passo 1 — auditar onde a seção de Preferências do Perfil escreve hoje.** Esse é o desbloqueio. Dependendo do resultado, o resto do plano segue direto ou ganha 1 sub-passo de correção.
