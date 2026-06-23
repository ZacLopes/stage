# PLANO-FASE-6 — Coleta de dados profile-first (reframe de "Onboarding enxuto")

> **Entregável desta sessão (plan mode):** este documento, no padrão das fases
> anteriores. **R1:** aprovado pelo fundador **antes** de qualquer código novo
> (exceto **T6.0**, o fix do bypass, autorizado e já executado nesta sessão —
> ver abaixo). Regras de ouro valem: **o fato vence** · **verificado, não
> declarado**.
>
> **Escopo:** resolver a causa-raiz dos perfis ocos e dar ao Stage uma coleta de
> dados de baixa fricção e alta profundidade — o que o match, a shortlist e a
> monetização exigem. Decisões de produto já tomadas pelo fundador (ver §0).

---

## Context — por que esta fase, e o DESVIO registrado do plano-mãe

O Stage não consegue entregar candidatos para empresas porque **metade da base
tem perfil "oco"** (sem experiência, sem skills) — e é isso que o match e a
shortlist precisam pra monetizar. Medições de 23/06 (queries no Supabase):

- **1.701 perfis relacionais; 98% concluem o onboarding** (1.670). Não é
  problema de desistência.
- **Quem importou CV (901): completude 72,8** (83% com experiência, 83% com
  skill). **Quem não importou (800): completude 22,7** (2% experiência, 2,5%
  skill). O caminho sem-CV coleta preferências + educação, mas **nunca**
  experiência/skills/resumo.
- **A importação colapsou** conforme o tráfego pago cresceu: 68% importavam (01/jun,
  completude 62) → 17% (08/jun, completude 28). Extrações/semana: ~350 → 3.
- **Só 11%** dos perfis estão "prontos pra shortlist" (com skills); **só 25%**
  têm ao menos 1 match ≥70.

### ⚠️ DESVIO do plano-mãe (o fato vence — registrar e levar ao arquiteto)

A **FASE 6 original ("Onboarding enxuto")** parte da premissa de que o gargalo é
**fricção/tempo** (≤8 telas, ≤90s) e propõe **TIRAR dados** do onboarding —
inclusive remover a tela de áreas (`DesiredTitlesScreen`), "coletada e não usada
no feed" (K3). **Os fatos refutam essa premissa:**

1. **Onboarding já converte 98%.** Encurtar não move a agulha da monetização.
2. **O gargalo é PROFUNDIDADE, não tempo.** Os perfis ocos vêm de (a) um bug de
   roteamento (T6.0) e (b) a dependência única de CV import — não de telas demais.
3. **Áreas é usada SIM** — não no ranking do feed, mas vale **30 pts no match** e
   é **filtro da busca de candidatos do admin** (`admin-candidates-search`).
   Removê-la machucaria a monetização. **Mantemos.**

**Reframe aprovado pelo fundador:** manter o onboarding atual (que já coleta o
essencial), **endurecer** o mínimo monetizável, e **adicionar uma camada de
profundidade** (trilha de IA conversacional) **depois** do onboarding — em vez de
enxugar e adiar dados. As ideias boas do F6 original que **adotamos**: CV como
acelerador recorrente (T6.4 do plano-mãe → nosso T6.2) e compressão de telas
**sem perder campos** (opcional). As que **invertemos**: não remover áreas; não
tornar dados opcionais. Campos exigidos pelo **TCE** (nome completo, DOB,
instituição, curso) seguem obrigatórios — restrição legal, intocável.

---

## §0 — Decisões de produto já tomadas pelo fundador (base deste plano)

1. **Onboarding leve, mantendo TODAS as perguntas atuais** (a lista já é coletada
   hoje); a coleta rica vem **depois**.
2. **Tipo de vaga vira obrigatório** no onboarding (hoje é pulável; vale 20 pts).
3. **Resumo gerado pela IA**, salvo em `profile_personal.summary`, exibido no
   Perfil e **reaproveitado na exportação do CV**.
