# Relatório completo do app Stage

Data de elaboração: 01/06/2026  
Base analisada: código-fonte local em `career_gamification`

## 1. Sumário executivo

O Stage é uma plataforma de carreira para estudantes, pessoas em início de carreira e candidatos a vagas de estágio, trainee e posições júnior. O app combina construção de perfil profissional, geração de currículo, importação de currículo existente, recomendações de vagas, análise de compatibilidade com vagas e adaptação de currículo com IA.

Apesar de o diretório do projeto se chamar `Gameficação Duolingo`, o produto exposto no código se apresenta como `Stage`. A inspiração de gamificação aparece na estrutura de trilha, fases, perguntas, desbloqueios, tutorial e experiência guiada, mas o produto final é um app de carreira, currículo e vagas.

Em termos de produto, o Stage tenta resolver um problema bem específico: candidatos iniciantes normalmente não sabem transformar experiências acadêmicas, projetos, atividades extracurriculares e habilidades em um perfil profissional claro. Além disso, têm dificuldade de entender quais vagas combinam com seu perfil e como adaptar o currículo para cada vaga. O app reduz essa fricção com três caminhos principais:

- importar um currículo em PDF e extrair dados automaticamente;
- construir o perfil por uma trilha guiada e gamificada;
- usar o perfil estruturado para gerar, salvar, exportar e adaptar currículos.

Em termos técnicos, o app é um Flutter mobile com Supabase como backend principal. O Supabase concentra autenticação, banco Postgres, Storage, Edge Functions, políticas RLS e jobs operacionais. A IA fica no servidor, principalmente em Edge Functions Deno/TypeScript, usando modelos OpenAI para extração de currículo, geração de conteúdo, análise de match e adaptação de currículo. O cliente Flutter nunca deveria precisar carregar chaves de IA.

Além do app mobile, existe um dashboard administrativo web em React/Vite/Tailwind. Esse dashboard amplia o produto para uma operação B2B: visualização de KPIs, usuários/candidatos, vagas, clientes empregadores, listas de candidatos, consentimento comercial, ranking e exportação CSV.

O produto, portanto, não é apenas um app de currículo. Ele já tem sinais de uma plataforma de matching entre candidatos e empregadores:

- app mobile para aquisição, ativação e uso pelos candidatos;
- banco estruturado de perfis profissionais;
- ingestão e normalização de vagas;
- análise de fit candidato-vaga;
- adaptação de CV como diferencial de conversão;
- área admin para operações, clientes B2B e listas de candidatos.

## 2. O que o app faz em linguagem não técnica

O Stage ajuda o usuário a montar uma presença profissional mais forte e a usar essa presença para encontrar vagas melhores.

Na prática, o usuário pode entrar no app, criar conta, importar um currículo ou construir um perfil do zero. Se importar um currículo, o app lê o PDF, tenta entender nome, contato, formação, experiências, habilidades, projetos, idiomas, certificações e outros elementos relevantes. Se preferir construir do zero, o app faz perguntas em formato de trilha, parecidas com uma experiência gamificada, para transformar dados pessoais e acadêmicos em conteúdo de currículo.

Depois que o perfil existe, o usuário vê vagas em formato de feed. Pode curtir, descartar, salvar, marcar como aplicado e abrir detalhes. O app calcula um score ou diagnóstico de compatibilidade entre o usuário e cada vaga. Esse score considera preferências de cargo, tipo de vaga, cidade, modelo de trabalho, salário, área, habilidades e conteúdo do perfil.

O usuário também pode gerar currículos, escolher templates, exportar PDF, salvar versões e adaptar o currículo para uma vaga específica. A adaptação busca reorganizar e destacar experiências reais do usuário de acordo com a vaga, sem inventar credenciais. O app inclui validações para impedir conteúdo artificial demais ou incompatível com o perfil.

Para quem opera a plataforma, o dashboard admin mostra indicadores de usuários, vagas, likes, candidaturas, currículos adaptados e consentimentos. Também permite buscar candidatos, revisar perfis, gerenciar empresas/clientes e gerar listas ranqueadas de candidatos para demandas B2B.

## 3. Público-alvo e posicionamento

O público principal parece ser formado por:

- estudantes universitários;
- estudantes de ensino médio em transição para carreira;
- candidatos a estágio;
- candidatos a trainee;
- candidatos júnior;
- pessoas com pouca experiência formal, mas com projetos, cursos, atividades e habilidades transferíveis.

O app foi desenhado para um público que precisa de orientação e estrutura. Muitas telas e serviços existem para transformar conteúdo disperso em uma narrativa profissional:

- atividades acadêmicas viram bullets;
- projetos viram experiência demonstrável;
- habilidades viram seção de competências;
- objetivos profissionais viram preferências de vagas;
- currículo importado vira perfil estruturado;
- perfil estruturado vira PDF exportável;
- vaga específica vira currículo adaptado.

O posicionamento mais forte do Stage é: "um assistente de carreira para candidatos iniciantes, com IA e gamificação para transformar perfil em oportunidades".

## 4. Jornada principal do usuário

### 4.1 Primeiro acesso

A inicialização do app passa por uma tela de splash com animação da marca Stage. Depois disso, o app decide para onde mandar o usuário com base no estado de autenticação e perfil.

Se o usuário não está logado, ele vê o onboarding/autenticação. Se está logado, o app verifica se já existe campanha criada, se precisa configurar perfil ou se deve cair em uma tela legada de conclusão.

O roteamento principal é:

- usuário sem sessão: onboarding;
- usuário com sessão e campanha: home;
- usuário com perfil incompleto ou fluxo inicial ativo: tela de "duas portas";
- usuário em fluxo antigo: tela de conclusão.

### 4.2 Autenticação

O app suporta login/cadastro por:

- Google OAuth;
- Apple Sign-In nativo;
- telefone, usando uma estratégia interna com email sintético baseado no número.

O cadastro por telefone, no código atual, não é um fluxo real de OTP/SMS. Ele usa um email artificial no formato semelhante a `phone_<digits>@stage.app` e senha. O telefone real é salvo depois em dados de perfil. Isso funciona como uma solução pragmática de cadastro, mas não substitui validação forte de posse do número.

No login social, há integração com Supabase Auth. O redirect OAuth usa o esquema `io.supabase.stage://login-callback`.

### 4.3 Escolha inicial: importar currículo ou construir perfil

Depois de logar, o usuário novo encontra a tela `TwoDoorsScreen`. Essa tela oferece dois caminhos:

- importar currículo;
- construir perfil pela trilha.

O caminho de importação é recomendado porque acelera o preenchimento. O caminho da trilha é útil para quem ainda não tem currículo pronto ou prefere construir com ajuda.

### 4.4 Importação de currículo

Ao importar currículo:

1. o usuário escolhe um PDF;
2. o app extrai texto localmente do PDF;
3. o app faz uma validação local para rejeitar documentos que claramente não são currículos;
4. o PDF é salvo no Supabase Storage;
5. um registro é salvo na biblioteca de currículos;
6. o texto extraído é salvo como base auxiliar;
7. uma Edge Function é chamada em segundo plano para extrair o perfil estruturado;
8. o resultado é salvo tanto em formato legado quanto nas novas tabelas relacionais de perfil.

