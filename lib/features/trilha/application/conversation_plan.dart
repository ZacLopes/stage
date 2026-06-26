// Construtor do PLANO da trilha (PLANO-FASE-6 T6.3, Increment 2).
//
// Dado o que falta no perfil (cérebro de lacunas — [ProfileGaps]), monta a fila
// de [ConversationStep] — ADAPTATIVO: só inclui passos pros campos ausentes, na
// ordem do mais barato (clique) ao mais rico. A entrevista de experiência
// (Increment 3) e o resumo por IA (Increment 4) são tratados à parte; aqui
// cobrimos habilidades, idiomas e as preferências/educação que ficaram em
// aberto (ex.: perfis que vieram do bypass sem preferências).
//
// Os `id`s dos passos e das opções são estáveis — o write-back (Increment 2b)
// roteia por eles pra gravar em profile_*.

import '../../profile/application/profile_gaps.dart';
import '../domain/conversation_step.dart';
import 'skill_suggestions.dart';

/// Monta o plano conversacional a partir das lacunas. [addressed] são os
/// trechos já abordados antes (memória [TrilhaProgress]) — pulados pra não
/// re-perguntar. Vazio quando não há nada novo pra coletar.
///
/// `educationStatus` fica de fora (já vem do onboarding); experiência tem fluxo
/// dinâmico próprio; resumo é gerado (Inc 4), não perguntado.
List<ConversationStep> buildConversationPlan(
  ProfileGaps gaps, {
  Set<String> addressed = const {},
  List<String> skillSuggestions = const [],
  List<String> skillCatalog = const [],
  Future<List<String>> Function()? skillSuggester,
  Future<List<String>> Function()? skillSuggestionsLoader,
}) {
  final missing = gaps.missing.map((l) => l.key).toSet();
  // Pergunta um trecho só se a lacuna existe E ele ainda não foi abordado
  // (memória — evita re-perguntar skills/experiência toda vez que abre).
  bool wants(LacunaKey key, String segment) =>
      missing.contains(key) && !addressed.contains(segment);

  final steps = <ConversationStep>[
    // Preferências (cliques rápidos).
    if (wants(LacunaKey.area, 'area')) _area(),
    if (wants(LacunaKey.workMode, 'workmode')) _workMode(),
    if (wants(LacunaKey.jobType, 'jobtype')) _jobType(),
    if (wants(LacunaKey.city, 'city')) _city(),
    // Educação (Tier 1 — chave pra o admin ACHAR o candidato: curso, semestre,
    // nível). Só aparece se faltar (o import não extrai esses campos).
    if (wants(LacunaKey.educationStatus, 'education')) _educationGate(),
    // Substância leve.
    if (wants(LacunaKey.skills, 'skills'))
      _skills(skillSuggestions, skillCatalog, skillSuggester,
          skillSuggestionsLoader),
    if (wants(LacunaKey.languages, 'languages')) _languages(),
    // Experiência (DINÂMICA): entrevista um campo por vez, loop "adicionar outra?".
    if (wants(LacunaKey.experience, 'experience')) _experienceGate(),
    // Extras (Tier 3): só pergunta se faltam e não foram abordados.
    if (wants(LacunaKey.linkedin, 'linkedin')) _linkedinGate(),
    if (wants(LacunaKey.certifications, 'certifications')) _certGate(),
    if (wants(LacunaKey.projects, 'projects')) _projectGate(),
    if (wants(LacunaKey.interests, 'interests')) _interests(),
    if (wants(LacunaKey.availability, 'availability')) _availabilityStep(),
  ];
  if (steps.isEmpty) return const [];
  return [_intro(), ...steps];
}

bool _answeredYes(StepAnswer a) => a.value is List && (a.value as List).contains('yes');

// ── Passos ──────────────────────────────────────────────────────────────────

ConversationStep _intro() => ConversationStep.single(
      id: 'intro',
      aiMessage:
          'Que bom te ver por aqui! Vou te fazer umas perguntas rapidinhas pra '
          'deixar seu perfil forte o bastante pras empresas te acharem. Pode ser?',
      input: const ChoiceInput(
        options: [StepOption(id: 'go', label: 'Pode! 🚀')],
      ),
    );

