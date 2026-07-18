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

  /// Passos exatos que o `expand` injetou. Guardar as identidades, e não apenas
  /// a quantidade, permite recusar um rewind se outra seção tiver sido
  /// intercalada na fila.
  final List<ConversationStep> expandedSteps;

  /// Revisão da fila quando a troca foi confirmada. Qualquer `injectNext`
  /// posterior invalida o rewind, inclusive se reinjetar a mesma instância de
  /// passo e a comparação por identidade isolada pudesse parecer válida.
  final int queueRevision;

  int get expandedCount => expandedSteps.length;

  const ConversationExchange({
    required this.step,
    required this.answer,
    this.expandedSteps = const [],
    this.queueRevision = 0,
  });
}

/// Resultado observável de uma submissão. A UI usa este contrato para nunca
/// exibir acknowledgement nem avançar quando o perfil não foi persistido.
enum ConversationSubmitResult { advanced, ignored, writeFailed }

class ConversationController extends ChangeNotifier {
  final List<ConversationStep> _steps;

  /// Gancho de write-back. Chamado a cada resposta. Uma falha é devolvida como
  /// [ConversationSubmitResult.writeFailed] e mantém o passo aberto para retry.
  final Future<void> Function(StepAnswer answer)? onAnswer;

  ConversationController(List<ConversationStep> steps, {this.onAnswer})
    : _steps = List.of(steps);

  int _index = 0;
  final List<ConversationExchange> _history = [];
  bool _saving = false;
  StepAnswer? _retryAnswer;
  int _queueRevision = 0;

  /// Passo que o usuário está respondendo agora (nulo quando a trilha acabou).
  ConversationStep? get current =>
      _index < _steps.length ? _steps[_index] : null;

  /// Trocas já concluídas, na ordem do fio.
  List<ConversationExchange> get history => List.unmodifiable(_history);

  /// True quando não há mais passos.
  bool get isDone => _index >= _steps.length;

  /// True enquanto o gancho de write-back roda (pra UI travar o input).
  bool get isSaving => _saving;

  /// Última resposta cuja persistência falhou. Permite retry de um toque sem
  /// obrigar a pessoa a redigitar ou reconstruir uma seleção longa.
  StepAnswer? get retryAnswer => _retryAnswer;

  int get totalSteps => _steps.length;
  int get answeredCount => _history.length;

  /// Progresso 0..1 (respostas dadas / total de passos).
  double get progress =>
      _steps.isEmpty ? 1.0 : (_history.length / _steps.length).clamp(0.0, 1.0);

  /// Registra a resposta do passo atual, dispara o write-back e avança.
  /// Ignora chamadas reentrantes (enquanto salva) e respostas fora de ordem.
  Future<ConversationSubmitResult> submit(StepAnswer answer) async {
    final step = current;
    if (step == null || _saving) return ConversationSubmitResult.ignored;
    if (answer.stepId != step.id) {
      assert(
        false,
        'StepAnswer.stepId (${answer.stepId}) != current (${step.id})',
      );
      return ConversationSubmitResult.ignored;
    }

    // Calcula a expansão antes da gravação. `expand` é puro; assim uma
    // eventual exceção nele nunca acontece depois de um write bem-sucedido.
    final more = step.expand?.call(answer) ?? const <ConversationStep>[];
    final submissionIndex = _index;
    final submissionRevision = _queueRevision;

    _saving = true;
    notifyListeners();

    try {
      if (onAnswer != null) {
        await onAnswer!(answer);
      }
    } catch (e) {
      // Não expõe o erro bruto na UI/analytics. O mesmo passo fica aberto e a
      // resposta pode ser reenviada quando a conexão voltar.
      debugPrint('[ConversationController] onAnswer falhou em ${step.id}: $e');
      _retryAnswer = answer;
      _saving = false;
      notifyListeners();
      return ConversationSubmitResult.writeFailed;
    }

    // `injectNext` e `restart` recusam mutação enquanto salva. Esta validação
    // mantém o motor fail-closed caso um novo mutador seja adicionado no futuro.
    final positionIsStable = _index == submissionIndex &&
        _queueRevision == submissionRevision &&
        submissionIndex < _steps.length &&
        identical(_steps[submissionIndex], step);
    if (!positionIsStable) {
      assert(false, 'A fila mudou durante ConversationController.submit');
      _saving = false;
      notifyListeners();
      return ConversationSubmitResult.ignored;
    }

    _index++;
    _retryAnswer = null;

    // Passos DINÂMICOS: o passo pode injetar follow-ups (loops "adicionar
    // outra?", ramos condicionais) logo após a posição atual.
    if (more.isNotEmpty) {
      _steps.insertAll(_index, more);
    }

    _history.add(
      ConversationExchange(
        step: step,
        answer: answer,
        expandedSteps: List<ConversationStep>.unmodifiable(more),
        queueRevision: _queueRevision,
      ),
    );

    _saving = false;
    notifyListeners();
    return ConversationSubmitResult.advanced;
  }