Essa jornada é importante porque permite que o usuário chegue rapidamente ao feed de vagas e às ferramentas de currículo.

### 4.5 Construção pela trilha

Se o usuário escolhe construir pela trilha, o app passa por perguntas e etapas que coletam dados pessoais, formação, experiências, habilidades, preferências e objetivos. O modelo de dados suporta muitos tipos de perguntas: múltipla escolha, sliders, campos de texto, listas dinâmicas, seleção de ferramentas, formulários de experiência, formulários acadêmicos, link input, telefone, cidade/estado e outros.

A ideia de produto é transformar um processo burocrático de preenchimento de currículo em uma sequência mais leve, com progresso visível e sensação de avanço.

### 4.6 Preferências de vagas

O app coleta preferências como:

- cargos desejados;
- tipo de vaga;
- modelo de trabalho;
- cidade/estado;
- outras localidades;
- faixa salarial ou expectativas;
- áreas de interesse.

Essas preferências alimentam o feed de vagas e o cálculo de compatibilidade.

### 4.7 Home

A home tem quatro abas:

- Vagas;
- Salvas;
- Currículo;
- Perfil.

A navegação usa bottom navigation. O app também tem tutorial inicial, prompt de notificações push depois de alguns segundos, tracking de troca de abas e comportamento especial para destacar upload/currículo quando necessário.

### 4.8 Feed de vagas

Na aba de vagas, o usuário interage com cards. Ele pode curtir, descartar, abrir detalhes, compartilhar, adaptar currículo e marcar interesse. O app usa um estilo de swipe com `flutter_card_swiper`.

O feed exclui vagas já interagidas, filtra vagas ativas e vencidas, usa preferências do usuário e busca uma quantidade grande de vagas para contornar limitações do componente de cards.

### 4.9 Vagas salvas

As vagas curtidas ficam em uma área própria. O usuário pode acompanhar vagas pendentes, aplicadas e possivelmente restaurar/remover itens. A bottom navigation mostra badge quando há vagas salvas/pendentes.

### 4.10 Currículo

Na aba de currículo, o usuário pode:

- visualizar dados de currículo;
- escolher template;
- gerar PDF;
- salvar versões;
- editar blocos de conteúdo;
- exportar/compartilhar;
- ver currículos importados;
- ver currículos adaptados.

Há uma biblioteca de currículos com fontes diferentes:

- manual;
- importado;
- adaptado.

### 4.11 Perfil

Na aba de perfil, o usuário edita dados pessoais, experiências, formação, habilidades, idiomas, projetos, certificações, interesses, prêmios, cursos e preferências. O app tem um editor mais estruturado do que um formulário simples: há autosave, operações otimistas, invalidação de cache e reuso desses dados em match, currículo e adaptação.

## 5. Principais funcionalidades de produto

### 5.1 Onboarding com baixo atrito

O app tenta diminuir a fricção inicial com duas opções claras: importar ou construir. Isso é bom porque usuários diferentes começam em estados diferentes. Quem já tem CV não quer responder uma trilha longa. Quem não tem CV precisa de orientação.

### 5.2 Perfil profissional estruturado

O perfil do usuário é a peça central. Ele não é apenas uma página visual. Ele vira uma base de dados relacional usada para:

- gerar currículo;
- calcular match com vagas;
- adaptar currículo;
- ranquear candidatos para clientes B2B;
- avaliar completude;
- filtrar e buscar candidatos no dashboard.

### 5.3 Importação inteligente de CV

A importação de PDF é mais do que upload. O sistema tenta entender o conteúdo do currículo e preencher dados estruturados. Isso reduz trabalho manual e melhora a qualidade do perfil.

### 5.4 Trilha gamificada

A trilha permite coletar informações com mais contexto e mais cuidado. Para candidatos iniciantes, isso é relevante porque muita informação útil não aparece como "experiência profissional" tradicional.

### 5.5 Geração de currículo

O app gera currículos em PDF a partir do perfil. Há templates e lógica para caber em uma página A4. O sistema tenta ajustar margem, fonte, espaçamento e densidade antes de remover conteúdo menos essencial.

### 5.6 Adaptação de currículo para vaga

A adaptação de CV é uma das funcionalidades mais estratégicas. O usuário seleciona uma vaga e o app gera uma versão adaptada do currículo, destacando elementos do perfil que combinam com a vaga. O resultado passa por preview e edição antes de baixar/salvar.

### 5.7 Match com vagas

O app calcula compatibilidade entre usuário e vaga. Há um caminho determinístico e um caminho com IA. O determinístico pontua dimensões objetivas; o com IA analisa com mais contexto, cacheia resultado e tenta explicar motivos.

### 5.8 Feed com swipe

O feed usa interação rápida: curtir ou descartar. Isso cria um comportamento parecido com apps de descoberta e ajuda a coletar sinais para o sistema.

### 5.9 Notificações

O app usa OneSignal para push. Há lógica para pedir permissão após entrada na home, e funções server-side para digest diário e broadcast.

### 5.10 Dashboard admin e operação B2B

O dashboard admin permite operar a plataforma:

- visualizar KPIs;
- ver vagas;
- buscar usuários;
- revisar consentimentos;
- cadastrar clientes;
- criar listas de candidatos;
- gerar ranking;
- aprovar/rejeitar candidatos;
- exportar CSV;
- auditar ações administrativas.

## 6. Telas e áreas principais

### 6.1 Splash

A tela de splash tem animação própria da marca Stage. Ela usa gradiente azul/ciano, desenho do "S" e wordmark. Também respeita redução de movimento.

### 6.2 VersionGate

Antes de liberar o app, há uma verificação de versão mínima suportada via tabela `app_config`. Se a versão instalada estiver abaixo do mínimo, o usuário vê uma tela de atualização obrigatória. Se a verificação falhar, o sistema segue em modo "fail-open", evitando bloquear usuários por erro de backend.

### 6.3 AuthGate

O `AuthGate` decide o destino do usuário com base em sessão, campanha e estado de perfil. Ele é o ponto central de roteamento pós-splash.

### 6.4 Onboarding e autenticação

Inclui opções de entrada social e telefone. Também há eventos de analytics específicos para cadastro e login.

### 6.5 TwoDoorsScreen

Tela de escolha entre importar currículo e construir pela trilha.

### 6.6 UploadPreviewSheet

Após escolher um PDF, o usuário vê um preview/confirmacao antes de avançar no fluxo de importação.

### 6.7 HomeScreen

Tela base com as quatro abas. Também inicializa tutorial, prompt de push e tracking de navegação.

### 6.8 JobsSwipeScreen

Tela de descoberta de vagas por cards. Ela gerencia prefetch de match, swipes, detalhes e adaptações.

### 6.9 ResumeAdaptationSheet

Tela/folha de adaptação de currículo para uma vaga. Ela verifica se o perfil tem dados suficientes antes de chamar o backend.

### 6.10 AdaptedResumePreviewScreen

Tela de preview da versão adaptada. Permite comparar original/adaptado, editar blocos, trocar template, renderizar preview e aprovar o download.

### 6.11 Resume tab

Área onde o usuário acessa currículos, templates, exportação e biblioteca.

### 6.12 Profile tab

Área de edição do perfil estruturado.

### 6.13 Admin dashboard

Aplicação web separada, com páginas:

- Overview;
- Vagas;
- Usuários;
- Empresas;
- Listas de candidatos.

