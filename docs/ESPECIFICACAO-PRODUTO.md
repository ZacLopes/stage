# Stage — Especificação de Produto
## App do candidato · Portal da empresa · Console de operações

**Versão:** Fase 1 (junho/2026) · **Stack assumida:** Flutter + Supabase (candidato), web (empresa), console interno · **Idioma do produto:** pt-BR

---

## 0. Princípios e modelo de objetos

O aplicativo não é organizado em torno de telas; é organizado em torno de **quatro objetos**, e cada tela existe para criar, enriquecer ou mover um deles:

| Objeto | O que é | Por que é o centro |
|---|---|---|
| **Perfil** | O candidato estruturado (experiências, formação, skills, preferências) | É o átomo: alimenta o match, vira a candidatura, vira o CV, e é o único ativo que não expira |
| **Vaga** | Uma oportunidade, com duas classes (própria / agregada) | É o combustível do feed — perecível por natureza; a classe define o comportamento |
| **Candidatura** | A transação perfil × vaga, com máquina de estados | É onde o valor acontece e onde o funil hoje fica escuro; tudo no app existe para criar candidaturas observáveis |
| **Colocação** | A contratação efetivada + ciclo de vida do TCE | É o objeto de receita e o registro legal de três partes |

Quatro regras de design derivadas do plano: (1) o perfil é o átomo; (2) a candidatura é a transação; (3) a colocação é o objeto de receita; (4) **nunca deixar o loop escurecer** — toda saída do app é instrumentada na ida e na volta.

Uma quinta regra, operacional: **toda promessa visível no app precisa de uma mecânica invisível que a sustente.** "Resposta garantida em 7 dias" não é copy, é um timer com fila de ops e fallback. Cada seção abaixo especifica a mecânica junto com a interface.

---

## 1. Arquitetura de informação

### 1.1 Três abas, mapeadas nos objetos

```
[ Vagas ]        [ Candidaturas ]        [ Perfil ]
  feed única        pipeline/tracker        perfil estruturado
  (lista + swipe)   (todas as fontes)       + variantes + export
```

A decisão de **três abas** (e não quatro ou cinco) é deliberada: cada aba é um objeto, e a navegação ensina o modelo mental do produto. Notificações ficam num centro acessível pelo topo (sino), não numa aba — notificação é um *evento sobre* objetos, não um objeto. Configurações ficam dentro de Perfil.

O que **sai** da arquitetura atual: a trilha gamificada como destino de navegação (os dados a aposentaram — ~998 usuários criaram CV, 20 completaram a trilha, 29 exportaram PDF; a demanda é pelo artefato, não pelo jogo). O que **muda de papel**: o swipe deixa de ser o paradigma e vira um *modo* dentro do feed (seção 3.2).

### 1.2 Inventário de telas (mapa completo)

**Candidato (mobile, Android + iOS + web leve):**

1. Onboarding (4 passos) → feed
2. Vagas: lista ranqueada · modo swipe · busca · filtros (bottom sheet) · estados de feed vazio
3. Detalhe da vaga (layout próprio / layout agregado)
4. Sheet de candidatura 1-toque (com diff da variante do CV)
5. Candidaturas: segmentos (Salvas / Enviadas / Em processo / Finalizadas) · detalhe com timeline · adição manual
6. Perfil: visão geral com completude · editor de experiência (perguntas dirigidas + bullets de IA) · skills · preferências · exportar/compartilhar
7. Central de notificações
8. Configurações (conta, alertas, privacidade/LGPD)

**Empresa (web):** landing/login · wizard de nova vaga · dashboard de vagas · shortlist · detalhe do candidato + ações · agenda de entrevistas · proposta/contratação · painel de compliance (TCE, seguro, horas, renovações) · faturas.

**Ops (console interno):** busca estruturada de candidatos · construtor de shortlist (com export em PDF) · fila de SLA · editor de estados de candidatura · QA de ingestão de vagas. *No mês 1, este console é o produto que a empresa "usa" — ela só não sabe.*

---

## 2. Onboarding e ativação

### 2.1 O diagnóstico que dita o redesenho