/// Áreas sugeridas (chips). O usuário também pode buscar ou escrever a sua.
const List<String> _kAreaSuggestions = [
  'Tecnologia', 'Engenharia', 'Design', 'Produto', 'Marketing', 'Vendas',
  'Finanças', 'Recursos Humanos', 'Operações', 'Jurídico', 'Administrativo',
  'Saúde',
];

/// Catálogo estendido só pra busca (áreas comuns além das sugeridas).
const List<String> _kAreaCatalog = [
  ..._kAreaSuggestions,
  'Educação', 'Comunicação', 'Logística', 'Agronegócio', 'Audiovisual',
  'Sustentabilidade', 'Dados', 'Pesquisa', 'Consultoria', 'Eventos', 'Moda',
  'Gastronomia', 'Turismo', 'Construção civil', 'Meio ambiente', 'Pública',
];

ConversationStep _area() => ConversationStep.single(
      id: 'gap.area',
      aiMessage:
          'Em quais áreas você quer atuar? Toque nas que combinam, busca ou '
          'escreve a sua — escolhe até 3. É o que mais pesa pra te conectar com '
          'as vagas certas.',
      input: const SuggestPickInput(
        suggestions: _kAreaSuggestions,
        catalog: _kAreaCatalog,
        maxSelections: 3,
        searchHint: 'Buscar ou escrever sua área…',
      ),
      acknowledgement: 'Anotado! Já dá pra mirar nas vagas dessas áreas.',
    );

ConversationStep _workMode() => ConversationStep.single(
      id: 'gap.workmode',
      aiMessage: 'Como você prefere trabalhar? (pode marcar mais de um)',
      input: const ChoiceInput(
        multi: true,
        options: [
          StepOption(id: 'remote', label: 'Remoto'),
          StepOption(id: 'hybrid', label: 'Híbrido'),
          StepOption(id: 'inPerson', label: 'Presencial'),
        ],
      ),
    );

ConversationStep _jobType() => ConversationStep.single(
      id: 'gap.jobtype',
      aiMessage: 'Que tipo de vaga te interessa? (pode marcar mais de um)',
      input: const ChoiceInput(
        multi: true,
        options: [
          StepOption(id: 'internship', label: 'Estágio'),
          StepOption(id: 'trainee', label: 'Trainee'),
          StepOption(id: 'juniorFullTime', label: 'CLT Júnior'),
          StepOption(id: 'temporary', label: 'Temporário'),
        ],
      ),
    );

ConversationStep _city() => ConversationStep.single(
      id: 'gap.city',
      aiMessage:
          'Em qual cidade você está? Uso isso pra te mostrar vagas próximas.',
      input: const GuidedTextInput(
        example: 'São Paulo, SP',
        hint: 'Cidade e estado',
        maxLength: 60,
        minLines: 1,
      ),
    );

ConversationStep _skills(
  List<String> suggestions,
  List<String> catalog,
  Future<List<String>> Function()? suggester,
  Future<List<String>> Function()? suggestionsLoader,
) {
  // Chips sugeridos (personalizados pela área); fallback genérico se vazio. O
  // loader (se houver) atualiza pela área escolhida DENTRO da trilha.
  final chips =
      suggestions.isNotEmpty ? suggestions : suggestedSkillsForAreas(const []);
  return ConversationStep.single(
    id: 'gap.skills',
    aiMessage:
        'Agora suas habilidades — toque nas que você manja, busca outras ou '
        'escreve do seu jeito. Quanto mais, mais vagas te encontram.',
    input: SuggestPickInput(
      suggestions: chips,
      catalog: catalog,
      searchHint: 'Buscar habilidade ou adicionar a sua…',
      suggestionsLoader: suggestionsLoader,
    ),
    acknowledgement: 'Boa! Essas habilidades já te abrem portas. 💪',
    // Depois de marcar: se faltam pra chegar a 3, entra num loop que OBRIGA
    // chegar lá (a IA ajuda na 1ª rodada); se já tem 3+, a IA sugere como bônus.
    expand: (a) => _afterSkills(a, suggester, catalog, suggestionsLoader),
  );
}

