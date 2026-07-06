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
import 'trilha_draft.dart';

/// Monta o plano conversacional a partir das lacunas. [addressed] são os
/// trechos já abordados antes (memória [TrilhaProgress]) — pulados pra não
/// re-perguntar. Vazio quando não há nada novo pra coletar.
///
/// `educationStatus` ENTRA quando falta (rede de segurança — quem vem pela porta
/// de importar CV não traz curso/semestre, que a extração não extrai); a maioria
/// preenche no onboarding. Experiência/projeto têm fluxo dinâmico próprio; resumo
/// é gerado (Inc 4), não perguntado.
List<ConversationStep> buildConversationPlan(
  ProfileGaps gaps, {
  Set<String> addressed = const {},
  List<String> skillSuggestions = const [],
  List<String> skillCatalog = const [],
  Future<List<String>> Function()? skillSuggester,
  Future<List<String>> Function()? skillSuggestionsLoader,
  // Typeahead canônico (null → cai no texto livre): cidade IBGE / instituição.
  Future<List<PickSuggestion>> Function(String query)? citySearch,
  Future<List<PickSuggestion>> Function(String query)? institutionSearch,
  // Rascunhos de item em construção (resumabilidade por passo): retoma no ponto.
  List<TrilhaItemDraft> drafts = const [],
  // Idiomas já escolhidos que ainda estão SEM nível (proficiency null). Na volta,
  // a trilha pergunta SÓ o nível desses — sem re-rodar o picker. Fase 7 · +10 T3.
  List<String> languagesNeedingLevel = const [],
}) {
  final missing = gaps.missing.map((l) => l.key).toSet();
  // Pergunta um trecho só se a lacuna existe E ele ainda não foi abordado
  // (memória — evita re-perguntar skills/experiência toda vez que abre).
  bool wants(LacunaKey key, String segment) =>
      missing.contains(key) && !addressed.contains(segment);

  // Rascunho do item parcial (1 por kind) — se houver, RETOMA no passo em vez
  // de re-perguntar o item inteiro (só vale enquanto a lacuna segue aberta).
  final expDraft = _draftFor(drafts, 'experience');
  final projDraft = _draftFor(drafts, 'project');
  final eduDraft = _draftFor(drafts, 'education');

  final steps = <ConversationStep>[
    // Preferências (cliques rápidos).
    if (wants(LacunaKey.area, 'area')) _area(),
    if (wants(LacunaKey.desiredPosition, 'desired_position'))
      _desiredPositionStep(),
    if (wants(LacunaKey.workMode, 'workmode')) _workMode(),
    if (wants(LacunaKey.jobType, 'jobtype')) _jobType(),
    if (wants(LacunaKey.city, 'city')) _city(citySearch),
    // Educação (Tier 1 — chave pra o admin ACHAR o candidato: curso, semestre,
    // nível). Só aparece se faltar (o import não extrai esses campos).
    if (wants(LacunaKey.educationStatus, 'education'))
      if (eduDraft != null) ..._resumeEducation(eduDraft, institutionSearch)
      else _educationGate(institutionSearch),
    // Substância leve.
    if (wants(LacunaKey.skills, 'skills'))
      _skills(skillSuggestions, skillCatalog, skillSuggester,
          skillSuggestionsLoader),
    // Idiomas: se já há idiomas escolhidos sem nível (ex.: voltou depois de
    // sair no meio, ou import trouxe idioma sem nível), pergunta SÓ os níveis
    // que faltam — não re-roda o picker. Senão, mostra o picker (que gera os
    // níveis dos escolhidos). Fase 7 · +10 (Tarefa 3).
    if (wants(LacunaKey.languages, 'languages'))
      if (languagesNeedingLevel.isNotEmpty)
        for (final lang in languagesNeedingLevel) _languageLevel(lang)
      else
        _languages(),
    // Experiência (DINÂMICA): entrevista um campo por vez, loop "adicionar outra?".
    // Com rascunho → RETOMA no passo em vez de re-perguntar o item inteiro.
    if (wants(LacunaKey.experience, 'experience'))
      if (expDraft != null) ..._resumeExperience(expDraft)
      else _experienceGate(),
    // Extras (Tier 3): só pergunta se faltam e não foram abordados.
    if (wants(LacunaKey.linkedin, 'linkedin')) _linkedinGate(),
    if (wants(LacunaKey.certifications, 'certifications')) _certGate(),
    if (wants(LacunaKey.awards, 'awards')) _awardGate(),
    if (wants(LacunaKey.projects, 'projects'))
      if (projDraft != null) ..._resumeProject(projDraft)
      else _projectGate(),
    if (wants(LacunaKey.interests, 'interests')) _interests(),
    if (wants(LacunaKey.availability, 'availability')) _availabilityStep(),
  ];
  if (steps.isEmpty) return const [];
  return [_intro(), ...steps];
}

