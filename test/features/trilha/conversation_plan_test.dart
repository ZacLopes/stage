import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/profile/application/profile_gaps.dart';
import 'package:career_gamification/features/trilha/application/conversation_plan.dart';
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
    bool hasLinkedin = true, // extras default "presentes" pra não poluir os
    bool hasCertifications = true, // testes do core; testes de extra passam false
    bool hasProjects = true,
    bool hasAvailability = true,
    bool hasInterests = true,
  }) =>
      analyzeProfileGaps(
        hasArea: hasArea,
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
        hasProjects: hasProjects,
        hasAvailability: hasAvailability,
        hasInterests: hasInterests,
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

    test('idiomas: expande pro nível de cada idioma NÃO-nativo (chips compactos)',
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
      // Português = nativo (sem passo); os demais ganham passo de nível.
      expect(levels.map((s) => s.id),
          ['lang.level.Inglês', 'lang.level.Espanhol']);
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
        hasLinkedin: false,
        hasCertifications: false,
        hasProjects: false,
        hasAvailability: false,
        hasInterests: false,
      ));
      final ids = plan.map((s) => s.id);
      expect(
        ids,
        containsAll([
          'linkedin.gate',
          'cert.gate',
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

    test('experiência: a gate expande em item ao responder "sim", vazio no "não"', () {
      final plan = buildConversationPlan(gaps());
      final gate = plan.firstWhere((s) => s.id == 'exp.gate');
      final yes = gate.expand!(StepAnswer.choice(
          'exp.gate', const [StepOption(id: 'yes', label: 'Sim')]));
      expect(yes.map((s) => s.id), contains('exp.0.company'));
      final no = gate.expand!(StepAnswer.choice(
          'exp.gate', const [StepOption(id: 'no', label: 'Não')]));
      expect(no, isEmpty);
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