/// Mínimo de skills exigido pela trilha — perfil com <3 skills é ruído no match.
const int _kMinSkills = 3;

int _pickCount(StepAnswer a) =>
    a.value is List ? (a.value as List).length : 0;

/// Após o passo de skills: <3 → loop obrigatório até 3; ≥3 → bônus opcional da IA.
List<ConversationStep> _afterSkills(
  StepAnswer answer,
  Future<List<String>> Function()? suggester,
  List<String> catalog,
  Future<List<String>> Function()? loader,
) {
  final n = _pickCount(answer);
  if (n >= _kMinSkills) {
    if (suggester == null) return const [];
    return [
      ConversationStep.single(
        id: 'gap.skills.more.1',
        aiMessage:
            'Deixa eu te ajudar a lembrar de mais algumas, com base no seu perfil…',
        input: AsyncSuggestInput(load: suggester, catalog: catalog),
        acknowledgement: 'Perfil ficando completo! 🙌',
      ),
    ];
  }
  return [_skillsBoost(suggester, catalog, loader, n, 1)];
}

/// Uma rodada do loop até [_kMinSkills]. 1ª rodada usa a IA (se houver); as
/// seguintes usam busca/texto livre (sem novo custo de IA), com mensagem que
/// escala. Obrigatório: minSelections = quantas faltam pra 3.
ConversationStep _skillsBoost(
  Future<List<String>> Function()? suggester,
  List<String> catalog,
  Future<List<String>> Function()? loader,
  int already,
  int round,
) {
  final remaining = _kMinSkills - already;
  final useAi = suggester != null && round == 1;
  final plural = remaining > 1 ? 'm' : '';
  final msg = round == 1
      ? 'Deixa eu te ajudar a lembrar de mais algumas, com base no seu perfil… '
          '(falta$plural $remaining pra deixar forte)'
      : 'Bora completar! Falta$plural $remaining — busca ou escreve do seu '
          'jeito (ferramentas, idiomas técnicos, o que você usa no dia a dia).';
  return ConversationStep.single(
    id: 'gap.skills.more.$round',
    aiMessage: msg,
    input: useAi
        ? AsyncSuggestInput(
            load: suggester, catalog: catalog, minSelections: remaining)
        : SuggestPickInput(
            suggestions: const [],
            catalog: catalog,
            suggestionsLoader: loader,
            minSelections: remaining,
            searchHint: 'Buscar habilidade ou adicionar a sua…',
          ),
    expand: (a2) {
      final total = already + _pickCount(a2);
      if (total >= _kMinSkills) return const [];
      return [_skillsBoost(suggester, catalog, loader, total, round + 1)];
    },
  );
}

ConversationStep _languages() => ConversationStep.single(
      id: 'gap.languages',
      aiMessage:
          'Quais idiomas você fala? Toque em todos que você manja — o '
          'português também.',
      input: const ChoiceInput(
        multi: true,
        options: [
          StepOption(id: 'Português', label: 'Português'),
          StepOption(id: 'Inglês', label: 'Inglês'),
          StepOption(id: 'Espanhol', label: 'Espanhol'),
          StepOption(id: 'Francês', label: 'Francês'),
          StepOption(id: 'Alemão', label: 'Alemão'),
          StepOption(id: 'Italiano', label: 'Italiano'),
          StepOption(id: 'Mandarim', label: 'Mandarim'),
        ],
      ),
      // Pra cada idioma NÃO-nativo escolhido, pergunta o nível em seguida
      // (português entra como 'nativo' automático no write-back).
      expand: (a) {
        final picked = a.value is List
            ? (a.value as List).whereType<String>()
            : const <String>[];
        return [
          for (final lang in picked)
            if (lang.toLowerCase() != 'português') _languageLevel(lang),
        ];
      },
      // addLanguage por idioma → voltar e re-responder duplicaria.
      reversible: false,
    );

