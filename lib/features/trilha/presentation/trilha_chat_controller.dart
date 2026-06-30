// Orquestrador do chat da trilha v2 (PLANO chat v2 — F2 + F3).
//
// Dono do FIO. Três fases:
//   - gate: abre perguntando "começar do zero / já tenho currículo".
//   - importing: leu o PDF → "Lendo…" → poll da extração → card-resumo.
//   - converse: a conversa guiada pelas lacunas (recomputadas após o import).
//
// A sessão das lacunas ([TrilhaSession]) é construída SÓ ao entrar em `converse`
// — depois do import, então reflete o que a extração preencheu (menos perguntas).
// Edição de card é in-place (re-save idempotente via [TrilhaSession.saveAnswer]).

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../services/ai_service.dart';
import '../../../services/analytics_events.dart';
import '../../../services/analytics_service.dart';
import '../../../services/profile_snapshot_service.dart';
import '../application/conversation_controller.dart';
import '../application/trilha_session.dart';
import '../domain/conversation_step.dart';

/// Camada que interpreta texto livre → ids de opção (default: [AIService]).
/// Injetável p/ teste. Assinatura = [AIService.interpretStepAnswer].
typedef StepInterpreter = Future<StepInterpretation?> Function({
  required String stepId,
  required String question,
  required String freeText,
  required List<Map<String, String>> options,
  bool multi,
});

Duration _typingFor(String msg) =>
    Duration(milliseconds: (msg.length * 16).clamp(420, 1200).toInt());
Duration _pauseFor(String msg) =>
    Duration(milliseconds: (msg.length * 4).clamp(200, 460).toInt());

enum ChatPhase { gate, importing, converse }

/// Contagem do que a extração trouxe (pro card-resumo).
class ImportSummary {
  final int experiences;
  final int skills;
  final int languages;
  final int education;
  const ImportSummary({
    required this.experiences,
    required this.skills,
    required this.languages,
    required this.education,
  });
  int get total => experiences + skills + languages + education;
  bool get isEmpty => total == 0;
}

/// Itens do fio.
sealed class ChatItem {
  const ChatItem();
}

class AiMsgItem extends ChatItem {
  final String text;
  const AiMsgItem(this.text);
}

class AnsweredItem extends ChatItem {
  final ConversationExchange exchange;
  const AnsweredItem(this.exchange);
}

/// Bolha do arquivo enviado (lado do usuário).
class FileBubbleItem extends ChatItem {
  final String name;
  const FileBubbleItem(this.name);
}

/// Card-resumo da extração + "Revisar e confirmar".
class ImportSummaryItem extends ChatItem {
  final ImportSummary summary;
  const ImportSummaryItem(this.summary);
}

class TrilhaChatController extends ChangeNotifier {
  TrilhaChatController({
    required this.userId,
    required this.sessionBuilder,
    this.snapshotService,
    this.onFinalize,
    this.onStarted,
    this.interpret,
    this.pollInterval = const Duration(milliseconds: 1500),
    this.maxPolls = 40,
  });

  final String userId;

  /// Constrói a sessão das lacunas a partir do perfil FRESCO (injetável p/ teste).
  final Future<TrilhaSession> Function(String userId) sessionBuilder;

  /// Pra o poll da extração (injetável p/ teste).
  final ProfileSnapshotService? snapshotService;

  final Future<String?> Function()? onFinalize;

  /// Chamado ao entrar em `converse` (telemetria com o nº de passos).
  final void Function(int totalSteps)? onStarted;

  /// Interpretador de texto livre → ids de opção. null ⇒ usa [AIService].
  final StepInterpreter? interpret;

  /// Cadência do poll da extração (injetável p/ teste encurtar). ~60s = 40×1.5s.
  final Duration pollInterval;
  final int maxPolls;

  TrilhaSession? _session;
  ConversationController? get _conv => _session?.controller;

  ChatPhase phase = ChatPhase.gate;
  final List<ChatItem> thread = [];
  bool typing = false;
  bool inputVisible = false;
  bool finished = false;
  bool finalizing = false;
  bool awaitingImportConfirm = false;
  String? generatedSummary;

  /// Trava de reentrância: enquanto uma submissão (toque/texto/edição) está em
  /// voo, ignora novas — senão dois envios paralelos duplicam card e re-revelam.
  bool _busy = false;