## 7. Arquitetura técnica geral

### 7.1 Visão de alto nível

A arquitetura é composta por quatro blocos:

- app Flutter;
- Supabase;
- Edge Functions com IA e automações;
- dashboard admin React.

O app Flutter é o cliente principal para candidatos. Ele contém UI, estado, serviços client-side, integração com Supabase, renderização de PDF, analytics e notificações.

O Supabase é o backend central. Ele fornece autenticação, banco Postgres, Storage e execução de Edge Functions. As migrations definem tabelas, índices, políticas RLS e funções RPC.

As Edge Functions concentram lógica sensível, integrações externas, chamadas de IA, geração de relatórios, sincronização de vagas e operações administrativas.

O dashboard admin consome Edge Functions administrativas, autenticando via Supabase e validando permissões contra a tabela `admin_users`.

### 7.2 Stack do app mobile

O app mobile usa:

- Flutter;
- Dart;
- Provider/ChangeNotifier para estado;
- Supabase Flutter;
- dotenv para variáveis;
- PostHog para analytics/session replay;
- OneSignal para push;
- Facebook App Events;
- App Tracking Transparency;
- File Picker;
- Syncfusion PDF;
- HTML/PDF rendering via `printing`;
- `pdf` e `share_plus`;
- `flutter_card_swiper`;
- `cached_network_image`;
- `flutter_html`;
- `url_launcher`;
- `sign_in_with_apple`;
- geolocalização/geocoding;
- fontes Inter e Outfit.

### 7.3 Stack do backend

O backend usa:

- Supabase Auth;
- Postgres;
- Row Level Security;
- Supabase Storage;
- Edge Functions Deno/TypeScript;
- OpenAI em funções server-side;
- PostHog server-side;
- OneSignal REST;
- Apify/Gupy e adapters ATS para ingestão de vagas;
- ntfy para alertas operacionais em alguns casos.

### 7.4 Stack do dashboard admin

O dashboard admin usa:

- React 18;
- Vite;
- TypeScript;
- Tailwind CSS;
- Supabase JS;
- TanStack Table;
- Recharts;
- lucide-react.

### 7.5 Padrão de camadas no Flutter

O projeto usa uma mistura de camadas:

- `screens` para telas;
- `widgets` para componentes;
- `viewmodels` para estado;
- `services` para integrações e regras transversais;
- `repositories` para persistência e Supabase;
- `features/profile` para uma estrutura mais modular de perfil;
- `models` para entidades antigas/compartilhadas.

O estado principal é gerenciado por Providers criados no `main.dart`.

Providers relevantes:

- `ProfileEditorViewModel`;
- `UserViewModel`;
- `GamificationViewModel`;
- `ProfileViewModel`;
- `PreferencesViewModel`;
- `ExtractionStatusViewModel`;
- `HomeViewModel`;
- `ResumeViewModel`;
- `JobsViewModel`;
- `TutorialController`;
- `PendingAdaptedCvTracker`.

## 8. Inicialização do app

O arquivo `lib/main.dart` é o ponto de entrada. Ele executa tarefas importantes:

- inicializa bindings Flutter;
- bloqueia orientação em portrait;
- carrega `.env`;
- inicializa Supabase;
- configura PostHog e session replay;
- registra handlers globais de erro;
- inicializa feature flags;
- inicializa serviços de preferências e trackers;
- inicializa Facebook Events;
- inicializa OneSignal;
- monta o grafo de Providers;
- cria o `MaterialApp`.

O app é envolvido por `runZonedGuarded`, o que permite capturar exceções assíncronas e enviá-las para analytics/error tracking.

A árvore principal inclui:

- `PostHogWidget`;
- `MaterialApp`;
- `VersionGate`;
- `SplashScreen`;
- `TutorialOverlay`.

Também existe um listener global para dispensar teclado ao tocar fora de campos.

## 9. Autenticação e identidade

### 9.1 Supabase Auth

O usuário é autenticado via Supabase. O `UserViewModel` centraliza grande parte do estado de sessão, perfil, login, logout e tracking.

### 9.2 Google e Apple

Login social usa OAuth/Sign-In nativo. O fluxo também contempla migração/linking de contas legadas email-senha para identidades Google/Apple.

### 9.3 Telefone

O fluxo de telefone usa um email sintético para criar conta. Isso permite cadastro por telefone sem depender, no estado atual do código, de SMS real. É uma área que exige clareza de produto e segurança caso o telefone passe a ser usado como fator confiável.

### 9.4 OneSignal identity

Ao identificar usuário, o app também faz login no OneSignal com o ID do usuário. No logout, desfaz essa associação.

### 9.5 Analytics de identidade

O app envia eventos como:

- `sign_up_completed`;
- `login_completed`;
- identificação PostHog;
- CompletedRegistration no Facebook;
- advanced matching em eventos do Facebook quando aplicável.

## 10. Modelo de perfil

### 10.1 Evolução do modelo

O app tem duas gerações de perfil:

- modelo legado em `user_profiles.gamification_data`;
- modelo novo em tabelas relacionais `profile_*`.

O modelo legado ainda é usado em partes do app, principalmente para compatibilidade e fallback. O modelo novo é mais forte para edição, busca, matching, IA, B2B e integridade.

### 10.2 Tabelas relacionais principais

As tabelas relacionais de perfil incluem:

- `profile_personal`;
- `profile_experiences`;
- `profile_bullets`;
- `profile_education`;
- `profile_education_majors`;
- `profile_education_minors`;
- `profile_education_activities`;
- `profile_languages`;
- `profile_skills`;
- `profile_certifications`;
- `profile_projects`;
- `profile_project_bullets`;
- `profile_interests`;
- `profile_awards`;
- `profile_coursework`;
- `profile_job_preferences`;
- `profile_desired_titles`;
- `profile_application_countries`;
- `profile_other_locations`;
- `profile_extraction_logs`.

### 10.3 Conteúdo do perfil

O perfil cobre:

- nome;
- email;
- telefone;
- localização;
- headline;
- resumo;
- LinkedIn;
- site;
- experiências;
- bullets de experiência;
- formação;
- cursos principais/secundários;
- atividades acadêmicas;
- idiomas;
- habilidades;
- certificações;
- projetos;
- bullets de projetos;
- interesses;
- prêmios;
- coursework;
- preferências de vaga;
- cargos desejados;
- localidades adicionais.

### 10.4 Edição de perfil

O `ProfileEditorViewModel` carrega várias seções em paralelo e permite edições com comportamento otimista. Dados pessoais têm autosave com debounce. Listas como skills e interesses podem ser substituídas em lote.

Quando algo muda, o app emite eventos de perfil para invalidar caches e forçar recalculo onde necessário.

### 10.5 Snapshot unificado

O `ProfileSnapshotService` cria uma visão consolidada do perfil. Essa visão é usada para:

- saber se o perfil está vazio;
- saber se o usuário pode adaptar currículo;
- gerar pseudo-texto para matching determinístico;
- gerar dados de currículo para renderização.

## 11. Importação e extração de currículo

### 11.1 Fluxo client-side

O serviço `CvImportService` coordena a importação:

1. abre seletor de arquivo;
2. aceita PDF;
3. extrai texto localmente;
4. valida se o documento parece currículo;
5. salva no Storage;
6. salva registro em `saved_resumes`;
7. persiste texto bruto aproveitável;
8. chama `extract-profile` em background.