/// Nível de um idioma — chips compactos (escala). Os ids são os valores
/// canônicos do banco (basic/intermediate/advanced/fluent/native).
ConversationStep _languageLevel(String lang) => ConversationStep.single(
      id: 'lang.level.$lang',
      aiMessage: 'Qual seu nível em $lang?',
      input: const ChoiceInput(
        compact: true,
        options: [
          StepOption(id: 'basic', label: 'Básico'),
          StepOption(id: 'intermediate', label: 'Intermediário'),
          StepOption(id: 'advanced', label: 'Avançado'),
          StepOption(id: 'fluent', label: 'Fluente'),
          StepOption(id: 'native', label: 'Nativo'),
        ],
      ),
      acknowledgement: 'Anotado!',
    );

// ── Experiência (dinâmica) ───────────────────────────────────────────────────

// ── Educação (Tier 1): só aparece se faltar curso/semestre/nível ─────────────
// O import de CV NÃO extrai esses campos; o admin filtra a shortlist por eles.
// Fluxo curto e adaptativo: momento dos estudos → (faculdade: instituição+curso+
// semestre | ensino médio: escola+ano | outro: nada). Grava ATÔMICO no último
// passo de cada ramo (semestre/ano) — ver TrilhaWriteback.
const _kSemesterOptions = <StepOption>[
  StepOption(id: '1', label: '1º'),
  StepOption(id: '2', label: '2º'),
  StepOption(id: '3', label: '3º'),
  StepOption(id: '4', label: '4º'),
  StepOption(id: '5', label: '5º'),
  StepOption(id: '6', label: '6º'),
  StepOption(id: '7', label: '7º'),
  StepOption(id: '8', label: '8º'),
  StepOption(id: '9', label: '9º'),
  StepOption(id: '10', label: '10º'),
  StepOption(id: '11', label: '11º'),
  StepOption(id: '12', label: '12º'),
];

String _firstChoiceId(StepAnswer a) =>
    a.value is List && (a.value as List).isNotEmpty
        ? (a.value as List).first as String
        : '';

ConversationStep _educationGate() => ConversationStep(
      id: 'gap.edu.moment',
      aiMessages: const [
        'Pra te mostrar as vagas certas, me conta: em que momento dos estudos '
            'você está?',
      ],
      input: const ChoiceInput(options: [
        StepOption(id: 'in_college', label: 'Cursando faculdade'),
        StepOption(id: 'college_paused', label: 'Faculdade trancada'),
        StepOption(id: 'in_school', label: 'No ensino médio'),
        StepOption(
            id: 'outro', label: 'Outro (já terminei / não estudo agora)'),
      ]),
      expand: (a) {
        final m = _firstChoiceId(a);
        if (m == 'in_school') return _eduSchoolSteps();
        if (m == 'in_college' || m == 'college_paused') {
          return _eduCollegeSteps();
        }
        return const []; // 'outro' → não coleta mais (fora do público-alvo)
      },
    );

List<ConversationStep> _eduCollegeSteps() => [
      ConversationStep.single(
        id: 'gap.edu.institution',
        aiMessage: 'Qual faculdade?',
        input: const GuidedTextInput(
          example: 'USP',
          hint: 'Nome da faculdade',
          maxLength: 80,
          minLines: 1,
        ),
      ),
      ConversationStep.single(
        id: 'gap.edu.course',
        aiMessage: 'E qual curso?',
        input: const GuidedTextInput(
          example: 'Administração',
          hint: 'Nome do curso',
          maxLength: 80,
          minLines: 1,
        ),
      ),
      ConversationStep.single(
        id: 'gap.edu.semester',
        aiMessage: 'Que semestre você está cursando?',
        input: const ChoiceInput(compact: true, options: _kSemesterOptions),
        acknowledgement:
            'Anotado! Isso ajuda demais as empresas a te acharem. ✨',
      ),
    ];