  int? editingIndex;
  ConversationStep? _editingStep;

  ConversationStep? get activeStep => _editingStep ?? _conv?.current;
  bool get isEditing => _editingStep != null;
  int get answeredCount => _conv?.answeredCount ?? 0;
  List<ConversationExchange> get history => _conv?.history ?? const [];
  ConversationStep? get currentStep => _conv?.current;
  int get totalSteps => _conv?.totalSteps ?? 0;

  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Abertura: gate de import ────────────────────────────────────────────────

  Future<void> start() async {
    phase = ChatPhase.gate;
    typing = true;
    _notify();
    const msg1 = 'Oi! Vou te ajudar a montar seu currículo.';
    await Future.delayed(_typingFor(msg1));
    if (_disposed) return;
    typing = false;
    thread.add(const AiMsgItem(msg1));
    _notify();
    await Future.delayed(_pauseFor(msg1));
    if (_disposed) return;
    thread.add(const AiMsgItem(
        'Como prefere começar? Você pode subir um currículo que já tem ou começar do zero.'));
    _notify();
    // A view mostra o widget de escolha do gate enquanto phase == gate.
  }

  /// "Começar do zero" → vai direto pra conversa.
  Future<void> chooseZero() async {
    if (phase != ChatPhase.gate) return;
    await _enterConverse();
  }

  /// Chamado pela view após o PDF ser escolhido. Só vale a partir do GATE — não
  /// dá pra re-importar no meio da conversa (reconstruir a sessão perderia o
  /// progresso). [extractionExpected]=false quando o PDF foi salvo mas o texto
  /// veio inutilizável (a extração nem roda) → pula o poll e cai na conversa.
  Future<void> onCvUploaded(String fileName,
      {bool extractionExpected = true}) async {
    if (phase != ChatPhase.gate) return; // só do gate; barra re-import e reentrância
    thread.add(FileBubbleItem(fileName));
    phase = ChatPhase.importing;
    typing = true;
    thread.add(const AiMsgItem('Lendo seu currículo…'));
    _notify();

    final summary = extractionExpected ? await _pollExtraction() : null;
    if (_disposed) return;
    typing = false;

    if (summary == null || summary.isEmpty) {
      // Failure-safe (lição T6.2): nunca marca completo calado — cai na conversa.
      thread.add(const AiMsgItem(
          'Não consegui ler tudo agora — vamos completando pela conversa.'));
      _notify();
      await _enterConverse();
      return;
    }
    thread.add(ImportSummaryItem(summary));
    awaitingImportConfirm = true;
    _notify();
    // Espera o "Revisar e confirmar" (confirmImport()).
  }

  /// Confirma o resumo da extração → recomputa as lacunas e segue.
  Future<void> confirmImport() async {
    if (!awaitingImportConfirm) return;
    awaitingImportConfirm = false;
    _notify();
    await _enterConverse();
  }

  /// Poll do snapshot até a extração (fire-and-forget) concluir. ~60s (40×1.5s).
  ///
  /// Pronto = `last_extracted_at` AVANÇOU (sinal explícito de extração concluída
  /// — `save_profile_from_json` sempre o seta) OU os counts cresceram. NÃO basta
  /// crescer: pra perfil pré-existente a RPC pula INSERT em tabela já populada
  /// (counts ficam iguais), então sem o timestamp daria falso timeout de 60s.
  Future<ImportSummary?> _pollExtraction() async {
    final svc = snapshotService ?? ProfileSnapshotService();
    DateTime? baseAt;
    int baseTotal = 0;
    try {
      final base = await svc.loadSnapshot(userId);
      baseAt = base.personal?.lastExtractedAt;
      baseTotal = _total(base);
    } catch (_) {/* baseline assume vazio */}
    for (var i = 0; i < maxPolls; i++) {
      await Future.delayed(pollInterval);
      if (_disposed) return null;
      try {
        final s = await svc.loadSnapshot(userId);
        final at = s.personal?.lastExtractedAt;
        final extracted =
            at != null && (baseAt == null || at.isAfter(baseAt));
        if (extracted || _total(s) > baseTotal) {
          return ImportSummary(
            experiences: s.experiences.length,
            skills: s.skills.length,
            languages: s.languages.length,
            education: s.education.length,
          );
        }
      } catch (_) {/* tenta de novo */}
    }
    return null; // timeout — extração não concluiu
  }