  /// Injeta passos na fila NO ponto atual (mesma mecânica do `expand`) — o
  /// assistente usa isto pra "entregar as perguntas" de uma seção sob demanda.
  /// Inserindo em [_index] o resultado é elegante nos dois casos:
  ///  - trilha ociosa/concluída (sem passo atual): os passos injetados viram o
  ///    novo `current`;
  ///  - com um passo ABERTO: os injetados entram ANTES dele → rodam primeiro e o
  ///    passo aberto RETOMA naturalmente depois (parquear/retomar de graça, pela
  ///    ordem da fila). No-op se vazio.
  bool injectNext(List<ConversationStep> steps) {
    if (steps.isEmpty || _saving) return false;
    final at = _index.clamp(0, _steps.length);
    _steps.insertAll(at, steps);
    _queueRevision++;
    notifyListeners();
    return true;
  }

  /// Pode voltar pro passo anterior? Só quando o último passo respondido é
  /// REVERSÍVEL (re-responder corrige, não duplica) — ver [ConversationStep].
  bool get canGoBack =>
      _history.isNotEmpty && canRewindExchange(_history.last);

  /// Verdadeiro apenas quando [exchange] ainda é a última troca e os
  /// follow-ups que ela inseriu continuam, por identidade, no segmento que
  /// seria removido. Qualquer intercalação faz o rewind falhar fechado.
  bool canRewindExchange(ConversationExchange exchange) {
    if (_saving ||
        _history.isEmpty ||
        !identical(_history.last, exchange) ||
        exchange.queueRevision != _queueRevision ||
        !exchange.step.reversible) {
      return false;
    }
    final expanded = exchange.expandedSteps;
    if (_index + expanded.length > _steps.length) return false;
    for (var offset = 0; offset < expanded.length; offset++) {
      if (!identical(_steps[_index + offset], expanded[offset])) return false;
    }
    return true;
  }

  /// Volta um passo: remove a última troca do histórico, descarta os passos
  /// que o `expand` dela injetou, e re-aponta o passo anterior pra ser
  /// re-respondido. NÃO desfaz o write-back (o passo é reversível → re-responder
  /// sobrescreve/é idempotente). No-op se [canGoBack] for falso.
  void goBack() {
    if (!canGoBack) return;
    final last = _history.removeLast();
    // Os passos injetados pelo expand ficam logo após a posição atual (foram
    // inseridos em _index após o incremento do submit).
    if (last.expandedSteps.isNotEmpty) {
      _steps.removeRange(_index, _index + last.expandedSteps.length);
    }
    _index--;
    notifyListeners();
  }

  /// Atualiza o histórico visual depois que uma edição segura foi realmente
  /// persistida. Nunca antecipa o card em relação ao write-back.
  bool replaceLatestAnswer(StepAnswer answer) {
    for (var i = _history.length - 1; i >= 0; i--) {
      final exchange = _history[i];
      if (exchange.step.id != answer.stepId) continue;
      _history[i] = ConversationExchange(
        step: exchange.step,
        answer: answer,
        expandedSteps: exchange.expandedSteps,
        queueRevision: exchange.queueRevision,
      );
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Substitui uma troca específica somente se ela ainda pertencer ao
  /// histórico vivo. A identidade evita confundir coletas diferentes que
  /// reutilizam o mesmo `stepId`.
  ConversationExchange? replaceAnswer(
    ConversationExchange expected,
    StepAnswer answer,
  ) {
    if (expected.step.id != answer.stepId) return null;
    final index = _history.indexWhere((item) => identical(item, expected));
    if (index < 0) return null;
    final replacement = ConversationExchange(
      step: expected.step,
      answer: answer,
      expandedSteps: expected.expandedSteps,
      queueRevision: expected.queueRevision,
    );
    _history[index] = replacement;
    notifyListeners();
    return replacement;
  }

  /// Reinicia a conversa (dev/preview).
  @visibleForTesting
  void restart() {
    if (_saving) return;
    _index = 0;
    _history.clear();
    _saving = false;
    _retryAnswer = null;
    _queueRevision = 0;
    notifyListeners();
  }
}