4. **Sem foto de CV.** Import = PDF + LinkedIn (link + PDF que o LinkedIn exporta).
5. **Idiomas entram no MVP** da trilha (junto com experiência + skills).
6. **Trilha de IA pra quem não importou: aparece logo após o onboarding** (convite
   suave) **E** fica acessível no hub do Perfil + nudges.
7. **MVP completo** (inclui tudo acima).

---

## T6.0 — Fix do bypass da CompletionScreen (✅ FEITO nesta sessão)

**Causa-raiz verificada dos perfis ocos:** o `AuthGate` ([splash_screen.dart](lib/features/splash/splash_screen.dart))
caía, como fallback pós-login, na **`CompletionScreen` legacy**. A opção
**"Começar do zero"** dela ([completion_screen.dart:152-174](lib/features/auth/completion_screen.dart))
chamava `markOnboardingCompleted()` **sem coletar nada**. Esse fallback era
atingido por quem tinha `user_profiles` legacy completo (`needsProfileSetup`=
false, porque o form de signup antigo coleta curso/semestre/universidade) mas
`profile_personal` vazio (`isInProfileFirstFlow`=false). **Medição: 473/800
perfis ocos (59%) batem exatamente essa condição;** 783/786 concluíram em <2h do
signup (descartado backfill). A redireção pra TwoDoors dependia da flag PostHog
`new_onboarding_enabled`, que falha em cold start (a própria
`FeatureFlagsService` existe por causa desse histórico).

**Fix aplicado (R3 ✔ R4 ✔ R6 ✔):**
- [splash_screen.dart](lib/features/splash/splash_screen.dart): função pura
  testável `resolvePostLoginRoute` + enum `PostLoginRoute`; o fallback agora vai
  pro **onboarding que coleta** (`TwoDoorsScreen`). A `CompletionScreen` legacy
  só volta via **kill-switch** `legacy_completion_screen_enabled`
  (default OFF ⇒ fix ligado; failure-safe: flag ausente/não-carregada ⇒ onboarding).
- [feature_flags_service.dart](lib/services/feature_flags_service.dart): constante
  `legacyCompletionScreenEnabled`.
- Migration [20260623120000_legacy_completion_screen_flag.sql](supabase/migrations/20260623120000_legacy_completion_screen_flag.sql)
  (seed do kill-switch OFF) + `migrations.manifest` atualizado (105).
- Teste [test/features/splash/post_login_route_test.dart](test/features/splash/post_login_route_test.dart)
  (6 casos, cobre a regressão dos perfis ocos + o kill-switch).
- **Verde:** `flutter analyze` (3 arquivos) 0 issues; `flutter test` 6/6.

**Falta (fundador, processo de release):** `supabase db push` da migration;
commit numa branch dedicada (`fix/onboarding-completion-bypass`); validação
device; release. *Não apliquei a migration nem commitei (R2 + release é do fundador).*
**Nota:** isto previne perfis ocos NOVOS; os ~473 existentes têm dados em
`user_profiles` legacy — recuperação opcional via migração `user_profiles →
profile_*` (fora do escopo; não é nudge).

---

## T6.1 — Onboarding: manter as perguntas, endurecer o essencial

O inventário (tela a tela) confirma que o onboarding **já coleta toda a lista do
fundador**, quase tudo por clique: atribuição, nome/sobrenome, e-mail, telefone,
DOB, momento de estudo (escola/faculdade/trancou/terminou/não estuda) + instituição
(typeahead) + curso + semestre, áreas (13 chips), cidade (CEP/GPS), cidades de
trabalho, modalidade (3 chips), tipo de vaga (4 chips).

- **Mudança mínima:** tornar **"Tipo de vaga" obrigatório** (remover o "Pular" em
  [job_types_screen.dart](lib/features/onboarding/presentation/preferences/job_types_screen.dart));
  modalidade já teve o "Pular" removido — manter. "Cidades de trabalho" pode seguir
  pulável (cidade-casa já capturada).
- **Import em destaque** na 1ª tela (`TwoDoorsScreen`).
- **NÃO** coletar experiência/skills/resumo aqui (confirmado: hoje não coleta) —
  isso é a "coleta maior depois" (T6.3).
