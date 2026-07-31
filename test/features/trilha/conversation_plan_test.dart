import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/profile/application/profile_gaps.dart';
import 'package:career_gamification/features/trilha/application/conversation_plan.dart';
import 'package:career_gamification/features/trilha/application/trilha_draft.dart';
import 'package:career_gamification/features/trilha/domain/conversation_step.dart';

/// Cobre o construtor adaptativo do plano: só pergunta o que falta, e nunca
/// inclui o que está fora do escopo desta fase (experiência/resumo).
/// PLANO-FASE-6 T6.3 Increment 2.
void main() {
  ProfileGaps gaps({
    bool hasArea = false,
    bool hasWorkMode = false,
    bool hasJobType = false,
    bool hasCity = false,
    bool hasEducationStatus = false,
    int skillsCount = 0,
    int experienceCount = 0,
    int languagesCount = 0,
    bool hasSummary = false,
    bool hasDesiredPosition = true, // extras default "presentes" pra não poluir
    bool hasLinkedin = true, // os testes do core; testes de extra passam false
    bool hasCertifications = true,
    bool hasAwards = true,
    bool hasProjects = true,
    bool hasAvailability = true,
    bool hasInterests = true,
    bool hasCompanyStage = true,
    bool hasWorkEnvironment = true,
    bool hasWorkStyle = true,
    // P1-8: senioridade entrou como lacuna Tier 3. Default "presente" pela
    // mesma razão dos outros extras — os testes do núcleo não devem mudar de
    // tamanho a cada campo novo. Quem cobre a coleta dela é
    // `experience_level_step_test.dart`.
    bool hasExperienceLevel = true,
  }) =>
      analyzeProfileGaps(
        hasArea: hasArea,
        hasDesiredPosition: hasDesiredPosition,
        hasWorkMode: hasWorkMode,
        hasJobType: hasJobType,
        hasCity: hasCity,
        hasEducationStatus: hasEducationStatus,
        skillsCount: skillsCount,
        experienceCount: experienceCount,
        languagesCount: languagesCount,
        hasSummary: hasSummary,
        hasLinkedin: hasLinkedin,
        hasCertifications: hasCertifications,
        hasAwards: hasAwards,
        hasProjects: hasProjects,
        hasAvailability: hasAvailability,
        hasInterests: hasInterests,
        hasCompanyStage: hasCompanyStage,
        hasWorkEnvironment: hasWorkEnvironment,
        hasWorkStyle: hasWorkStyle,
        hasExperienceLevel: hasExperienceLevel,
      );

  group('buildConversationPlan', () {
    test('perfil oco: pergunta tudo o que esta fase cobre (intro + 7 + experiência)', () {
      final plan = buildConversationPlan(gaps());
      final ids = plan.map((s) => s.id).toList();
      expect(ids.first, 'intro');
      expect(
        ids,
        containsAll([
          'gap.area',
          'gap.workmode',
          'gap.jobtype',
          'gap.city',
          'gap.edu.moment', // educação (curso/semestre/nível) — chave p/ shortlist
          'gap.skills',
          'gap.languages',
          'exp.gate',
        ]),
      );
      expect(plan, hasLength(9)); // intro + 7 + gate de experiência
    });

    test('fit cultural: os 3 passos aparecem quando faltam; sumem quando cheios',
        () {
      final falta = buildConversationPlan(gaps(
        hasCompanyStage: false,
        hasWorkEnvironment: false,
        hasWorkStyle: false,
      )).map((s) => s.id);
      expect(
          falta,
          containsAll(const [
            'gap.company_stage',
            'gap.work_environment',
            'gap.work_style',
          ]));
      // Cheios (default do helper) → não re-pergunta.
      final cheio = buildConversationPlan(gaps()).map((s) => s.id);
      expect(cheio, isNot(contains('gap.company_stage')));
      expect(cheio, isNot(contains('gap.work_environment')));
      expect(cheio, isNot(contains('gap.work_style')));
    });

    test('sectionSteps: entrega os passos reais de UMA seção (ignora o gate)', () {
      // O assistente usa isto pra "quero preencher X" mesmo com a seção cheia.
      expect(sectionSteps(LacunaKey.skills).map((s) => s.id), contains('gap.skills'));
      expect(sectionSteps(LacunaKey.experience).map((s) => s.id), contains('exp.gate'));
      expect(sectionSteps(LacunaKey.city).map((s) => s.id), contains('gap.city'));
      expect(sectionSteps(LacunaKey.companyStage).map((s) => s.id),
          contains('gap.company_stage'));
      expect(sectionSteps(LacunaKey.availability).map((s) => s.id),
          contains('gap.availability'));
      // Resumo é gerado por IA, não perguntado.
      expect(sectionSteps(LacunaKey.summary), isEmpty);
    });

    test('perfil completo (só falta resumo, que é gerado): plano vazio', () {
      final plan = buildConversationPlan(gaps(
        hasArea: true,
        hasWorkMode: true,
        hasJobType: true,
        hasCity: true,
        hasEducationStatus: true,
        skillsCount: 5,
        languagesCount: 1,
        experienceCount: 1,
        // hasSummary: false → falta, mas é gerado (Inc 4), não perguntado
      ));
      expect(plan, isEmpty);
    });

    test('adaptativo: só skills faltando → intro + skills', () {
      final plan = buildConversationPlan(gaps(
        hasArea: true,
        hasWorkMode: true,
        hasJobType: true,
        hasCity: true,
        hasEducationStatus: true,
        skillsCount: 0, // só isso falta
        experienceCount: 1,
        languagesCount: 1,
      ));
      expect(plan.map((s) => s.id), ['intro', 'gap.skills']);
    });

    ProfileGaps skillsGap() => gaps(
          hasArea: true,
          hasWorkMode: true,
          hasJobType: true,
          hasCity: true,
          hasEducationStatus: true,
          skillsCount: 0,
          experienceCount: 1,
          languagesCount: 1,
        );

    StepAnswer picks(String stepId, List<String> names) => StepAnswer.choice(
        stepId, names.map((n) => StepOption(id: n, label: n)).toList());

    test('skills <3: loop OBRIGA chegar a 3 (IA na 1ª rodada, exige o que falta)',
        () {
      final plan = buildConversationPlan(skillsGap(),
          skillSuggester: () async => const ['Power BI']);
      final skills = plan.firstWhere((s) => s.id == 'gap.skills');

      // Escolheu 1 → boost rodada 1 (IA), exigindo as 2 que faltam.
      final r1 = skills.expand!(picks('gap.skills', ['Excel']));
      expect(r1.single.id, 'gap.skills.more.1');
      expect((r1.single.input as AsyncSuggestInput).minSelections, 2);

      // Marcou só +1 (total 2) → outra rodada, exigindo a que ainda falta.
      final r2 = r1.single.expand!(picks('gap.skills.more.1', ['SQL']));
      expect(r2.single.id, 'gap.skills.more.2');
      expect((r2.single.input as SuggestPickInput).minSelections, 1);

      // Atingiu 3 → o loop para.
      final done = r2.single.expand!(picks('gap.skills.more.2', ['CSS']));
      expect(done, isEmpty);
    });

    test('skills >=3: IA vira bônus opcional (minSelections 0 → pode pular)', () {
      final plan = buildConversationPlan(skillsGap(),
          skillSuggester: () async => const ['Power BI']);
      final skills = plan.firstWhere((s) => s.id == 'gap.skills');
      final bonus =
          skills.expand!(picks('gap.skills', ['Excel', 'Python', 'SQL']));
      expect(bonus.single.id, 'gap.skills.more.1');
      expect((bonus.single.input as AsyncSuggestInput).minSelections, 0);
    });

    test('skills <3 SEM IA: ainda obriga 3 via busca/texto livre', () {
      final plan = buildConversationPlan(skillsGap()); // sem suggester
      final skills = plan.firstWhere((s) => s.id == 'gap.skills');
      final r1 = skills.expand!(picks('gap.skills', ['Excel']));
      expect(r1.single.id, 'gap.skills.more.1');
      // Sem IA → picker comum, ainda exigindo as que faltam.
      expect((r1.single.input as SuggestPickInput).minSelections, 2);
    });

    test('idiomas: expande pro nível de CADA idioma escolhido (chips compactos)',
        () {
      final plan = buildConversationPlan(gaps(
        hasArea: true,
        hasWorkMode: true,
        hasJobType: true,
        hasCity: true,
        hasEducationStatus: true,
        skillsCount: 5,
        experienceCount: 1,
        languagesCount: 0,
      ));
      final langs = plan.firstWhere((s) => s.id == 'gap.languages');
      final levels =
          langs.expand!(picks('gap.languages', ['Português', 'Inglês', 'Espanhol']));
      // TODOS os idiomas escolhidos ganham passo de nível, inclusive português.
      expect(levels.map((s) => s.id),
          ['lang.level.Português', 'lang.level.Inglês', 'lang.level.Espanhol']);
      expect((levels.first.input as ChoiceInput).compact, true);
    });

    test('extras: pergunta LinkedIn, certificações e projetos quando faltam', () {
      final plan = buildConversationPlan(gaps(
        hasArea: true,
        hasWorkMode: true,
        hasJobType: true,
        hasCity: true,
        hasEducationStatus: true,
        skillsCount: 5,
        experienceCount: 1,
        languagesCount: 1,
        hasDesiredPosition: false,
        hasLinkedin: false,
        hasCertifications: false,
        hasAwards: false,
        hasProjects: false,
        hasAvailability: false,
        hasInterests: false,
      ));
      final ids = plan.map((s) => s.id);
      expect(
        ids,
        containsAll([
          'gap.desired_position', // cargo desejado (logo após áreas)
          'linkedin.gate',
          'cert.gate',
          'award.gate',
          'project.gate',
          'gap.interests', // interesses é OBRIGATÓRIO — pergunta direta, sem gate
          'gap.availability',
        ]),
      );
      // Interesses não tem mais gate "quer? sim/não" (é obrigatório) e deixa
      // ADICIONAR um tema fora da lista (SuggestPickInput, mín. 1).
      expect(ids, isNot(contains('interests.gate')));
      final interests = plan.firstWhere((s) => s.id == 'gap.interests');
      expect(interests.input, isA<SuggestPickInput>());
      expect((interests.input as SuggestPickInput).minSelections, 1);
      expect((interests.input as SuggestPickInput).allowFreeText, isTrue);
      // gate expande na resposta "sim".
      final certGate = plan.firstWhere((s) => s.id == 'cert.gate');
      final yes = certGate.expand!(StepAnswer.choice(
          'cert.gate', const [StepOption(id: 'yes', label: 'Sim')]));
      expect(yes.map((s) => s.id), contains('cert.0.name'));
    });

    test('nunca inclui passo de resumo (gerado, não perguntado)', () {
      final plan = buildConversationPlan(gaps());
      final ids = plan.map((s) => s.id);
      expect(ids.any((id) => id.contains('summary')), false);
    });

    test('educação: gate só aparece se faltar; ramos faculdade/escola/outro', () {
      // hasEducationStatus=false (default) → lacuna → gate presente.
      final plan = buildConversationPlan(gaps());
      final moment = plan.firstWhere((s) => s.id == 'gap.edu.moment');

      final college = moment.expand!(StepAnswer.choice(
          'gap.edu.moment', const [StepOption(id: 'in_college', label: 'x')]));
      expect(college.map((s) => s.id),
          containsAll(['gap.edu.institution', 'gap.edu.course', 'gap.edu.semester']));

      final school = moment.expand!(StepAnswer.choice(
          'gap.edu.moment', const [StepOption(id: 'in_school', label: 'x')]));
      expect(school.map((s) => s.id),
          containsAll(['gap.edu.school', 'gap.edu.schoolyear']));

      final outro = moment.expand!(StepAnswer.choice(
          'gap.edu.moment', const [StepOption(id: 'outro', label: 'x')]));
      expect(outro, isEmpty); // fora do público-alvo → não coleta mais

      // Já tem status → sem gate.
      final filled = buildConversationPlan(gaps(hasEducationStatus: true));
      expect(filled.map((s) => s.id), isNot(contains('gap.edu.moment')));
    });

    test('resumabilidade: draft de experiência suprime o gate e retoma no passo',
        () {
      final plan = buildConversationPlan(gaps(), drafts: const [
        TrilhaItemDraft(
            kind: 'experience',
            itemIndex: 0,
            lastStepId: 'exp.0.estagio.start',
            fields: {'kind': 'estagio', 'company': 'X', 'role': 'Y'}),
      ]);
      final ids = plan.map((s) => s.id);
      expect(ids, isNot(contains('exp.gate'))); // gate suprimido
      expect(ids, contains('exp.0.estagio.current')); // retoma logo após 'start'
      expect(ids,
          isNot(contains('exp.0.estagio.company'))); // não re-pergunta o feito
    });

    test('resumabilidade: draft de projeto retoma após o último passo', () {
      final plan = buildConversationPlan(gaps(hasProjects: false), drafts: const [
        TrilhaItemDraft(
            kind: 'project',
            itemIndex: 0,
            lastStepId: 'project.0.did',
            fields: {}),
      ]);
      final ids = plan.map((s) => s.id);
      expect(ids, isNot(contains('project.gate')));
      // Retoma em 'when' e segue até o gate 'current' (o 'link' vem depois, via
      // expand do current — espelha o fluxo de experiência).
      expect(ids, containsAll(['project.0.when', 'project.0.current']));
      expect(ids, isNot(contains('project.0.name'))); // já respondido
    });

    test('resumabilidade: draft de projeto que JÁ ENCERROU pede a data de fim',
        () {
      final plan = buildConversationPlan(gaps(hasProjects: false), drafts: const [
        TrilhaItemDraft(
            kind: 'project',
            itemIndex: 0,
            lastStepId: 'project.0.current',
            fields: {'isCurrent': false}),
      ]);
      final ids = plan.map((s) => s.id);
      expect(ids, containsAll(['project.0.end', 'project.0.link']));
    });

    test('resumabilidade: draft de educação (faculdade) retoma no curso', () {
      final plan = buildConversationPlan(gaps(), drafts: const [
        TrilhaItemDraft(
            kind: 'education',
            itemIndex: 0,
            lastStepId: 'gap.edu.institution',
            fields: {'moment': 'in_college'}),
      ]);
      final ids = plan.map((s) => s.id);
      expect(ids, isNot(contains('gap.edu.moment'))); // momento já respondido
      expect(ids,
          containsAll(['gap.edu.course', 'gap.edu.semester', 'gap.edu.graduation']));
      expect(ids, isNot(contains('gap.edu.institution'))); // já respondido
    });

    test('resumabilidade: abandonou no semestre → retoma só na formatura', () {
      final plan = buildConversationPlan(gaps(), drafts: const [
        TrilhaItemDraft(
            kind: 'education',
            itemIndex: 0,
            lastStepId: 'gap.edu.semester',
            fields: {'moment': 'in_college'}),
      ]);
      final ids = plan.map((s) => s.id).toList();
      // Só falta a previsão de formatura (o passo terminal da faculdade).
      expect(ids, contains('gap.edu.graduation'));
      expect(
          ids,
          isNot(anyElement(isIn(const [
            'gap.edu.moment',
            'gap.edu.institution',
            'gap.edu.course',
            'gap.edu.semester',
          ]))));
    });

    test('experiência: o seletor enfileira UM item por tipo escolhido + "more"; '
        'vazio (pulou) não enfileira nada', () {
      final plan = buildConversationPlan(gaps());
      final gate = plan.firstWhere((s) => s.id == 'exp.gate');
      // Escolheu 2 estágios + 1 voluntariado → 3 itens, com índices globais.
      final picked = gate.expand!(StepAnswer(
        stepId: 'exp.gate',
        value: const ['estagio', 'estagio', 'voluntariado'],
        displayText: 'Estágio ×2, Voluntariado',
      ));
      final ids = picked.map((s) => s.id).toList();
      // Cada tipo vira um bloco (perguntas na língua do tipo), com n global.
      expect(ids, contains('exp.0.estagio.company'));
      expect(ids, contains('exp.1.estagio.company'));
      expect(ids, contains('exp.2.voluntariado.company'));
      // Ao fim, "adicionar outra?" (reabre o seletor).
      expect(ids, contains('exp.more'));
      // Pulou (lista vazia) → não enfileira nada.
      final none = gate.expand!(StepAnswer(
          stepId: 'exp.gate', value: const <String>[], displayText: 'pulou'));
      expect(none, isEmpty);
    });

    test('experiência "outro": o bloco começa pedindo o nome do tipo (label)', () {
      final plan = buildConversationPlan(gaps());
      final gate = plan.firstWhere((s) => s.id == 'exp.gate');
      final picked = gate.expand!(StepAnswer(
          stepId: 'exp.gate', value: const ['outro'], displayText: 'Outro'));
      expect(picked.map((s) => s.id), contains('exp.0.outro.label'));
    });

    test('experiência: pede resultado verificável, sem incentivar invenção', () {
      final plan = buildConversationPlan(gaps());
      final gate = plan.firstWhere((s) => s.id == 'exp.gate');
      final picked = gate.expand!(StepAnswer(
          stepId: 'exp.gate', value: const ['estagio'], displayText: 'Estágio'));
      final current =
          picked.firstWhere((s) => s.id == 'exp.0.estagio.current');
      final tail = current.expand!(StepAnswer.choice(
          'exp.0.estagio.current',
          const [StepOption(id: 'yes', label: 'Sim, ainda estou')]));
      final result = tail.firstWhere((s) => s.id == 'exp.0.estagio.ofazia');
      final prompt = result.aiMessages.join(' ');

      expect(prompt, contains('qual foi o resultado'));
      expect(prompt, contains('números, prazo ou escala'));
      expect(prompt, contains('só o que você consegue defender'));
    });

    test('experiência: a IA RESUME o item anotado (recap no passo terminal)', () {
      final plan = buildConversationPlan(gaps());
      final gate = plan.firstWhere((s) => s.id == 'exp.gate');
      final items = gate.expand!(StepAnswer(
          stepId: 'exp.gate', value: const ['estagio'], displayText: ''));
      final current =
          items.firstWhere((s) => s.id == 'exp.0.estagio.current');
      // "Não estou mais" → revela [end, ofazia].
      final tail = current.expand!(StepAnswer.choice(
          'exp.0.estagio.current', const [StepOption(id: 'no', label: 'Não')]));
      final ofazia = tail.firstWhere((s) => s.id == 'exp.0.estagio.ofazia');
      expect(ofazia.recap, isNotNull);

      final history = [
        StepAnswer.text('exp.0.estagio.company', 'Magalu'),
        StepAnswer.text('exp.0.estagio.role', 'Estagiário'),
        StepAnswer.monthYear('exp.0.estagio.start', 2023, 3),
        StepAnswer.choice('exp.0.estagio.current',
            const [StepOption(id: 'no', label: 'Não')]),
        StepAnswer.monthYear('exp.0.estagio.end', 2024, 12),
        StepAnswer.text('exp.0.estagio.ofazia', 'fiz coisas'),
      ];
      final recap = ofazia.recap!(history)!;
      expect(recap, contains('Estagiário'));
      expect(recap, contains('Magalu'));
      expect(recap, contains('Estágio')); // rótulo do tipo
      expect(recap, contains('03/2023 – 12/2024')); // período
    });

    test('todo passo do plano tem uma fala e uma entrada', () {
      final plan = buildConversationPlan(gaps());
      for (final step in plan) {
        expect(step.aiMessages, isNotEmpty);
        expect(step.aiMessages.first.trim(), isNotEmpty);
      }
    });

    test('memória: trechos abordados são pulados (não re-pergunta)', () {
      // Tudo falta, mas skills e experiência já foram abordados antes.
      final plan =
          buildConversationPlan(gaps(), addressed: {'skills', 'experience'});
      final ids = plan.map((s) => s.id);
      expect(ids, isNot(contains('gap.skills')));
      expect(ids, isNot(contains('exp.gate')));
      expect(ids, contains('gap.area')); // os outros ainda são perguntados
    });

    test('memória: tudo abordado → plano vazio', () {
      final plan = buildConversationPlan(gaps(), addressed: {
        'area',
        'workmode',
        'jobtype',
        'city',
        'education',
        'skills',
        'languages',
        'experience',
      });
      expect(plan, isEmpty);
    });
  });
}
