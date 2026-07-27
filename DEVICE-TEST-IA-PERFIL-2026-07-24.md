# Device-test IA/Perfil — 24/07/2026

**Como foi feito:** iPhone 17 Pro (simulador), build **debug**, contra o Supabase de
**PRODUÇÃO** (migrations até `20260720120000`). Conta de teste
`187ed041-3809-4de7-ad9d-eccba3dc4297`, onboarding percorrido do zero.
Parte da sessão rodou com `trilha_assist_v1` forçada ON por um override local
só-debug em `feature_flags_service.dart` — **esse override foi revertido**; o
working tree contém apenas o trabalho de F4/F5/F6.

Base: `PLANO-IA-PERFIL-FASE-6.md`, `PLANO-IA-PERFIL-FASE-5.md`,
`PLANO-IA-PERFIL-FASE-4.md`, `HANDOFF-CLAUDE-CODE-IA-PERFIL.md`.

---

## 1. BLOQUEADOR A — escrita da coleta guiada fica invisível até reiniciar o app

**Gravidade:** alta. Bloqueia ligar `trilha_assist_v1`.
**Flag:** aparece com `trilha_assist_v1` ON (é o fluxo do Assistente).

### Reprodução medida

1. Assistente → chip "Adicionar experiência" → fluxo guiado completo
   (tipo `Estágio` → empresa → cargo → início → término → descrição).
2. Recibo na conversa: `✓ Adicionei ao seu perfil: sEtagiario de Dados ·
   Ardis Consultoria — Estágio · 07/2026 – 07/2026.`
3. Banco (verificado por SQL): `profile_experiences` = 1 linha, `kind='estagio'`,
   1 linha em `profile_bullets`, RLS `auth.uid() = user_id` normal. **A escrita
   está correta e legível.**
4. **Perfil → Dados: "Experiência profissional (0)"**; completude parada em 45%.
5. **Perfil → Currículos → Ver prévia: sem seção EXPERIÊNCIA** (só cabeçalho +
   FORMAÇÃO) — logo o PDF exportado também sairia sem ela.
6. Background + foreground do app: **não resolve**.
7. **Cold start: "Experiência profissional (1)"** com card e bullet; completude
   45% → 52%.

### Causa-raiz (confirmada no código)

`_scheduleProfileReload()` (`lib/features/resume/resume_tab.dart:144`) faz o
certo — `context.read<ProfileEditorViewModel>().load()` +
`ProfileEvents.instance.notifyChanged()` — e o comentário dele afirma cobrir
"add/remove/edita skill, idioma, campo, bullet, **experiência**".

Mas ele está ligado **somente** aos writers de *ferramenta* do assistente
(`assistWriteField`, `assistItemAdder`, `assistItemRemover` —
`resume_tab.dart:207-232`).

`lib/features/trilha/application/trilha_writeback.dart` — o write-back da
**coleta guiada**, que é o caminho do chip "Adicionar experiência" — tem **zero**
ocorrências de `ProfileEvents`, `notifyChanged` ou reload.

Agrava: `ProfileEditorViewModel` **emite** `ProfileEvents.notifyChanged()`
(`profile_editor_view_model.dart:633`) mas **não assina** o stream — só escuta
`onAuthStateChange` (`:83`). Assinantes de `ProfileEvents` hoje:
`user_viewmodel`, `general_resume_card`, `jobs_viewmodel`, `jobs_swipe_screen`.

Ou seja: a correção de invalidação da **Fase 3 F3** cobriu as ferramentas do
assistente e passou batido na coleta guiada.

### Impacto no usuário

O header do Assistente tem o link **"Ver meu perfil"**. O usuário lê "adicionei
ao seu perfil", clica, e vê zero experiências. Lê como o assistente mentindo —
no fluxo que é a razão de existir de toda a frente IA/Perfil.

Mitigação existente: `_InfoTab` tem `RefreshIndicator(onRefresh: () => vm.load())`
(`profile_screen.dart:779`), então **o dado não se perde** e o pull-to-refresh
recupera. Mas nada indica ao usuário que precisa puxar.

### Correção sugerida (não aplicada)

Disparar o mesmo reload/notify a partir da conclusão do `TrilhaWriteback`, ou
fazer `ProfileEditorViewModel` assinar `ProfileEvents.instance.changes`. A
segunda opção fecha a classe inteira do bug, mas exige cuidado com o loop
(ele mesmo emite em `:633`).