- **Opcional (adotado do F6 original, sem perder dados):** comprimir nome+sobrenome
  +e-mail+telefone em menos telas. Não remover campos.

---

## T6.2 — Importação reforçada (PDF + LinkedIn) e recorrente

Maior alavanca de qualidade (72,8 vs 22,7). Remover o atrito "não tenho PDF agora":
- **PDF:** já existe (`extract-profile`).
- **LinkedIn:** capturar o **link** (`profile_personal.linkedin_url` já existe) e
  orientar o **"Salvar como PDF" do LinkedIn** → importar via `extract-profile`
  (mesmo pipeline). *Raspar o link é frágil/contra os termos; o PDF exportado é rico
  e legal.*
- **Recorrente:** banner persistente no hub do Perfil + lembrete pós-cadastro pra
  quem entrou sem importar (alinha com T6.4 do plano-mãe).
- **Hardening:** se `extract-profile` falhar, NÃO marcar nada como completo
  silenciosamente (lição do Path 2 do T6.0); mostrar erro e cair na trilha.

---

## T6.3 — Trilha de IA conversacional (o núcleo novo): experiência + skills + idiomas

A "coleta maior depois". **Não se constrói do zero:** o conteúdo já existe na
tabela `questions` (172 perguntas) — a antiga trilha gamificada:
- **t3 (experiência) = 152 perguntas**, ramificadas por categoria (emprego,
  estágio/trainee, liderança estudantil, projeto, pesquisa, voluntariado), com
  prompts que dão confiança + exemplos ("Me conta 2-3 coisas concretas que você
  fez. *Pode ser desorganizado, eu organizo depois.*") → geram bullets via
  `generate-bullets`.
- **t4 (skills/idiomas):** "Se abríssemos sua caixa de ferramentas, o que você
  domina?" → categorias → ferramentas; idiomas com nível; certificações.

**O que fazer — ressuscitar e modernizar:**
- **Adaptável (cérebro de lacunas):** antes de começar, lê `profile_*` e monta a
  fila só do que falta. Importou e já tem experiência? Pula pra skills. Oco? Roteiro
  completo.
- **Widget-first:** cada passo é chips/picker/exemplos clicáveis (mata a página em
  branco). A IA só faz o difícil: virar exemplos em bullets, extrair estrutura de
  texto solto, montar o resumo.
- **Reposicionada:** de "gamificação/XP" → **"complete e apareça pras empresas"**.
- **Onde aparece (decisão §0.6):** convite suave **logo após o onboarding** pra
  quem não importou **+** sempre acessível no hub do Perfil + nudges no momento de
  match.
- **Reuso:** [trail_to_profile_bridge.dart](lib/features/gamification/services/trail_to_profile_bridge.dart)
  (resposta estruturada → `profile_*`, com merge/dedup) — **reconciliar prefixos**
  `m1..m5` (bridge) vs `t1..t5` (tabela `questions`); `ProfileRepositorySupabase`
  (escritas prontas); `skills_catalog`+typeahead (já ON).
- **Anti-invenção:** a IA **formata** o que o usuário deu, nunca inventa experiência
  (reusar disciplina do pipeline `adapt`).

---

## T6.4 — Resumo gerado pela IA (salvo + reusado no CV)

Depois que o usuário tem área + experiência + skills, a IA **gera o resumo**
(`generate-summary`) e **salva em `profile_personal.summary`** (campo já existe).
Exibido no hub (editável) e **reaproveitado na exportação do CV** (o PDF já sai com
resumo pronto). Não é etapa de digitação — é subproduto de 1 toque, reofertado
quando o perfil muda.

---

## T6.5 — Hub de completude no Perfil + cérebro de lacunas

O Perfil deixa de ser formulário passivo e vira **hub ativo**:
- Topo: completude + enquadramento de valor ("Perfis completos aparecem pra mais
  empresas").
- Botão **"Completar com a IA"** (entra na trilha já sabendo as lacunas).
- Cartões de lacuna ("Adicione 1 experiência", "Faltam skills") que abrem o passo
  exato.
- Mostra o resumo da IA; mantém edição manual (deixa de ser a porta principal).
- **Cérebro de lacunas:** componente único que responde "o que falta pra ESTE
  usuário ser vendável?" (deriva de `profile_*`; começa reaproveitando a lógica do
  `completeness_score`). Alimenta trilha + nudges + cartões. **É o que conecta
  onboarding + import + IA + perfil num sistema só.**

---

## T6.6 — Banco: mudanças mínimas (de propósito)

O schema já cobre tudo (18+ tabelas `profile_*`). **Nenhuma tabela nova pra dados
de carreira.** `linkedin_url` e `summary` já existem; `saved_resumes.source` é texto
(grava `linkedin_pdf` sem migration). **Adições opcionais:**
- `profile_guided_progress` (user_id, passo, status) pra a trilha ser **retomável**.
- Revisar a fórmula do **`completeness_score`** pra pesar campos monetizáveis (Tier
  1/2), não cosméticos — ela guia nudges e o cérebro de lacunas.

---

## T6.7 — Telemetria (R7) + flags (R4)

- **Eventos novos por passo da trilha** (constante em `analytics_events.dart` +
  emissor no mesmo PR; abandono por etapa).
- **Flags estruturais** (`app_feature_flags`, carrega no startup — NÃO PostHog):
  trilha de IA atrás de flag, rollout 10→50→100. (O kill-switch do T6.0 já segue
  esse padrão.)

---

## Critérios de aceite (medição real, não declarada)

- **Norte:** % da coorte nova "pronta pra shortlist" (área+cidade+semestre+≥3
  skills+modalidade) sobe forte vs. baseline 11% — sobretudo entre não-importadores.
- **Reverter a queda de completude por coorte semanal** (62→28 em junho → subir).
- **% de não-importadores com ≥1 experiência e ≥3 skills** (hoje ~2%) sobe — teste
  direto da trilha.
- **% de usuários com ≥1 match ≥70** (hoje 25%) sobe.
- **Funil da trilha:** início→conclusão e abandono por passo (PostHog).
- **TCE intacto:** nome completo, DOB, instituição, curso seguem coletados/obrigatórios.
- Trilha atrás de flag, com A/B medindo lift de completude.

---

## Desvios do plano-mãe registrados (para o arquiteto)

| Plano-mãe F6 | Decisão desta fase | Por quê (fato) |
|---|---|---|
| Tirar `DesiredTitlesScreen` (áreas) | **Manter** | Áreas = 30pts no match + filtro do admin (não-usada-no-feed ≠ não-usada) |
| Gender/AgeRange opcionais; comprimir | Compressão **opcional, sem remover campos** | Onboarding já converte 98%; risco>retorno em mexer |
| Foco em fricção/tempo (≤90s) | Foco em **profundidade** | Gargalo medido é depth + bypass, não tempo |
| (não previa) | **Trilha de IA + hub + cérebro de lacunas** | Recupera a substância que só o CV trazia |

---

## O que esta fase NÃO inclui (sem novo prompt)

Recuperação dos ~473 perfis ocos existentes (migração `user_profiles→profile_*`);
match v2 treinado em outcomes; foto de CV; Vaga Stage / console (Fase 4); Android
(Fase 5); qualquer refactor fora do caminho das tarefas (R6).

---

## Verificação (como testar de ponta a ponta)

- **T6.0 (feito):** `flutter analyze` + `flutter test` verdes; após `db push`,
  validar device que um usuário com `user_profiles` legacy completo + `profile_personal`
  vazio cai em `TwoDoorsScreen` (não CompletionScreen).
- **Banco:** rodar as queries de completude por coorte (antes/depois) via MCP
  Supabase (leitura) pra medir lift.
- **Match real:** semear 1 preferência antes de testar `analyze-match` (perfil vazio
  cai no bypass do Cenário C e não prova nada — `CLAUDE.md`).
- **App:** `flutter test` + 1 widget test por tela nova (R3); validar a trilha na
  conta interna.
- **Funil:** eventos PostHog novos por passo pra achar onde trava.
