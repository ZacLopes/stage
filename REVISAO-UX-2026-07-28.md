# Revisão de produto e UX do Stage — 28/07/2026

**Método:** passada cega no simulador iOS (iPhone 17 Pro, iOS 26.5), conta nova criada do zero
(`phone_5511987650143@stage.app`), build `flutter build ios --debug --simulator` da árvore atual
(idêntica em conteúdo a `origin/main` — `git diff --stat HEAD origin/main` = vazio; HEAD é o commit
pré-merge do PR #27).

**Duas passadas:** Passada 1 com as flags de produção; Passada 2 com `trilha_assist_v1` ligada.
**A flag foi ligada às 18:04 UTC e restaurada às 18:07 UTC** (`enabled=false, rollout_pct=0`,
confirmado por `SELECT` posterior). Nenhuma outra flag foi tocada; `trilha_coleta_v1` seguiu ON/100.

**Evidências:** `revisao-ux-2026-07-28-evidencias/` — 41 screenshots + o PDF real exportado
pelo app. ⚠️ **Pasta NÃO versionada** (21 MB de PNG; está no `.gitignore`). Ela existe apenas
na máquina onde a revisão rodou — os nomes de arquivo citados abaixo servem para localizar a
evidência lá, e para quem repetir a revisão saber o que capturar.

**Sobre "afeta usuário hoje":** cada achado abaixo diz se o código já está na build publicada
(**LIVE**) ou se é **PRÉ-RELEASE**.

> ⚠️ **Correção de 31/07/2026 — a build publicada NÃO é a 2.5.0.** Esta linha dizia
> "a build da App Store é `d3ee037` (2.5.0+10, 22/06)". É falso, e eu nunca tinha
> conferido. O lookup público da App Store (`itunes.apple.com/lookup?id=6755893277`)
> devolve **versão 2.4.0, no ar desde 16/06/2026** — commit `37edebc`. A 2.5.0 (+8/+9/+10)
> só existiu em TestFlight e no simulador: 12 usuários no total contra 346 da 2.4.0 em
> `app_cold_start`.
>
> Isso **não muda a gravidade de nenhum achado**, inclusive do P0 do consentimento de IA
> — o buraco existe igual na 2.4.0 (`AiConsentModal` na árvore, zero call sites). Muda o
> artefato citado, não o dano. Mas quem for reproduzir um achado precisa saber contra qual
> build.

---

## 1. Sumário executivo

Se eu tivesse uma semana, faria **três coisas**, nesta ordem:

**1. Fechar o buraco de consentimento de IA (P0-1). Um dia de trabalho, risco jurídico desproporcional.**
O app tem uma tela de consentimento LGPD exemplar — nomeia a OpenAI, lista os dados, exige checkbox.
Ela nunca é mostrada. Eu **recusei explicitamente** o consentimento em Configurações e, em seguida,
o app adaptou meu currículo com IA normalmente, enviando nome, formação e habilidades para a OpenAI.
`ai_consent = false` no banco, antes e depois. O gate existe no código (`resume_viewmodel.dart`),
mas nunca foi ligado ao fluxo novo de "adaptar para a vaga" — nem no `main`, nem na build publicada.
Isso é dano em curso, não pré-release.

**2. Parar de inventar experiência no currículo (P0-2). É o produto que se vende.**
Marquei duas caixinhas num sheet que pergunta "o que você sabe mas não escreveu no CV" — caixinhas
extraídas da própria descrição da vaga. O resumo gerado saiu: *"Estudante de Engenharia de Produção
**com experiência em** elaboração de relatórios e cotações com fornecedores"*. O perfil tem
**zero** experiências. O rodapé da mesma tela afirma "Nenhuma informação foi inventada". O validador
anti-invenção do adapt v2 protege a **lista de skills** (rejeita "skill inventada"), mas não protege
a **prosa do resumo**. Como a receita vem de vender perfis para empresas, um CV que afirma
experiência inexistente é o pior defeito possível: queima o candidato e o Stage junto.

**3. Consertar o corredor "sem skills → com skills", que é exatamente onde o produto sangra.**
O gate de skills é ótimo (honesto, específico, com CTA). Mas o CTA **"Adicionar habilidades ao perfil"
joga a pessoa no topo de Perfil › Dados**, com a seção Habilidades uma tela inteira abaixo, sem
rolagem, sem destaque — e sem nenhum caminho de volta para a vaga que originou tudo. A pessoa que
seguiu o convite do produto é abandonada no meio do caminho. Junto disso: o gate pede "pelo menos 3
habilidades" e o modal seguinte pede "de 6 a 12" com um contador contraditório ("0/12" + "Você pode
adicionar mais 6"). Três números diferentes para a mesma tarefa, em 20 segundos.

**Contexto que muda a leitura do resto:** boa parte dos achados de polimento que encontrei já estava
catalogada no `PLANO-CORRECOES-DEVICE-TEST.md` (26/07) — num **backlog explicitamente fora de escopo**
("§6 — não é escopo desta rodada"). Não são descobertas; são itens conhecidos que vão sair na 2.5.0
do jeito que estão. Marquei cada um. O valor real desta revisão está nos **~20 achados novos**,
concentrados em consentimento, integridade do CV gerado, o explicador de match, o tutorial e
acessibilidade — quatro áreas que nenhum documento do repositório cobre.

---

## 2. Achados

### P0 — quebra o funil / risco de negócio

---

#### P0-1 · O app usa IA sobre dados pessoais mesmo com o consentimento explicitamente RECUSADO

**Status:** LIVE (o bypass existe em `d3ee037` e no `main`) · **NOVO**

**Passos:**
1. Conta nova → Perfil › ⚙️ Configurações → Privacidade → "Consentimento de IA".
2. A tela "Uso de Inteligência Artificial" abre com o checkbox **desmarcado**. Tocar em **"Recusar"**.
3. Voltar: Configurações segue mostrando "Consentimento de IA — **Não autorizado**".
4. Ir em Vagas → tocar no botão ✦ de qualquer vaga → "Adaptar como está".

**Esperado:** o app bloqueia a ação e mostra a tela de consentimento, ou explica que a IA está
indisponível porque o consentimento foi recusado.

**Aconteceu:** a adaptação roda inteira. Aparece "Validando que nada foi inventado…", o CV volta
adaptado por GPT, com resumo em português gerado sobre meus dados. Consulta ao banco imediatamente
depois: `ai_consent = false`, `ai_consent_timestamp = null`.

**Evidências:** `settings-consentimento-ia-nao-autorizado.png`, `ia-roda-apos-recusar-consentimento.png`

**Por que importa:** é tratamento de dado pessoal por terceiro (OpenAI, Inc., nomeada na própria tela)
sem base legal — e contra uma recusa registrada. O app construiu o artefato de conformidade e não o
ligou. Além do risco LGPD, é uma quebra de confiança direta: a tela promete controle que não existe.

**Onde está:** o gate `if (userProfile == null || !userProfile.aiConsent)` existe em
`lib/features/resume/resume_viewmodel.dart:903,947` e `resume_detail_screen.dart:415` (caminhos
legados de currículo). O fluxo novo não tem nenhuma checagem: `grep -rn "aiConsent" lib/features/jobs/`
retorna **vazio**, tanto no `main` quanto em `d3ee037`.

**Sugestão:** aplicar o mesmo gate no ponto de entrada do adapt (`resume_adaptation_sheet.dart`),
mostrando `AiConsentModal` quando `!aiConsent` e abortando se recusado. `AiConsentModal` hoje **não
tem nenhum call site** em `lib/` — é uma tela órfã.

---

#### P0-2 · O resumo gerado afirma experiência profissional que não existe, sob um selo de "nada foi inventado"

**Status:** LIVE · **NOVO**

**Passos:**
1. Conta nova, perfil com **0 experiências** (Perfil › Dados mostra "Experiência profissional (0)").
2. Vagas → ✦ numa vaga → no sheet "Algo que esqueceu de mencionar?", marcar duas caixinhas
   ("Elaboração de relatórios", "Cotações com fornecedores") — itens que vêm da descrição da vaga.
3. "Adaptar com 2 habilidades" → ler o bloco "Resumo Profissional".

**Esperado:** o resumo pode dizer que a pessoa *conhece* ou *tem familiaridade com* aqueles temas.
Nunca que tem **experiência** neles, já que não há uma única experiência cadastrada.

**Aconteceu:** *"Estudante de Engenharia de Produção **com experiência em** elaboração de relatórios e
cotações com fornecedores. Possuo conhecimento em Power BI e Excel…"* — e o rodapé da tela afirma
**"Nenhuma informação foi inventada."** O texto foi para o PDF exportado.

**Evidências:** `adapt-resumo-inventa-experiencia.png` e o PDF real
`cv-adaptado-harvard-ats.pdf` (seção SUMÁRIO).

**Por que importa:** o produto vendido ao lado B2B é o perfil. Um resumo que converte "marquei uma
caixinha" em "tenho experiência" produz shortlist contaminada e expõe o candidato numa entrevista.
E é exatamente a promessa que o app repete em três telas ("A IA não inventa", "Nada será inventado",
"Nenhuma informação foi inventada").

**Nota técnica relevante:** o validador anti-invenção do adapt v2 **funciona** — o
`DEVICE-TEST-IA-PERFIL-2026-07-24.md:265` mostra rejeições por `skill inventada: "Python"`. Ele cobre
a lista de skills; a prosa do resumo passa livre. O buraco é específico e localizado.

**Sugestão:** estender o validador ao campo `summary`: proibir os lemas "experiência em/com",
"atuação em", "vivência em" quando `profile_experiences` estiver vazio; e derivar o verbo da origem
do dado (skill declarada → "conhecimento em"; experiência com bullets → "experiência em").

---

### P1 — atrito forte no funil de ativação

---

#### P1-3 · O CTA "Adicionar habilidades ao perfil" não leva às habilidades, e não há volta para a vaga

**Status:** LIVE · **NOVO** (parente do E4 conhecido, mas outra instância)

**Passos:**
1. Conta nova sem skills → Vagas → ✦ numa vaga.
2. Aparece o gate "Seu perfil ainda não tem habilidades suficientes… pelo menos 3 habilidades".
3. Tocar em **"Adicionar habilidades ao perfil"**.

**Esperado:** cair na seção Habilidades, aberta ou destacada, pronta para digitar.

**Aconteceu:** cai no **topo** de Perfil › Dados, mostrando "Informações pessoais / Experiência
profissional / Educação". "Habilidades (0)" está uma tela inteira abaixo — é preciso rolar e
descobrir sozinho. Depois de salvar as skills, **não há nenhum caminho de volta para a vaga**: a
pessoa precisa lembrar qual era e reencontrá-la no feed.

**Evidências:** `adapt-gate-skills-bom.png` (o gate, que é bom), `perfil-secoes-icones-inconsistentes.png`
(onde a pessoa efetivamente cai, com Habilidades abaixo da dobra).

**Por que importa:** é literalmente o corredor onde o produto sangra — a pessoa **aceitou** preencher
o perfil e o app a perde no caminho. Agrava: as seções vazias usam ícones diferentes (lápis em
Habilidades e Interesses, `+` em Idiomas/Certificações/Projetos), então "como adiciono?" não é óbvio
justamente no momento em que ela foi mandada adicionar (isso é o **D6** conhecido).

**Sugestão:** rolar/expandir a seção alvo no deep-link (a aba já tem as âncoras), e devolver a pessoa
à vaga de origem ao salvar — ou, melhor, abrir o editor de skills como modal por cima da vaga, sem
sair do contexto.

---

#### P1-4 · O Assistente manda tocar numa opção que não existe e engole a mensagem do usuário

**Status:** PRÉ-RELEASE (`trilha_chat_controller.dart` não existe em `d3ee037`) · **NOVO**
· **Passada 1 (flag OFF = configuração de produção)**

**Passos:**
1. Conta nova → aba **Assistente**.
2. No campo "Escreva uma mensagem…", digitar `Quais habilidades faltam no meu perfil?` e enviar.

**Esperado:** ou uma resposta útil, ou uma recusa que aponte para algo clicável e visível.

**Aconteceu:** o bot responde *"Não tenho certeza do que você quis dizer 🤔 **Toca numa opção aí em
cima**."* — mas **não há nenhuma opção acima**. O único controle da tela é o botão "Bora começar",
que está **abaixo** da mensagem. E a pergunta que digitei **não aparece** na conversa: nenhum balão
de usuário é renderizado, então parece que a mensagem sumiu.

**Evidência:** `assistente-flagOFF-opcao-inexistente.png`

**Por que importa:** o slide 2 do carrossel de intro vende exatamente isso — *"Um agente de IA monta
seu currículo — **É só conversar**"*. Na configuração que vai sair, conversar não funciona, e a
instrução de erro aponta para o nada. É a promessa de topo do funil quebrando no primeiro toque.

**Sugestão:** com a flag OFF, ou esconder a barra de chat (deixando só os passos guiados), ou trocar a
copy para apontar o controle que existe ("Toca em **Bora começar** logo abaixo"). E ecoar sempre a
mensagem do usuário como balão — vale para os dois modos.

---

#### P1-5 · O explicador de match se contradiz na mesma frase e pune vaga remota por cidade

**Status:** LIVE · **NOVO**

**Passos:**
1. Conta nova com "Remoto/Híbrido/Presencial" marcados e Curitiba como cidade.
2. Vagas → tocar no card para abrir o detalhe → ler o bloco "Match parcial".

**Esperado:** vaga remota + preferência por remoto = ponto positivo. E, como a própria tela de filtros
promete "**Remoto sempre passa**", uma vaga remota não deveria perder ponto por cidade.

**Aconteceu:** duas linhas erradas, ambas marcadas com ⊖ (negativo):
- *"**Modelo** — Você prefere remoto, **mas** a vaga é remoto."* — a frase se contradiz sozinha e o
  acerto é contado como falha.
- *"**Localização** — Eusébio, CE não está entre suas cidades preferidas"* — enquanto os blocos
  logo abaixo dizem **Local: Remoto** e **Modelo: Remoto**.

**Evidência:** `vaga-detalhe-match-contraditorio.png`

**Por que importa:** o match score é o coração do feed e o argumento do produto. Um explicador que se
contradiz destrói a credibilidade do número inteiro — e ensina a pessoa a ignorá-lo. Aparece em toda
vaga remota fora da cidade do usuário, o que no Brasil é a maioria do inventário remoto.

**Sugestão:** tratar `remoto` como short-circuit: se a vaga é remota e a pessoa aceita remoto, emitir
✓ em Modelo e **omitir** (não penalizar) a linha de Localização, alinhando com a regra já anunciada
nos filtros.

---

#### P1-6 · Abandonar o onboarding e voltar faz a pessoa reresponder uma pergunta já salva

**Status:** LIVE · **NOVO**

**Passos:**
1. Criar conta → escolher uma das duas portas → responder "Como nos conheceu?" (escolhi "Outro").
2. Seguir até a pergunta de faculdade e **matar o app** (ou reiniciar o device).
3. Reabrir o app.

**Esperado:** voltar de onde parou, ou pelo menos com tudo que foi respondido já marcado.

**Aconteceu:** o wizard recomeça na tela das duas portas. Os campos de **texto** vêm preenchidos
(nome, sobrenome, e-mail — os dados estão salvos: verifiquei `profile_personal` no banco). Mas a
pergunta **"Como nos conheceu?"** volta com **nenhuma opção selecionada** e o "Continuar" desabilitado,
apesar de `attribution_source = 'Outro'` estar gravado. A tela de gênero, em contraste, **restaura**
a seleção corretamente — então é um defeito isolado dessa etapa.

**Por que importa:** abandono no meio do onboarding é o comportamento mais comum do funil. Fazer a
pessoa reresponder algo que ela já respondeu (e que o app já sabe) é atrito gratuito no ponto de maior
desistência. E como a pergunta serve ao negócio (atribuição), não ao usuário, o custo psicológico é
maior ainda.

**Sugestão:** hidratar a seleção a partir de `profile_personal.attribution_source` no `initState` da
`attribution_screen.dart`, como as outras telas de escolha já fazem.

---

#### P1-7 · "Usar localização atual" gira para sempre: sem timeout, sem erro, sem rótulo

**Status:** LIVE · **NOVO**

**Passos:**
1. Onboarding → tela "Onde você mora?" → tocar em **"Usar localização atual"**.
2. Conceder a permissão. (No simulador sem localização definida — equivalente a um device que não
   consegue obter fix.)

**Esperado:** um timeout com mensagem honesta ("não consegui pegar sua localização, digita seu CEP").

**Aconteceu:** um spinner minúsculo dentro de uma caixinha branca **sem rótulo**, encostado na margem
direita, desconectado de qualquer texto — e **girando indefinidamente**. Deixei mais de dois minutos:
nunca resolve, nunca erra, nunca some.

**Evidências:** `onb-local-spinner-orfao.png`, `onb-cep-ok-spinner-infinito.png`

**Por que importa:** não bloqueia (dá para digitar o CEP ao lado, e isso funciona muito bem), mas é
exatamente o tipo de tela ambígua que faz a pessoa achar que o app travou e fechar. Acontece em
qualquer device sem fix de GPS — indoor, modo econômico, permissão parcial.

**Sugestão:** `timeout` de ~8s no `getCurrentPosition`, caindo em snackbar + foco no campo de CEP; e
dar rótulo/`Semantics` ao botão, que hoje é um quadrado sem nome.

---

#### P1-8 · O onboarding pergunta o momento de carreira e o perfil diz "Não definido"

**Status:** LIVE · **NOVO** (o `PLANO-CORRECOES` §1.6 registra o campo como "exposto com estado vazio
honesto" — o que não está documentado é que o onboarding **pergunta** e não grava)

**Passos:**
1. Onboarding → "Em que momento você está agora?" → escolher **"Estou na faculdade"** → completar.
2. Perfil › **Objetivos** → rolar até "Momento de carreira".

**Esperado:** "Estou na faculdade" (ou equivalente).

**Aconteceu:** **"Não definido"**. Confirmei no banco:
`profile_job_preferences.experience_level = []` (array vazio). A resposta alimentou o sub-formulário
de educação (criou `profile_education` com semestre e situação corretos) mas nunca chegou ao campo de
senioridade.

**Por que importa:** senioridade é filtro de shortlist B2B. O dado foi coletado do usuário, ele viu a
si mesmo respondendo, e o produto o descarta — depois mostra um vazio que convida a refazer o trabalho.
Perda silenciosa de dado com valor comercial direto.

**Sugestão:** mapear a resposta da `career_moment` para `experience_level` no mesmo write do
onboarding.

---

#### P1-9 · "Continuar" da tela de duas portas é um botão morto

**Status:** LIVE · **NOVO**

**Passos:**
1. Criar conta. Primeira tela pós-cadastro: "Vamos construir seu perfil".
2. O card "Usar meu CV para preencher o perfil" já aparece com anel de seleção ciano.
3. Tocar em **"Continuar"** (embaixo).

**Esperado:** avançar com a opção selecionada.

**Aconteceu:** **nada**. Sem navegação, sem toast, sem shake. Só avança tocando **no card**. O botão
fica permanentemente no estado desabilitado (azul claro) mesmo com um card visualmente selecionado.

**Evidência:** `two-doors.png`

**Por que importa:** é a **primeira tela depois de criar a conta** — 100% dos cadastros passam por ela,
e "Continuar" é o alvo mais óbvio da tela. Quem toca ali e não vê reação conclui que o app quebrou,
no primeiro segundo de uso.

**Sugestão:** ou remover o botão (os cards já navegam), ou torná-lo o caminho real e tirar o anel de
seleção falso dos cards.

---

#### P1-10 · Com fonte grande do sistema, o card do feed fica inutilizável

**Status:** LIVE · **NOVO** (nenhum documento do repositório trata acessibilidade)

**Passos:**
1. `xcrun simctl ui <udid> content_size accessibility-extra-large` (equivale a Ajustes → Tela e Brilho
   → Tamanho do Texto no fim da faixa de acessibilidade).
2. Abrir o app na aba Vagas.

**Esperado:** texto maior, layout reflui, conteúdo continua legível.

**Aconteceu:** o card principal quebra:
- o nome da empresa transborda e colide com o anel de match ("BOTTOM OVERFLOWED BY 106 PIXELS");
- o anel mostra "**Alt**" no lugar de "Alta" e transborda 49px;
- **"SOBRE A VAGA" fica completamente vazia** — a descrição da vaga some do card;
- no sheet de CV adaptado, o título estoura 131px para a direita.

**Evidências:** `a11y-feed-card-quebrado.png`, `a11y-overflow-fonte-grande.png`

**Honestidade sobre a evidência:** as tarjas amarelas/pretas de overflow são indicadores do **debug
build**. Em release elas não aparecem — mas o layout quebra igual, com o texto simplesmente **cortado
em silêncio**. O defeito é o mesmo; só a sinalização é de debug.

**Por que importa:** é a tela central do app, e a descrição da vaga desaparece por inteiro. Fonte
grande não é um caso exótico: é o default de muita gente com baixa visão, e o app não tem nenhum
outro recurso de acessibilidade compensando.

**Sugestão:** trocar os `Row`/altura fixa do cabeçalho do card por `Flexible`+`FittedBox`, e limitar
`textScaleFactor` do anel de match; no mínimo garantir que o corpo da descrição nunca perca espaço
para o cabeçalho.

---

#### P1-11 · A palavra "Major" vaza para dentro do currículo entregue ao recrutador

**Status:** LIVE · **NOVO**

**Passos:**
1. Onboarding com curso "Engenharia de Producao".
2. Adaptar um CV para uma vaga → "Revisar e baixar" → abrir a prévia e o PDF.

**Esperado:** "Graduação · Engenharia de Produção".

**Aconteceu:** **"Graduação · Engenharia de Producao Major"** — o sufixo interno em inglês vai para a
tela, para o PDF e para os cinco templates (confirmei em Harvard ATS e One-Page Compact).

**Evidências:** `cv-preview-major-vazado.png`, `template-onepage-titulo-duplicado.png`, e o PDF
`cv-adaptado-harvard-ats.pdf` (seção EDUCAÇÃO).

**Causa (verificada no código, depois de ver na tela):**
`lib/features/jobs/models/adapted_resume.dart:385` —
```dart
final majorWord = isEn ? 'Major' : 'Major';
```
Um ternário com **os dois ramos iguais**: o caminho pt-BR nunca foi traduzido. O mesmo trecho existe
em `d3ee037`. Note que o time já resolveu isso no **outro** caminho — `profile_resume_mapper.dart:20`
documenta explicitamente "nunca injeta os sufixos artificiais ingleses 'Major'/'Minor'". Consertaram
o currículo geral e esqueceram o adaptado.

**Por que importa:** é o documento que a pessoa manda para a empresa, num app pt-BR only. Um termo
em inglês solto no meio da formação denuncia geração automática e deprecia o candidato — e o
candidato é o produto.

**Sugestão:** `isEn ? 'Major' : ''` (com trim do espaço) ou remover o sufixo do caminho pt-BR, como já
foi feito no mapper.

---

### P2 — problema real, fora do caminho crítico

---

#### P2-12 · O mesmo estado tem três nomes na mesma tela (e um quarto no tutorial)

**Status:** LIVE · **NOVO** (o C2 conhecido é sobre o empty-state, não sobre a ação)

Na aba Candidaturas, para a **mesma** transição:
- cabeçalho: "1 **aplicada** de 1 salva"
- pílula de segmento: "**Enviadas**"
- chip de status do card: "**Enviada**"
- card de ajuda azul, no topo da mesma tela: marque como "**Já apliquei**"
- menu "…" do card: "Marcar como **aplicada**"
- tutorial (passo 4/7): marque como "**aplicada**"

**Evidências:** `candidaturas-aplicada-vs-enviada.png`, `tutorial-4-aplicada-inexistente.png`

**Por que importa:** o card de ajuda instrui a procurar "Já apliquei" e esse texto não existe em lugar
nenhum do app. Vocabulário instável na aba que existe justamente para organizar.
**Sugestão:** escolher um verbo ("Já me candidatei") e usá-lo no menu, no chip, no card de ajuda e no
tutorial.

---

#### P2-13 · O match score aparece em três formatos diferentes no mesmo fluxo

**Status:** LIVE · **NOVO**

Card do feed: **"Alta match"** (rótulo qualitativo) → detalhe da vaga: **"50%"** → resultado do
adapt: **"75/100"**. Três escalas para o mesmo conceito, em três toques.

Pior: o **tutorial (2/7)** diz *"O **número** no canto do card é o match com seu perfil"* — e o card
não mostra número nenhum, mostra a palavra "Média".

**Evidências:** `tutorial-2-numero-vs-media.png`, `vaga-detalhe-match-contraditorio.png` (50%),
`adapt-resumo-inventa-experiencia.png` (75/100)

**Nota:** "Alta match" também não é português idiomático (ordem invertida do inglês); "Match alto"
ou "Compatibilidade alta" resolveria.

**Sugestão:** um formato só na superfície do usuário; se o card usa rótulo, o tutorial precisa dizer
"rótulo", não "número".

---

#### P2-14 · A regra de senha é anunciada e não é aplicada em lugar nenhum

**Status:** LIVE · **NOVO**

**Passos:** cadastro por telefone → campo Senha diz *"Mínimo 8 caracteres, uma letra e um número"* →
digitar `abcdefgh` (8 letras, **nenhum número**).

**Aconteceu:** o botão "Continuar" **habilita** e a **conta é criada**. Nem o cliente nem o servidor
recusam. Foi assim que criei a conta desta revisão.

**Por que importa:** contraste gritante com o campo de e-mail logo adiante, que faz validação inline
exemplar (borda vermelha + mensagem + botão travado). O app sabe validar; aqui só não valida.
**Sugestão:** aplicar a regra anunciada, ou anunciar a regra real.

---

#### P2-15 · Termos e Política de Privacidade só existem no caminho do telefone e somem depois

**Status:** LIVE · **NOVO**

- A tela de criação de conta **não** mostra nenhum aviso de Termos/Privacidade para
  **"Continuar com Google"** nem **"Continuar com Apple"** — só o caminho do telefone tem o texto
  "Ao continuar, você concorda com nossos Termos de Uso e Política de Privacidade".
- Depois do cadastro, **Configurações não tem link de Termos nem de Privacidade**. A Política de
  Privacidade existe, mas enterrada dentro de Privacidade → "Consentimento de IA" — ou seja, só
  alcançável passando por uma tela de consentimento que exige responder para sair.

**Evidência:** `auth-sem-termos.png` (tela de auth, sem scroll, sem aviso)

**Por que importa:** transparência LGPD e diretriz de App Store; e a pessoa não consegue reler o que
aceitou. **Sugestão:** aviso único acima dos três botões de auth + item "Termos e Privacidade" em
Configurações.

---

#### P2-16 · A tela de consentimento de IA não tem saída

**Status:** LIVE · **NOVO**

Aberta a partir de Configurações, a tela "Uso de Inteligência Artificial" **não tem botão de voltar**
e **não aceita o gesto de swipe-back** (testei). Só sai por "Recusar" ou "Aceitar e continuar" — ou
seja, quem entrou só para ler é obrigado a emitir uma declaração de vontade.

**Sugestão:** botão de fechar quando a tela é aberta por consulta (e não como gate).

---

#### P2-17 · Requisitos e benefícios da vaga saem com marcador duplo e frases soltas viram requisito

**Status:** LIVE · **NOVO**

O texto vindo do ATS é quebrado por linha e cada linha ganha um ✓/•, **sem remover o marcador
original**. Resultado real, na tela:
- `✓ - Lembre-se que também podemos te fazer uma ligação…` (hífen do texto original preservado)
- `✓ • Plano de Saúde;` (bullet original + bullet do app, com o `;` do ATS)
- `✓ Desejamos uma ótima seleção para você!` — uma despedida renderizada como **requisito**.

Também: a descrição preserva blocos enormes de linhas em branco do ATS, criando vãos de várias
centenas de pixels.

**Evidências:** `vaga-requisitos-parse-ruim.png`, `vaga-beneficios-bullet-duplicado.png`

**Por que importa:** é o conteúdo que a pessoa lê para decidir se se candidata. Parece descuidado e
polui a leitura em toda vaga do Gupy.
**Sugestão:** normalizar (`^[-•*–]\s*`, colapsar `\n{3,}`, trim de `;`) e descartar linhas sem forma
de item.

---

#### P2-18 · O nome da empresa vem poluído e quebra as frases do app

**Status:** LIVE · **NOVO**

O campo empresa desta vaga é literalmente **"Estágio M. Dias Branco"**. Consequências visíveis:
- no card, sob um selo **ESTÁGIO**, lê-se "ESTÁGIO / Estágio M. Dias Bran…" (redundante e truncado);
- no detalhe, o template gera **"Sobre a Estágio M. Dias Branco"** — agramatical.

**Evidência:** `vaga-detalhe-match-contraditorio.png` (cabeçalho)

**Sugestão:** limpar prefixos de tipo de vaga no ingest (`^(Estágio|Vaga|Programa)\s+`) e usar
"Sobre a empresa" como cabeçalho fixo, sem interpolar o nome.

---

#### P2-19 · O sheet de skills extras reoferece o que a pessoa acabou de cadastrar

**Status:** LIVE · **CONHECIDO** (D2 no `PLANO-CORRECOES` §6.2, com causa-raiz mapeada em
`extract-job-skills`) — mantido aqui porque não foi corrigido e o usuário encosta nele.

Cinco minutos depois de eu cadastrar Excel, Power BI e Python, o sheet "Marque o que você tem **mas
não escreveu no CV**" me ofereceu **Excel, Power BI e Python**.

**Evidência:** `adapt-skills-confirm-repete-declaradas.png`

---

#### P2-20 · A adição manual de candidatura oferece 4 status; a edição oferece 7

**Status:** LIVE · **NOVO**

No formulário "Adicionar candidatura": Enviada, Em análise, Entrevista, Proposta.
No menu de status de um card existente: Em análise, Pré-selecionado, Entrevista, Proposta,
Contratado, Recusada, Retirada.

Não dá para registrar uma candidatura antiga já recusada — é preciso criar como "Enviada" e editar
depois. **Sugestão:** mesmo conjunto nos dois lugares.

---

#### P2-21 · Os status misturam gênero gramatical (e um deles misgenera a usuária)

**Status:** LIVE · **NOVO**

Na mesma lista: "Pré-selecionad**o**" e "Contratad**o**" (concordando com o *candidato*) convivem com
"Enviad**a**", "Recusad**a**", "Retirad**a**" (concordando com a *candidatura*).

**Evidência:** `status-genero-misto.png`

Para uma conta cujo gênero informado é feminino, "Contratado" aparece assim mesmo.
**Sugestão:** padronizar no sujeito "candidatura" (Enviada, Pré-selecionada, Em entrevista, Com
proposta, Aprovada, Recusada, Retirada) — resolve concordância e neutralidade de uma vez.

---

#### P2-22 · A marca troca de gênero: "o Stage" e "a Stage"

**Status:** LIVE · **NOVO**

- Permissão de localização: "**O** Stage usa sua localização…"
- Formulário de candidatura manual: "Pra acompanhar o que aconteceu fora **da** Stage."

**Sugestão:** fixar "o Stage" no guia de copy.

---

#### P2-23 · "ou pule se topa qualquer lugar" — mas o "pular" está escondido

**Status:** LIVE · **NOVO**

Na tela "Onde você quer trabalhar?", o texto diz *"Adicione cidades específicas — **ou pule** se topa
qualquer lugar."* Só que o app **já adicionou automaticamente** a cidade de residência, e o link
"Pular etapa" **só aparece quando a lista está vazia**. Para "pular", a pessoa precisa primeiro
deletar a cidade que ela não colocou.

**Evidência:** `onb-pular-etapa-so-com-lista-vazia.png` (link visível só após remover Curitiba)

**Por que importa:** todo mundo sai do onboarding com um filtro geográfico que não escolheu, o que
encolhe o feed silenciosamente — justo o que não se quer num inventário pequeno.
**Sugestão:** manter "Pular etapa" sempre visível, e marcar a cidade automática como sugestão
removível ("adicionamos Curitiba porque você mora lá").

---

#### P2-24 · Dois modais empilhados: a confirmação fica ilegível

**Status:** LIVE · **NOVO**

**(a)** Ao baixar o PDF, o diálogo "CV salvo! Sua versão adaptada para … ficou em Perfil →
Currículos" é imediatamente **coberto pelo share sheet do iOS**, cortado no meio da frase — a pessoa
não chega a ler onde o CV foi parar. (`pdf-modais-empilhados.png`)

**(b)** Ao salvar a primeira vaga, o prompt de **ATT** aparece **por cima** do sheet de comemoração
"Você salvou sua primeira vaga!". (`att-sobre-sheet-de-sucesso.png`)

O timing do ATT (após engajamento) é uma boa decisão; o problema é só a sobreposição.
**Sugestão:** encadear — mostrar o share sheet ao fechar o diálogo, e o ATT ao fechar a comemoração.

---

#### P2-25 · Telefone sem formatação no currículo

**Status:** LIVE · **NOVO**

O app formata o telefone como `(11) 98765-0143` em toda a interface, mas o CV — tela e PDF — imprime
`Telefone: +55 11987650143`. Num documento para recrutador, destoa. (Ver `cv-adaptado-harvard-ats.pdf`.)

---

#### P2-26 · No modelo One-Page Compact o título da seção sai duplicado

**Status:** LIVE · **NOVO**

Trocando o modelo para **One-Page Compact**, a seção renderiza o cabeçalho "habilidades técnicas"
(minúsculo, roxo) e, **na linha seguinte**, "HABILIDADES TÉCNICAS" em caixa alta antes dos itens.
O mesmo rótulo, duas vezes seguidas. (No Harvard ATS não acontece porque o cabeçalho da seção tem
outro texto.) **Evidência:** `template-onepage-titulo-duplicado.png`

---

#### P2-27 · Os modelos de currículo são descritos em jargão que o público não fala

**Status:** LIVE · **NOVO**

Num app pt-BR only para estagiários: *"ideal pra **IB/Consulting/Corporate**"*, *"Tech/dev,
**FAANG-friendly**"*, *"**Banking/MBA**, conservador"*, *"Estudante **early-career**"*, *"**accent**
azul cobalt"*. Três dos cinco modelos são descritos para um público (IB, MBA, FAANG) que não é o
do produto. **Evidência:** `templates-jargao-ib-faang.png`

Na mesma família, a tela de carregamento do adapt diz *"Reformulando **bullets** pro **fit**…"* —
dois termos internos vazando para o usuário. (`adapt-loading-jargao-bullets-fit.png`)

---

#### P2-28 · O contador de habilidades se contradiz, e o número exigido muda entre telas

**Status:** LIVE · **CONHECIDO** (D5 no backlog `PLANO-CORRECOES` §6.1) — mantido por não estar
corrigido e por combinar com um segundo problema **não** catalogado:

- O modal mostra **"0/12"** ao lado de **"Você pode adicionar mais 6."** (`skills-0de12-mais6.png`)
  — um número corre para o mínimo recomendado, o outro para o teto, sem dizer isso.
- E o **gate que trouxe a pessoa até ali pedia "pelo menos 3 habilidades"**, enquanto este modal pede
  "de 6 a 12". Três números para a mesma tarefa em menos de um minuto (essa parte é nova).

---

#### P2-29 · Todos os currículos adaptados se chamam igual

**Status:** LIVE · **CONHECIDO** (D3 no backlog §6.2)

Na aba Currículos, o card sai como **"CV adaptado - Est…"**. Como a feature existe para gerar **um CV
por vaga**, a lista tende a ficar com vários itens visualmente idênticos. Some-se a isso a miniatura,
que é um **esqueleto cinza genérico** e parece carregamento eterno.
**Evidência:** `curriculos-thumb-placeholder-titulo-truncado.png`

---

### P3 — polimento

- **P3-30 · O botão da tela final do onboarding está cortado.** Em "Perfil criado!", o CTA
  "Completar com a IA" começa em **x=0** (colado/cortado na borda esquerda) e sobra margem à direita —
  não é só falta de margem, está deslocado. Todas as outras telas do wizard usam ~21pt dos dois lados.
  `onb-perfil-criado-botao-sem-margem.png` · **CONHECIDO** (device-test §5: "o único sangrado até as
  bordas") e **não corrigido**.
- **P3-31 · A régua de segmentos de Candidaturas corta "Finaliza…"** sem fade nem indício de rolagem.
  `candidaturas-1-pendentes-chip-cortado.png` · **CONHECIDO** (C4, backlog §6.1), não corrigido.
- **P3-32 · "1 Pendentes"** — singular com plural. Mesmo print acima. **NOVO**.
- **P3-33 · "Baixar PDF" e "Entendi" em ciano** enquanto o primário do app é o azul Stage.
  **CONHECIDO** (D4, backlog §6.1), não corrigido.
- **P3-34 · `+` vs lápis em seções vazias do perfil.** **CONHECIDO** (D6, backlog §6.1), não corrigido.
- **P3-35 · "Continuar" habilita com 1 caractere** em nome e sobrenome. **CONHECIDO** (SEC.5, backlog),
  não corrigido.
- **P3-36 · Slider de semestre mostra "1º semestre" duas vezes** no estado inicial (rótulo mínimo +
  bolha do valor) — que é o estado que todo mundo vê ao chegar. `onb-semestre-slider-duplicado.png` ·
  **NOVO**.
- **P3-37 · A permissão de localização cita um botão que não existe:** o texto do iOS diz *"quando
  você toca em '**Usar minha localização**'"*, e o botão na tela se chama "**Usar localização atual**".
  **NOVO**.
- **P3-38 · O "desfazer" do feed não faz nada no primeiro card** (nada a desfazer) e continua com
  aparência de habilitado, sem feedback. **NOVO**. *(Ressalva: snackbars duram ~4s; posso ter perdido
  um. O que afirmo é que o botão parece ativo e nada visível acontece.)*
- **P3-39 · Filtros:** "Match score mínimo" traz o subtítulo *"Só mostra vagas com afinidade alta com
  você"* mesmo com o controle em **"Qualquer"** — descreve um filtro que não está aplicado. E a mesma
  folha mistura "2/5 selecionadas" com "3 selecionado(s)". `filtros-match-score-off.png` · **NOVO**.
- **P3-40 · Mistura de 2ª pessoa:** "**Toca** numa opção", "**Toca** nas que combinam" (tu) convivem
  com "**Escolha** ao menos uma", "**Informe** abaixo", "**Deslize, aplique**" (você). **NOVO**.
- **P3-41 · Quatro padrões de seleção no mesmo wizard:** check sem controle (origem, gênero), rádio
  redondo (momento), checkbox quadrado (modelo de trabalho), chips (áreas). **NOVO**.
- **P3-42 · O DDI é caixa de texto livre no cadastro** (rejeita letras, ok) e vira **seletor com
  bandeira** duas telas depois, para o mesmo dado. **NOVO**.
- **P3-43 · Educação repete "Em andamento"** como subtítulo e de novo em "Situação: Faculdade em
  andamento"; e "Previsão de conclusão: Não informada" nunca foi perguntada no onboarding — dado que
  recrutador de estágio pede. **NOVO**.
- **P3-44 · O sublinhado amarelo do diálogo "CV salvo!" corta os descendentes** (g, p, ç) das
  palavras. `cv-salvo-sublinhado-amarelo.png` · **NOVO**.
- **P3-45 · Os botões do sheet "primeira vaga salva" ficam fora do card branco**, apoiados sobre o
  card da vaga que está atrás — o agrupamento visual quebra.
  `primeira-vaga-botoes-fora-do-card.png` · **NOVO**.

---

## 3. Opinião de design (não são defeitos)

1. **O carrossel de intro promete o que o app não entrega hoje.** "Sem formulários intermináveis.
   Deslize, aplique e pronto" antecede um wizard de 12 telas + tutorial de 7 passos, e a candidatura
   acontece **fora** do app. "Um agente de IA monta seu currículo — é só conversar" descreve a
   Passada 2, não a configuração que vai sair. Eu alinharia a promessa ao produto real, ou ligaria a
   flag antes de prometer.
2. **O detalhe da vaga não tem ação.** A tela de maior intenção termina em metadados; para salvar ou
   aplicar é preciso fechar o sheet. **Isto é deliberado** — o `CLAUDE.md` registra "um único call
   site de apply… o `JobDetailsSheet` não tem botão de aplicar". Não reporto como defeito, mas
   continuo achando que é onde um "Salvar" renderia mais.
3. **O ✦ é o botão mais proeminente do feed** (maior, azul cheio, central) sendo a ação mais cara e
   menos frequente. Salvar/rejeitar é o que se faz dezenas de vezes por sessão.
4. **A pergunta de atribuição ("Como nos conheceu?") é a primeira coisa depois do cadastro.** Serve à
   empresa, não à pessoa, e ocupa o momento de maior fragilidade do funil. Eu a moveria para depois
   da primeira vaga salva.
5. **A barra de completude em verde a 45%** sinaliza "está bom" quando o perfil está fraco — e verde
   é `success` no design system. Âmbar até ~70% comunicaria melhor. *(Já registrado no device-test.)*
6. **Pin de localização vermelho sobre halo verde** destoa do DS (vermelho = erro).
   *(Já registrado no device-test.)*
7. **O ícone do gate de skills é um alerta vermelho** para um estado que não é erro — é "falta um
   passo". Âmbar seria mais acolhedor no exato ponto em que se pede esforço.
8. **A aba Currículos e a prévia usam ciano como primário**, o resto do app usa azul Stage. Mesmo
   sendo D4 um item conhecido de 1 linha, vale tratar como decisão de sistema, não como um botão.
9. **Chamar o Assistente de "copiloto de carreira"** (saudação, flag ON) e de "agente de IA" (intro)
   contraria o **contrato de linguagem do §2 do handoff**, que fixa **"Assistente"** como termo único.
   Da mesma família: "Skills" no tracker de etapas e "Skills Técnicas" no resultado do adapt, onde o
   perfil diz "Habilidades".

---

## 4. O que está bom (não mexer)

- **Validação inline do e-mail** no onboarding: borda vermelha, mensagem específica, botão travado,
  destrava ao corrigir. É o padrão que o resto do app deveria seguir.
- **CEP → cidade.** Digitei `80230010` e apareceu "Curitiba, PR, Brasil" instantaneamente. Rápido,
  claro, e salva a etapa mesmo com o GPS falhando.
- **O gate de skills do adapt.** Diz o que falta, por que importa, quantas skills, e oferece um botão
  para resolver. É honesto e não é beco — só erra o destino (P1-3). O conteúdo da mensagem está certo.
- **O sheet de skills extras e o rodapé anti-invenção.** "A IA não inventa. Diga o que sabe mas ficou
  de fora do CV" é a moldura correta. E o botão que muda para "Adaptar com 2 habilidades" conforme a
  seleção é um detalhe muito bem feito.
- **O diff explicável do adapt** (ANTES riscado / DEPOIS, "2 ajustes aplicados"). Raro e valioso:
  a pessoa vê exatamente o que a IA mexeu.
- **A máquina de estados de Candidaturas.** Mudar status funciona, o contador atualiza, a aba
  **acompanha o item** e o snackbar confirma ("Candidatura adicionada · Enviadas"). O selo
  "Adicionada por você" é claro. **Isto melhorou desde o device-test de 24/07** — ver §6.
- **Validação do formulário de candidatura manual:** submeter vazio produz erros inline precisos.
- **A tela de consentimento de IA, como artefato.** Nomeia a OpenAI, lista os dados, separa
  finalidade, linka as duas políticas, exige checkbox e mantém o botão desabilitado até marcar. É
  material de referência — o problema é só que ninguém a chama (P0-1).
- **Progressive disclosure no onboarding:** escolher "Estou na faculdade" abre faculdade/curso/semestre
  ali mesmo, com o Continuar travado até completar.
- **A folha de filtros:** deixa explícito que são "só desta busca", conta o que está ativo e explica
  "Remoto sempre passa".
- **A taxonomia inclusiva de experiência (flag ON):** "vale estágio, voluntariado, monitoria, atlética,
  freela, empresa da família", com saída honesta "Ainda não tenho experiência". É a melhor copy do app
  e ataca de frente o problema do perfil vazio.
- **Troca de modelo de currículo:** cinco modelos com miniaturas reais, regenera e persiste.
- **Timing do ATT** (depois do primeiro engajamento, não na abertura).

---

## 5. Mapa de cobertura

**Percorrido:** carrossel de intro (3 slides) · tela de auth · cadastro por telefone (incl. validações
de DDI, telefone, senha) · onboarding completo, 12 etapas · retomada do onboarding após kill do app ·
tela "Perfil criado!" · prompt de push · tutorial completo (7/7) · feed de vagas (modo Cards) ·
folha de filtros (rolagem completa) · detalhe da vaga (rolagem completa) · gate de skills · editor de
habilidades (typeahead, 6 skills) · sheet de skills extras · adapt de CV ponta a ponta (2×) ·
prévia Adaptado/Original · troca de modelo (Harvard ATS → One-Page Compact) · **export e abertura do
PDF real** · aba Currículos + menu do card + visualizador · salvar vaga · aba Candidaturas (4
segmentos, menu "…", troca de status, adição manual, validação) · Perfil › Dados · Perfil › Objetivos
(rolagem completa) · Configurações (rolagem completa) · tela de consentimento de IA · aba Assistente
com a flag **OFF** e com a flag **ON** · teste de fonte grande (`accessibility-extra-large`).

**Não alcançado — e por quê:**
- **Importar um CV (porta "Usar meu CV")** e, por consequência, o card **"Fonte importada"**, o fluxo
  de conflitos e a remoção de fonte. Escolhi a porta "Preencher passo a passo" no primeiro toque e
  não tinha um PDF de currículo plausível para injetar no simulador sem inventar dados de pessoa real.
  **É a maior lacuna desta revisão**, e é justamente onde o device-test de 24/07 achou o E1.
- **Modo lista do feed** (só usei Cards) e **exaustão do feed** — não swipei vagas suficientes.
- **Currículo geral persistido** (Passada 2) — depende do import/auto-save; não exercitei o caminho
  que dispara o falso positivo esperado das migrations faltantes.
- **Editar/remover** itens já existentes de experiência, educação, idiomas, projetos — só criei.
- **"Aplicar no site"** e o prompt de retorno ("Sim, me candidatei") — não abri o navegador externo.
- **Login de conta existente / recuperação de senha** — só criei conta. Registro que **não encontrei
  nenhum "Esqueci minha senha"**; o `PLANO-CORRECOES` (B5) confirma que **não existe tela de login**
  e que toda entrada passa por tentar cadastro. Não reproduzi, então não reporto como achado.
- **VoiceOver / contraste medido** — testei só o eixo de tamanho de fonte.
- **Notificações push reais** e o digest.

**Ressalvas de método:**
- Recusei o ATT (opção mais preservadora de privacidade), o que pode alterar telemetria.
- O simulador estava com teclado **en-US e autocorreção ligada** no início. Isso corrompeu
  entradas ("Ribeiro"→"Roberto", "Universidade"→"University") e me levou a **suspeitar de um bug de
  capitalização no app**. Investiguei, provei que era artefato do ambiente (teste com palavras sem
  dicionário), desliguei a autocorreção e refiz os dados. **Não reportei nada disso.**
- A seção **"[DEV] Ferramentas"** aparece em Configurações neste build. Verifiquei no código:
  `if (kDebugMode || _devmodeUnlocked)` — **ausente em release**. Descartado como falso positivo do
  meu build de debug.

**Dados de teste:** criei a conta `f8de91d4-…` e, dentro dela, 1 vaga salva (M. Dias Branco), 1
candidatura manual ("Empresa Teste QA"), 6 habilidades e 2 currículos adaptados. Nada foi apagado —
sinalizo caso queiram limpar. Nenhum dado de terceiros foi consultado ou reproduzido.

---

## 6. Reconciliação (Etapa B)

Li `HANDOFF-CLAUDE-CODE-IA-PERFIL.md` (§2 contrato de linguagem), `DEVICE-TEST-IA-PERFIL-2026-07-24.md`,
`PLANO-CORRECOES-DEVICE-TEST.md` e `CLAUDE.md` **depois** de fechar a lista.

### 6.1 Achados NOVOS (não aparecem em nenhum dos documentos)

P0-1 (consentimento de IA não aplicado) · P0-2 (resumo inventa experiência) · P1-3 (deep-link de
skills erra o destino e não volta) · P1-4 (Assistente aponta opção inexistente, flag OFF) ·
P1-5 (explicador de match contraditório) · P1-6 (atribuição não restaura) · P1-7 (spinner de
localização infinito) · P1-8 (momento de carreira coletado e descartado) · P1-9 ("Continuar" morto) ·
P1-10 (quebra com fonte grande) · P1-11 ("Major" no CV) · P2-12 (vocabulário de "aplicada") ·
P2-13 (três formatos de match + tutorial errado) · P2-14 (senha) · P2-15 (Termos/Privacidade) ·
P2-16 (consentimento sem saída) · P2-17 (parse de requisitos) · P2-18 (nome da empresa poluído) ·
P2-20 (status 4 vs 7) · P2-21 (gênero dos status) · P2-22 ("o/a Stage") · P2-23 ("pule" escondido) ·
P2-24 (modais empilhados) · P2-25 (telefone no CV) · P2-26 (título duplicado no One-Page) ·
P2-27 (jargão dos modelos) · P3-32, P3-36 a P3-45.

**Destaque:** **acessibilidade não é mencionada em nenhum dos quatro documentos.** P1-10 é a primeira
medição desse eixo.

### 6.2 Achados CONHECIDOS que continuam valendo (não corrigidos)

| Meu # | Documento | Situação |
|---|---|---|
| P2-19 | D2, backlog §6.2 | Sheet reoferece skills já declaradas. Causa-raiz mapeada em `extract-job-skills`. Não corrigido. |
| P2-28 (parte) | D5, backlog §6.1 | "0/12" + "mais 6". Não corrigido. *(A divergência 3 vs 6–12 entre gate e modal é minha, nova.)* |
| P2-29 | D3, backlog §6.2 | Título do card truncado. Não corrigido. |
| P3-30 | device-test §5 | "CTA sangrado até as bordas". Não corrigido — e é pior do que "sem margem": está deslocado/cortado à esquerda. |
| P3-31 | C4, backlog §6.1 | Régua cortando "Finaliza…". Não corrigido. |
| P3-33 | D4, backlog §6.1 | "Baixar PDF" em ciano. Não corrigido (1 linha). |
| P3-34 | D6, backlog §6.1 | `+` vs lápis. Não corrigido. |
| P3-35 | SEC.5, backlog §6.1 | "Continuar" com 1 caractere. Não corrigido (2 linhas). |
| Opinião 4 | device-test §5 | Push sem tela de pré-permissão. Continua assim. |
| Opinião 5 | device-test §5 | Completude verde a 45%. Continua assim. |
| Opinião 6 | device-test §5 | Pin vermelho / halo verde. Continua assim. |
| Passada 2 | device-test §5 | Coach-mark cobrindo conteúdo (lá, a 5ª opção; aqui, um balão da conversa) e três balões redundantes seguidos. Continua assim. |
| — | device-test §5 | "Alta match" para perfil sem experiência nem skills. Reproduzido: meu perfil marcou **Alta** com 0 experiências. |

**Leitura importante:** o `PLANO-CORRECOES-DEVICE-TEST.md` §6 abre com *"não é escopo desta rodada"*.
Ou seja, os itens acima são conhecidos **e conscientemente adiados** — vão sair na 2.5.0 como estão.
Não estou pedindo para refazer a priorização; estou registrando que o usuário encosta neles.

### 6.3 Achados anteriores que eu verifiquei como CORRIGIDOS

Vale registrar porque contradizem documentos ainda na raiz (o fato vence):

- **C1** ("o app nunca segue o item para o novo segmento") — **corrigido**. Ao marcar como aplicada,
  a aba pulou para *Enviadas* com o item visível; ao adicionar manualmente, pulou para *Enviadas* com
  snackbar. Nunca caí em tela vazia.
- **C3** ("os 4 segmentos não aparecem com lista vazia") — **corrigido**. Vi as quatro pílulas na aba
  ainda zerada, durante o tutorial.
- **C5** ("selo `manual` cru") — **corrigido**. O card mostra **"Adicionada por você"**.
- **C2** ("empty-state explica *swipe pra direita*") — **parcialmente corrigido**. A menção a swipe
  sumiu; o texto ainda diz "Nenhuma **vaga salva** ainda" numa aba chamada Candidaturas.

*(Compatível com a memória do projeto: PR #25, "Aba Candidaturas — C1–C5", 27/07 — posterior ao
`PLANO-CORRECOES`, de 26/07.)*

### 6.4 Descartados como falso positivo

- **Auto-save do Currículo geral falhando com a flag ON** — falso positivo declarado no Anexo 1
  (migrations pendentes). Não cheguei a acioná-lo (não importei CV), então não tenho o que comentar
  sobre a copy da mensagem.
- **Currículos listando importados junto com gerados** — falso positivo declarado; além disso não
  importei nada.
- **"[DEV] Ferramentas" em Configurações** — artefato do build de debug (`kDebugMode`). Verificado e
  descartado.
- **Capitalização/troca de palavras nos campos de texto** ("Universidade"→"University",
  "do"→"Do") — autocorreção en-US do simulador. Provado com palavras fora do dicionário e eliminado
  desligando a autocorreção. **Não é bug do app.**
- **"Select All / Scan Text" em inglês** no menu de texto — é o iOS no locale do simulador.
- **"Salvar" habilitado com 0 habilidades** — cheguei a suspeitar, mas o print mostra o botão
  corretamente **desabilitado** em `0/12`. Não é achado.
- **Vocabulário "Currículo" vs "Fonte importada"** — o Anexo 1 pede atenção a isso. **Não encontrei**
  nenhuma tela chamando o arquivo recebido de "currículo" nos caminhos que percorri. Ressalva: não
  percorri o fluxo de import, que é onde esse vocabulário mais aparece.

---

## 7. Diferença entre as duas passadas

**Ligar `trilha_assist_v1` melhora a experiência de forma clara — não é ambíguo.**

| | Flag OFF (o que vai sair) | Flag ON |
|---|---|---|
| Entrada da aba | Tracker de 5 etapas + 2 balões + "Bora começar" | Card "Fortalecer perfil — 2 de 5", saudação, **5 chips de partida** e "Ver meu perfil" |
| Texto livre | *"Não tenho certeza… Toca numa opção aí em cima"* — **e não há opção acima** | Resposta real: diagnóstico de lacunas + barra 55% + **6 destinos tocáveis** |
| Próximo passo | Um caminho só, linear | "O que falta no meu perfil?", "Quais vagas combinam comigo?", "Adicionar experiência" |

Com a flag ON, a mesma pergunta que falhava (`Quais habilidades faltam no meu perfil?`) devolveu
*"Seu perfil tá com algumas lacunas! Faltam experiências, idiomas, um resumo profissional…"* com
atalhos diretos para Experiências, Idiomas, LinkedIn, Cargo desejado, Certificações e Conquistas.
Para um produto cujo gargalo declarado é perfil raso, essa é a diferença entre um beco e um corredor.

**O que só aparece com a flag ON:** o Assistente conversacional de verdade, o seletor de experiência
por tipo (com "Ainda não tenho experiência"), os chips de partida, o coach-mark ✦ e o card
"Fortalecer perfil". **Não consegui ver** o card "Fonte importada" nem o Currículo geral persistido —
ambos dependem de importar um CV (ver §5).

**Custos de ligar, honestamente:**
1. **P0-1 fica pior.** O Assistente também manda dados para a OpenAI, e continua sem checar
   consentimento — mais superfície sobre o mesmo buraco. **Eu resolveria P0-1 antes do rollout.**
2. Os defeitos conhecidos da Passada 2 seguem lá: coach-mark cobrindo conteúdo, três balões
   redundantes, duas entradas de texto simultâneas, chip primário "Melhorar meu resumo" para quem tem
   0 experiências.
3. A saudação chama o produto de **"copiloto de carreira"**, contrariando o contrato de linguagem que
   fixa "Assistente".

**Recomendação:** ligar, depois de (a) fechar P0-1 e (b) trocar a copy de "copiloto" para
"Assistente". Mantendo a flag OFF, o app sai com uma barra de chat que convida a escrever e responde
mandando tocar num botão inexistente — pior do que não ter chat.

---

## 8. Se eu tivesse uma semana

| Dia | O quê | Achado |
|---|---|---|
| 1 | Ligar `AiConsentModal` no fluxo de adapt (e no Assistente) | P0-1 |
| 1 | `isEn ? 'Major' : ''` — uma linha, vai para o PDF de todo mundo | P1-11 |
| 2 | Validador do resumo: proibir "experiência em" sem experiência | P0-2 |
| 2–3 | Deep-link de skills: rolar até a seção + voltar para a vaga | P1-3 |
| 3 | Match: remoto vira ✓ e omite a linha de localização | P1-5 |
| 4 | Copy do Assistente com flag OFF + ecoar a mensagem do usuário | P1-4 |
| 4 | Hidratar a tela de atribuição; mapear momento → `experience_level` | P1-6, P1-8 |
| 5 | Timeout de localização; matar o "Continuar" morto; normalizar parse do ATS | P1-7, P1-9, P2-17 |
| 5 | Varredura de vocabulário: "aplicada", formatos de match, "o Stage" | P2-12, P2-13, P2-22 |

Acessibilidade (P1-10) não cabe numa semana junto com o resto, mas merece uma fatia própria logo em
seguida — é a única área do app sem nenhuma cobertura anterior.

---

*Revisão feita por Claude (Opus 5) em 28/07/2026, no simulador iOS. Nada foi commitado. A flag
`trilha_assist_v1` foi ligada e restaurada para `enabled=false, rollout_pct=0`.*