O funil atual quebra no upload de CV (`cv_upload_completed` = 52 num universo de 1.676) e a maioria constrói do zero. Conclusão: **o CV não pode ser portão de entrada**. O onboarding novo pede o mínimo que destrava o matching e entrega o feed em menos de 90 segundos; o perfil se completa *em contexto*, puxado por momentos de candidatura — não empurrado por um wizard.

### 2.2 Fluxo (4 passos, ~75 segundos)

| Passo | Pergunta | Por que essa e não outra |
|---|---|---|
| 1 | Auth (Apple/Google/e-mail) + **data de nascimento** | Data de nascimento é obrigação, não opção: há ~94 registros de ensino médio na base e LGPD exige tratamento distinto para menores (seção 13) |
| 2 | Curso + instituição + semestre/previsão de formatura | São os três campos que o TCE e o filtro legal de estágio exigem; instituição vem de autocomplete contra a tabela `institutions` (corrige o campo livre que hoje polui o dado — "Ensino Médio" no campo universidade) |
| 3 | Cidade + raio de deslocamento + modalidade aceita | Proximidade é fator de match com peso alto para estágio (6h/dia tornam deslocamento decisivo) |
| 4 | Áreas de interesse (máx. 3) + disponibilidade (manhã/tarde/integral) | Três no máximo força priorização e melhora o primeiro feed |

Depois do passo 4: **feed imediatamente**, com um banner discreto de completude ("Seu perfil está 35% — perfis acima de 80% entram em 3x mais shortlists"). Upload de CV existente vira atalho opcional ("Já tem currículo? Importe e a gente preenche por você") que faz *parse-to-prefill* das experiências — inverte a função: de portão para acelerador.

### 2.3 Definição de ativação

Ativação continua sendo `job_swiped`/primeira interação com vaga (mantém comparabilidade com a base histórica), mas ganha um segundo marco: **primeira candidatura ou primeiro save com perfil ≥ 50%** — o usuário que cruzou esse marco é o que o modelo de retenção deve perseguir.

---
## 3. Feed de vagas (aba Vagas)

### 3.1 Uma fila, duas classes

Feed unificado — separar vagas próprias e agregadas em abas fragmentaria um inventário que já é raso e recriaria o problema dos 8 canais. A classe da vaga muda o **comportamento do card**, não o lugar dele:

| Dimensão | Agregada | Própria ("Vaga Stage") |
|---|---|---|
| Selo no card | Fonte discreta ("via Gupy", "via empresa") | "Vaga Stage · resposta em até 7 dias" |
| Candidatura | Redireciona para fora + prompt de retorno | 1 toque, perfil é a candidatura |
| Pós-candidatura | Status auto-reportado (tracker) | Timeline real com push a cada transição |
| Papel estratégico | Volume, frescor, aquisição, SEO, lead comercial | Monetização, dados de outcome, diferenciação |

### 3.2 Lista como padrão, swipe como modo

O padrão vira **lista ranqueada** com filtros; o swipe sobrevive como "modo descoberta" (botão no topo). Três razões com dado por trás. Primeira: swipe maximiza a vazão de julgamentos — 34 swipes/usuário sobre 469 vagas é uma máquina de *acelerar a exaustão do catálogo* (19% chegam ao fim do feed). Lista desacelera o consumo do estoque e privilegia profundidade sobre vazão. Segunda: as entrevistas mostram comportamento de busca dirigida (filtros, curso, prazo), não só browsing — lista com filtros atende; swipe não. Terceira: o save no swipe (5,8%) mistura "interessante" com "impulso"; o save deliberado da lista produz um sinal de preferência mais limpo para o modelo. O gesto continua disponível na própria lista (swipe da célula para a direita = salvar, esquerda = descartar), preservando a memória muscular dos usuários atuais.

### 3.3 Anatomia do card

Empresa (ou "empresa confidencial" quando agregada sem marca) · título · chips de área e modalidade · bolsa (valor ou faixa; quando ausente, "a combinar" — nunca esconder o campo) · distância ("8 km de você") · badge de frescor ("nova hoje", "fecha em 3 dias") · **2–3 razões de match em chips** ("Excel", "experiência com atendimento", "seu curso") · selo de classe. O número do score **não aparece** no card por padrão (seção 4).

### 3.4 Função de ranking (especificação)