### 11.2 Extração local de texto

O `ResumePdfExtractor` usa Syncfusion para extrair texto do PDF. Ele também normaliza linhas e corrige artefatos conhecidos de extração, como problemas com caracteres em palavras que contêm `i/m` após letras específicas.

### 11.3 Validação contra documentos sensíveis incorretos

O `CvContentValidator` tenta rejeitar documentos que não são currículos, como:

- extratos bancários;
- documentos de identidade gov.br;
- holerites/folhas de pagamento.

Essa validação existe localmente e também é espelhada no servidor. O objetivo é evitar salvar ou enviar para IA documentos sensíveis que o usuário escolheu por engano.

### 11.4 Edge Function `extract-profile`

A função `extract-profile` é uma das partes mais importantes do backend.

Ela:

- autentica o usuário;
- aceita PDF em base64;
- aceita texto extraído como fallback;
- limita tamanho do PDF;
- valida se parece currículo;
- chama OpenAI com schema estruturado;
- aplica pós-processamento;
- aplica validações anti-invenção;
- calcula completude/confiança;
- salva JSON legado em `user_profiles`;
- chama RPC para salvar nas tabelas relacionais;
- registra logs em `profile_extraction_logs`;
- envia eventos para PostHog;
- pode alertar operação em falha parcial.

O modelo usado nessa função é `gpt-4o`, com structured outputs via schema em `_shared/profile_schema.ts`.

### 11.5 Schema de extração

O schema de perfil inclui seções pessoais, experiências, educação, idiomas, habilidades, certificações, projetos, interesses, prêmios e coursework. Ele também guarda sinais de confiança e permite converter o perfil extraído para formatos legados de currículo.

### 11.6 Golden set de extração

Existe um diretório `golden_set` para avaliar regressões no extrator. Ele prevê PDFs anonimizados, ground truth, scripts de execução e comparação. O README deixa claro que CVs adversariais devem ter ground truth manual para evitar auto-validação pelo próprio modelo.

Esse é um bom sinal de maturidade na parte de IA, porque extração de currículo é frágil e precisa ser monitorada com exemplos reais.

## 12. Trilha gamificada

### 12.1 Estrutura

A trilha é modelada com:

- `Track`;
- `Phase`;
- `Question`;
- `QuestionType`.

As respostas são salvas em tabelas como:

- `user_answers`;
- `raw_responses`;
- `user_progress`.

### 12.2 Tipos de perguntas

O enum de tipos de perguntas é grande e permite experiências ricas:

- múltipla escolha;
- escolha única;
- escala;
- texto;
- seleção de personagem;
- história interativa;
- slider de equilíbrio;
- drag and drop;
- vibe select;
- chat;
- vision cards;
- seleção de squad;
- ladder de level up;
- id card builder;
- seleção de ícones;
- lista dinâmica;
- input de link;
- input de telefone;
- cidade/estado;
- formulário de experiência;
- formulário acadêmico;
- catálogo de ferramentas;
- formulário de contato;
- inventário de experiências;
- destaques acadêmicos.

### 12.3 Objetivo da trilha

A trilha existe para transformar perguntas difíceis em microinterações. Em vez de perguntar "escreva seu currículo", o app pergunta partes menores e depois usa essas partes para gerar conteúdo profissional.

### 12.4 Persistência

O `SupabaseRepository` lida com tracks, fases, perguntas, progresso e respostas. Ele também faz prefetch de dados para reduzir latência.

## 13. Geração de currículo

### 13.1 ResumeViewModel

O `ResumeViewModel` gerencia:

- dados do currículo;
- conteúdo gerado;
- idioma;
- template selecionado;
- warnings;
- estimativa de uma página;
- edições pendentes;
- cache local;
- geração com IA;
- persistência de edições.

### 13.2 Idiomas

O app suporta currículo em português e inglês, com parâmetro de idioma `pt`/`en`.

### 13.3 Geração com IA

A Edge Function `generate-resume` usa modelo `gpt-4o` para transformar respostas/perfil em conteúdo de currículo. Ela recebe respostas com perguntas, contexto de área e idioma. O prompt impõe regras de formato e estilo, incluindo estrutura de JSON e seções esperadas.

### 13.4 Templates

Templates identificados:

- `harvard_ats`;
- `jakes_resume`;
- `forte_foundation`;
- `one_page_compact`;
- `cobalt_modern`.

### 13.5 Renderização PDF

O `PdfService` renderiza HTML para PDF via `Printing.convertHtml`. Há uma lógica adaptativa para caber em A4, ajustando densidade antes de sacrificar conteúdo.

### 13.6 Estratégia de uma página

A renderização tenta vários tiers:

- de layouts mais expandidos;
- para layouts mais compactos;
- reduzindo margens;
- ajustando fonte;
- ajustando line-height;
- removendo seções menos essenciais apenas em tiers mais agressivos.

O sistema preserva seções importantes como resumo, experiência, educação e skills.

### 13.7 ResumeRenderer

O `ResumeRenderer` escolhe entre renderização legada e renderização baseada no perfil relacional. Há feature flag para templates v2 e fallback quando o perfil estruturado está vazio.

## 14. Biblioteca de currículos

### 14.1 Fontes de currículo

O app classifica currículos salvos em:

- `manual`;
- `imported`;
- `adapted`.

### 14.2 Tabela `saved_resumes`

A tabela guarda:

- título;
- caminho do arquivo;
- data de criação;
- fonte;
- dados estruturados opcionais;
- template opcional.

### 14.3 Operações

O `ProfileViewModel` permite:

- listar currículos;
- salvar currículo;
- apagar currículo;
- compartilhar/baixar;
- atualizar template re-renderizando o PDF;
- resolver títulos duplicados com sufixos.

## 15. Feed de vagas

### 15.1 Modelo de vaga

O modelo `Job` inclui:

- título;
- empresa;
- descrição;
- área;
- requisitos;
- cidade/estado;
- modelo de trabalho;
- tipo de vaga;
- salário em centavos;
- método de aplicação;
- URL ou email;
- status ativo;
- datas.

Valores comuns:

- modelo: `remoto`, `hibrido`, `presencial`;
- tipo: `estagio`, `trainee`, `clt_junior`, `temporario`.

### 15.2 Repositório de vagas

O `JobRepository` busca vagas ativas com join de empresa, exclui vagas já interagidas e ignora vagas expiradas. Ele aplica filtros de preferências de forma permissiva quando dados estão ausentes.

### 15.3 Swipes

O `SwipeRepository` salva ações de swipe, permite undo, busca vagas curtidas, remove/restaura likes e marca vagas como aplicadas.

### 15.4 JobsViewModel

O `JobsViewModel` gerencia:

- lista de vagas;
- IDs já swipados;
- vagas curtidas;
- filtros locais;
- preferências;
- cache de match;
- invalidação quando o perfil muda.

Ele não inicializa automaticamente no auth para evitar eventos de feed antes do onboarding. A tela de swipe chama `init()`.

### 15.5 UX de feed

A tela de vagas usa cards com prefetch de match. Ela busca match dos primeiros cards e mantém um buffer. Também limita concorrência para evitar sobrecarga.

## 16. Cálculo de match

