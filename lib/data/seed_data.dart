import 'models/models.dart';

class SeedData {
  static List<Track> getTracks() {
    return [
      Track(
        id: 'track_1',
        title: 'Direção',
        description: 'Sua direção profissional.',
        color: 0xFF4F46E5, // Indigo
        iconAsset: 'assets/icons/user.svg',
        orderIndex: 1,
      ),
      Track(
        id: 'track_2',
        title: 'Minha Base',
        description: 'Formação Acadêmica e Conquistas.',
        color: 0xFF06B6D4, // Cyan
        iconAsset: 'assets/icons/briefcase.svg',
        orderIndex: 2,
      ),
      Track(
        id: 'track_3',
        title: 'Minhas Experiências',
        description: 'Ferramentas, soft skills e idiomas.',
        color: 0xFFF97316, // Orange
        iconAsset: 'assets/icons/book.svg',
        orderIndex: 3,
      ),
      Track(
        id: 'track_4',
        title: 'Hard Skills & Idiomas',
        description: 'Mapeie suas ferramentas e línguas.',
        color: 0xFF10B981, // Emerald
        iconAsset: 'assets/icons/flag.svg',
        orderIndex: 4,
      ),
      // TRACK 5: Links & Logística
      Track(
        id: 'track_5',
        title: 'Links & Logística',
        description: 'Conecte seu perfil ao mercado e organize os detalhes finais.',
        color: 0xFF8B5CF6, // Violet (retained from original track_5)
        iconAsset: 'assets/images/icons/rocket.png',
        orderIndex: 5,
      ),
    ];
  }

  static List<Phase> getPhases() {
    return [
      // --- MUNDO 1: Direção ---
      Phase(id: 't1_p3', trackId: 'track_1', orderIndex: 1, title: 'Direção', description: 'Área, tipo de vaga e norte profissional.', xpReward: 100),

      // --- MUNDO 2 ---
      Phase(id: 't2_p1', trackId: 'track_2', orderIndex: 1, title: 'Minha Guilda', description: 'Formação acadêmica completa.', xpReward: 120),
      Phase(id: 't2_p2', trackId: 'track_2', orderIndex: 2, title: 'Cursos', description: 'Cursos e certificações externas.', xpReward: 120),
      Phase(id: 't2_p3', trackId: 'track_2', orderIndex: 3, title: 'Medalhas de Honra', description: 'Conquistas acadêmicas.', xpReward: 120),

      // --- MUNDO 3 ---
      Phase(id: 't3_p1', trackId: 'track_3', orderIndex: 1, title: 'O Ponto de Partida', description: 'Valide suas vivências.', xpReward: 150),
      Phase(id: 't3_p2', trackId: 'track_3', orderIndex: 2, title: 'Atividades', description: 'Atividades extracurriculares.', xpReward: 150),
      // Phase 4 removed as requested

      // --- MUNDO 4 (ATUALIZADO) ---
      Phase(id: 't4_p1', trackId: 'track_4', orderIndex: 1, title: 'Minhas Ferramentas Técnicas', description: 'O que você domina.', xpReward: 180),
      Phase(id: 't4_p2', trackId: 'track_4', orderIndex: 2, title: 'Idiomas', description: 'Línguas e fluência.', xpReward: 180),

      // --- MUNDO 5 ---
      // --- MUNDO 5 (ATUALIZADO): Links & Logística ---
      Phase(id: 't5_p1', trackId: 'track_5', orderIndex: 1, title: 'Presença Digital', description: 'Seus perfis profissionais.', xpReward: 200),
      Phase(id: 't5_p2', trackId: 'track_5', orderIndex: 2, title: 'Logística Final', description: 'Detalhes importantes.', xpReward: 200),
    ];
  }

