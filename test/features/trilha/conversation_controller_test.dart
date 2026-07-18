import 'dart:async';

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

    test('injectNext: injetado roda ANTES e o passo aberto RETOMA (parquear)',
        () async {
      final c = ConversationController(script());
      await c.submit(
          StepAnswer.choice('s1', const [StepOption(id: 'go', label: 'Bora')]));
      expect(c.current?.id, 's2'); // passo aberto
      // Assistente injeta uma seção sob demanda ANTES do passo aberto.
      c.injectNext([
        ConversationStep.single(
            id: 'gap.skills',
            aiMessage: 'q',
            input: const GuidedTextInput(example: 'x')),
      ]);
      expect(c.current?.id, 'gap.skills'); // injetado roda primeiro
      await c.submit(StepAnswer.text('gap.skills', 'Python'));
      expect(c.current?.id, 's2'); // o passo aberto retomou naturalmente
    });

    test('injectNext na trilha concluída: injetados viram o current', () async {
      final c = ConversationController(script());
      await c.submit(
          StepAnswer.choice('s1', const [StepOption(id: 'go', label: 'Bora')]));
      await c.submit(
          StepAnswer.choice('s2', const [StepOption(id: 'excel', label: 'Excel')]));
      expect(c.current, isNull); // concluída
      c.injectNext([
        ConversationStep.single(
            id: 'gap.city',
            aiMessage: 'q',
            input: const GuidedTextInput(example: 'x')),
      ]);
      expect(c.current?.id, 'gap.city');
      expect(c.isDone, false);
    });

    test('injectNext vazio é no-op', () {
      final c = ConversationController(script());
      c.injectNext(const []);
      expect(c.current?.id, 's1');
      expect(c.totalSteps, 2);
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

    test('falha no write-back mantém o passo e retry avança uma vez', () async {
      var shouldFail = true;
      var calls = 0;
      final c = ConversationController(
        script(),
        onAnswer: (a) async {
          calls++;
          if (shouldFail) throw Exception('rede caiu');
        },
      );
      final answer = StepAnswer.choice('s1', const [
        StepOption(id: 'go', label: 'Bora'),
      ]);

      final failed = await c.submit(answer);
      expect(failed, ConversationSubmitResult.writeFailed);
      expect(c.current?.id, 's1');
      expect(c.answeredCount, 0);
      expect(c.history, isEmpty);
      expect(c.isSaving, isFalse);
      expect(c.retryAnswer, same(answer));

      shouldFail = false;
      final retried = await c.submit(answer);
      expect(retried, ConversationSubmitResult.advanced);
      expect(c.current?.id, 's2');
      expect(c.answeredCount, 1);
      expect(calls, 2);
      expect(c.retryAnswer, isNull);
    });

    test('falha no write-back não injeta os passos do expand', () async {
      final c = ConversationController(
        [
          ConversationStep.single(
            id: 'gate',
            aiMessage: 'Tem?',
            input: const ChoiceInput(
              options: [StepOption(id: 'yes', label: 'Sim')],
            ),
            expand: (_) => [
              ConversationStep.single(
                id: 'follow-up',
                aiMessage: 'Conte mais',
                input: const GuidedTextInput(example: 'x'),
              ),
            ],
          ),
        ],
        onAnswer: (_) async {
          throw Exception('offline');
        },
      );

      final result = await c.submit(
        StepAnswer.choice('gate', const [StepOption(id: 'yes', label: 'Sim')]),
      );

      expect(result, ConversationSubmitResult.writeFailed);
      expect(c.current?.id, 'gate');
      expect(c.totalSteps, 1);
      expect(c.history, isEmpty);
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
          reversible: false, // simula exp.ofazia/project.link/cert.date
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

    test('goBack falha fechado se injectNext intercalou outra seção', () async {
      final tail = ConversationStep.single(
        id: 'tail',
        aiMessage: 'Tail',
        input: const GuidedTextInput(example: 'x'),
      );
      final gate = ConversationStep.single(
        id: 'gate',
        aiMessage: 'Gate',
        input: const ChoiceInput(
          options: [StepOption(id: 'yes', label: 'Sim')],
        ),
        expand: (_) => [tail],
      );
      final inserted = ConversationStep.single(
        id: 'inserted',
        aiMessage: 'Outra seção',
        input: const GuidedTextInput(example: 'y'),
      );
      final c = ConversationController([gate]);

      await c.submit(
        StepAnswer.choice(
          'gate',
          const [StepOption(id: 'yes', label: 'Sim')],
        ),
      );
      final gateExchange = c.history.single;
      c.injectNext([inserted]);

      expect(c.current, same(inserted));
      expect(c.canRewindExchange(gateExchange), isFalse);
      expect(c.canGoBack, isFalse);
      c.goBack();
      expect(c.history.single, same(gateExchange));
      expect(c.current, same(inserted));
      expect(c.totalSteps, 3); // gate + seção intercalada + tail original
    });

    test('revisão bloqueia rewind mesmo se reinjetar a mesma instância',
        () async {
      final tail = ConversationStep.single(
        id: 'tail',
        aiMessage: 'Tail',
        input: const GuidedTextInput(example: 'x'),
      );
      final gate = ConversationStep.single(
        id: 'gate',
        aiMessage: 'Gate',
        input: const GuidedTextInput(example: 'y'),
        expand: (_) => [tail],
      );
      final c = ConversationController([gate]);

      await c.submit(StepAnswer.text('gate', 'ok'));
      final exchange = c.history.single;
      c.injectNext([tail]);

      expect(c.current, same(tail));
      expect(c.canRewindExchange(exchange), isFalse);
      c.goBack();
      expect(c.history.single, same(exchange));
      expect(c.totalSteps, 3);
    });

    test('injectNext é recusado enquanto submit aguarda o write-back', () async {
      final writeGate = Completer<void>();
      final tail = ConversationStep.single(
        id: 'tail',
        aiMessage: 'Tail',
        input: const GuidedTextInput(example: 'x'),
      );
      final gate = ConversationStep.single(
        id: 'gate',
        aiMessage: 'Gate',
        input: const GuidedTextInput(example: 'y'),
        expand: (_) => [tail],
      );
      final inserted = ConversationStep.single(
        id: 'inserted',
        aiMessage: 'Outra seção',
        input: const GuidedTextInput(example: 'z'),
      );
      final c = ConversationController(
        [gate],
        onAnswer: (_) => writeGate.future,
      );

      final submission = c.submit(StepAnswer.text('gate', 'ok'));
      expect(c.isSaving, isTrue);
      expect(c.injectNext([inserted]), isFalse);
      expect(c.current, same(gate));
      expect(c.totalSteps, 1);

      writeGate.complete();
      expect(await submission, ConversationSubmitResult.advanced);
      expect(c.current, same(tail));
      expect(c.canGoBack, isTrue);
      c.goBack();
      expect(c.current, same(gate));
      expect(c.history, isEmpty);
      expect(c.totalSteps, 1);
    });

    test('restart volta ao começo', () async {
      final c = ConversationController(script());
      await c.submit(StepAnswer.choice('s1', const [StepOption(id: 'go', label: 'Bora')]));
      c.restart();
      expect(c.current?.id, 's1');
      expect(c.history, isEmpty);
      expect(c.progress, 0.0);
    });

    test('edição persistida substitui a resposta no histórico', () async {
      final c = ConversationController(script());
      await c.submit(
        StepAnswer.choice('s1', const [StepOption(id: 'go', label: 'Bora')]),
      );

      final changed = c.replaceLatestAnswer(
        StepAnswer.choice(
          's1',
          const [StepOption(id: 'go', label: 'Vamos')],
        ),
      );

      expect(changed, isTrue);
      expect(c.history.single.answer.displayText, 'Vamos');
      expect(c.replaceLatestAnswer(StepAnswer.text('unknown', 'x')), isFalse);
    });

    test('edição exata não confunde respostas que reutilizam o step id',
        () async {
      final repeated = ConversationStep.single(
        id: 'same',
        aiMessage: 'Mesmo passo',
        input: const GuidedTextInput(example: 'x'),
      );
      final c = ConversationController([repeated, repeated]);
      await c.submit(StepAnswer.text('same', 'primeira'));
      final first = c.history.single;
      await c.submit(StepAnswer.text('same', 'segunda'));
      final second = c.history.last;

      final replacement = c.replaceAnswer(
        first,
        StepAnswer.text('same', 'primeira corrigida'),
      );

      expect(replacement, isNotNull);
      expect(c.history.first.answer.displayText, 'primeira corrigida');
      expect(c.history.last.answer.displayText, 'segunda');
      expect(c.replaceAnswer(first, StepAnswer.text('same', 'stale')), isNull);
      expect(c.replaceAnswer(second, StepAnswer.text('wrong', 'x')), isNull);
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