List<ConversationStep> _eduSchoolSteps() => [
      ConversationStep.single(
        id: 'gap.edu.school',
        aiMessage: 'Qual escola?',
        input: const GuidedTextInput(
          example: 'Colégio Pedro II',
          hint: 'Nome da escola',
          maxLength: 80,
          minLines: 1,
        ),
      ),
      ConversationStep.single(
        id: 'gap.edu.schoolyear',
        aiMessage: 'Que ano você está?',
        input: const ChoiceInput(compact: true, options: [
          StepOption(id: '1', label: '1º ano'),
          StepOption(id: '2', label: '2º ano'),
          StepOption(id: '3', label: '3º ano'),
        ]),
        acknowledgement: 'Anotado! Isso ajuda demais. ✨',
      ),
    ];

ConversationStep _experienceGate() => ConversationStep(
      id: 'exp.gate',
      aiMessages: const [
        'Agora a parte que mais conta pras empresas: suas experiências.',
        'Já fez ALGO que te ensinou no mundo real? Vale muito além de emprego — '
            'estágio, monitoria, atlética ou liga acadêmica, voluntariado, '
            'trabalho na empresa da família, freela, ajudar num negócio… conta tudo.',
      ],
      input: const ChoiceInput(options: [
        StepOption(id: 'yes', label: 'Já sim'),
        StepOption(id: 'no', label: 'Ainda não'),
      ]),
      expand: (a) => _answeredYes(a) ? _experienceItem(0) : const [],
    );

List<ConversationStep> _experienceItem(int n) => [
      ConversationStep.single(
        id: 'exp.$n.company',
        aiMessage: n == 0
            ? 'Bora! Qual foi a empresa ou organização?'
            : 'E a empresa/organização dessa?',
        input: const GuidedTextInput(
          example: 'Magazine Luiza',
          hint: 'Nome da empresa',
          maxLength: 80,
          minLines: 1,
        ),
      ),
      ConversationStep.single(
        id: 'exp.$n.role',
        aiMessage: 'Qual era seu cargo ou função lá?',
        input: const GuidedTextInput(
          example: 'Estagiário de Marketing',
          hint: 'Seu cargo',
          maxLength: 80,
          minLines: 1,
        ),
      ),
      ConversationStep.single(
        id: 'exp.$n.start',
        aiMessage: 'Quando você começou?',
        input: const MonthYearInput(),
      ),
      ConversationStep.single(
        id: 'exp.$n.current',
        aiMessage: 'Você ainda está nessa experiência?',
        input: const ChoiceInput(options: [
          StepOption(id: 'yes', label: 'Sim, ainda estou'),
          StepOption(id: 'no', label: 'Não, já saí'),
        ]),
        expand: (a) => _answeredYes(a)
            ? _experienceTail(n)
            : [_endStep(n), ..._experienceTail(n)],
      ),
    ];

ConversationStep _endStep(int n) => ConversationStep.single(
      id: 'exp.$n.end',
      aiMessage: 'E quando terminou?',
      input: const MonthYearInput(),
    );

List<ConversationStep> _experienceTail(int n) => [
      ConversationStep(
        id: 'exp.$n.ofazia',
        aiMessages: const [
          'Agora o mais importante: o que você fazia lá? Conta 2-3 coisas '
              'concretas — pode ser do seu jeito, eu organizo depois. 😉',
        ],
        input: const GuidedTextInput(
          example: 'Atendia clientes, organizava o estoque e montei uma '
              'planilha que agilizou os pedidos',
          maxLength: 280,
          minLines: 3,
        ),
        acknowledgement:
            'Show! Vou guardar isso pra montar um bullet caprichado no seu CV. ✨',
        // Save terminal (addExperience + bullet) → não dá pra voltar e duplicar.
        reversible: false,
      ),
      ConversationStep.single(
        id: 'exp.$n.more',
        aiMessage: 'Quer adicionar outra experiência?',
        input: const ChoiceInput(options: [
          StepOption(id: 'yes', label: 'Sim, tenho mais'),
          StepOption(id: 'no', label: 'Não, é só essa'),
        ]),
        expand: (a) => _answeredYes(a) ? _experienceItem(n + 1) : const [],
      ),
    ];

// ── Extras: LinkedIn + Certificações ─────────────────────────────────────────