```
elegibilidade: score_relevância ≥ 0,35  (abaixo disso a vaga NÃO aparece,
                                          nem sendo própria — relevância sempre filtra primeiro)

ranking = score_relevância
        × (w1·frescor + w2·proximidade + w3·responsividade_da_fonte)
        + boost_classe_própria   (aplicado SÓ acima do gate de elegibilidade;
                                  própria ganha no empate, nunca fura a relevância)

regras de diversidade: máx. 2 cards seguidos da mesma empresa ou área
fatia de exploração: ~10% das posições reservadas a vagas de score incerto
                     (coleta de dado para o modelo; rotuladas internamente)
```

`responsividade_da_fonte` é um fator novo e estratégico: fontes/empresas que historicamente respondem candidatos sobem; o Gupy de processo infinito desce. O feed passa a *precificar o silêncio* — coerente com a reclamação nº 2 das entrevistas.

### 3.5 Estados de feed (a honestidade como retenção)

A exaustão do feed é real e mentir sobre ela destrói confiança. Estados explícitos: **fim das relevantes** ("Você viu as 14 vagas de Marketing desta semana. Entram ~10 novas por semana — ative o alerta e a gente te chama") · **fim com expansão** ("Quer ver vagas a até 25 km? E vagas remotas de outras cidades?") · **pedido de empresa** ("Tem uma empresa onde você queria estagiar? Pede que a gente corre atrás" — cada pedido vira lead comercial com nome de empresa e prova de demanda). Seções dentro do feed: "Novas para você", "Fecham em breve", "Empresas que respondem rápido".

---

## 4. Sistema de match

### 4.1 Estado atual, dito sem anestesia

O gap de 25 pontos entre salvas (65) e descartadas (40) está confundido: o score aparece antes do swipe em ~72% dos cards, então parte do gap é o score *causando* o save (ancoragem), não prevendo. Até existirem rótulos de outcome, o score é um artefato de UI. O plano trata isso em três tempos.

### 4.2 v1 — heurístico explicável (semanas 1–4)

Função de compatibilidade baseada em features, sem ML opaco: curso×área (tabela de afinidade), skills declaradas × skills requeridas (extraídas da vaga por classificador), semestre × senioridade pedida, distância × modalidade, disponibilidade × horário. Cada fator contribui pontos **e gera uma razão legível** — as chips do card são o subproduto do cálculo, não um enfeite. Saída em três bandas (Alta / Média / Baixa compatibilidade) em vez de número de 0 a 100: bandas comunicam sem fingir precisão que não existe.

### 4.3 O experimento de holdout (semana 1, antes de qualquer retrabalho)

20% das impressões de card têm score e razões **ocultados** pré-swipe (revelados depois, no detalhe). Medir: gap de save-rate por banda de score no grupo com exibição vs. sem. Se o gap colapsa sem exibição, o score atual é ancoragem e sai de cena até o v2; se persiste, há sinal preditivo real e o v1 pode ser calibrado em cima. Custo: ~2 dias de engenharia. Valor: saber se o "match" do pitch é verdade.

### 4.4 v2 — treinado em outcomes (a partir do mês 3–4)

Rótulos, do mais forte ao mais fraco: contratação em vaga própria > shortlist em vaga própria > candidatura própria > candidatura externa confirmada no prompt de retorno > save. O modelo v2 prevê P(shortlist) e P(contratação) por par perfil×vaga — e passa a servir **dois lados com objetivos distintos**: para o candidato, ordenar o feed; para a empresa, ordenar a shortlist. Mesmas features, funções de perda diferentes. Regra de governança: razões sempre visíveis; score nunca vira caixa-preta que decide sozinho quem a empresa vê (ops revisa shortlists na fase concierge — e essa revisão humana rotula erros do modelo).

---

## 5. Perfil estruturado (aba Perfil)

### 5.1 O que muda em relação à trilha

A trilha gamificada se aposenta como paradigma; sobrevive como **sequenciamento** — uma lista de próximos passos com payoff explícito, não um mapa de fases com mascote. O centro vira o **perfil-mestre estruturado**: dados que servem simultaneamente ao match, à candidatura 1-toque, ao CV em PDF e — mais tarde — à shortlist que a empresa lê. A arquitetura já decidida se mantém e ganha função ampliada: `raw_responses` por usuário (não por campanha), variantes por candidatura, Harvard MCS como template único, export PDF via HTML+CSS.