  int _total(ProfileSnapshot s) =>
      s.experiences.length +
      s.skills.length +
      s.languages.length +
      s.education.length;

  // ── Converse: monta a sessão + revela ───────────────────────────────────────

  Future<void> _enterConverse() async {
    if (_session != null) return; // idempotente: nunca reconstrói a sessão viva
    phase = ChatPhase.converse;
    typing = true; // feedback enquanto monta a sessão (sem fio "pelado")
    _notify();
    final session = await sessionBuilder(userId);
    if (_disposed) return;
    _session = session;
    onStarted?.call(totalSteps);
    await _reveal();
  }

  Future<void> _reveal() async {
    final step = _conv?.current;
    if (step == null) {
      _onDone();
      return;
    }
    typing = true;
    inputVisible = false;
    _notify();
    await Future.delayed(
        _typingFor(step.aiMessages.isNotEmpty ? step.aiMessages.first : ''));
    if (_disposed) return;
    typing = false;
    for (final m in step.aiMessages) {
      thread.add(AiMsgItem(m));
      _notify();
      await Future.delayed(_pauseFor(m));
      if (_disposed) return;
    }
    inputVisible = true;
    _notify();
  }

  /// Entrada pública (toque num widget inline). Protegida por [_busy].
  Future<void> submit(StepAnswer answer) async {
    if (_busy) return;
    _busy = true;
    try {
      await _doSubmit(answer);
    } finally {
      _busy = false;
    }
  }

  Future<void> _doSubmit(StepAnswer answer) async {
    if (_editingStep != null) {
      await _applyEdit(answer);
      return;
    }
    final conv = _conv;
    if (conv == null) return;
    final step = conv.current;
    if (step == null) return;
    inputVisible = false;
    _notify();

    final before = conv.answeredCount;
    await conv.submit(answer);
    if (_disposed) return;
    // Defesa: se a submissão não avançou (stepId stale / writeback em voo), NÃO
    // duplica o card nem re-revela — só restaura o input do passo corrente.
    if (conv.answeredCount <= before) {
      inputVisible = conv.current != null;
      _notify();
      return;
    }
    thread.add(AnsweredItem(conv.history.last));
    _notify();

    final ack = step.acknowledgement;
    if (ack != null && ack.trim().isNotEmpty) {
      typing = true;
      _notify();
      await Future.delayed(_typingFor(ack));
      if (_disposed) return;
      typing = false;
      thread.add(AiMsgItem(ack));
      _notify();
      await Future.delayed(_pauseFor(ack));
      if (_disposed) return;
    }
    await _reveal();
  }

  /// Texto livre da barra de baixo (F4). Passo de TEXTO (GuidedText) responde
  /// direto; passo de ESCOLHA (chips/slider) passa por interpretação por IA
  /// (mapeia o texto → ids de opção). Os demais tipos pedem o widget.
  Future<void> submitFreeText(String text) async {
    if (_busy) return;
    final step = activeStep;
    if (step == null) return;
    final t = text.trim();
    if (t.isEmpty) return;
    _busy = true;
    try {
      final input = step.input;
      if (input is GuidedTextInput) {
        await _doSubmit(StepAnswer.text(step.id, t));
        return;
      }
      if (input is ChoiceInput) {
        await _interpretChoice(step, input, t);
        return;
      }
      // Mês/ano e typeahead (cidade/instituição) precisam do widget — texto
      // livre cru não canoniza com segurança. Convida a tocar.
      _pushAi('Pra essa aqui, toca numa das opções acima 🙂');
    } finally {
      _busy = false;
    }
  }