  static List<Question> getQuestions() {
    return [
      // ... (Existing questions omitted for brevity, keeping only Secret World updates below)

      // --- M1: Direção (3 etapas) ---
      Question(id: 'M1_3_1_Q2', phaseId: 't1_p3', type: QuestionType.dynamicList, content: 'Em qual área você quer focar agora? (Selecione até 2)', options: ['Vendas & Novos Negócios', 'Marketing & Branding', 'Finanças & Controladoria', 'Venture Capital & Private Equity', 'Administração & Processos', 'Tecnologia & Programação', 'Dados & Business Intelligence', 'Produto & UX Design', 'Recursos Humanos & Cultura', 'Operações & Logística', 'Consultoria Estratégica', 'Ainda estou explorando / Aberto a oportunidades']),
      Question(id: 'M1_3_1_Q25', phaseId: 't1_p3', type: QuestionType.multipleChoice, content: 'Que tipo de oportunidade você está buscando agora?', options: ['Estágio', 'Trainee', 'Primeiro emprego (CLT)', 'Estágio internacional ou intercâmbio com trabalho', 'Freelance / projetos pontuais', 'Ainda explorando']),
      Question(id: 'M1_3_1_Q3', phaseId: 't1_p3', type: QuestionType.text, content: 'Pensando nos próximos 2-3 anos, o que você quer construir profissionalmente?', options: ['Ex: quero entrar em uma empresa de tecnologia que valorize desenvolvimento técnico e crescer em produtos digitais...']),

      // --- M2.1: Minha Guilda (formulário único) ---
      Question(id: 'M2_1_1_Q1', phaseId: 't2_p1', type: QuestionType.academicForm, content: 'Me conta sobre a sua formação acadêmica.', options: []),
      Question(id: 'M2_1_1_Q2', phaseId: 't2_p1', type: QuestionType.binaryChoice, content: 'Além da sua formação atual, você tem outra bagagem acadêmica?', options: []),
      Question(id: 'M2_1_1_Q3', phaseId: 't2_p1', type: QuestionType.retroIdCard, content: 'Onde você estudou e qual foi o curso?', options: []),

      // --- M2.2: Cursos (movidos de M3) ---
      Question(id: 'M3_2_1_Q1', phaseId: 't2_p2', type: QuestionType.binaryChoice, content: 'Além da formação acadêmica, você fez algum curso com certificação?', options: ['Sim, investi em cursos', 'Não, foquei em outras experiências']),
      Question(id: 'M3_2_1_Q2', phaseId: 't2_p2', type: QuestionType.learningVault, content: 'Quais são as conquistas da sua estante de aprendizado?', options: []),

      // --- M2.3: Medalhas de Honra ---
      Question(id: 'M2_3_1_Q1', phaseId: 't2_p3', type: QuestionType.rewardCardSelect, content: 'Você conquistou alguma bolsa de estudos por mérito?', options: ['Sim, 100%', 'Sim, Parcial', 'Não']),
      Question(id: 'M2_3_1_Q4', phaseId: 't2_p3', type: QuestionType.yesNoWithDetail, content: 'Algum professor já te deu um destaque ou você ganhou algum prêmio acadêmico?', options: []),

      // --- M3.1: O Ponto de Partida ---
      Question(
        id: 'M3_1_1_Q1',
        phaseId: 't3_p1',
        type: QuestionType.experienceTypeSelect,
        content: 'Qual dessas experiências você já realizou (mesmo que sem carteira assinada)?',
        options: [
          '{"id": "corporate", "label": "Experiência Corporativa", "description": "Estágios ou empregos com contrato formal.", "icon": "business"}',
          '{"id": "startup", "label": "Startup ou Venture Própria", "description": "Criei meu próprio negócio, app ou projeto.", "icon": "rocket_launch"}',
          '{"id": "freelance", "label": "Freelance ou \\"Bicos\\"", "description": "Serviços autônomos e projetos extras.", "icon": "handshake"}',
          '{"id": "social", "label": "Voluntariado ou Social", "description": "Impacto em ONGs ou comunidades.", "icon": "volunteer_activism"}',
          '{"id": "other", "label": "Outro", "description": "Algo diferente que também conta.", "icon": "edit"}',
          '{"id": "none", "label": "Buscando a primeira experiência", "description": "Ainda não tive vivências práticas.", "icon": "school"}'
        ]
      ),
      Question(id: 'M3_1_1_Q2', phaseId: 't3_p1', type: QuestionType.experienceForm, content: 'Conte mais sobre essa experiência!', options: []),

      // --- M3.2: Atividades extracurriculares (movidas de M2) ---
      Question(
        id: 'M2_3_1_Q2',
        phaseId: 't3_p2',
        type: QuestionType.activitiesGrid,
        content: 'Além das aulas, você realizou alguma dessas atividades?',
        options: [
          '{"id": "ligas", "label": "Ligas", "icon": "groups", "detailTitle": "Qual foi a Liga? (Ex: Tech, Marketing...)", "reflectiveTitle": "Qual foi seu papel e sua maior entrega lá?"}',
          '{"id": "lodges", "label": "Lodges", "icon": "public", "detailTitle": "Para qual destino você foi?", "reflectiveTitle": "Qual foi o maior aprendizado dessa imersão?"}',
          '{"id": "startup_school", "label": "Startup School", "icon": "rocket_launch", "detailTitle": "Qual era o nome do projeto/startup?", "reflectiveTitle": "Qual marco você atingiu (MVP, Venda, Pitch)?"}',
          '{"id": "esportes", "label": "Esportes", "icon": "sports_soccer", "detailTitle": "Qual modalidade?", "reflectiveTitle": "Como essa disciplina ajuda você no trabalho?"}',
          '{"id": "outros", "label": "Outros", "icon": "star", "detailTitle": "Qual o nome da iniciativa?", "reflectiveTitle": "O que exatamente você desenvolveu nesse projeto?"}',
          '{"id": "none", "label": "Não participei", "icon": "block", "detailTitle": "", "reflectiveTitle": ""}'
        ]
      ),




      // --- M4.1: Ferramentas (chip + nível inline) ---
      Question(
        id: 'M4_1_1_Q1',
        phaseId: 't4_p1',
        type: QuestionType.toolsCatalog,
        content: 'Quais dessas áreas você domina? Selecione e escolha seu nível.',
        options: [
          'Pacote Office / Administrativo',
          'Design & Criatividade',
          'Programação & Tech',
          'Dados & Análise',
          'Redes Sociais & Marketing',
          'Gestão de Projetos',
          'Vendas & Negociação',
          'Outros',
        ],
      ),

      // --- M4.2: Idiomas ---
      Question(id: 'M4_2_1_Q1', phaseId: 't4_p2', type: QuestionType.badgeMultiSelect, content: 'Além do Português, quais idiomas você domina ou está estudando?', options: ['Inglês', 'Espanhol', 'Francês', 'Alemão', 'Japonês', 'Outro']),
      Question(id: 'M4_2_1_Q2', phaseId: 't4_p2', type: QuestionType.stepSlider, content: 'Qual é o seu nível de conhecimento em {language}?', options: ['Básico', 'Intermediário', 'Avançado', 'Fluente']),
      Question(id: 'M4_2_1_Q4', phaseId: 't4_p2', type: QuestionType.yesNoWithDetail, content: 'Você possui alguma certificação oficial (como TOEFL, IELTS ou Cambridge)?', options: []),

      // --- M5.1: Presença Digital (formulário único) ---
      Question(id: 'M5_1_1_Q1', phaseId: 't5_p1', type: QuestionType.contactForm, content: 'Vamos conectar você ao mercado. Preencha seus dados de contato.', options: []),

      // --- M5.2: Logística Final ---
      Question(id: 'M5_2_1_Q1', phaseId: 't5_p2', type: QuestionType.cityStateInput, content: 'Onde você mora atualmente? (Cidade e Estado)', options: []),
      Question(id: 'M5_2_1_Q2', phaseId: 't5_p2', type: QuestionType.licenseSelect, content: 'Você possui Carteira de Habilitação (CNH)?', options: []),
    ];
  }
}