### 5.2 Estrutura de dados do perfil

Identidade e contato (verificação de e-mail institucional quando existir — selo "estudante verificado") · Formação (instituição via autocomplete, curso, semestre, previsão de formatura) · **Experiências** (profissionais, acadêmicas, extracurriculares, projetos — cada uma com raw_responses e bullets aprovados) · Skills com proficiência (hard e soft, máx. 12 — escassez força sinal) · Idiomas · Certificações · Disponibilidade e preferências (modalidade, horário, raio, bolsa mínima *privada* — usada no match, nunca exibida à empresa).

### 5.3 Perguntas dirigidas + bullets incrementais (o coração do editor)

Por experiência, quatro perguntas abertas dirigidas, uma por tela, com exemplos do domínio do usuário:

1. "O que era essa experiência e o que você fazia no dia a dia?"
2. "Teve algo que você melhorou, criou ou organizou? Como era antes e como ficou?"
3. "Tem algum número? Pessoas atendidas, vendas, tempo economizado, seguidores, notas..."
4. "Quais ferramentas você usava?" (chips sugeridas por área + campo livre)

Cada resposta é gravada como `raw_response` chaveada por (usuário, experiência, pergunta). A IA gera 2–4 bullets no padrão Harvard (verbo de ação + tarefa + resultado) **incrementalmente, após cada resposta** — o usuário vê o CV nascendo enquanto responde, o que é o motor de motivação que a trilha tentava simular com gamificação. Edição inline; aprovação explícita por bullet. **Regra anti-fabricação:** a IA só reformula conteúdo presente nas raw_responses; nunca acrescenta fatos. (Isso é ética e é produto: o candidato vai defender esses bullets numa entrevista.)

### 5.4 Completude com payoff (pesos)

Formação 15 · ≥1 experiência com bullets aprovados 25 · ≥5 skills 15 · disponibilidade/preferências 15 · contato verificado 10 · idiomas 10 · 2ª experiência 10. **Foto não pontua** (não induzir viés de seleção por aparência). 80% = "Perfil Stage completo", que destrava o enquadramento da candidatura 1-toque e é o número citado em todo o app ("perfis 80%+ entram em 3x mais shortlists" — promessa a validar com dado real e ajustar a copy ao que for verdade).

### 5.5 Variantes por candidatura (tailoring)

Ao candidatar-se a uma vaga própria, o sistema gera uma **variante** do mestre: reordena experiências por aderência, seleciona os bullets mais relevantes, ajusta o headline, e propõe no máximo 1–2 bullets *reescritos* (mesmos fatos, ênfase diferente). O usuário vê um **diff** ("o que mudou e por quê") e aprova. A variante é congelada e anexada à candidatura — a empresa vê exatamente o que foi enviado, auditável. Isso ataca a dor mapeada nas entrevistas ("múltiplas versões por vaga") transformando-a de trabalho manual em um toque de revisão.

### 5.6 Export e compartilhamento

PDF em 1 toque (Harvard MCS, HTML+CSS→PDF) sem portões; link público opcional de perfil web (`stage.app/p/usuario`) — útil inclusive para candidaturas externas, e cada link compartilhado é aquisição orgânica. Métrica de sucesso do redesenho: taxa de export/uso de variante ≥ 10x os 29 exports atuais no mesmo período relativo.

---
## 6. Candidatura — as duas mecânicas completas

### 6.1 Vaga própria: 1 toque + SLA

**Fluxo:** detalhe da vaga → "Candidatar com meu perfil" → bottom sheet de confirmação: preview do perfil, diff da variante (seção 5.5), no máximo 1–2 perguntas da empresa (limite imposto pelo produto — o wizard da empresa não permite mais; é a antítese do processo-Gupy) → enviar. Tempo alvo: < 30 segundos.

**Máquina de estados da candidatura:**

