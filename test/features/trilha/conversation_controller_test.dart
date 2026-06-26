import 'package:flutter_test/flutter_test.dart';
import 'package:career_gamification/features/trilha/application/conversation_controller.dart';
import 'package:career_gamification/features/trilha/domain/conversation_step.dart';

/// Cobre o motor conversacional: avanço da fila, histórico do fio, progresso,
/// gancho de write-back e robustez (PLANO-FASE-6 T6.3).
void main() {
  List<ConversationStep> script() => [
        ConversationStep.single(
          id: 's1',
          aiMessage: 'Oi!',
          input: const ChoiceInput(options: [StepOption(id: 'go', label: 'Bora')]),
        ),
        ConversationStep.single(
          id: 's2',
          aiMessage: 'Suas skills?',
          input: const ChoiceInput(
            multi: true,
            options: [StepOption(id: 'excel', label: 'Excel')],
          ),
        ),
      ];

  group('ConversationController', () {
    test('estado inicial: 1º passo atual, sem histórico, progresso 0', () {
      final c = ConversationController(script());
      expect(c.current?.id, 's1');
      expect(c.history, isEmpty);
      expect(c.isDone, false);
      expect(c.progress, 0.0);
      expect(c.totalSteps, 2);
    });

    test('submit avança a fila e cresce o histórico', () async {
      final c = ConversationController(script());
      await c.submit(StepAnswer.choice('s1', const [StepOption(id: 'go', label: 'Bora')]));
      expect(c.current?.id, 's2');
      expect(c.answeredCount, 1);
      expect(c.history.first.step.id, 's1');
      expect(c.progress, 0.5);
      expect(c.isDone, false);
    });

    test('responder todos os passos termina a trilha', () async {
      final c = ConversationController(script());
      await c.submit(StepAnswer.choice('s1', const [StepOption(id: 'go', label: 'Bora')]));
      await c.submit(StepAnswer.choice('s2', const [StepOption(id: 'excel', label: 'Excel')]));
      expect(c.isDone, true);
      expect(c.current, isNull);
      expect(c.progress, 1.0);
      expect(c.answeredCount, 2);
    });

    test('o gancho de write-back é chamado com a resposta', () async {
      final captured = <StepAnswer>[];
      final c = ConversationController(script(), onAnswer: (a) async {
        captured.add(a);
      });
      await c.submit(StepAnswer.choice('s1', const [StepOption(id: 'go', label: 'Bora')]));
      expect(captured, hasLength(1));
      expect(captured.first.stepId, 's1');
      expect(captured.first.value, ['go']);
    });

    test('falha no write-back NÃO derruba a conversa (defensivo)', () async {
      final c = ConversationController(script(), onAnswer: (a) async {
        throw Exception('rede caiu');
      });
      // Não deve lançar — e deve avançar mesmo assim.
      await c.submit(StepAnswer.choice('s1', const [StepOption(id: 'go', label: 'Bora')]));
      expect(c.current?.id, 's2');
      expect(c.answeredCount, 1);
    });

    test('goBack volta um passo: reverte índice e histórico', () async {
      final c = ConversationController(script());
      await c.submit(
          StepAnswer.choice('s1', const [StepOption(id: 'go', label: 'Bora')]));
      expect(c.current?.id, 's2');
      expect(c.canGoBack, true); // s1 é reversível
      c.goBack();
      expect(c.current?.id, 's1'); // voltou
      expect(c.answeredCount, 0);
      expect(c.history, isEmpty);
    });

    test('canGoBack é false sem histórico (1º passo)', () {
      final c = ConversationController(script());
      expect(c.canGoBack, false);
    });

    test('canGoBack é false em passo NÃO-reversível (save que insere)',
        () async {
      final c = ConversationController([
        ConversationStep.single(
          id: 's1',
          aiMessage: 'x',
          input: const ChoiceInput(options: [StepOption(id: 'go', label: 'Bora')]),
          reversible: false, // simula exp.ofazia/project.link/cert.name
        ),
        script()[1],
      ]);
      await c.submit(
          StepAnswer.choice('s1', const [StepOption(id: 'go', label: 'Bora')]));
      expect(c.canGoBack, false); // não dá pra voltar e duplicar
      c.goBack(); // no-op
      expect(c.current?.id, 's2'); // não voltou
      expect(c.answeredCount, 1);
    });

    test('goBack remove os passos que o expand injetou', () async {
      final c = ConversationController([
        ConversationStep.single(
          id: 'gate',
          aiMessage: 'Tem?',
          input: const ChoiceInput(options: [StepOption(id: 'yes', label: 'Sim')]),
          expand: (a) => [
            ConversationStep.single(
                id: 'item.a',
                aiMessage: 'A?',
                input: const ChoiceInput(options: [StepOption(id: 'x', label: 'X')])),
            ConversationStep.single(
                id: 'item.b',
                aiMessage: 'B?',
                input: const ChoiceInput(options: [StepOption(id: 'y', label: 'Y')])),
          ],
        ),
        ConversationStep.single(
            id: 'fim',
            aiMessage: 'Fim',
            input: const ChoiceInput(options: [StepOption(id: 'z', label: 'Z')])),
      ]);
      await c.submit(
          StepAnswer.choice('gate', const [StepOption(id: 'yes', label: 'Sim')]));
      expect(c.current?.id, 'item.a'); // injetou item.a + item.b
      expect(c.totalSteps, 4);
      c.goBack(); // volta pro gate
      expect(c.current?.id, 'gate');
      expect(c.totalSteps, 2); // item.a/item.b removidos (sem follow-ups órfãos)
    });

    test('restart volta ao começo', () async {
      final c = ConversationController(script());
      await c.submit(StepAnswer.choice('s1', const [StepOption(id: 'go', label: 'Bora')]));
      c.restart();
      expect(c.current?.id, 's1');
      expect(c.history, isEmpty);
      expect(c.progress, 0.0);
    });

    test('StepAnswer.text monta value e displayText corretos', () {
      final a = StepAnswer.text('s3', '  organizei um evento  ');
      expect(a.value, 'organizei um evento');
      expect(a.displayText, 'organizei um evento');
    });

    test('expand injeta passos dinâmicos logo após a resposta', () async {
      final steps = [
        ConversationStep.single(
          id: 'gate',
          aiMessage: 'mais?',
          input: const ChoiceInput(options: [StepOption(id: 'yes', label: 'Sim')]),
          expand: (a) => [
            ConversationStep.single(
              id: 'extra',
              aiMessage: 'extra',
              input: const ChoiceInput(options: [StepOption(id: 'ok', label: 'Ok')]),
            ),
          ],
        ),
      ];
      final c = ConversationController(steps);
      expect(c.totalSteps, 1);
      await c.submit(
          StepAnswer.choice('gate', const [StepOption(id: 'yes', label: 'Sim')]));
      // O passo injetado virou o atual; a trilha não terminou.
      expect(c.current?.id, 'extra');
      expect(c.totalSteps, 2);
      expect(c.isDone, false);
    });

    test('expand vazio: nada injetado, trilha segue normal', () async {
      final steps = [
        ConversationStep.single(
          id: 'gate',
          aiMessage: 'mais?',
          input: const ChoiceInput(options: [StepOption(id: 'no', label: 'Não')]),
          expand: (a) => const [],
        ),
      ];
      final c = ConversationController(steps);
      await c.submit(
          StepAnswer.choice('gate', const [StepOption(id: 'no', label: 'Não')]));
      expect(c.isDone, true);
    });
  });
}
