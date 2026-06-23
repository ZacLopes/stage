// Motor da Trilha de Coleta conversacional (PLANO-FASE-6 T6.3).
//
// Dirige uma fila de [ConversationStep]: expõe o passo atual, acumula o
// histórico do fio (pergunta da IA + resposta do usuário + reação da IA) e,
// ao responder, dispara um gancho de write-back ([onAnswer]) — que na fase
// seguinte plugamos no TrailToProfileBridge pra gravar em profile_*.
//
// É um ChangeNotifier puro (sem UI), testável de forma isolada. No Increment 1
// recebe uma fila roteirizada; depois a fila passa a ser montada pelo cérebro
// de lacunas ([ProfileGaps]).

import 'package:flutter/foundation.dart';

import '../domain/conversation_step.dart';

/// Uma troca concluída no fio: o passo (pergunta + reação) e a resposta dada.
@immutable
class ConversationExchange {
  final ConversationStep step;
  final StepAnswer answer;

  const ConversationExchange({required this.step, required this.answer});
}

class ConversationController extends ChangeNotifier {
  final List<ConversationStep> _steps;

  /// Gancho de write-back. Chamado a cada resposta. Defensivo: uma falha aqui
  /// NUNCA derruba a conversa (igual à filosofia do TrailToProfileBridge).
  final Future<void> Function(StepAnswer answer)? onAnswer;

  ConversationController(List<ConversationStep> steps, {this.onAnswer})
      : _steps = List.unmodifiable(steps);

  int _index = 0;
  final List<ConversationExchange> _history = [];
  bool _saving = false;

  /// Passo que o usuário está respondendo agora (nulo quando a trilha acabou).
  ConversationStep? get current =>
      _index < _steps.length ? _steps[_index] : null;

  /// Trocas já concluídas, na ordem do fio.
  List<ConversationExchange> get history => List.unmodifiable(_history);

  /// True quando não há mais passos.
  bool get isDone => _index >= _steps.length;

  /// True enquanto o gancho de write-back roda (pra UI travar o input).
  bool get isSaving => _saving;

  int get totalSteps => _steps.length;
  int get answeredCount => _history.length;

  /// Progresso 0..1 (respostas dadas / total de passos).
  double get progress =>
      _steps.isEmpty ? 1.0 : (_history.length / _steps.length).clamp(0.0, 1.0);

  /// Registra a resposta do passo atual, dispara o write-back e avança.
  /// Ignora chamadas reentrantes (enquanto salva) e respostas fora de ordem.
  Future<void> submit(StepAnswer answer) async {
    final step = current;
    if (step == null || _saving) return;
    if (answer.stepId != step.id) {
      assert(false, 'StepAnswer.stepId (${answer.stepId}) != current (${step.id})');
      return;
    }

    _saving = true;
    notifyListeners();

    if (onAnswer != null) {
      try {
        await onAnswer!(answer);
      } catch (e) {
        // Write-back é defensivo — a conversa continua mesmo se a gravação
        // falhar (o usuário pode completar o perfil mesmo offline-ish).
        debugPrint('[ConversationController] onAnswer falhou em ${step.id}: $e');
      }
    }

    _history.add(ConversationExchange(step: step, answer: answer));
    _index++;
    _saving = false;
    notifyListeners();
  }

  /// Reinicia a conversa (dev/preview).
  @visibleForTesting
  void restart() {
    _index = 0;
    _history.clear();
    _saving = false;
    notifyListeners();
  }
}