| Estado | Quem move | Prazo/SLA | O candidato vê |
|---|---|---|---|
| `enviada` | sistema | t0 | "Recebida ✓ · resposta até {t0+7d}" |
| `em_triagem` | automático | imediato | "Seu perfil está sendo avaliado" |
| `shortlist` | empresa/ops | ≤ 7 dias | "Você está entre os finalistas" + push |
| `entrevista` | empresa | agendamento in-app | data/hora + lembrete 24h e 1h antes |
| `proposta` | empresa | aceite in-app | bolsa, início, horário → aceitar/recusar |
| `contratada` | aceite | dispara Colocação + TCE | timeline completa + onboarding do estágio |
| `nao_selecionada` | empresa/ops | ≤ 7 dias | recusa categorizada e educada (abaixo) |

**Mecânica do SLA (a parte invisível):** o relógio começa em `enviada`. A empresa tem botões de 1 toque na shortlist (aprovar / recusar com motivo); se em D+6 não agiu, ops recebe a candidatura numa **fila de SLA** e age — nudge na empresa ou recusa categorizada em nome dela. *A Stage é dona do SLA, não a empresa* — terceirizar a promessa ao cliente é o jeito de quebrá-la. Métrica de contra-prova: taxa de violação do SLA < 5%.

**Recusa categorizada:** a empresa escolhe em 1 toque (perfil distante dos requisitos · buscava mais experiência em X · vaga preenchida · outro candidato mais aderente) e o app traduz para o candidato em copy gentil e útil ("A empresa buscava alguém com mais vivência em Excel avançado — adicione um projeto ou certificação e seu match em vagas parecidas sobe"). Uma feature, três efeitos: resolve a reclamação nº 2 das entrevistas (silêncio), gera rótulo de treino para o modelo, e devolve ao candidato um próximo passo acionável no perfil.

**Soft close:** vaga própria pausa novas candidaturas ao atingir ~25 candidatos com score acima do corte ("vaga concorrida — 23 candidatos"). Protege o SLA, cria urgência honesta e poupa o candidato da loteria de 1.000-por-vaga das grandes plataformas.

### 6.2 Vaga agregada: redirecionamento instrumentado

**Fluxo:** detalhe → "Candidatar no site da empresa" (rotulado com a fonte) → browser externo. **Na volta ao app** (detecção de resume após tap de saída), bottom sheet: "Você se candidatou para {vaga}?" — **Sim** → cria entrada no tracker (`enviada_externa`) e pergunta opcional da fonte; **Não** → "O que te fez desistir?" em 1 toque (processo longo demais · vaga já fechada · pediram coisas demais · só estava olhando) — esse dado de desistência por fonte é ouro estratégico (quantifica a fricção do Gupy por evidência própria, vira argumento de venda para a empresa dona da vaga); **Depois** → re-pergunta única em 24h via push suave. Cada link de saída carrega UTM da Stage: quando a vaga externa é de uma empresa-alvo, o relatório "80 estudantes salvaram sua vaga este mês, 31 clicaram" é a abertura da conversa comercial.

---

## 7. Tracker (aba Candidaturas)

O sistema-de-registro da busca inteira do usuário — incluindo o que acontece fora da Stage. As entrevistas mostram ~20 candidaturas simultâneas em 8+ canais com prazos perdidos no caos; o tracker resolve essa dor validada e, como subproduto, gera os rótulos fracos que treinam o match v2 antes da densidade de vagas próprias.

**Estrutura:** em mobile, segmentos (Salvas · Enviadas · Em processo · Entrevistas · Finalizadas) com listas — kanban literal de colunas não funciona em 390px. **Três tipos de entrada:** candidatura Stage (automática, status em tempo real, intocável pelo usuário) · externa confirmada (vinda do prompt de retorno, status auto-reportado) · manual (adição em 10 segundos: empresa, vaga, link opcional, status — para o que aconteceu 100% fora). Cada entrada: prazo, notas, próximo passo, lembrete configurável ("entrevista amanhã 14h").

**Loop semanal:** digest de domingo à noite ("Sua semana: 5 enviadas, 1 entrevista marcada, 2 sem resposta há 14 dias — arquivar?"). O arquivamento sugerido mantém o tracker limpo e — detalhe que importa — o "sem resposta há 14 dias" reforça, pela experiência vivida, o valor do selo de 7 dias das vagas Stage. O produto ensina o usuário a preferir o inventário que monetiza, sem dizer uma palavra de marketing.

---

## 8. Notificações (política completa)