ConversationStep _linkedinGate() => ConversationStep(
      id: 'linkedin.gate',
      aiMessages: const ['Você tem um perfil no LinkedIn?'],
      input: const ChoiceInput(options: [
        StepOption(id: 'yes', label: 'Tenho'),
        StepOption(id: 'no', label: 'Não tenho'),
      ]),
      expand: (a) => _answeredYes(a)
          ? [
              ConversationStep.single(
                id: 'linkedin.url',
                aiMessage:
                    'Cola o link aqui — recrutadores adoram dar uma olhada.',
                input: const GuidedTextInput(
                  example: 'linkedin.com/in/seunome',
                  hint: 'Link do seu LinkedIn',
                  maxLength: 120,
                  minLines: 1,
                ),
                acknowledgement: 'Anotado! 🔗',
              ),
            ]
          : const [],
    );

ConversationStep _certGate() => ConversationStep(
      id: 'cert.gate',
      aiMessages: const [
        'Tem alguma certificação ou curso que valha destacar? (TOEFL, Google, '
            'Excel avançado…)',
      ],
      input: const ChoiceInput(options: [
        StepOption(id: 'yes', label: 'Tenho'),
        StepOption(id: 'no', label: 'Não tenho'),
      ]),
      expand: (a) => _answeredYes(a) ? _certItem(0) : const [],
    );

List<ConversationStep> _certItem(int n) => [
      ConversationStep.single(
        id: 'cert.$n.name',
        aiMessage: n == 0 ? 'Qual?' : 'E qual a próxima?',
        input: const GuidedTextInput(
          example: 'Inglês — TOEFL (2024)',
          hint: 'Nome da certificação',
          maxLength: 100,
          minLines: 1,
        ),
        // addCertification → voltar e re-responder duplicaria.
        reversible: false,
      ),
      ConversationStep.single(
        id: 'cert.$n.more',
        aiMessage: 'Tem mais alguma?',
        input: const ChoiceInput(options: [
          StepOption(id: 'yes', label: 'Sim, tenho mais'),
          StepOption(id: 'no', label: 'Não, é só'),
        ]),
        expand: (a) => _answeredYes(a) ? _certItem(n + 1) : const [],
      ),
    ];

// ── Extra: Projetos (dinâmico) ───────────────────────────────────────────────

ConversationStep _projectGate() => ConversationStep(
      id: 'project.gate',
      aiMessages: const [
        'E projetos? Vale tudo que você botou pra rodar: app, TCC, trabalho da '
            'faculdade, organização de evento, conteúdo/social media, iniciativa '
            'própria, freela… Conta muito, ainda mais com pouca experiência formal.',
      ],
      input: const ChoiceInput(options: [
        StepOption(id: 'yes', label: 'Já sim'),
        StepOption(id: 'no', label: 'Não'),
      ]),
      expand: (a) => _answeredYes(a) ? _projectItem(0) : const [],
    );