bool _answeredYes(StepAnswer a) => a.value is List && (a.value as List).contains('yes');

// ── Resumabilidade por passo: retoma o item parcial onde parou ───────────────
TrilhaItemDraft? _draftFor(List<TrilhaItemDraft> drafts, String kind) {
  for (final d in drafts) {
    if (d.kind == kind) return d;
  }
  return null;
}

/// Passos de um item DEPOIS do último respondido. Se o id não está na lista
/// (ex.: parou logo após o gate/momento), devolve tudo — retoma do começo do item.
List<ConversationStep> _stepsAfter(
    List<ConversationStep> steps, String lastStepId) {
  final i = steps.indexWhere((s) => s.id == lastStepId);
  return i < 0 ? steps : steps.sublist(i + 1);
}

List<ConversationStep> _resumeProject(TrilhaItemDraft d) {
  final n = d.itemIndex;
  final field = d.lastStepId.split('.').last;
  final isCurrent = d.fields['isCurrent'] == true;
  switch (field) {
    case 'name':
    case 'what':
    case 'did':
    case 'when':
      // _projectItem = [name, what, did, when, current(expand → end/tail)].
      return _stepsAfter(_projectItem(n), d.lastStepId);
    case 'current':
      // respondeu o "ainda tá rolando?" → cauda (com 'end' se já encerrou).
      return isCurrent
          ? _projectTail(n)
          : [_projectEnd(n), ..._projectTail(n)];
    case 'end':
      return _projectTail(n);
    default:
      return _projectItem(n);
  }
}

List<ConversationStep> _resumeEducation(TrilhaItemDraft d,
    Future<List<PickSuggestion>> Function(String)? institutionSearch) {
  final branch = d.fields['moment'] == 'in_school'
      ? _eduSchoolSteps()
      : _eduCollegeSteps(institutionSearch);
  return _stepsAfter(branch, d.lastStepId);
}

List<ConversationStep> _resumeExperience(TrilhaItemDraft d) {
  final n = d.itemIndex;
  final field = d.lastStepId.split('.').last;
  final isCurrent = d.fields['isCurrent'] == true;
  switch (field) {
    case 'company':
    case 'role':
    case 'start':
      // _experienceItem = [company, role, start, current(expand → end/tail)].
      return _stepsAfter(_experienceItem(n), d.lastStepId);
    case 'current':
      // respondeu o "ainda está?" → cauda (com 'end' se não for atual).
      return isCurrent
          ? _experienceTail(n)
          : [_endStep(n), ..._experienceTail(n)];
    case 'end':
      return _experienceTail(n);
    default:
      return _experienceItem(n); // fallback defensivo
  }
}

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