**Dispara:** vaga nova relevante (agrupada, máx. 1 push/dia, só acima da banda Alta) · mudança de status de candidatura (imediata — é a notificação mais valiosa do app) · prazo de vaga salva em 48h · lembretes de entrevista (24h e 1h) · SLA cumprido ("a empresa respondeu em 3 dias"). **Nunca dispara:** streak, "sentimos sua falta", marketing genérico. A regra-mãe: push só quando há algo novo *sobre um objeto do usuário*. Canais: push como primário; e-mail como digest semanal; WhatsApp transacional (status de candidatura) fica anotado como candidato a teste no mês 3+ — no Brasil ele provavelmente supera o push em conversão, mas custa integração e opt-in formal.

---

## 9. Portal da empresa (web)

A promessa de cinco minutos, tela a tela:

**Wizard de vaga (5 passos):** arquétipo de função por área (templates: "Estágio em Marketing — Social Media", "Estágio Administrativo — Financeiro"... que pré-preenchem descrição e skills, editáveis) → requisitos com **máximo 3 obrigatórios** (o limite força a empresa a priorizar e é o que torna o match honesto) → bolsa com benchmark contextual ("vagas similares em SP: R$ 1.100–1.600", referência Guia Cia de Estágios) → modalidade e horário → revisão e publicação. Perguntas customizadas: máx. 2, opcionais.

**Shortlist:** 3–6 cards de candidatos, cada um com as razões de match em destaque, perfil expandível, PDF do CV (a variante congelada), e duas ações de 1 toque: *chamar para entrevista* / *recusar com motivo*. Na fase concierge, quem monta a shortlist é ops via console; o portal só a exibe — a empresa não distingue.

**Entrevista → proposta → contratação:** a empresa oferece janelas de horário, o candidato confirma no app; proposta formal (bolsa, data de início, jornada) com aceite in-app; o aceite dispara a Colocação e a esteira do TCE.

**Painel de compliance (o produto que o CIEE vende, com matching e velocidade na frente):** status do TCE com as três assinaturas (empresa ✓ · estudante ✓ · instituição ⏳) · apólice de seguro vinculada e visível · controle de jornada 6h/30h e recesso proporcional · alertas de renovação (6 meses) e de teto legal (2 anos) · coleta dos relatórios de atividade semestrais devidos à instituição · faturas (taxa + repasse de bolsa opcional via PIX). Deliberadamente um painel chato e completo — chato-e-completo é o que tira o medo do vínculo CLT do dono da PME.

**Realidade da fase 1:** wizard = formulário simples; shortlist = montada no console e publicada; compliance = você + templates de e-sign + planilha de prazos. O portal renderiza; a operação é Wizard of Oz. A regra é nunca prometer na interface uma automação que ainda é você — prometer o *resultado* (resposta em 72h) e cumpri-lo manualmente.

---
## 10. Console de operações (a terceira superfície, subestimada)

No mês 1, o console **é** a empresa. Cinco ferramentas, nesta ordem de construção:

1. **Busca estruturada de candidatos** — filtros sobre o perfil (área, curso, semestre, skills, distância do CEP da vaga, completude, último acesso). É a ferramenta que destrava a primeira shortlist; pode nascer como query no Supabase + view.
2. **Construtor de shortlist** — seleciona 3–6 perfis, anexa razões, gera o PDF padronizado (fase WhatsApp) e/ou publica no portal. Registra quem foi considerado e descartado (rótulo de treino).
3. **Fila de SLA** — candidaturas a ≤48h do estouro, ordenadas; ações de nudge e recusa assistida.
4. **Editor de estados** — mover candidaturas manualmente (a "automação" da timeline do candidato no início é uma pessoa com esse editor — e a timeline continua sendo real, porque o estado é real).
5. **QA de ingestão** — fila de vagas agregadas com classificação de área duvidosa, links mortos, duplicatas.

Construir em Retool/Supabase Studio é aceitável; o que não é aceitável é ops operando por planilha sem escrever nos objetos canônicos — aí o dado de treino e as métricas nascem mortos.

---

## 11. Modelo de dados

### 11.1 Entidades e campos essenciais