List<ConversationStep> _projectItem(int n) => [
      ConversationStep.single(
        id: 'project.$n.name',
        aiMessage: n == 0 ? 'Qual o nome do projeto?' : 'E o nome desse?',
        input: const GuidedTextInput(
          example: 'App de finanças pessoais',
          hint: 'Nome do projeto',
          maxLength: 80,
          minLines: 1,
        ),
      ),
      // O que ERA (contexto) e o que VOCÊ fez (bullet) — separados pra ficar
      // claro o que escrever em cada um.
      ConversationStep.single(
        id: 'project.$n.what',
        aiMessage:
            'O que era esse projeto? A ideia em 1-2 frases — o que ele fazia '
            'ou resolvia.',
        input: const GuidedTextInput(
          example: 'Um app pra estudantes controlarem os gastos do mês',
          maxLength: 200,
          minLines: 2,
        ),
      ),
      ConversationStep(
        id: 'project.$n.did',
        aiMessages: const [
          'E o que VOCÊ fez nele? Sua parte, e o resultado se teve — pode ser do '
              'seu jeito, eu organizo. 😉',
        ],
        input: const GuidedTextInput(
          example: 'Programei o app em Flutter sozinho; teve 200 downloads',
          maxLength: 240,
          minLines: 3,
        ),
        acknowledgement: 'Show! Só mais uns detalhes rápidos e fecho esse (dá pra pular). ✨',
      ),
      // Enriquecimento OPCIONAL (um toque pra pular) — data + link.
      ConversationStep.single(
        id: 'project.$n.when',
        aiMessage: 'Quando você fez? (se não lembrar, pula)',
        input: const MonthYearInput(optional: true),
      ),
      ConversationStep.single(
        id: 'project.$n.link',
        aiMessage:
            'Tem um link pra mostrar? (GitHub, site, Behance…) Se não, pula.',
        input: const GuidedTextInput(
          example: 'github.com/seunome/projeto',
          hint: 'Link do projeto',
          maxLength: 120,
          minLines: 1,
          optional: true,
        ),
        // Save terminal atômico (addProject + bullet) → não volta pra duplicar.
        reversible: false,
      ),
      ConversationStep.single(
        id: 'project.$n.more',
        aiMessage: 'Quer adicionar outro projeto?',
        input: const ChoiceInput(options: [
          StepOption(id: 'yes', label: 'Sim, tenho mais'),
          StepOption(id: 'no', label: 'Não, é só'),
        ]),
        expand: (a) => _answeredYes(a) ? _projectItem(n + 1) : const [],
      ),
    ];

// ── Extra: Disponibilidade ───────────────────────────────────────────────────

ConversationStep _availabilityStep() => ConversationStep.single(
      id: 'gap.availability',
      aiMessage: 'Por último: quando você poderia começar?',
      input: const ChoiceInput(options: [
        StepOption(id: 'immediate', label: 'Imediatamente'),
        StepOption(id: 'within_month', label: 'Em até 1 mês'),
        StepOption(id: 'after_graduation', label: 'Após me formar'),
        StepOption(id: 'flexible', label: 'Tenho flexibilidade'),
      ]),
      acknowledgement: 'Perfeito, anotado!',
    );

// ── Extra: Interesses / temas (fit cultural) ─────────────────────────────────

// Interesses é OBRIGATÓRIO (decisão do fundador): sem gate "quer? sim/não" —
// pergunta direta. SuggestPickInput (chips + busca + "+ Adicionar" texto livre)
// pra o usuário ADICIONAR um tema que não está na lista; minSelections: 1 exige
// pelo menos um pra liberar o "Continuar".
const _kInterestSuggestions = <String>[
  'Sustentabilidade',
  'Tecnologia',
  'Educação',
  'Saúde',
  'Finanças',
  'Inovação',
  'Diversidade & inclusão',
  'Empreendedorismo',
  'Marketing',
  'Design',
  'Dados & IA',
  'Meio ambiente',
  'Impacto social',
  'Cultura & arte',
  'Esportes',
  'Agronegócio',
];

// Extras só pro typeahead (não viram chips) — o texto livre cobre o resto.
const _kInterestCatalog = <String>[
  ..._kInterestSuggestions,
  'Games',
  'Moda',
  'Música',
  'Turismo',
  'Gastronomia',
  'Comunicação',
  'Logística',
  'Jurídico',
  'Recursos Humanos',
  'Ciência',
  'Política',
  'Voluntariado',
  'Mídia',
  'Varejo',
  'Indústria',
  'Engenharia',
  'Arquitetura',
  'Audiovisual',
  'Direitos humanos',
  'Saúde mental',
];

ConversationStep _interests() => ConversationStep.single(
      id: 'gap.interests',
      aiMessage:
          'Pra fechar, marque alguns temas ou causas que te interessam — isso '
          'ajuda as empresas com a sua cara a te encontrarem.',
      input: const SuggestPickInput(
        suggestions: _kInterestSuggestions,
        catalog: _kInterestCatalog,
        minSelections: 1,
        searchHint: 'Buscar ou escrever um tema…',
      ),
      acknowledgement: 'Curti! Isso ajuda no fit cultural. ✨',
    );