### 16.1 Match determinístico

O `MatchScoreCalculator` usa uma pontuação baseada em dimensões:

- área: 30 pontos;
- tipo de vaga: 20 pontos;
- cidade/localização: 15 pontos;
- modelo de trabalho: 15 pontos;
- salário: 10 pontos;
- skills/conteúdo do perfil: 10 pontos.

Também há estados especiais:

- `unknown`;
- `pending`;
- `noResume`.

A confiança do score depende de quantas dimensões declaradas existem:

- alta com muitos dados;
- média com dados intermediários;
- baixa com poucos dados.

### 16.2 Match com IA

A Edge Function `analyze-match` usa IA para analisar candidato e vaga. Ela:

- carrega perfil relacional;
- carrega preferências;
- cria hash de perfil;
- usa cache em `match_analyses`;
- aplica TTL de 30 dias;
- usa prompt versionado;
- tem rate limit diário;
- retorna score e motivos.

O modelo indicado é `gpt-4o-mini`.

### 16.3 Bypass quando não há dados

Se o usuário não tem preferências nem perfil, a função retorna um caso especial com score neutro e motivo `Sem perfil`. O cliente interpreta como estado desconhecido, evitando fingir precisão.

### 16.4 Derivação de score

O backend não confia cegamente na aritmética do modelo. Ele interpreta os motivos e deriva o score de forma controlada, reduzindo risco de inconsistência.

## 17. Adaptação de currículo

### 17.1 Objetivo

A adaptação de currículo transforma um currículo geral em uma versão alinhada a uma vaga específica. A intenção é destacar experiências, habilidades e projetos reais que melhor dialogam com os requisitos da vaga.

### 17.2 Pré-checagem no cliente

Antes de chamar o backend, o app verifica se o usuário tem dados suficientes. Se o perfil estiver vazio demais, o app evita chamar uma função cara que provavelmente retornaria erro.

### 17.3 Fluxo visual

O fluxo inclui:

1. seleção da vaga;
2. confirmação de skills quando necessário;
3. chamada de adaptação;
4. loading com mensagens;
5. resultado;
6. preview editável;
7. comparação original/adaptado;
8. troca de template;
9. aprovação e download;
10. salvamento na biblioteca.

### 17.4 Edge Function `adapt-resume-to-job`

A função tem uma pipeline com:

- modelo de draft;
- possível refinamento;
- prompt versionado;
- cache em `adapted_resumes`;
- hash de fonte;
- rate limit diário;
- validação anti-invenção;
- quality score;
- persistência do resultado.

O código indica uso de `gpt-4o-mini` para draft e `gpt-4o` para refinamento opcional.

### 17.5 Caminho v2

Há uma versão v2 atrás de feature flag `adapt_v2_enabled`, com prompt `v15-v2`. Ela usa perfil relacional, detecta densidade do perfil, valida preservação de dados importantes e tenta retry em caso de falha de validação.

### 17.6 Erros tratados

O cliente trata erros estruturados:

- perfil incompleto;
- rate limit;
- adaptação rejeitada;
- resposta de IA inválida;
- vaga não encontrada;
- usuário não autorizado;
- timeout;
- erro de rede.

### 17.7 Preview e edição

O `AdaptedResumePreviewScreen` é importante porque não baixa automaticamente o resultado. O usuário revisa, edita e só então aprova. Isso reduz risco de uma adaptação inadequada ser usada sem controle humano.

## 18. Ingestão e gestão de vagas

### 18.1 Tabelas principais

As vagas usam tabelas como:

- `companies`;
- `jobs`;
- `swipe_actions`;
- `external_job_sources`;
- `match_analyses`;
- `adapted_resumes`;
- `jobs_skill_extraction`.

### 18.2 Sincronização ATS

A função `sync-jobs-ats` busca fontes externas ativas e usa adapters como Greenhouse e Lever. Ela tem orçamento de tempo, marca vagas antigas como inativas e registra evento de conclusão.

### 18.3 Sincronização Apify/Gupy

A função `sync-jobs-apify` usa scraper Gupy via Apify. Ela filtra Brasil, mapeia tipos de vaga/modelo de trabalho, aplica blacklist de alguns casos operacionais/massificados e preserva HTML de descrição.

### 18.4 Outras funções de vagas

Há funções e scripts relacionados a:

- ingestão por email;
- sincronização Brasil;
- extração de skills de vaga;
- cron/schedule de jobs.

## 19. Notificações

### 19.1 Cliente

O app inicializa OneSignal sem pedir permissão imediatamente. O prompt é acionado depois de o usuário entrar na home, reduzindo interrupção no onboarding.

### 19.2 Digest diário

A função `notifications-daily-digest` envia push em janela D+1, considerando situações como:

- usuário com currículo adaptado pendente de exportação;
- fase concluída;
- novas vagas.

### 19.3 Broadcast

A função `notifications-broadcast` envia mensagens para segmentos OneSignal, com suporte a título, mensagem, dados e dry run. Também registra eventos de envio.

## 20. Analytics e observabilidade

### 20.1 PostHog

O app usa PostHog para:

- eventos de produto;
- identificação de usuário;
- session replay;
- feature flags;
- eventos de lifecycle;
- eventos de tela;
- tracking de onboarding, auth, vagas e currículo;
- captura manual de exceções.

### 20.2 Session replay e PII

O session replay é configurado com cuidado e há componentes de máscara de PII. Isso é relevante porque o app manipula currículos, emails, telefones e dados profissionais.

### 20.3 Facebook App Events

O app usa Facebook App Events para eventos como cadastro concluído e visualização de conteúdo. Também há tratamento de App Tracking Transparency antes de certas interações.

### 20.4 Logs server-side

O backend registra:

- logs de geração de IA;
- logs de extração de perfil;
- eventos PostHog server-side;
- logs de sincronização;
- logs de admin;
- relatórios diários.

### 20.5 Error tracking

Erros Flutter, erros de plataforma e erros em zonas assíncronas são enviados para o serviço de analytics como exceções, com contexto de tela/evento/sessão.

## 21. Feature flags e configuração remota

### 21.1 App config

A tabela `app_config` guarda configuração como versão mínima suportada.

### 21.2 Feature flags locais

A tabela `app_feature_flags` permite ligar/desligar recursos e rollouts. O app usa essas flags para partes como templates v2 e adaptação v2.

### 21.3 PostHog flags

Também há uso de flags do PostHog, por exemplo para controlar a versão de match com IA.

## 22. Dashboard admin

### 22.1 Objetivo

O dashboard admin transforma o Stage em uma operação com capacidade comercial. Ele permite que administradores monitorem a base, gerenciem vagas e criem listas de candidatos para demandas de empresas.

### 22.2 Autenticação admin

O admin usa Supabase Auth para sessão, mas a autorização real depende da tabela `admin_users`. A função `_shared/admin.ts` valida:

- header Authorization;
- sessão Supabase válida;
- email ativo em `admin_users`;
- role `owner` ou `analyst`;
- owner-only quando necessário.

As funções administrativas usam service role no backend, não no cliente.

### 22.3 Auditoria

As ações admin gravam em `admin_audit_log`, com:

- email do admin;
- ação;
- tipo de entidade;
- ID de entidade;
- metadata;
- IP;
- user agent.

### 22.4 Overview