/// Cargo/posição desejada específica (além da área) — opcional, logo após as
/// áreas. Vai pra profile_job_preferences.desired_position e dá um BÔNUS no match.
ConversationStep _desiredPositionStep() => ConversationStep.single(
      id: 'gap.desired_position',
      aiMessage: 'E tem um cargo ou posição específica em mente? '
          '(opcional — ex.: Desenvolvedor Front-end, Analista de Dados)',
      input: const GuidedTextInput(
        example: 'Desenvolvedor Front-end',
        hint: 'Cargo desejado',
        maxLength: 80,
        minLines: 1,
        optional: true,
      ),
      acknowledgement: 'Anotado! Vou usar isso pra afinar suas vagas. 🎯',
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

ConversationStep _city(
        Future<List<PickSuggestion>> Function(String)? search) =>
    ConversationStep.single(
      id: 'gap.city',
      aiMessage:
          'Em qual cidade você está? Uso isso pra te mostrar vagas próximas.',
      // Typeahead do catálogo IBGE (cidade canônica + UF) → não polui o filtro
      // do admin. Sem o serviço (ex.: teste), cai no texto livre.
      input: search != null
          ? AsyncPickInput(search: search, searchHint: 'Buscar sua cidade…')
          : const GuidedTextInput(
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
      // Pergunta o nível de CADA idioma escolhido — inclusive português (o
      // usuário pode não ser nativo, e ele quer poder informar o nível de todos).
      expand: (a) {
        final picked = a.value is List
            ? (a.value as List).whereType<String>()
            : const <String>[];
        return [for (final lang in picked) _languageLevel(lang)];
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

ConversationStep _educationGate(
        Future<List<PickSuggestion>> Function(String)? institutionSearch) =>
    ConversationStep(
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
          return _eduCollegeSteps(institutionSearch);
        }
        return const []; // 'outro' → não coleta mais (fora do público-alvo)
      },
    );

List<ConversationStep> _eduCollegeSteps(
        Future<List<PickSuggestion>> Function(String)? institutionSearch) =>
    [
      ConversationStep.single(
        id: 'gap.edu.institution',
        aiMessage: 'Qual faculdade?',
        // Typeahead do catálogo institutions (fixa o institution_id canônico).
        input: institutionSearch != null
            ? AsyncPickInput(
                search: institutionSearch,
                searchHint: 'Buscar sua faculdade…')
            : const GuidedTextInput(
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
        acknowledgement: 'Anotado! ✨',
      ),
      _eduGraduationStep(),
    ];

/// Previsão de formatura — eixo de match forte (trainee/estágio filtram por isso;
/// só o semestre não pinga, porque a duração do curso varia). Chips dos próximos
/// anos + "ainda não sei". É o passo TERMINAL da faculdade (grava o item).
ConversationStep _eduGraduationStep() {
  final y = DateTime.now().year;
  return ConversationStep.single(
    id: 'gap.edu.graduation',
    aiMessage: 'E quando você se forma? (a previsão já ajuda muito as empresas)',
    input: ChoiceInput(compact: true, options: [
      for (var i = 0; i <= 5; i++)
        StepOption(id: '${y + i}', label: '${y + i}'),
      const StepOption(id: 'unsure', label: 'Ainda não sei'),
    ]),
    acknowledgement:
        'Boa! Isso ajuda a te encaixar na hora certa (trainee, estágio…). 🎓',
    // Save terminal da faculdade (addEducation) → não volta pra duplicar.
    reversible: false,
  );
}

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
        // Save terminal da escola (igual graduation/ofazia/link) → não duplica.
        reversible: false,
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
            ? 'Bora, uma por vez! Qual foi a empresa ou organização? '
                'Depois você adiciona as outras.'
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
        aiMessage: 'Trabalhou em mais algum lugar?',
        input: const ChoiceInput(options: [
          StepOption(id: 'yes', label: '+ Adicionar outra empresa'),
          StepOption(id: 'no', label: 'Não, era só essa'),
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
          example: 'Inglês avançado (TOEFL)',
          hint: 'Nome da certificação',
          maxLength: 100,
          minLines: 1,
        ),
      ),
      ConversationStep.single(
        id: 'cert.$n.issuer',
        aiMessage: 'Quem emitiu? (opcional — ex.: Google, Alura, Cambridge)',
        input: const GuidedTextInput(
          example: 'Google',
          hint: 'Emissor',
          maxLength: 80,
          minLines: 1,
          optional: true,
        ),
      ),
      ConversationStep.single(
        id: 'cert.$n.date',
        aiMessage: 'Quando você tirou? (se não lembrar, pula)',
        input: const MonthYearInput(optional: true),
        // Save terminal atômico (addCertification) → não volta pra duplicar.
        reversible: false,
      ),
      ConversationStep.single(
        id: 'cert.$n.more',
        aiMessage: 'Tem mais alguma?',
        input: const ChoiceInput(options: [
          StepOption(id: 'yes', label: '+ Adicionar outra'),
          StepOption(id: 'no', label: 'Não, é só'),
        ]),
        expand: (a) => _answeredYes(a) ? _certItem(n + 1) : const [],
      ),
    ];

// ── Extra: Conquistas / prêmios (dinâmico, espelha certificações) ────────────

ConversationStep _awardGate() => ConversationStep(
      id: 'award.gate',
      aiMessages: const [
        'Você já ganhou algum prêmio ou conquista? Vale competição, hackathon, '
            'bolsa, menção honrosa, destaque acadêmico, olimpíada… conta tudo.',
      ],
      input: const ChoiceInput(options: [
        StepOption(id: 'yes', label: 'Já sim'),
        StepOption(id: 'no', label: 'Ainda não'),
      ]),
      expand: (a) => _answeredYes(a) ? _awardItem(0) : const [],
    );

List<ConversationStep> _awardItem(int n) => [
      ConversationStep.single(
        id: 'award.$n.name',
        aiMessage: n == 0 ? 'Qual foi?' : 'E qual a próxima?',
        input: const GuidedTextInput(
          example: '1º lugar no Hackathon da USP',
          hint: 'Prêmio ou conquista',
          maxLength: 100,
          minLines: 1,
        ),
      ),
      ConversationStep.single(
        id: 'award.$n.date',
        aiMessage: 'Quando foi? (se não lembrar, pula)',
        input: const MonthYearInput(optional: true),
        // Save terminal atômico (addAward) → não volta pra duplicar.
        reversible: false,
      ),
      ConversationStep.single(
        id: 'award.$n.more',
        aiMessage: 'Tem mais alguma?',
        input: const ChoiceInput(options: [
          StepOption(id: 'yes', label: '+ Adicionar outra'),
          StepOption(id: 'no', label: 'Não, era só'),
        ]),
        expand: (a) => _answeredYes(a) ? _awardItem(n + 1) : const [],
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
        aiMessage: n == 0
            ? 'Bora, um por vez! Qual o nome do projeto? '
                'Depois você adiciona os outros.'
            : 'E o nome desse?',
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
      // Enriquecimento OPCIONAL (um toque pra pular) — data de início.
      ConversationStep.single(
        id: 'project.$n.when',
        aiMessage: 'Quando você começou? (se não lembrar, pula)',
        input: const MonthYearInput(optional: true),
      ),
      // Ainda tá rolando? Se não, pergunta quando terminou (espelha experiência).
      ConversationStep.single(
        id: 'project.$n.current',
        aiMessage: 'Você ainda está nesse projeto?',
        input: const ChoiceInput(options: [
          StepOption(id: 'yes', label: 'Sim, ainda'),
          StepOption(id: 'no', label: 'Não, encerrei'),
        ]),
        expand: (a) => _answeredYes(a)
            ? _projectTail(n)
            : [_projectEnd(n), ..._projectTail(n)],
      ),
    ];

ConversationStep _projectEnd(int n) => ConversationStep.single(
      id: 'project.$n.end',
      aiMessage: 'E quando terminou? (se não lembrar, pula)',
      input: const MonthYearInput(optional: true),
    );

List<ConversationStep> _projectTail(int n) => [
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
        aiMessage: 'Fez mais algum projeto?',
        input: const ChoiceInput(options: [
          StepOption(id: 'yes', label: '+ Adicionar outro projeto'),
          StepOption(id: 'no', label: 'Não, era só esse'),
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
