import 'dart:async';

import 'package:career_gamification/features/trilha/application/assistant_context_store.dart';
import 'package:career_gamification/features/trilha/application/conversation_controller.dart';
import 'package:career_gamification/features/trilha/application/trilha_session.dart';
import 'package:career_gamification/features/trilha/domain/conversation_step.dart';
import 'package:career_gamification/features/trilha/presentation/trilha_chat_controller.dart';
import 'package:career_gamification/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _SpyStore implements AssistantContextStore {
  _SpyStore([this.snapshot = const AssistantContextSnapshot.empty()]);

  AssistantContextSnapshot snapshot;
  int loads = 0;
  int saves = 0;
  int clears = 0;
  List<AssistantContextTurn> lastSaved = const [];

  @override
  Future<AssistantContextSnapshot> load(String userId) async {
    loads++;
    return snapshot;
  }

  @override
  Future<void> save(String userId, List<AssistantContextTurn> turns) async {
    saves++;
    lastSaved = List.unmodifiable(turns);
  }

  @override
  Future<void> clear(String userId) async {
    clears++;
  }
}

TrilhaChatController _buildController({
  required bool assistEnabled,
  required _SpyStore store,
  AssistantTurnFn? turn,
  Future<List<String>> Function()? preFilledLoader,
  void Function()? onSessionBuilt,
}) {
  Future<void> save(StepAnswer _) async {}
  final step = ConversationStep.single(
    id: 'profile.company',
    aiMessage: 'Qual empresa?',
    input: const GuidedTextInput(example: 'Stage'),
  );
  return TrilhaChatController(
    userId: 'user-a',
    assistEnabled: assistEnabled,
    assistantContextStore: store,
    assistantTurn: turn,
    preFilledLoader: preFilledLoader ?? () async => const ['skills'],
    sessionBuilder: (_) async {
      onSessionBuilt?.call();
      return TrilhaSession(
        controller: ConversationController([step], onAnswer: save),
        saveAnswer: save,
      );
    },
  );
}

void main() {
  test(
    'histórico leva turnos anteriores e mensagem atual apenas uma vez',
    () async {
      final store = _SpyStore(
        AssistantContextSnapshot(const [
          AssistantContextTurn(
            userText: 'pergunta anterior',
            assistantText: 'resposta anterior',
          ),
        ]),
      );
      String? receivedMessage;
      List<Map<String, dynamic>>? receivedHistory;
      Future<AssistantTurn?> assistantTurn({
        required String message,
        Map<String, dynamic>? openStep,
        Map<String, dynamic> context = const {},
        List<Map<String, dynamic>> history = const [],
      }) async {
        receivedMessage = message;
        receivedHistory = history;
        return const AssistantTurn(
          tool: 'answer_question',
          args: {},
          reply: 'resposta atual',
          promptVersion: 'test',
        );
      }

      final controller = _buildController(
        assistEnabled: true,
        store: store,
        turn: assistantTurn,
      );

      await controller.start();
      await controller.submitFreeText('mensagem atual');

      expect(receivedMessage, 'mensagem atual');
      expect(receivedHistory, [
        {'role': 'user', 'text': 'pergunta anterior'},
        {'role': 'assistant', 'text': 'resposta anterior'},
      ]);
      expect(
        receivedHistory!.where((row) => row['text'] == 'mensagem atual'),
        isEmpty,
      );
      expect(store.saves, 1);
      expect(store.lastSaved, hasLength(2));
      expect(store.lastSaved.last.userText, 'mensagem atual');
      expect(store.lastSaved.last.assistantText, 'resposta atual');
    },
  );

  test(
    'reabrir reidrata só bolhas textuais, sem greeting, cards ou writeback',
    () async {
      final store = _SpyStore(
        AssistantContextSnapshot(const [
          AssistantContextTurn(userText: 'Oi', assistantText: 'Como ajudo?'),
          AssistantContextTurn(
            userText: 'Quero vagas',
            assistantText: 'Vamos procurar.',
          ),
        ]),
      );
      var assistantCalls = 0;
      var sessionBuilds = 0;
      Future<AssistantTurn?> assistantTurn({
        required String message,
        Map<String, dynamic>? openStep,
        Map<String, dynamic> context = const {},
        List<Map<String, dynamic>> history = const [],
      }) async {
        assistantCalls++;
        return null;
      }

      final controller = _buildController(
        assistEnabled: true,
        store: store,
        onSessionBuilt: () => sessionBuilds++,
        turn: assistantTurn,
      );

      await controller.start();

      expect(store.loads, 1);
      expect(store.saves, 0);
      expect(sessionBuilds, 0);
      expect(assistantCalls, 0);
      expect(controller.inputVisible, isTrue);
      expect(controller.typing, isFalse);
      expect(controller.thread, hasLength(4));
      expect(
        controller.thread.every(
          (item) => item is UserMsgItem || item is AiMsgItem,
        ),
        isTrue,
      );
      expect(controller.thread.whereType<StarterChipsItem>(), isEmpty);
      expect(
        controller.thread
            .whereType<AiMsgItem>()
            .map((item) => item.text)
            .where((text) => text.contains('copiloto')),
        isEmpty,
      );
    },
  );

  test(
    'resposta que cria passo ou card não entra na memória textual',
    () async {
      final store = _SpyStore();
      Future<AssistantTurn?> assistantTurn({
        required String message,
        Map<String, dynamic>? openStep,
        Map<String, dynamic> context = const {},
        List<Map<String, dynamic>> history = const [],
      }) async => const AssistantTurn(
        tool: 'start_section',
        args: {'section': 'skills'},
        reply: 'Bora preencher suas skills.',
        promptVersion: 'test',
      );
      final controller = TrilhaChatController(
        userId: 'user-a',
        assistEnabled: true,
        assistantContextStore: store,
        assistantTurn: assistantTurn,
        assistSectionSteps: (_) => [
          ConversationStep.single(
            id: 'gap.skills',
            aiMessage: 'Quais skills?',
            input: const GuidedTextInput(example: 'SQL'),
          ),
        ],
        sessionBuilder: (_) async => TrilhaSession(
          controller: ConversationController(const []),
          saveAnswer: (_) async {},
        ),
      );
      addTearDown(controller.dispose);

      await controller.start();
      await controller.submitFreeText('quero preencher skills');

      expect(controller.currentStep?.id, 'gap.skills');
      expect(store.saves, 0);
    },
  );

  test('flag OFF faz zero load e zero write no store', () async {
    final store = _SpyStore(
      AssistantContextSnapshot(const [
        AssistantContextTurn(userText: 'antiga', assistantText: 'memória'),
      ]),
    );
    final filled = Completer<List<String>>();
    final controller = _buildController(
      assistEnabled: false,
      store: store,
      preFilledLoader: () => filled.future,
    );

    final opening = controller.start();
    expect(store.loads, 0);
    expect(store.saves, 0);
    controller.dispose();
    filled.complete(const []);
    await opening;

    expect(store.loads, 0);
    expect(store.saves, 0);
  });
}