A página de overview mostra KPIs:

- usuários totais;
- perfis completos;
- vagas ativas;
- vagas totais;
- likes;
- aplicações;
- currículos adaptados;
- consentimentos concedidos;
- consentimentos pendentes;
- taxa de completude;
- taxa de aplicação.

Também exibe séries recentes e gráficos por área/fonte.

### 22.5 Vagas

A página de vagas permite:

- buscar por cargo, descrição ou empresa;
- filtrar status;
- ver detalhes;
- ver métricas de likes/aplicações;
- criar lista de candidatos a partir de uma vaga.

### 22.6 Usuários/candidatos

A página de usuários permite:

- buscar por nome, email ou curso;
- filtrar por skill;
- filtrar por consentimento;
- abrir detalhe;
- revelar PII sob ação explícita;
- atualizar consentimento comercial;
- ver skills e cargos desejados.

### 22.7 Empresas

A página de clientes permite cadastrar e gerenciar empresas B2B.

### 22.8 Listas de candidatos

A página de listas permite:

- criar uma demanda;
- associar cliente;
- usar vaga existente ou preencher título/área/requisitos;
- definir score mínimo;
- gerar ranking;
- revisar candidatos;
- aprovar ou rejeitar candidatos;
- exportar CSV.

### 22.9 Ranking B2B

A função `admin-candidate-lists` monta perfis de candidatos e calcula score considerando:

- cargo/título;
- skills;
- localidade;
- modelo de trabalho;
- tipo de vaga;
- prontidão/completude;
- sinais de atividade como likes/aplicações.

Só candidatos exportáveis e com consentimento adequado entram na exportação final.

## 23. Banco de dados e persistência

### 23.1 Categorias de tabelas

O banco se organiza em algumas famílias:

- conteúdo da trilha;
- progresso do usuário;
- perfil legado;
- perfil relacional;
- currículos;
- vagas e empresas;
- swipes e aplicações;
- análises de match;
- adaptações de currículo;
- configurações e feature flags;
- logs;
- notificações;
- administração B2B.

### 23.2 Tabelas legadas/base

Incluem:

- `tracks`;
- `phases`;
- `questions`;
- `user_answers`;
- `raw_responses`;
- `user_progress`;
- `user_profiles`;
- `saved_resumes`;
- `ai_generation_logs`;
- `security_audit_log`.

### 23.3 Campanhas

Há tabelas:

- `target_jobs`;
- `campaigns`.

O app usa existência de campanha como um sinal de onboarding completo.

### 23.4 Vagas

Incluem:

- `companies`;
- `jobs`;
- `swipe_actions`;
- `user_preferences`;
- `external_job_sources`;
- `match_analyses`;
- `adapted_resumes`;
- `jobs_skill_extraction`.

### 23.5 Perfil relacional

As tabelas `profile_*` são o núcleo novo do perfil.

### 23.6 Admin/B2B

Incluem:

- `admin_users`;
- `employer_clients`;
- `candidate_list_requests`;
- `candidate_data_sharing_consents`;
- `candidate_list_items`;
- `candidate_list_exports`;
- `admin_audit_log`.

### 23.7 Storage

O bucket principal identificado para currículos é `resumes`. Ele guarda PDFs importados, gerados e adaptados.

## 24. Segurança, privacidade e LGPD

### 24.1 RLS

As migrations criam políticas RLS para impedir que usuários vejam ou alterem dados de outros usuários. Tabelas de perfil têm políticas próprias por usuário.

### 24.2 Service role isolada

Operações administrativas e funções sensíveis usam service role apenas no servidor. O cliente admin chama Edge Functions autenticadas, não acessa o service role diretamente.

### 24.3 Validação de documentos

O app tenta evitar ingestão acidental de documentos sensíveis que não sejam currículos. Isso é essencial porque o produto trabalha com upload de PDFs.

### 24.4 PII no analytics

Há preocupação explícita com máscara de PII em session replay. Ainda assim, como o produto manipula currículos, qualquer novo evento deve ser revisado para não enviar dados pessoais desnecessários.

### 24.5 Consentimento B2B

O dashboard inclui `candidate_data_sharing_consents`. Isso mostra que compartilhamento comercial de dados de candidatos é tratado como estado próprio, não como permissão implícita.

### 24.6 Revelação de PII no admin

No dashboard, o detalhe de usuário permite revelar PII por ação explícita. Isso ajuda a reduzir exposição casual.

### 24.7 Auditoria admin

Ações administrativas são registradas. Isso é importante para rastreabilidade em contexto B2B e dados pessoais.

### 24.8 App Tracking Transparency

O app posterga certas permissões e integra ATT no fluxo. Isso é relevante para conformidade em iOS.

### 24.9 Anti-invenção em IA

As funções de extração e adaptação têm validações para reduzir invenção de dados. Em currículo, isso é crítico: o sistema não deve criar experiências, cursos, títulos ou habilidades falsas.

## 25. IA no produto

### 25.1 Usos principais de IA

A IA aparece em:

- extração de perfil a partir de PDF;
- geração de currículo;
- geração de perfil/bullets/resumos;
- análise de match;
- adaptação de currículo;
- sugestão de ferramentas/skills;
- extração de skills de vagas;
- parsing alternativo de CV.

### 25.2 Estratégia de segurança da IA

O app tende a usar IA no servidor com:

- prompts versionados;
- schemas;
- pós-processamento;
- validação;
- cache;
- rate limit;
- logs;
- fallback;
- feature flags.

### 25.3 Modelos identificados

Modelos mencionados no código:

- `gpt-4o` para extração e geração de currículo;
- `gpt-4o-mini` para análise de match e drafts de adaptação;
- `gpt-4o` como refinamento opcional em adaptação.

### 25.4 Cache

Há cache para:

- match em `match_analyses`;
- adaptação em `adapted_resumes`;
- conteúdo de currículo/perfil localmente via SharedPreferences;
- extração de perfil por versão/fonte.

### 25.5 Rate limits

Há rate limits em funções como:

- análise de match;
- adaptação de currículo.

No caso de `generate-resume`, o código indica que rate limiting está comentado/desabilitado em desenvolvimento, o que deve ser revisado antes de produção se ainda estiver assim.

## 26. Qualidade e testes

### 26.1 Testes Flutter atuais

Os testes automatizados presentes estão concentrados em educação/perfil:

- serialização/deserialização de `Education`;
- comportamento do modal de edição de educação para faculdade/escola.

Isso cobre uma parte importante do modelo novo, mas ainda é pouco diante do tamanho do produto.

### 26.2 Golden set

O `golden_set` é uma estratégia específica para qualidade de extração de currículo. Ele é mais relevante do que um teste unitário simples porque valida comportamento de IA contra PDFs reais anonimizados.

### 26.3 Áreas que merecem mais testes

Áreas de alto risco que merecem mais cobertura:

- importação de CV;
- validação de documentos não-CV;
- `ProfileSnapshotService`;
- renderização de currículo;
- fallback de templates;
- cálculo determinístico de match;
- adaptação de currículo;
- permissões/RLS críticas;
- funções admin de exportação;
- consentimento B2B;
- sync de vagas;
- fluxo de auth/linking;
- VersionGate.

## 27. Pontos fortes do projeto

### 27.1 Produto com fluxo completo