  /// Interpreta [text] contra as opções do passo de escolha [input] e, se casar
  /// com confiança, despacha por [submit] (mesmo caminho do toque). Senão,
  /// mantém o widget e pede pra tocar. Failure-safe: erro/timeout ⇒ fallback.
  Future<void> _interpretChoice(
      ConversationStep step, ChoiceInput input, String text) async {
    inputVisible = false;
    typing = true;
    _notify();

    final fn = interpret ?? AIService().interpretStepAnswer;
    StepInterpretation? result;
    try {
      result = await fn(
        stepId: step.id,
        question: step.aiMessages.join(' ').trim(),
        freeText: text,
        options: [
          for (final o in input.options) {'id': o.id, 'label': o.label},
        ],
        multi: input.multi,
      );
    } catch (_) {
      result = null;
    }
    if (_disposed) return;
    typing = false;

    final r = result;
    final matched = r == null
        ? const <StepOption>[]
        : input.options.where((o) => r.matchedIds.contains(o.id)).toList();

    // Telemetria R7 — só métricas, NUNCA o texto digitado (PII/LGPD).
    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaColetaFreeTextInterpreted, props: {
      'step_id': step.id,
      'matched_count': matched.length,
      'char_count': text.length,
      'confidence': r?.confidence ?? 'none',
    });

    final lowConf = r == null || r.confidence == 'low';
    if (matched.isEmpty || lowConf) {
      inputVisible = true; // mantém o widget pra tocar
      _pushAi(
          'Não tenho certeza do que você quis dizer 🤔 Toca numa opção aí em cima.');
      return;
    }

    final selected =
        input.multi ? _cap(matched, input.maxSelections) : [matched.first];
    // _doSubmit direto: já estamos dentro da seção _busy (via submitFreeText).
    await _doSubmit(StepAnswer.choice(step.id, selected));
  }

  List<StepOption> _cap(List<StepOption> xs, int? max) =>
      (max != null && xs.length > max) ? xs.sublist(0, max) : xs;

  void _pushAi(String text) {
    thread.add(AiMsgItem(text));
    _notify();
  }

  // ── Edição de card (in-place) ───────────────────────────────────────────────

  void beginEdit(AnsweredItem item) {
    if (!item.exchange.step.reversible) return;
    final idx = thread.indexOf(item);
    if (idx < 0) return;
    editingIndex = idx;
    _editingStep = item.exchange.step;
    _notify();
  }

  void cancelEdit() {
    editingIndex = null;
    _editingStep = null;
    _notify();
  }

  Future<void> _applyEdit(StepAnswer answer) async {
    final idx = editingIndex;
    final step = _editingStep;
    editingIndex = null;
    _editingStep = null;
    _notify();
    if (idx == null || step == null) return;
    final session = _session;
    if (session == null) return;

    // Passo com RAMIFICAÇÃO dinâmica (expand) — ex.: "ainda está nessa
    // experiência?" sim→não passa a pedir a data de saída. Se é o ÚLTIMO
    // respondido (nada depois foi inserido ainda → seguro, sem duplicar) e a
    // resposta MUDOU, re-avalia o ramo: poda os follow-ups antigos, rebobina o
    // gate (goBack) e re-submete pra revelar o ramo certo.
    final conv = _conv;
    if (conv != null && step.expand != null) {
      final h = conv.history.length;
      final isLast = h > 0 && conv.history[h - 1].step.id == step.id;
      final changed =
          isLast && conv.history[h - 1].answer.displayText != answer.displayText;
      if (isLast && changed && conv.canGoBack) {
        if (idx >= 0 && idx <= thread.length) {
          thread.removeRange(idx, thread.length);
        }
        conv.goBack();
        _notify();
        await _doSubmit(answer); // re-roda o expand + revela o follow-up
        return;
      }
    }

    // Edição leve (campo simples / sem mudança de ramo): re-grava + troca o card.
    await session.saveAnswer(answer); // idempotente (merge/dedup)
    if (_disposed) return;
    thread[idx] =
        AnsweredItem(ConversationExchange(step: step, answer: answer));
    // Restaura o widget do passo CORRENTE ao sair da edição — senão, ao editar
    // por texto livre (que zerou inputVisible), o passo atual sumiria.
    inputVisible = !typing && _conv?.current != null;
    _notify();
  }

  // ── Conclusão ───────────────────────────────────────────────────────────────

  void _onDone() {
    finished = true;
    inputVisible = false;
    typing = false;
    _notify();
    _runFinalize();
  }

  Future<void> _runFinalize() async {
    final fn = onFinalize;
    if (fn == null) return;
    finalizing = true;
    _notify();
    String? summary;
    try {
      summary = await fn();
    } catch (_) {
      summary = null;
    }
    if (_disposed) return;
    finalizing = false;
    generatedSummary = summary;
    _notify();
  }
}
