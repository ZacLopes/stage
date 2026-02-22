import 'models/models.dart';

class SeedData {
  static List<Track> getTracks() {
    return [
      Track(
        id: 'track_1',
        title: 'Quem eu sou',
        description: 'Meu momento, estilo e valores.',
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
      // --- MUNDO 1 (ATUALIZADO) ---
      Phase(id: 't1_p1', trackId: 'track_1', orderIndex: 1, title: 'Meus Pontos Fortes', description: 'Descubra seus talentos naturais.', xpReward: 100),
      Phase(id: 't1_p2', trackId: 'track_1', orderIndex: 2, title: 'Minha cultura e trabalho', description: 'Onde você brilha mais.', xpReward: 100),
      Phase(id: 't1_p3', trackId: 'track_1', orderIndex: 3, title: 'Minha Bússola', description: 'Motivação e Objetivos.', xpReward: 100),

      // --- MUNDO 2 (ATUALIZADO) ---
      Phase(id: 't2_p1', trackId: 'track_2', orderIndex: 1, title: 'Minha Guilda', description: 'Instituição e Curso.', xpReward: 120),
      Phase(id: 't2_p2', trackId: 'track_2', orderIndex: 2, title: 'Datas e Logística', description: 'Cronograma do curso.', xpReward: 120),
      Phase(id: 't2_p3', trackId: 'track_2', orderIndex: 3, title: 'Medalhas de Honra', description: 'Conquistas acadêmicas.', xpReward: 120),


      // --- MUNDO 3 ---
      // --- MUNDO 3 (ATUALIZADO) ---
      Phase(id: 't3_p1', trackId: 'track_3', orderIndex: 1, title: 'O Ponto de Partida', description: 'Valide suas vivências.', xpReward: 150),
      Phase(id: 't3_p2', trackId: 'track_3', orderIndex: 2, title: 'Cursos & Certificações', description: 'Sua estante de aprendizado.', xpReward: 150),
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

      // --- M1.1: Meus Pontos Fortes ---
      Question(id: 'M1_1_1_Q1', phaseId: 't1_p1', type: QuestionType.characterSelect, content: 'Em projetos e novos negócios, qual é o seu papel?', options: []),
      Question(id: 'M1_1_1_Q2', phaseId: 't1_p1', type: QuestionType.interactiveStory, content: 'Faltam 24h para a entrega final de um projeto e um problema crítico aconteceu. Qual é a sua reação instintiva?', options: []),
      Question(id: 'M1_1_1_Q3', phaseId: 't1_p1', type: QuestionType.balanceSlider, content: 'Como você prefere lidar com informações e tarefas?', options: []),
      Question(id: 'M1_1_1_Q4', phaseId: 't1_p1', type: QuestionType.dragAndDrop, content: 'Onde você se sente mais confortável se comunicando?', options: ['Falando e Apresentando', 'Escrevendo e Estruturando', 'Visualizando e Criando', 'Ouvindo e Pesquisando']),
      
      // --- M1.2: Minha Cultura e Trabalho ---
      Question(id: 'M1_2_1_Q1', phaseId: 't1_p2', type: QuestionType.vibeSelect, content: 'Em qual destes ambientes você sente que produziria melhor?', options: []),
      Question(id: 'M1_2_1_Q2', phaseId: 't1_p2', type: QuestionType.quickTimeEvent, content: 'Você recebeu uma tarefa que nunca fez antes. Qual é seu primeiro passo?', options: []),


      // --- M1.3: Minha Bússola ---
      Question(id: 'M1_3_1_Q1', phaseId: 't1_p3', type: QuestionType.dragAndDrop, content: 'O que é "Sucesso" para você neste momento da carreira?', options: []),
      Question(id: 'M1_3_1_Q2', phaseId: 't1_p3', type: QuestionType.dynamicList, content: 'Em qual área você quer focar agora? (Selecione até 2)', options: ['Vendas & Novos Negócios', 'Marketing & Branding', 'Finanças & Controladoria', 'Venture Capital & Private Equity', 'Administração & Processos', 'Tecnologia & Programação', 'Dados & Business Intelligence', 'Produto & UX Design', 'Recursos Humanos & Cultura', 'Operações & Logística', 'Consultoria Estratégica', 'Ainda estou explorando / Aberto a oportunidades']),
      Question(id: 'M1_3_1_Q3', phaseId: 't1_p3', type: QuestionType.visionCards, content: 'Como você visualiza o seu futuro ideal daqui a alguns anos?', options: []),

      // --- M2.1: Minha Guilda ---
      // --- M2.1: Minha Guilda ---
      // Removed Q1: Education Level (Deleted)
      Question(id: 'M2_1_1_Q1', phaseId: 't2_p1', type: QuestionType.idCardBuilder, content: 'Onde você estuda e qual o seu curso?', options: []),
      Question(id: 'M2_1_1_Q2', phaseId: 't2_p1', type: QuestionType.binaryChoice, content: 'Além da sua formação atual, você tem outra bagagem acadêmica?', options: []),
      Question(id: 'M2_1_1_Q3', phaseId: 't2_p1', type: QuestionType.retroIdCard, content: 'Onde você estudou e qual foi o curso?', options: []),
      Question(id: 'M2_1_1_Q4', phaseId: 't2_p1', type: QuestionType.bridgeText, content: 'Mudar de curso ou somar áreas diferentes é sinal de repertório. Como essa sua passagem por [Curso Anterior] ajuda você a ser um profissional melhor hoje?', options: []),

      // --- M2.2: Datas e Logística ---
      Question(id: 'M2_2_1_Q1', phaseId: 't2_p2', type: QuestionType.dualWheelDate, content: 'Quando seu curso começou e quando termina?', options: []),
      Question(id: 'M2_2_1_Q2', phaseId: 't2_p2', type: QuestionType.stepSlider, content: 'Em qual semestre você está agora?', options: ['1º Sem', '2º Sem', '3º Sem', '4º Sem', '5º Sem', '6º Sem', '7º Sem', '8º Sem', 'Finalizando']),
      Question(id: 'M2_2_1_Q3', phaseId: 't2_p2', type: QuestionType.iconSelect, content: 'Em qual período você estuda?', options: ['Matutino', 'Vespertino', 'Noturno', 'Integral', 'EAD']),

      // --- M2.3: Medalhas de Honra ---
      Question(id: 'M2_3_1_Q1', phaseId: 't2_p3', type: QuestionType.rewardCardSelect, content: 'Você conquistou alguma bolsa de estudos por mérito?', options: ['Sim, 100%', 'Sim, Parcial', 'Não']),
      Question(
        id: 'M2_3_1_Q2', 
        phaseId: 't2_p3', 
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
      Question(id: 'M2_3_1_Q3', phaseId: 't2_p3', type: QuestionType.miniTextBox, content: 'Qual foi o seu maior desafio ou conquista nessas atividades? (Opcional)', options: []),
      Question(id: 'M2_3_1_Q4', phaseId: 't2_p3', type: QuestionType.yesNoWithDetail, content: 'Algum professor já te deu um destaque ou você ganhou algum prêmio acadêmico?', options: []),

      // --- M3.1: O Ponto de Partida ---
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

      // --- M3.2: Cursos (Portal de Entrada & Learning Vault) ---
      Question(
        id: 'M3_2_1_Q1', 
        phaseId: 't3_p2', 
        type: QuestionType.binaryChoice, 
        content: 'Além da formação acadêmica, você fez algum curso com certificação?', 
        options: ['Sim, investi em cursos', 'Não, foquei em outras experiências']
      ),
      Question(
        id: 'M3_2_1_Q2', 
        phaseId: 't3_p2', 
        type: QuestionType.learningVault, 
        content: 'Quais são as conquistas da sua estante de aprendizado?', 
        options: []
      ),




      // --- M4.1: Minhas Ferramentas Técnicas ---
      Question(id: 'M4_1_1_Q1', phaseId: 't4_p1', type: QuestionType.dynamicList, content: 'Se abríssemos sua "caixa de ferramentas", quais dessas categorias você domina?', options: [
        'Pacote Office / Administrativo',
        'Design & Criatividade',
        'Programação & Tech',
        'Dados & Finanças',
        'Redes Sociais & Marketing',
        'Vendas & Negociação',
        'Recursos Humanos (RH)',
        'Direito & Legislação',
        'Saúde & Medicina',
        'Engenharia & Construção',
        'Logística & Supply Chain',
        'Educação & Ensino',
        'Gastronomia & Culinária',
        'Turismo & Hospitalidade',
        'Meio Ambiente & Sustentabilidade',
        'Música & Áudio',
        'Redação & Tradução',
        'Ciência & Pesquisa',
        'Manutenção & Reparos',
        'Agricultura & Pecuária',
        'Games & Esports',
        'Moda & Estilo',
        'Gestão de Projetos',
        'Segurança & Defesa',
      ]),
      Question(id: 'M4_1_1_Q2', phaseId: 't4_p1', type: QuestionType.dynamicList, content: 'Agora, liste os softwares específicos que você mais usa (ex: Excel, Figma):', options: []),
      Question(id: 'M4_1_1_Q3', phaseId: 't4_p1', type: QuestionType.stepSlider, content: 'Qual o seu nível de domínio em {tool}?', options: ['Básico', 'Intermediário', 'Avançado']),

      // --- M4.2: Idiomas ---
      Question(id: 'M4_2_1_Q1', phaseId: 't4_p2', type: QuestionType.badgeMultiSelect, content: 'Além do Português, quais idiomas você domina ou está estudando?', options: ['Inglês', 'Espanhol', 'Francês', 'Alemão', 'Japonês', 'Outro']),
      Question(id: 'M4_2_1_Q2', phaseId: 't4_p2', type: QuestionType.stepSlider, content: 'Qual é o seu nível de conhecimento em {language}?', options: ['Básico', 'Intermediário', 'Avançado', 'Fluente']),
      Question(id: 'M4_2_1_Q3', phaseId: 't4_p2', type: QuestionType.rewardCardSelect, content: 'Qual dessas situações melhor descreve como você usa esse idioma hoje?', options: ['Consumo de Conteúdo', 'Comunicação Escrita', 'Conversação']),
      Question(id: 'M4_2_1_Q4', phaseId: 't4_p2', type: QuestionType.yesNoWithDetail, content: 'Você possui alguma certificação oficial (como TOEFL, IELTS ou Cambridge)?', options: []),

      // --- M5.1: Presença Digital ---
      Question(id: 'M5_1_1_Q1', phaseId: 't5_p1', type: QuestionType.linkInput, content: 'Qual é o link do seu perfil no LinkedIn?', options: ['linkedin']),
      Question(id: 'M5_1_1_Q2', phaseId: 't5_p1', type: QuestionType.platformSelect, content: 'Você tem algum lugar onde mostra seus projetos ou trabalhos na prática?', options: ['GitHub', 'Behance', 'Dribbble', 'Portfólio Pessoal', 'Instagram Profissional', 'Outro', 'Não tenho']),
      Question(id: 'M5_1_1_Q3', phaseId: 't5_p1', type: QuestionType.email, content: 'Qual é o seu e-mail profissional?', options: []),
      Question(id: 'M5_1_1_Q4', phaseId: 't5_p1', type: QuestionType.phoneInput, content: 'Qual o seu número de WhatsApp para contato?', options: []),

      // --- M5.2: Logística Final ---
      Question(id: 'M5_2_1_Q1', phaseId: 't5_p2', type: QuestionType.cityStateInput, content: 'Onde você mora atualmente? (Cidade e Estado)', options: []),
      Question(id: 'M5_2_1_Q2', phaseId: 't5_p2', type: QuestionType.licenseSelect, content: 'Você possui Carteira de Habilitação (CNH)?', options: []),
      Question(id: 'M5_2_1_Q3', phaseId: 't5_p2', type: QuestionType.text, content: 'Alguma observação final que você gostaria que o recrutador soubesse?', options: []),
    ];
  }
}
