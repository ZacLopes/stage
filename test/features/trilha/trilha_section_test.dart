import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/trilha/application/conversation_controller.dart';
import 'package:career_gamification/features/trilha/application/trilha_section.dart';
import 'package:career_gamification/features/trilha/domain/conversation_step.dart';

/// Lógica pura do stepper de seções da aba Currículo (R3). Cobre o mapa
/// passo→seção (incluindo `outros`) e a derivação de status — em especial a
/// imunidade à injeção dinâmica de passos (loop de skills / níveis de idioma
/// não "des-concluem") e o "sticky" quando o passo atual cai em `outros`.

ConversationStep _step(String id) => ConversationStep.single(
      id: id,
      aiMessage: 'q',
      input: const ChoiceInput(options: [StepOption(id: 'a', label: 'A')]),
    );

ConversationExchange _ex(String stepId, {Object value = const ['a']}) =>
    ConversationExchange(
      step: _step(stepId),
      answer: StepAnswer(stepId: stepId, value: value, displayText: 'x'),
    );

void main() {
  group('trilhaSectionForStepId', () {
    test('mapeia as 5 seções pelos prefixos', () {
      expect(trilhaSectionForStepId('gap.edu.moment'), TrilhaSection.formacao);
      expect(
          trilhaSectionForStepId('gap.edu.semester'), TrilhaSection.formacao);
      expect(trilhaSectionForStepId('exp.gate'), TrilhaSection.experiencia);
      expect(
          trilhaSectionForStepId('exp.0.company'), TrilhaSection.experiencia);
      expect(trilhaSectionForStepId('gap.skills'), TrilhaSection.skills);
      expect(trilhaSectionForStepId('gap.skills.more.0'), TrilhaSection.skills);
      expect(trilhaSectionForStepId('gap.languages'), TrilhaSection.idiomas);
      expect(trilhaSectionForStepId('lang.level.Inglês'), TrilhaSection.idiomas);
      expect(
          trilhaSectionForStepId('gap.interests'), TrilhaSection.interesses);
      expect(
          trilhaSectionForStepId('interests.gate'), TrilhaSection.interesses);
    });

    test('passos fora das 5 caem em outros', () {
      const ids = [
        'intro',
        'gap.area',
        'gap.workmode',
        'gap.jobtype',
        'gap.city',
        'gap.availability',
        'linkedin.gate',
        'linkedin.url',
        'cert.0.name',
        'project.0.link',
      ];
      for (final id in ids) {
        expect(trilhaSectionForStepId(id), TrilhaSection.outros, reason: id);
      }
    });
  });

  group('sectionStatuses', () {
    test('vazio → todas as 5 seções pending', () {
      final s = sectionStatuses(history: const [], current: null);
      for (final sec in kStepperSections) {
        expect(s[sec], SectionStatus.pending, reason: sec.name);
      }
    });

    test('passo atual de uma das 5 → current', () {
      final s = sectionStatuses(
          history: const [], current: _step('gap.edu.moment'));
      expect(s[TrilhaSection.formacao], SectionStatus.current);
      expect(s[TrilhaSection.skills], SectionStatus.pending);
    });

    test('skills NÃO des-conclui no loop de mais skills; vira done quando sai',
        () {
      final history = [_ex('gap.skills')];
      // Ainda no loop "adicionar mais skills" → skills é a seção ativa.
      final s = sectionStatuses(
          history: history, current: _step('gap.skills.more.0'));
      expect(s[TrilhaSection.skills], SectionStatus.current);
      // Avançou pra formação → skills aparece concluída (done).
      final s2 = sectionStatuses(
          history: history, current: _step('gap.edu.moment'));
      expect(s2[TrilhaSection.skills], SectionStatus.done);
      expect(s2[TrilhaSection.formacao], SectionStatus.current);
    });

    test('idiomas NÃO des-conclui durante os níveis por idioma', () {
      final history = [_ex('gap.languages')];
      final s = sectionStatuses(
          history: history, current: _step('lang.level.Inglês'));
      expect(s[TrilhaSection.idiomas], SectionStatus.current);
      final s2 =
          sectionStatuses(history: history, current: _step('gap.interests'));
      expect(s2[TrilhaSection.idiomas], SectionStatus.done);
    });

    test('sticky: passo em outros mantém a última seção ativa destacada', () {
      final s = sectionStatuses(
        history: const [],
        current: _step('gap.city'), // outros
        stickyCurrent: TrilhaSection.formacao,
      );
      expect(s[TrilhaSection.formacao], SectionStatus.current);
    });

    test('preFilled marca seções já preenchidas no perfil como done', () {
      final s = sectionStatuses(
        history: const [],
        current: null,
        preFilled: const {
          TrilhaSection.experiencia,
          TrilhaSection.idiomas,
        },
      );
      expect(s[TrilhaSection.experiencia], SectionStatus.done);
      expect(s[TrilhaSection.idiomas], SectionStatus.done);
      expect(s[TrilhaSection.formacao], SectionStatus.pending);
    });

    test('passos terminais marcam done (experiência/formação/interesses)', () {
      expect(
        sectionStatuses(history: [_ex('exp.0.ofazia')], current: null)[
            TrilhaSection.experiencia],
        SectionStatus.done,
      );
      expect(
        sectionStatuses(history: [_ex('gap.edu.graduation')], current: null)[
            TrilhaSection.formacao],
        SectionStatus.done,
      );
      expect(
        sectionStatuses(history: [_ex('gap.interests')], current: null)[
            TrilhaSection.interesses],
        SectionStatus.done,
      );
    });
  });

  group('activeFiveSection', () {
    test('retorna a seção quando o passo é uma das 5, senão null', () {
      expect(activeFiveSection(_step('gap.skills')), TrilhaSection.skills);
      expect(activeFiveSection(_step('gap.city')), isNull); // outros
      expect(activeFiveSection(null), isNull);
    });
  });
}