| Tabela | Campos-chave | Notas |
|---|---|---|
| `students` | id, auth_id, nome, nascimento, email, email_institucional_verificado, telefone, cidade, geo, consent_flags, anonymous_ids[] | `anonymous_ids[]` resolve a identidade pré/pós-login (corrige o problema de denominadores do corte de 28/05) |
| `profiles` | student_id (1:1), headline, completude, disponibilidade, modalidades[], raio_km, bolsa_minima_privada, atualizado_em | completude é calculada, nunca digitada |
| `experiences` | id, student_id, tipo (profissional/acadêmica/projeto/extracurricular), org, papel, início, fim, ordem | |
| `raw_responses` | id, student_id, experience_id, question_id, texto, criado_em | **por usuário**, reutilizável entre variantes — decisão já tomada, mantida |
| `bullets` | id, experience_id, texto, status (sugerido/aprovado/editado), origem_raw_ids[] | rastreabilidade IA→fato |
| `skills` / `student_skills` | taxonomia fixa + proficiência | máx. 12 por perfil |
| `institutions` | id, nome, tipo, cidade, status_convenio, contato_assinatura | o registro de signatários do TCE começa aqui |
| `employers` | id, razão_social, cnpj, porte, setor, geo, origem (LOI/outbound/pedido_de_empresa) | |
| `employer_contacts` | employer_id, nome, papel, whatsapp, email | o decisor da PME é uma pessoa, não um cargo |
| `listings` | id, **source (own/aggregated)**, employer_id?, origin_url?, origin_source, título, área (enum fixa), skills_req[], bolsa_min/max, modalidade, geo, horário, status (ativa/pausada/soft_closed/expirada), verificada_em, soft_close_threshold | a enum fixa de área corrige o buraco de taxonomia atual (Design = 0 em parte porque a taxonomia segue as fontes) |
| `applications` | id, student_id, listing_id, **type (stage/external_confirmed/manual)**, estado, variant_id?, respostas[], sla_deadline, rejection_category?, eventos_em | a máquina de estados da seção 6.1 |
| `profile_variants` | id, application_id, snapshot_json, diff_json, aprovado_em | congelada e auditável |
| `placements` | id, application_id, employer_id, student_id, institution_id, tce_id, assinaturas{empresa,estudante,instituição}, apólice_seguro, bolsa, início, fim_previsto, status (ativa/renovação/encerrada/**convertida**) | `convertida` é a flag que liga a esteira de efetivação (Step 4 do plano) |
| `subscriptions` / `invoices` | employer_id, sku (success_only/complete/admin_only), valores, ciclo | |
| `events` | append-only, server-side, ator, objeto, transição, ts | a fonte da verdade analítica para tudo que toca receita |

### 11.2 Regras de acesso (RLS, resumo)

Estudante lê/escreve só o próprio grafo; empresa lê apenas candidaturas das próprias vagas **e apenas a variante congelada** (nunca o mestre, nunca a bolsa-mínima privada, nunca contato direto antes da shortlist); ops com papel elevado e trilha de auditoria; instituição (futuro portal) lê só as colocações dos próprios alunos.

### 11.3 Eventos canônicos (espinha analítica)

`profile_completed_80` · `listing_published(source)` · `application_submitted(type)` · `application_state_changed(de,para,quem)` · `sla_breached` · `external_return_prompt(resposta,motivo?)` · `shortlist_delivered(horas_desde_vaga)` · `placement_signed` · `placement_converted`. O PostHog continua para análise de produto; eventos de receita são espelhados em `events` no banco — analytics de cliente não pode ser sistema de registro de dinheiro.

---

## 12. Arquitetura técnica e pipeline de ingestão

**Stack:** Flutter multiplataforma com **Android como prioridade de release** (país ~81% Android; o ICP orgânico ainda mais), web do candidato leve com **páginas de vaga indexáveis** (SSR/estático — cada vaga própria vira ativo de SEO e link compartilhável em grupo de CA; link compartilhado deve cair na Stage, não no concorrente). Portal da empresa em web pura. Supabase mantido (auth, Postgres, RLS, storage, edge functions).

**Pipeline de ingestão (agregadas):** adaptadores por fonte → normalizador (schema único) → dedupe (hash empresa+título+cidade) → classificador de área/skills (LLM com a enum fixa) → **verificador de frescor** (recheca links diariamente; vaga morta sai do feed no mesmo dia — o catálogo já roda 98% revisado em 7 dias; manter e endurecer) → fila de QA para baixa confiança. Conformidade por fonte: preferir APIs públicas e parcerias; registrar termos por adaptador (a resposta estratégica à fragilidade jurídica da agregação é a migração para inventário próprio, mas enquanto agrega, agrega limpo).

**Serviços de IA (server-side, edge functions):** geração incremental de bullets · geração de diff de variante · classificação de vagas · razões de match. Nenhuma chamada de IA no client; tudo auditável e versionado (prompt + modelo + input hash por output gerado).

**Integrações da esteira de colocação:** e-sign com assinatura tripartite · corretora parceira para apólice por colocação · cobrança PIX/boleto. Na fase 1, e-sign por template manual já cumpre; a integração própria entra no Step 2 do plano.

---

## 13. Privacidade, LGPD e menores

Itens de agora, não de depois: **data de nascimento no onboarding** com fluxo distinto para <18 (consentimento reforçado; e como o ICP atual é estágio de ensino superior, menores entram em experiência limitada/waitlist — sem perfil público, sem compartilhamento com empresas) · minimização (a empresa vê a variante, não o mestre) · retenção e exclusão (delete real do grafo do estudante; variantes anexadas a colocações ativas são retidas por obrigação legal e isso é dito com clareza no fluxo) · consentimentos granulares (uso do perfil para matching · contato por empresa · comunicação) · base legal mapeada por tabela. A ~centena de registros de ensino médio na base atual passa por triagem: idade confirmada → experiência limitada, ou conta encerrada com aviso.

---

## 14. Ordem de construção e métricas por superfície

### 14.1 Sprints (assumindo Claude Code + você; 2 semanas por sprint)

| Sprint | Entrega | Por que nessa ordem |
|---|---|---|
| 1 | Resolução de identidade + eventos canônicos + **holdout do score** | Tudo que vier depois precisa ser medível; o holdout decide o discurso de match |
| 1–2 | Perfil estruturado v1 (perguntas dirigidas + bullets + completude + export) reaproveitando o trabalho do Stage Resume + **busca de candidatos no console** | É a fatia que destrava a primeira shortlist (Trilha C do plano) |
| 3 | Feed em lista + filtros + estados de exaustão + card com razões | Desacelera o burn do catálogo e melhora o sinal de save |
| 3–4 | Tracker MVP + prompt de retorno em agregadas | Liga a instrumentação do funil escuro e a dor dos 8 canais |
| 4–5 | Vaga própria fim-a-fim: card com selo, 1-toque com variante, timeline (estados movidos pelo console), fila de SLA | O produto que a empresa compra; automação mínima, promessa cumprida na mão |
| 5–6 | **Android beta** + páginas web indexáveis de vaga | A leitura do iceberg do ICP e o canal orgânico |
| 6–8 | Portal da empresa v0 (wizard + shortlist + ações de 1 toque) + recusa categorizada | Tira ops do WhatsApp gradualmente; a recusa fecha o loop do SLA |
| 8+ | Esteira TCE/e-sign/seguro + painel de compliance | Step 2 do plano (agente de integração) |

### 14.2 Métricas por superfície (saúde, não vaidade)

Feed: % de sessões que veem ≥5 vagas banda Alta · taxa de exaustão semanal (meta: cair de 19% para <10% nos clusters). Perfil: % de novos cadastros que chegam a 80% em 7 dias (meta ≥35%) · taxa de export/variante (meta ≥10x a base atual). Candidatura própria: tempo mediano até shortlist (≤72h) · violação de SLA (<5%) · candidaturas por vaga até soft close. Tracker: % de ativos semanais com ≥1 entrada externa (≥30%) — é a prova de que viramos o sistema-de-registro. Agregadas: taxa de resposta ao prompt de retorno · motivos de desistência por fonte. North-star geral: **colocações verificadas/semana**; norte do candidato: **candidatos semanais com perfil ≥80% que aplicaram em ≥1 vaga**.

---

*Documento de trabalho — pares com o "Stage Business Plan, Phase 1" (Seção 7) e o detalha em profundidade de implementação. Decisões aqui assumem as conclusões do plano: feed unificado com duas classes, monetização no lado empresa, concierge antes de self-serve.*