---

## 2. BLOQUEADOR B — nenhum CV salvo abre editável se o app subir antes da migration

**Gravidade:** alta. **Não está atrás de flag nenhuma** — vaza mesmo com
`trilha_assist_v1` OFF.

`lib/features/profile/resume_detail_screen.dart:118` mudou no working tree:

```dart
- bool get _isEditable =>
-     widget.resume.title.startsWith(ResumeViewModel.kTrailResumeBaseTitle);
+ bool get _isEditable => widget.resume.source == SavedResumeSource.trail;
```

`SavedResumeSource.fromDb` faz fallback para `manual` em valor desconhecido
(`lib/data/models/models.dart:778-784`). O valor `'trail'` só passa a existir com
`supabase/migrations/20260722120000_backfill_trail_source.sql`, **não aplicada**
(o CHECK em prod nem aceita `'trail'`).

**Resultado contra o banco atual:** 100% das linhas leem `manual` ⇒
`_isEditable == false` ⇒ somem "Editar texto" (`:718-732`), "Regerar com IA"
(`:738-746`) e o "Exportar PDF" do dock (`:750`). Sem erro, sem aviso. O share do
PDF continua funcionando; o que se perde é editar e regerar.

O comentário no código cobre o caso "build **antigo** + DB novo". A combinação
quebrada é a inversa: **build novo + DB antigo**.

**Correção:** ordem de co-deploy obrigatória — migration `20260722120000` (e a
`20260721120000`) em prod **antes** do app. Ou tornar `_isEditable` tolerante
(`source == trail || title.startsWith(kTrailResumeBaseTitle)`) enquanto o
backfill não roda.

---

## 3. Co-deploy pendente (não é bug)

Após "Exportar PDF" do Currículo geral com a flag ON: `saved_resumes` do usuário
= **0 linhas**, `source='general'` = 0. A migration `20260721120000` não está em
prod, então `save_general_resume_version_v1` não existe.

Comportamento é **honesto**: o share funciona, o card não afirma versão que não
existe, e o evento sai com `status:'failed'`. Risco: se o app subir antes da
migration, o versionamento no-opa em silêncio.

---

## 4. Bugs menores (verificados)

| # | Achado | Evidência |
|---|---|---|
| B1 | PDF exportado sai como **`curriculo_.pdf`**, sem nome | `general_resume_export.dart:252` usa `(user?.name ?? 'profissional')`, mas `user_profiles.name` é **string vazia**, não NULL — o `??` não dispara. Share sheet mostrou `curriculo_ · 817 bytes` |
| B2 | Onboarding não grava `user_profiles.name` (causa-raiz de B1) | grava `profile_personal.first_name/last_name` ("Zac Teste"/"silva") e deixa `user_profiles.name = ''` |
| B3 | Capitalização inconsistente entre os passos de nome | "primeiro nome" auto-capitaliza; "sobrenome" não → perfil e CV exibem "Zac Teste **s**ilva" |
| B4 | `profileHasContent` deixa exportar CV quase vazio | 0 experiências + 0 skills + 1 educação de ensino médio ⇒ "Exportar PDF" liberado; PDF de **817 bytes** |
| B5 | Login tenta **cadastro** antes de login | log: `User already exists, attempting to sign in instead...` + `AuthRetryableFetchException(Connection closed before full header was received, /auth/v1/token)`. Falha transitória de rede vira "não consigo entrar" com senha certa |
| B6 | Sem validação de datas | estágio com término **igual** ao início (07/2026 → 07/2026) aceito sem aviso |
| B7 | `debugPrint` em loop | `Debug: Snapshot is the same as the last one, nothing changed, do nothing.` repetindo continuamente durante uso normal |

---

## 5. UX / design (verificado no simulador)