O app não para em "gerar currículo". Ele conecta perfil, currículo, vaga, match, adaptação e aplicação. Essa cadeia aumenta valor real para o usuário.

### 27.2 Dados estruturados

O movimento para tabelas relacionais `profile_*` é tecnicamente importante. Ele melhora query, admin, matching, ranking B2B e evolução do produto.

### 27.3 Boa separação de IA sensível

Chamadas de IA ficam em Edge Functions, não no cliente. Isso protege chaves e permite controle de logs, rate limit e validação.

### 27.4 Feature flags

Feature flags permitem rollout gradual de templates, match e adaptação.

### 27.5 Cuidado com CV e PII

Há validação de documentos, máscara de PII, consentimento B2B e auditoria admin.

### 27.6 Operação B2B em construção

O dashboard admin mostra que o produto está evoluindo para uma plataforma com monetização/operacao por empresas.

### 27.7 Fallbacks

Várias partes têm fallback: versão mínima fail-open, perfil legado vs relacional, match determinístico vs IA, extração com texto fallback, renderização v1/v2.

## 28. Riscos e dívidas técnicas

### 28.1 README ainda genérico

O README principal ainda parece scaffold padrão do Flutter. Para um projeto deste tamanho, isso aumenta custo de onboarding de novos devs.

### 28.2 Fluxo de telefone sem OTP real

O cadastro por telefone usa email sintético. Se o produto comunicar "login por telefone" como identidade confiável, precisa de OTP/SMS ou outro mecanismo de verificação.

### 28.3 Cobertura de testes pequena

Existem poucos testes Flutter em relação ao tamanho e criticidade do app. A parte de IA tem golden set, mas muitos fluxos client-side e server-side ainda parecem depender de validação manual.

### 28.4 Complexidade de dual-write

Manter perfil legado e perfil relacional ao mesmo tempo é pragmático, mas aumenta risco de divergência. O código precisa continuar claro sobre qual fonte é autoritativa em cada fluxo.

### 28.5 IA com prompts e validações complexas

O uso de IA é poderoso, mas aumenta superfície de regressão. Prompts versionados e golden set ajudam, mas adaptação e extração ainda exigem monitoramento constante.

### 28.6 Admin/B2B ainda recente

O dashboard admin e funções B2B aparecem como parte nova/untracked no workspace atual. Isso pode indicar trabalho em progresso. Antes de produção, precisa de revisão forte de permissões, exportação, consentimento e auditoria.

### 28.7 Geração de currículo com rate limit desabilitado

O código sugere que rate limit em `generate-resume` está comentado/desabilitado em dev. Se isso estiver igual em produção, há risco de custo e abuso.

### 28.8 Ingestão de vagas depende de fontes externas

Scrapers e ATS externos são frágeis. Mudanças em Gupy, Apify, Greenhouse ou Lever podem quebrar mapeamentos ou reduzir qualidade de vagas.

### 28.9 App muito dependente de Supabase

Supabase concentra auth, banco, storage e functions. Isso simplifica operação, mas aumenta impacto de instabilidade ou configuração incorreta.

## 29. Fluxos técnicos detalhados

### 29.1 Bootstrap técnico

1. `main.dart` inicializa Flutter.
2. Carrega `.env`.
3. Inicializa Supabase.
4. Configura PostHog.
5. Inicializa feature flags e serviços globais.
6. Inicializa OneSignal/Facebook.
7. Cria Providers.
8. Renderiza `MaterialApp`.
9. `VersionGate` decide se versão é permitida.
10. `SplashScreen` executa animação.
11. `AuthGate` decide rota.

### 29.2 Cadastro e identificação

1. Usuário escolhe Google, Apple ou telefone.
2. Supabase cria/retorna sessão.
3. `UserViewModel` carrega perfil.
4. App identifica usuário no PostHog.
5. App associa usuário no OneSignal.
6. App emite eventos de auth/cadastro.
7. AuthGate envia para onboarding ou home.

### 29.3 Importação de currículo

1. Usuário escolhe importar.
2. `FilePicker` retorna PDF.
3. `ResumePdfExtractor` extrai texto.
4. `CvContentValidator` valida documento.
5. Arquivo vai para Storage.
6. `saved_resumes` recebe registro.
7. Texto bruto vai para `user_profiles.gamification_data`.
8. `extract-profile` roda em background.
9. Backend chama IA.
10. Backend salva legado e relacional.
11. App atualiza status de extração/perfil.

### 29.4 Construção pela trilha

1. Usuário escolhe trilha.
2. App carrega tracks/phases/questions.
3. Usuário responde perguntas.
4. Respostas são salvas.
5. Progresso é atualizado.
6. Ao completar fluxo, app cria target/campaign.
7. Perfil e currículo ficam habilitados.

### 29.5 Feed de vagas

1. `JobsSwipeScreen` chama `JobsViewModel.init()`.
2. Repositório busca vagas ativas.
3. Vagas já swipadas são excluídas.
4. Preferências são aplicadas.
5. Cards são montados.
6. Match é pré-carregado.
7. Usuário curte ou descarta.
8. Ação é salva em `swipe_actions`.
9. Likes aparecem na aba Salvas.

### 29.6 Match com IA

1. Cliente pede análise.
2. Edge Function autentica usuário.
3. Carrega vaga.
4. Carrega perfil/preferências.
5. Gera hash de perfil.
6. Verifica cache.
7. Se necessário, chama modelo.
8. Valida/deriva score.
9. Salva em `match_analyses`.
10. Retorna score e explicações.

### 29.7 Adaptação de currículo

1. Usuário abre adaptação em uma vaga.
2. Cliente verifica perfil mínimo.
3. Usuário confirma skills se necessário.
4. Cliente chama `adapt-resume-to-job`.
5. Backend carrega perfil, vaga e currículo.
6. Verifica cache/rate limit.
7. Gera draft.
8. Valida anti-invenção.
9. Refina ou tenta retry se aplicável.
10. Salva em `adapted_resumes`.
11. Cliente abre preview.
12. Usuário edita/aprova.
13. PDF é gerado.
14. Currículo adaptado é salvo em `saved_resumes`.

### 29.8 Admin: lista de candidatos

1. Admin loga no dashboard.
2. Edge Function valida sessão e `admin_users`.
3. Admin cria lista com vaga existente ou requisitos manuais.
4. Backend cria `candidate_list_requests`.
5. Admin clica gerar.
6. Backend monta perfis de candidatos.
7. Score de ranking é calculado.
8. Itens são salvos em `candidate_list_items`.
9. Admin aprova/rejeita.
10. Exportação CSV só inclui candidatos permitidos/exportáveis.
11. Ação é auditada.

## 30. Funções Supabase relevantes

Funções identificadas por finalidade:

