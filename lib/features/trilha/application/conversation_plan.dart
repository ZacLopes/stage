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
    // Substância leve.
    if (wants(LacunaKey.skills, 'skills'))
      _skills(skillSuggestions, skillCatalog, skillSuggester),
    if (wants(LacunaKey.languages, 'languages')) _languages(),
    // Experiência (DINÂMICA): entrevista um campo por vez, loop "adicionar outra?".
    if (wants(LacunaKey.experience, 'experience')) _experienceGate(),
    // Extras (Tier 3): só pergunta se faltam e não foram abordados.
    if (wants(LacunaKey.linkedin, 'linkedin')) _linkedinGate(),
    if (wants(LacunaKey.certifications, 'certifications')) _certGate(),
    if (wants(LacunaKey.projects, 'projects')) _projectGate(),
    if (wants(LacunaKey.interests, 'interests')) _interestsGate(),
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

ConversationStep _area() => ConversationStep.single(
      id: 'gap.area',
      aiMessage:
          'Em quais áreas você quer atuar? Escolhe até 3 — é o que mais pesa '
          'pra te conectar com as vagas certas.',
      input: const ChoiceInput(
        multi: true,
        maxSelections: 3,
        options: [
          StepOption(id: 'Tecnologia', label: 'Tecnologia'),
          StepOption(id: 'Engenharia', label: 'Engenharia'),
          StepOption(id: 'Design', label: 'Design'),
          StepOption(id: 'Produto', label: 'Produto'),
          StepOption(id: 'Marketing', label: 'Marketing'),
          StepOption(id: 'Vendas', label: 'Vendas'),
          StepOption(id: 'Finanças', label: 'Finanças'),
          StepOption(id: 'Recursos Humanos', label: 'Recursos Humanos'),
          StepOption(id: 'Operações', label: 'Operações'),
          StepOption(id: 'Jurídico', label: 'Jurídico'),
          StepOption(id: 'Administrativo', label: 'Administrativo'),
          StepOption(id: 'Saúde', label: 'Saúde'),
          StepOption(id: 'Geral', label: 'Ainda explorando'),
        ],
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
) {
  // Chips sugeridos (personalizados pela área); fallback genérico se vazio.
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
    ),
    acknowledgement: 'Boa! Essas habilidades já te abrem portas. 💪',
    // Depois de marcar, a IA sugere mais algumas pelo perfil (passo opcional).
    expand: suggester == null
        ? null
        : (_) => [_skillsAiSuggest(suggester, catalog)],
  );
}

ConversationStep _skillsAiSuggest(
        Future<List<String>> Function() suggester, List<String> catalog) =>
    ConversationStep.single(
      id: 'gap.skills.more',
      aiMessage:
          'Deixa eu te ajudar a lembrar de mais algumas, com base no seu perfil…',
      input: AsyncSuggestInput(load: suggester, catalog: catalog),
      acknowledgement: 'Perfil ficando completo! 🙌',
    );

ConversationStep _languages() => ConversationStep.single(
      id: 'gap.languages',
      aiMessage:
          'Quais idiomas você manja, além do português? (se nenhum, pode pular '
          'tocando em "Só português")',
      input: const ChoiceInput(
        multi: true,
        options: [
          StepOption(id: 'none', label: 'Só português'),
          StepOption(id: 'Inglês', label: 'Inglês'),
          StepOption(id: 'Espanhol', label: 'Espanhol'),
          StepOption(id: 'Francês', label: 'Francês'),
          StepOption(id: 'Alemão', label: 'Alemão'),
          StepOption(id: 'Italiano', label: 'Italiano'),
          StepOption(id: 'Mandarim', label: 'Mandarim'),
        ],
      ),
    );

// ── Experiência (dinâmica) ───────────────────────────────────────────────────

ConversationStep _experienceGate() => ConversationStep(
      id: 'exp.gate',
      aiMessages: const [
        'Agora a parte que mais conta pras empresas: suas experiências.',
        'Você já trabalhou, estagiou, fez algum projeto ou voluntariado? Vale '
            'qualquer coisa — mesmo curta, informal ou sem salário.',
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
          'Agora o mais importante: o que você fazia lá? Conta 1-2 coisas '
              'concretas, do seu jeito — eu organizo depois. 😉',
        ],
        input: const GuidedTextInput(
          example:
              'Cuidava das redes sociais e criei posts que aumentaram o engajamento',
          maxLength: 240,
          minLines: 3,
        ),
        acknowledgement:
            'Show! Vou guardar isso pra montar um bullet caprichado no seu CV. ✨',
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
        'Você fez algum projeto pessoal, acadêmico ou freelance? (app, TCC, '
            'iniciativa, freela…) Conta muito, especialmente com pouca '
            'experiência formal.',
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
      ConversationStep(
        id: 'project.$n.desc',
        aiMessages: const [
          'Em poucas palavras: o que era e o que você fez? Pode ser do seu jeito.',
        ],
        input: const GuidedTextInput(
          example:
              'Criei um app em Flutter pra controlar gastos; teve 200 downloads',
          maxLength: 240,
          minLines: 3,
        ),
        acknowledgement: 'Massa! Isso enriquece bastante seu perfil. ✨',
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

ConversationStep _interestsGate() => ConversationStep(
      id: 'interests.gate',
      aiMessages: const [
        'Quer marcar alguns temas ou causas que te interessam? Ajuda a te '
            'conectar com empresas com a sua cara. (opcional)',
      ],
      input: const ChoiceInput(options: [
        StepOption(id: 'yes', label: 'Bora'),
        StepOption(id: 'no', label: 'Agora não'),
      ]),
      expand: (a) => _answeredYes(a)
          ? [
              ConversationStep.single(
                id: 'gap.interests',
                aiMessage: 'Toque nos temas que combinam com você:',
                input: const ChoiceInput(multi: true, options: [
                  StepOption(id: 'Sustentabilidade', label: 'Sustentabilidade'),
                  StepOption(id: 'Tecnologia', label: 'Tecnologia'),
                  StepOption(id: 'Educação', label: 'Educação'),
                  StepOption(id: 'Saúde', label: 'Saúde'),
                  StepOption(id: 'Finanças', label: 'Finanças'),
                  StepOption(id: 'Inovação', label: 'Inovação'),
                  StepOption(
                      id: 'Diversidade & inclusão',
                      label: 'Diversidade & inclusão'),
                  StepOption(
                      id: 'Empreendedorismo', label: 'Empreendedorismo'),
                  StepOption(id: 'Marketing', label: 'Marketing'),
                  StepOption(id: 'Design', label: 'Design'),
                  StepOption(id: 'Dados & IA', label: 'Dados & IA'),
                  StepOption(id: 'Meio ambiente', label: 'Meio ambiente'),
                  StepOption(id: 'Impacto social', label: 'Impacto social'),
                  StepOption(id: 'Cultura & arte', label: 'Cultura & arte'),
                  StepOption(id: 'Esportes', label: 'Esportes'),
                  StepOption(id: 'Agronegócio', label: 'Agronegócio'),
                ]),
                acknowledgement: 'Curti! Isso ajuda no fit cultural. ✨',
              ),
            ]
          : const [],
    );