**Fluxo de adaptação — o de maior retorno.** O gate `profile_incomplete` funciona
e a copy é excelente ("preciso de pelo menos uma experiência, projeto ou formação
completa — ou um CV importado em PDF"). Mas ele dispara **depois** da folha
"Algo que esqueceu de mencionar?": o usuário escolhe habilidades, clica "Adaptar
como está", e só então descobre que não dava — o app já sabia antes de abrir a
folha. E o único CTA é "Importar CV em PDF", embora a mensagem cite três
caminhos; não há saída para adicionar experiência nem para o Assistente.
Dado que **63% das falhas de adaptação são `profile_incomplete`**
(`PLANO-IA-PERFIL-FASE-6.md` §2), mover o gate para antes da folha é a correção
de UX de maior retorno da fase.

**Onboarding**
- TwoDoorsScreen: CTA "Continuar" desabilitado que **nunca** habilita; a
  navegação real é tocar o card (chevron `>`). O card "Usar meu CV" tem borda
  ciano idêntica ao estado *selecionado* das outras telas.
- **Quatro linguagens visuais de seleção** no mesmo fluxo: borda ciano sem ação
  (TwoDoors); borda ciano + fill + check (como nos conheceu / gênero); chip azul
  sólido (áreas); checkbox à direita (modalidade / tipo de vaga).
- "Onde você quer trabalhar?" promete "**ou pule** se topa qualquer lugar" — não
  existe botão de pular.
- Sem validação de nome: "Continuar" habilitado com 1 caractere.
- Prompt de push dispara na entrada, sem tela de pré-permissão.
- CTA "Completar com a IA" é o único sangrado até as bordas.

**Perfil**
- Barra de completude em **verde** a 45% — verde é `success` no design system, e
  destoa do azul da marca.
- **"Onde você mora" está em Objetivos**, mas é um *fato* — pelo contrato de
  linguagem da §2 do handoff pertence a Dados.
- Pin de localização **vermelho** sobre halo **verde** (vermelho = erro no DS).

**Assistente (flag ON)**
- Coach-mark "Toca no ✦ pra ver tudo que eu faço" **cobre** a 5ª opção do seletor
  de experiência ("Atlética / Liga / Entidade") e é redundante com o chip
  "Tudo que eu faço", ambos na tela ao mesmo tempo.
- Chip primário é "**Melhorar meu resumo**" para um perfil com 0 experiências —
  next-best-action errado (já registrado como backlog v3).
- **Duas entradas de texto simultâneas**: o campo inline do passo e a barra de
  chat, ambas habilitadas, sem indicação de qual usar.
- Três balões seguidos do bot ao entrar pelo chip, dois redundantes ("Bora
  adicionar sua experiência!" + "Agora a parte que mais conta pras empresas:
  suas experiências").

**Vagas**
- "**Alta** match" para perfil recém-criado sem experiência nem skills —
  contradiz o princípio "realismo > inflação".

---

## 6. O que FUNCIONA (verificado ao vivo, flag ON)

- **F5.2** card "Fonte importada" no fim de Perfil → Dados, estado vazio com
  convite "Importar currículo" (`ImportedSourceCardView.empty`) — não vira beco.
- **F5.3** seção virou "Arquivos e versões"; empty-state usa a copy nova
  ("Seus currículos gerados e adaptados para vagas aparecerão aqui"), sem citar
  "importar".
- **F4.4** card do Currículo geral com "Modelo: Harvard ATS Brasil" + "Trocar";
  copy cai corretamente no fallback "Gerado a partir dos dados atuais" porque
  ainda não há versão salva (`versionLabel == null`).
- **F6.0** `resolveOriginalSource` está implementada **e ligada**
  (`adapted_resume_preview_screen.dart:310`) — não é código morto. **O plano da
  Fase 6 lista F6.0 como fatia a fazer; ela já está pronta.**
- Coleta guiada de experiência POR TIPO: taxonomia inclusiva (emprego, estágio,
  monitoria/IC, voluntariado, atlética, freela, empresa da família, outro),
  multi-select com contador, recap por resposta com editar, saída honesta
  "Ainda não tenho experiência", copy anti-invenção.
- Escrita guiada chega ao banco com `kind` correto.
- Completude **única** (45%) na aba Dados — Fase 3 F2 ok.
- Export PDF: estado de busy honesto, share sheet abre.

---

## 7. Correção ao plano (o fato vence)

`HANDOFF-CLAUDE-CODE-IA-PERFIL.md` §7 afirma: *"Cargo desejado, senioridade/nível
e fit cultural ainda não estão todos expostos em Objetivos."*

**Desatualizado.** Os três estão expostos em Perfil → Objetivos, com estados
vazios honestos ("Não informado" / "Não definido") e ação Editar.

---

## 8. Aba Candidaturas (`applications_tracker_v1` ON/100 em prod)

Testada de ponta a ponta com a flag do Assistente **OFF** (realidade de produção).

### Funciona

- Validação do formulário é honesta: submeter vazio mostra erros inline
  ("Informe a empresa" / "Informe a vaga") com borda vermelha; preencher limpa.
- Escrita correta: `applications` gravou `type='manual'`, `status='submitted'`,
  `external_company='Nubank'`, `external_title='Estagio de Dados'`.
- **Máquina de estados da Fase 1 funciona:** mudança para Entrevista gerou
  `status='interview'` e o evento `submitted->interview (user)` — o actor
  resolveu como `user`, não `system`.
- Menu de status oferece só transições válidas a partir do estado atual.

### Defeitos

| # | Achado |
|---|---|
| C1 | **O app nunca segue o item para o novo segmento.** Depois de *adicionar* (status Enviada) ele fica em "Salvas" mostrando "Nenhuma vaga salva ainda"; depois de *mudar o status* para Entrevista ele fica em "Enviadas" mostrando "Nenhuma candidatura enviada ainda". Duas ações seguidas do usuário terminam numa tela vazia, com o item a um toque de distância |
| C2 | Empty-state inicial diz **"Nenhuma vaga salva ainda"** e explica *swipe pra direita* — vocabulário da aba "Salvas" antiga, numa aba chamada Candidaturas cujo subtítulo é "Acompanhe aqui suas candidaturas" |
| C3 | Os 4 segmentos **não aparecem** quando não há nenhum item; surgem só depois do primeiro registro |
| C4 | A régua de segmentos fica **cortada na borda direita** ("Finaliza…") sem fade nem indício de que rola |
| C5 | O badge do card exibe **`manual`** cru — valor do enum vazando para a UI |

### Nota sobre a baseline do plano

`PLANO-IA-PERFIL-FASE-6.md` §1.7 afirma "0 candidaturas `type='manual'` e 0
`external_url`". **Este teste criou a primeira linha `type='manual'` em prod**
(conta de teste, `648f2f63-a710-4f86-9a63-7d03c03d3a6c`). Considerar ao reler
essa métrica.

## 9. BLOQUEADOR C — `adaptation_rejected` é perfil sem SKILLS, não qualidade do modelo

**Corrige a conclusão da §2 do `PLANO-IA-PERFIL-FASE-6.md`.**

Depois que o perfil ganhou 1 experiência, o gate `canAdaptCv` **liberou** e a
adaptação rodou de verdade. Ela falhou — e os logs da Edge dão a causa exata:

```
[adapt-v2] failure_diff attempt=1: input_skills_count=0  input_skills=[]
  output_skills=[Python, Análise de Dados, Machine Learning, Relatórios,
                 Visualização de Dados, Pandas, Numpy, Scikit-learn]
[adapt-v2] validation failed attempt=1: field=skills
  message=skill inventada: "Python" (1 unmatched > 0 translation slots for extras=[])

[adapt-v2] failure_diff attempt=2: output_skills=[Análise de Dados, Relatórios,
                                                  Machine Learning]
[adapt-v2] rejected after retry ... message=skill inventada: "Análise de Dados"
```

### Por que isso importa

O plano trata `profile_incomplete` (63%) e `adaptation_rejected` (37%) como
causas diferentes e classifica a segunda como "qualidade do motor de IA, fora do
escopo". A evidência diz outra coisa:

- O usuário tem **zero skills** no perfil (`input_skills=[]`).
- O validador anti-invenção rejeita **qualquer** skill de saída que não esteja na
  entrada, e só tolera extras quando o usuário preencheu a folha "Algo que
  esqueceu de mencionar?" (`extras=[]` porque ele pulou).
- Para uma vaga de Ciência de Dados o modelo **sempre** vai emitir alguma seção
  de skills. Logo: **perfil com 0 skills + folha de extras pulada ⇒ a adaptação
  falha de forma determinística.** O retry não ajuda — não é variância do LLM,
  é contradição estrutural.

### O defeito preciso

**`canAdaptCv` e o validador discordam.** O pré-check exige experiência,
projeto **ou** formação — e não olha skills. O validador exige skills. O gate
deixa entrar quem o validador vai expulsar.

Consequência: uma fatia relevante dos 37% de `adaptation_rejected` é o **mesmo
problema de perfil oco** dos outros 63%, só que descoberto tarde e com uma
mensagem que não ajuda.

### Defeitos de UX no mesmo caminho

| # | Achado |
|---|---|
| A1 | A mensagem é "A adaptação não passou na verificação de integridade. **Tente novamente**." e o CTA é **"Tentar de novo"** — mas a falha é determinística. É uma affordance falsa: nenhuma quantidade de retentativas resolve |
| A2 | A mensagem não diz o que o usuário precisa fazer (adicionar habilidades ao perfil, ou preencher a folha de extras) |
| A3 | No retry seguinte a tela exibiu a **exceção crua**: `ClientException: Connection closed before full header was received, uri=https://<project>.supabase.co/functions/v1/adapt-resume-to-job` — jargão técnico em inglês para usuário pt-BR **e vazamento da URL/ref do projeto Supabase na UI** |
| A4 | `Connection closed before full header was received` apareceu **duas vezes** nesta sessão (login e adapt) — sugere timeout de cliente curto demais para chamadas de Edge longas (o adapt faz 2 tentativas de OpenAI, ~15 s) |

### Confirmação lateral

O log da Edge também confirma o B1/B2 do lado servidor:
`[adapt-resume] user=187ed041… name="" rawTextLen=0` — nome vazio.

## 10. Verificado e DESCARTADO como problema

Com `trilha_assist_v1` OFF, o card "Currículo geral" **não aparece** em Perfil →
Currículos. Cheguei a suspeitar de regressão, mas o gating
`if (assistEnabled) ... GeneralResumeCard()` **já existe no `main`**
(`profile_screen.dart:323` em HEAD). É o rollback pretendido, não um defeito
introduzido pelo working tree.

## 11. Experimento controlado que PROVA o Bloqueador C

Depois de adicionar **3 skills** (Python, Excel, SQL) pelo editor manual, repeti a
adaptação **sem selecionar nenhum extra** — única variável alterada: skills 0 → 3.

**A adaptação passou.** "✓ Adaptado · 2 ajustes aplicados":
- Skills Técnicas: ANTES `Python | Excel | SQL` → DEPOIS `Python | SQL | Excel`
  (reordenação, nada inventado)
- Experiência: bullet reformulado

Isso confirma que `adaptation_rejected` era o **perfil sem skills**, não a
qualidade do motor. O diff antes/depois da UI é honesto e bem construído.

### F6.0 validada em runtime

Sem CV importado e sem documento de saída salvo, `resolveOriginalSource` retornou
null e a aba "Original" caiu no **fallback de `ResumeData`** — a degradação
projetada: nem spinner infinito, nem falso sucesso. ✔

**Porém, achado de nomenclatura:** a aba **"Original" é um EDITOR**, não uma
referência. Traz chips de skill removíveis (`✕`), "+ Adicionar" e
"↩ Voltar ao original" — e já exibe o badge **"✏️ Mudou"** antes de o usuário
tocar em nada. O toggle promete uma comparação *Adaptado × Original* e um dos
lados é editável, o que embaralha o significado de "original".

### Restante do fluxo (tudo funcionando)

- Download gera `saved_resumes` com `source='adapted'`, `resume_data` presente,
  `template_id='harvard_ats'`; toast "CV salvo! … ficou em Perfil →" com
  affordance de navegação.
- Detalhe do CV adaptado: **view-only + troca de modelo**
  (`_isStructuredAdapted`), só "Compartilhar" no dock — correto por design.
- **`ResumeTemplateSelector`** (o mesmo componente que o "Trocar" da F4.4 abre):
  5 modelos com thumbnails reais e copy honesta ("O PDF será regerado com o
  modelo novo e substituído em Currículos"). Troquei para Cobalt Modern: o PDF
  regerou em 2 colunas e o banco persistiu `template_id='cobalt_modern'`
  **mantendo o mesmo `file_path`** (blob substituído no Storage, sem linha nova).
- Typeahead de skills (`skills_typeahead_v1`): "Pyth" → Python; "SQL" → SQL /
  PostgreSQL / MySQL. As 3 skills gravaram com `canonical_skill_id` preenchido.
- **Contraste que isola o Bloqueador A:** o save do editor manual atualizou a UI
  na hora (completude 52% → 61%), porque quem escreve é o próprio
  `ProfileEditorViewModel`. A escrita guiada do Assistente não atualizou nada.

### Novos defeitos desta rodada

| # | Achado |
|---|---|
| D1 | Nome do arquivo do CV adaptado sai como **`curriculo__1eee2f.pdf`** — underscore duplo + prefixo do UUID da vaga, sem nome do usuário. Mesma causa-raiz do B1 (`user.name` vazio). É o arquivo que o candidato anexa |
| D2 | A folha "Algo que esqueceu de mencionar?" oferece **skills que já estão no perfil** (ofereceu "Python" logo depois de eu adicionar Python). Não filtra pelo que o usuário já tem |
| D3 | O card da biblioteca mostra o **título truncado** ("CV adaptado - Pro…") em vez de vaga/empresa — com 2+ CVs adaptados todos ficam com o mesmo rótulo ilegível. **Valida a F6.4 com evidência de uso** |
| D4 | O CTA "Baixar PDF" é **ciano**, enquanto o primário do app é o azul `#1565A8` |
| D5 | Editor de skills: copy "Você pode adicionar mais **6**" ao lado do contador **0/12** — o "6" é o mínimo recomendado, mas lê-se como teto |
| D6 | Seções vazias em Dados usam affordances diferentes: `+` (Idiomas, Projetos) vs **lápis** (Habilidades, Certificações, Interesses). Para uma seção com (0), lápis é contraintuitivo |
| D7 | O e-mail renderizado no cabeçalho do CV saiu como `s@f.g` (dado de teste, mas o app não valida formato de e-mail de contato antes de imprimir no documento) |

## 12. Importação + remoção da fonte — Fase 5 validada de ponta a ponta

Cenário montado: PDF real de currículo ("Maria Oliveira Santos" — nome, telefone e
cidade DIFERENTES do perfil) colocado no "On My iPhone" do simulador e importado
pelo app, com `trilha_assist_v1` ON.

### O motor 3.0I de revisão de conflitos funciona — e a política está certa

O card "Do seu CV — Escolhe o que trazer pro seu perfil" classificou cada item:

| Item | Badge | Default |
|---|---|---|
| Nome (CV: Maria Oliveira Santos / Você: Zac Teste silva) | `difere` | **desmarcado** |
| Telefone (CV: (11) 98877-6655 / Você: 43991260202) | `difere` | **desmarcado** |
| Cidade (CV: Sao Paulo, SP / Você: Londrina, PR) | `difere` | **desmarcado** |
| Resumo, LinkedIn, 4 skills, 3 idiomas, 2 experiências, 1 formação | `novo` | marcado |

CTA com contagem honesta: **"Aplicar 14 itens"**. Recibo pós-aplicação:
**"Trouxe 14 itens do seu CV"** com **Desfazer**. Stepper subiu 3/5 → 4/5.

### Invariante "manual vence" — PROVADO

| Campo | Antes | CV dizia | Depois |
|---|---|---|---|
| `first_name` | Zac Teste | Maria Oliveira | **Zac Teste** ✔ |
| `phone_number` | 43991260202 | (11) 98877-6655 | **43991260202** ✔ |
| `linkedin_url` | vazio | maria… | **preenchido** ✔ |
| `summary` | vazio | Estudante de Eng. | **preenchido** ✔ |

Valor manual não-vazio venceu; slot vazio foi preenchido. Merge **aditivo**, sem
replace: experiências 1→3 (a "Ardis Consultoria" preexistente sobreviveu),
educação 1→2, skills 3→7, idiomas 0→3.

### Metadados da F5.1 — todos gravados pelo caminho novo

```
source=imported · original_filename=cv_maria_oliveira.pdf · extraction_status=ready
is_current_source=true · client_import_id=f37c4b64-… · file_path=…/imports/….pdf
```

E o card renderiza exatamente isso: **"cv_maria_oliveira.pdf" · "Importado em
24/07/2026" · "Arquivo lido"** · [Ver] [Substituir] · Remover (destrutivo em
hierarquia menor, vermelho).

### Remoção — o invariante central da Fase 5, PROVADO em produção

Diálogo mostrou o ramo **tranquilizador** (correto: `profileHasContent` = true):
*"Remover o arquivo importado NÃO apaga os dados que ele preencheu no seu perfil —
eles continuam salvos."*

Medição antes → depois da remoção:

| | Antes | Depois |
|---|---|---|
| `saved_resumes` source=imported | 1 | **0** ✔ |
| profile_experiences | 3 | **3** ✔ |
| profile_bullets | 6 | **6** ✔ |
| profile_education | 2 | **2** ✔ |
| profile_skills | 7 | **7** ✔ |
| profile_languages | 3 | **3** ✔ |
| linkedin_url / summary (vieram do CV) | preenchidos | **preenchidos** ✔ |

**Zero linhas perdidas em qualquer tabela `profile_*`.** A promessa da tela
cumpriu-se literalmente — este é o invariante §8.4 "remover fonte não remove os
dados incorporados ao perfil", verificado ponta a ponta.

**Bônus:** o blob do Storage também foi removido (só resta o PDF adaptado). Não
houve blob órfão — melhor que o pior caso admitido pela §8.4.

**Sem beco:** o card voltou ao estado vazio com o convite "Importar currículo", e
**atualizou na hora** (o `removeImportedSource` recarrega o VM).

### Defeitos encontrados neste fluxo

| # | Achado |
|---|---|
| E1 | **Terceira instância do Bloqueador A.** Depois do import, o card "Fonte importada" continua dizendo **"Nenhum currículo importado"** apesar da linha existir no banco. As seções da aba atualizam (Certificações 0→2) porque usam `ProfileEditorViewModel`; o card usa `ProfileViewModel.savedResumes`, que ninguém recarrega. Só aparece depois de um pull-to-refresh na aba **Currículos** (que é quem chama `loadSavedResumes`). O caminho de *remoção* recarrega; o de *import* não |
| E2 | **Skills importadas não são normalizadas pela taxonomia.** "Power BI" veio com `canonical_skill_id`; **"Estatistica", "Gestao de Processos" e "Excel Avancado" vieram SEM**. As digitadas no editor manual (via typeahead) têm todas. Assimetria entre os dois caminhos de escrita |
| E3 | **Duplicata semântica aceita:** o perfil já tinha "Excel" (canônica) e o import adicionou **"Excel Avancado"** como skill separada, classificada como `novo` em vez de possível duplicata. O usuário fica com as duas no CV |
| E4 | O handoff entre abas é abrupto: tocar "Importar currículo" em Perfil → Dados joga o usuário na aba **Assistente**, no meio de uma conversa, sem nenhuma frase explicando o pulo |

> Ressalva honesta sobre E2: o PDF de teste foi gerado em ASCII (sem acentos),
> então parte da falha de match pode ser artefato do arquivo. Mas
> "Excel Avancado" × "Excel" é variante real independente de acento, e a ausência
> de `canonical_skill_id` no caminho de import é observação direta.

## 13. Suíte de testes

Após reverter o override de flag: `flutter test --reporter compact` →
**782 testes, `All tests passed!`** (exit 0). A auditoria de código havia
registrado 1 vermelho em `test/features/trilha/trilha_assist_flag_test.dart`
causado exclusivamente pelo override; com ele removido a suíte volta ao verde.

## 12. Não testado nesta sessão

**Remoção da fonte importada** (exige um CV importado em PDF + a flag ON).

**BLOQUEADOR B em runtime:** não reproduzido. Ele afeta CVs `trail`
("Currículo Stage…"), e o único escritor de `source='trail'` é
`phase_completion_widget.dart:277`, dentro da gamificação sem entry point vivo —
não há como criar um pela UI. O CV `adapted` que gerei abre view-only **por
design** (`_isStructuredAdapted`), o que mostra a *forma* da ausência mas não
prova o defeito. Continua verificado por código + banco, não em runtime.

E dois riscos levantados pela auditoria de código que exigem forçar falha de rede:

- `home_screen.dart:364-372` — "Sim, me candidatei" chama
  `clearPendingApply()` **incondicionalmente** e o erro é engolido em
  `jobs_viewmodel.dart:1613-1615`; `applications_tracker_v1` está **ON/100 em
  prod**.
- `add_edit_experience_modal.dart:150` — `onSave` sem `await` seguido de `pop()`;
  os callbacks nunca lançam (capturam e chamam `_setError`). Mesmo padrão em
  educação, projeto, idioma.