- `extract-profile`: extração estruturada de currículo;
- `generate-resume`: geração de currículo;
- `generate-profile`: geração de perfil;
- `generate-bullets`: geração de bullets;
- `generate-summary`: geração de resumo;
- `suggest-tools`: sugestão de ferramentas;
- `extract-job-skills`: extração de skills de vaga;
- `analyze-match`: análise de compatibilidade;
- `adapt-resume-to-job`: adaptação de currículo;
- `parse-cv`: parser alternativo/rollback;
- `parse-cv-pdf`: parser de PDF;
- `sync-jobs-ats`: sincronização ATS;
- `sync-jobs-apify`: sincronização Gupy/Apify;
- `sync-jobs-brazil`: sincronização Brasil;
- `ingest-jobs-email`: ingestão por email;
- `notifications-daily-digest`: digest de push;
- `notifications-broadcast`: broadcast push;
- `notify-signup`: notificação de cadastro;
- `daily-report`: relatório diário;
- `admin-me`: dados do admin atual;
- `admin-overview`: KPIs;
- `admin-users`: usuários/candidatos;
- `admin-jobs`: vagas;
- `admin-clients`: empresas/clientes;
- `admin-candidate-lists`: listas/ranking/exportação;
- `admin-audit`: auditoria.

## 31. Arquivos e diretórios importantes

### 31.1 App Flutter

- `lib/main.dart`: bootstrap do app.
- `lib/screens`: telas principais.
- `lib/viewmodels`: estado de telas e fluxos.
- `lib/services`: integrações e regras transversais.
- `lib/repositories`: acesso a Supabase e persistência.
- `lib/features/profile`: domínio/presentação/repositório do perfil novo.
- `lib/models.dart`: modelos da trilha gamificada.
- `lib/theme`: tema visual.

### 31.2 Backend Supabase

- `supabase/migrations`: schema, RLS, funções SQL e tabelas.
- `supabase/functions`: Edge Functions.
- `supabase/functions/_shared`: módulos compartilhados.
- `supabase/functions/_shared/profile_schema.ts`: schema de perfil.
- `supabase/functions/_shared/admin.ts`: autenticação/autorização admin.

### 31.3 Dashboard admin

- `admin_dashboard/src/app`: shell, auth, layout e login.
- `admin_dashboard/src/features/overview`: KPIs.
- `admin_dashboard/src/features/jobs`: vagas.
- `admin_dashboard/src/features/users`: candidatos.
- `admin_dashboard/src/features/clients`: empresas.
- `admin_dashboard/src/features/candidate-lists`: listas de candidatos.
- `admin_dashboard/src/lib/api.ts`: invocação de Edge Functions admin.

### 31.4 Qualidade de IA

- `golden_set/README.md`;
- `golden_set/scripts/run_extraction.ts`;
- `golden_set/scripts/compare.ts`;
- `golden_set/scripts/bootstrap_ground_truth.ts`.

## 32. Métricas de produto implícitas

O código e o dashboard sugerem que o time acompanha ou pretende acompanhar:

- total de usuários;
- perfis completos;
- vagas ativas;
- total de vagas;
- likes;
- aplicações;
- currículos adaptados;
- consentimentos concedidos;
- consentimentos pendentes;
- taxa de completude;
- taxa de aplicação;
- atividade recente por dia;
- vagas por área;
- vagas por fonte;
- score médio de vagas;
- ranking de candidatos;
- exportações B2B.

Essas métricas indicam uma lógica de funil:

1. cadastro;
2. perfil completo;
3. consumo de vagas;
4. like;
5. aplicação;
6. adaptação de currículo;
7. consentimento/uso B2B.

## 33. Possível narrativa comercial

Uma forma simples de explicar o Stage para usuários finais:

"O Stage te ajuda a transformar sua trajetória em um currículo profissional e encontrar vagas que combinam com você. Você pode importar seu currículo ou construir seu perfil por uma trilha guiada. Depois, o app mostra vagas, explica seu match e adapta seu currículo para cada oportunidade."

Uma forma simples de explicar para empresas:

"O Stage estrutura perfis de talentos em início de carreira, mede sinais de interesse e compatibilidade com vagas, e permite gerar listas ranqueadas de candidatos com consentimento para contato."

Uma forma simples de explicar para investidores/parceiros:

"O Stage combina aquisição B2C com infraestrutura B2B de matching. O app cria valor para candidatos por meio de currículo, IA e vagas; o dashboard transforma esses perfis e sinais em operação comercial para empregadores."

## 34. Recomendações de documentação

### 34.1 README principal

O README deveria explicar:

- o que é o Stage;
- como rodar o Flutter app;
- como configurar `.env`;
- como rodar Supabase local/remoto;
- como deployar Edge Functions;
- como rodar o dashboard admin;
- como rodar testes;
- como rodar golden set;
- arquitetura em uma página;
- principais variáveis de ambiente;
- cuidados com chaves e PII.

### 34.2 Documento de arquitetura

Seria útil ter um documento separado com:

- diagrama Flutter/Supabase/Functions/Admin;
- fluxo de importação de CV;
- fluxo de adaptação;
- modelo de dados de perfil;
- estratégia legado vs relacional;
- regras de RLS.

### 34.3 Runbooks

Runbooks recomendados:

- falha em `extract-profile`;
- aumento de custo OpenAI;
- falha em sync de vagas;
- vazamento/rotação de service role;
- revisão de exportação B2B;
- rollback de prompt;
- rollback de feature flag.

## 35. Recomendações técnicas prioritárias

### 35.1 Fortalecer testes dos fluxos críticos

Prioridade para:

- validação de CV;
- ProfileSnapshot;
- match determinístico;
- renderização de currículo;
- adaptação com mocks;
- admin export/consent;
- auth gate.

### 35.2 Formalizar fonte autoritativa de perfil

Enquanto legado e relacional coexistem, documentar qual fonte manda em:

- geração de currículo;
- adaptação;
- match;
- dashboard;
- edição manual;
- importação.

### 35.3 Revisar telefone

Decidir se telefone é apenas dado de contato ou fator de login confiável. Se for login confiável, implementar OTP.

### 35.4 Revisar rate limits

Garantir rate limits ativos em todas as funções com custo de IA.

### 35.5 Checklist de privacidade para eventos

Criar regra simples: nenhum evento deve enviar texto bruto de currículo, telefone, email, endereço ou descrição pessoal detalhada sem necessidade explícita.

### 35.6 Documentar operações admin

Antes de uso B2B real, documentar:

- quem pode exportar;
- quando candidato entra em CSV;
- como consentimento é obtido;
- como revogação afeta exportações;
- como auditar acesso a PII.

## 36. Conclusão

O Stage é um app de carreira com uma arquitetura relativamente ambiciosa. Ele combina uma experiência mobile voltada ao candidato com backend robusto em Supabase, uso intenso de IA, dados estruturados de perfil, ingestão de vagas, analytics e uma camada admin/B2B.

O núcleo do produto é o perfil profissional estruturado. Tudo orbita esse ativo: currículo, match, adaptação, feed, ranking B2B e analytics. A importação de currículo e a trilha gamificada são duas estratégias diferentes para construir esse perfil. A adaptação de currículo e o match são as funcionalidades que transformam o perfil em ação prática.

Do ponto de vista técnico, os acertos mais importantes são manter IA no servidor, usar perfil relacional, aplicar RLS, ter feature flags, ter validações anti-invenção e começar a medir qualidade de extração com golden set. Os principais riscos estão em cobertura de testes, complexidade legado/relacional, consentimento B2B, rate limits de IA e documentação operacional.

Em resumo: o app já tem base para ser explicado como uma plataforma completa de carreira e matching. Ele não é apenas uma interface gamificada; é um sistema com coleta estruturada de dados, inteligência aplicada, geração documental, descoberta de oportunidades e ferramentas de operação para conectar candidatos a empresas.
