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

/// Mensagem do USUÁRIO digitada na barra (assistente) — pra a conversa mostrar
/// o que a pessoa falou (respostas de passo viram AnsweredItem, não isto).
class UserMsgItem extends ChatItem {
  final String text;
  const UserMsgItem(this.text);
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

/// Estado do card de mutação do assistente (Fase B).
enum AssistEditStatus { pending, applied, undone, cancelled }

/// Operação da mutação: trocar um campo (update), adicionar (add), remover
/// (remove — destrutivo) um item de lista, ou reescrever um bullet (bullet,
/// keyed por id).
enum AssistEditOp { update, add, remove, bullet }

/// Card de ALTERAÇÃO do assistente: propõe (pending, com Aplicar/Cancelar) →
/// aplica (applied, com Desfazer) → desfaz (undone). A view renderiza conforme
/// o [status] e [op]; o controller o transiciona (confirm/cancel/undoAssistEdit).
class AssistEditItem extends ChatItem {
  final String id;
  final AssistEditOp op;
  final String field; // campo (update) ou kind (add/remove: skill/language)
  final String fieldLabel; // "Cargo desejado" / "suas skills"
  final String beforeRaw; // valor cru anterior (update, pro undo)
  final String beforeText; // "—" ou o texto anterior (update)
  final String afterText; // exibição do novo valor / do item
  final String value; // valor cru a aplicar / item a add/remove
  final String refId; // id da linha (op=bullet: o bullet_id)
  /// Undo CAPTURADO na aplicação (ex.: remover experiência guarda o restore que
  /// re-insere o registro). Quando presente, tem prioridade sobre o undo por op.
  Future<void> Function()? capturedUndo;
  AssistEditStatus status;
  AssistEditItem({
    required this.id,
    this.op = AssistEditOp.update,
    required this.field,
    required this.fieldLabel,
    this.beforeRaw = '',
    this.beforeText = '',
    required this.afterText,
    required this.value,
    this.refId = '',
    this.status = AssistEditStatus.pending,
  });
}

/// Um item extraído de um textão colado (Fase C): kind canônico + valor + como
/// exibir. kinds: skill / language / desired_position.
class AssistExtractEntry {
  final String kind;
  final String value;
  final String label; // "Skill: Python" / "Cargo: Analista"
  const AssistExtractEntry(
      {required this.kind, required this.value, required this.label});
}

/// Card "Peguei isto 👇" (extração multi-campo): lista os itens, confirma tudo
/// de uma vez, e um Desfazer reverte o lote inteiro.
class AssistExtractItem extends ChatItem {
  final String id;
  final List<AssistExtractEntry> entries;
  AssistEditStatus status;
  final List<Future<void> Function()> undos = []; // preenchido ao aplicar
  AssistExtractItem({
    required this.id,
    required this.entries,
    this.status = AssistEditStatus.pending,
  });
}

/// Editor VISUAL de skills (Fase C): mostra as skills atuais em chips (✕ pra
/// tirar) + campo/sugestões pra adicionar. "Salvar" aplica o líquido (adds +
/// removes) e deixa um Desfazer que reverte o lote. O estado de edição vive no
/// widget; aqui ficam só o baseline (skills no momento de abrir), as sugestões,
/// e o resultado aplicado (pro undo).
class SkillsEditorItem extends ChatItem {
  final String id;
  final List<String> initial;
  final List<String> suggestions;
  AssistEditStatus status;
  List<String> addedApplied = const [];
  List<String> removedApplied = const [];
  final List<Future<void> Function()> undos = [];
  SkillsEditorItem({
    required this.id,
    required this.initial,
    this.suggestions = const [],
    this.status = AssistEditStatus.pending,
  });
}

/// Valor atual de um campo (pro diff/undo do assistente).
class AssistFieldValue {
  final String raw; // valor cru (id/texto) — '' se vazio
  final String text; // exibição ("São Paulo" / "—")
  final String label; // rótulo do campo ("Cidade")
  const AssistFieldValue(
      {required this.raw, required this.text, required this.label});
}

/// Lê o valor atual de um campo (pro diff/undo). null ⇒ campo não editável aqui.
typedef AssistFieldReader = Future<AssistFieldValue?> Function(String field);

/// Aplica um valor cru a um campo (value '' limpa). Reusa o write-back.
typedef AssistFieldWriter = Future<void> Function(String field, String value);

/// Turno do assistente (injetável p/ teste). Mesma forma de [AIService.assistantTurn].
typedef AssistantTurnFn = Future<AssistantTurn?> Function({
  required String message,
  Map<String, dynamic>? openStep,
  Map<String, dynamic> context,
  List<Map<String, dynamic>> history,
});

class TrilhaChatController extends ChangeNotifier {
  TrilhaChatController({
    required this.userId,
    required this.sessionBuilder,
    this.snapshotService,
    this.preFilledLoader,
    this.onFinalize,
    this.onStarted,
    this.interpret,
    this.assistEnabled = false,
    this.assistantTurn,
    this.assistContextLoader,
    this.assistSectionSteps,
    this.assistReadField,
    this.assistWriteField,
    this.assistItemAdder,
    this.assistItemRemover,
    this.assistItemResolver,
    this.assistBulletReader,
    this.assistBulletWriter,
    this.assistReversibleRemover,
    this.assistProactiveLoader,
    this.assistSkillsLoader,
    this.assistSkillSuggester,
    this.pollInterval = const Duration(milliseconds: 1500),
    this.maxPolls = 40,
  });

  final String userId;

  /// Constrói a sessão das lacunas a partir do perfil FRESCO (injetável p/ teste).
  final Future<TrilhaSession> Function(String userId) sessionBuilder;

  /// Pra o poll da extração (injetável p/ teste).
  final ProfileSnapshotService? snapshotService;

  /// Rótulos (pt-BR, minúsculo) das seções que o perfil JÁ tem — pra abertura
  /// adaptativa. Chamado 1x no [start]. null/vazio ⇒ perfil vazio ⇒ mostra o
  /// gate de import (comportamento padrão). Ex.: `['formação', 'skills', 'idiomas']`.
  final Future<List<String>> Function()? preFilledLoader;

  final Future<String?> Function()? onFinalize;

  /// Chamado ao entrar em `converse` (telemetria com o nº de passos).
  final void Function(int totalSteps)? onStarted;

  /// Interpretador de texto livre → ids de opção. null ⇒ usa [AIService].
  final StepInterpreter? interpret;

  // ── Assistente de IA na barra (PLANO-ASSISTENTE, Fase A) ──────────────────
  /// Flag `trilha_assist_v1`. OFF ⇒ a barra mantém o comportamento de hoje
  /// (responder o passo aberto). ON ⇒ o texto passa pelo assistente.
  final bool assistEnabled;

  /// Turno do assistente (injetável p/ teste). null ⇒ [AIService.assistantTurn].
  final AssistantTurnFn? assistantTurn;

  /// Monta o grounding (lacunas + inventário compacto, SEM PII) pro assistente.
  /// null ⇒ contexto vazio (o assistente ainda responde/conduz, só sem
  /// personalizar tanto).
  final Future<Map<String, dynamic>> Function()? assistContextLoader;

  /// Passos reais de uma seção pra "quero preencher X" — o app liga com os
  /// searchers (cidade/instituição/skills). Recebe o nome da seção (LacunaKey
  /// em snake). Vazio/null ⇒ sem handoff (cai em conversa).
  final List<ConversationStep> Function(String section)? assistSectionSteps;

  /// Fase B: lê o valor atual de um campo (pro diff/undo). null ⇒ sem mutação.
  final AssistFieldReader? assistReadField;

  /// Fase B: aplica um valor a um campo (reusa o write-back). null ⇒ sem mutação.
  final AssistFieldWriter? assistWriteField;

  /// Fase B: adiciona um item de lista (kind, value) — ex.: skill/idioma (merge).
  final AssistFieldWriter? assistItemAdder;

  /// Fase B: remove um item de lista (kind, value) — destrutivo.
  final AssistFieldWriter? assistItemRemover;

  /// Fase B: resolve "qual item" pra remover — (kind, query) → nomes que casam
  /// (0 ⇒ não achou; 1 ⇒ segue; 2+ ⇒ desambigua).
  final Future<List<String>> Function(String kind, String query)?
      assistItemResolver;

  /// Fase B: lê um bullet por id (pro diff/undo). raw/text = o texto atual;
  /// label = a experiência ("Ambev"). null ⇒ id inválido.
  final AssistFieldReader? assistBulletReader;

  /// Fase B: reescreve um bullet (bulletId, novo texto). Undo regrava o antigo.
  final AssistFieldWriter? assistBulletWriter;

  /// Fase B: remoção REVERSÍVEL de item multi-campo (experiência/projeto):
  /// captura o registro, deleta, e devolve um restore (pro undo re-inserir).
  /// null / retorno null ⇒ cai no remover simples (skill/idioma). (kind, value).
  final Future<Future<void> Function()?> Function(String kind, String value)?
      assistReversibleRemover;

  /// Fase C (proativo): a maior lacuna que resta — `{section, label}` — pra o
  /// assistente SUGERIR o próximo ganho ao concluir. null ⇒ sem sugestão.
  final Future<Map<String, String>?> Function()? assistProactiveLoader;

  /// Editor visual de skills: nomes das skills atuais (pra mostrar em chips).
  /// null/vazio ⇒ sem skills → cai na coleta (start_section).
  final Future<List<String>> Function()? assistSkillsLoader;

  /// Editor visual de skills: sugestões pra adicionar (pela área), best-effort.
  final Future<List<String>> Function()? assistSkillSuggester;

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

  /// Na VOLTA (abertura adaptativa), a saudação de retorno — msg1 reconhece o
  /// que já existe + msg2 convida a completar — já diz o "vamos lá". Então o
  /// passo de abertura ('intro') entra só com o CTA, sem repetir a bolha de
  /// saudação (que soa como "começando agora"). Vale só pra 1ª revelação.
  bool _suppressIntroGreeting = false;

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
    // Descobre o que o perfil já tem pra escolher a abertura. Enquanto decide,
    // fica em `converse`+typing (neutro) — o gate só renderiza em phase==gate,
    // então não pisca os botões durante a decisão.
    phase = ChatPhase.converse;
    typing = true;
    _notify();
    List<String> filled = const [];
    try {
      filled = (await preFilledLoader?.call()) ?? const [];
    } catch (_) {
      filled = const []; // failure-safe: cai no gate padrão
    }
    if (_disposed) return;
    if (filled.isEmpty) {
      await _startGate();
    } else {
      await _startAdaptive(filled);
    }
  }

  /// Perfil vazio: abertura padrão + gate "começar do zero / já tenho currículo".
  Future<void> _startGate() async {
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

  /// Perfil já tem dado: reconhece o que existe e vai DIRETO completar o que
  /// falta (pula o gate de import — não faz sentido oferecer "começar do zero").
  Future<void> _startAdaptive(List<String> filled) async {
    phase = ChatPhase.converse; // sem gate
    // A saudação de retorno abaixo (msg1 + msg2) já dá as boas-vindas e convida
    // — então o passo de abertura não repete a saudação genérica (só o CTA).
    _suppressIntroGreeting = true;
    typing = true;
    _notify();
    final msg1 = 'Oi! Vi que você já tem ${_humanJoin(filled)} no seu perfil.';
    await Future.delayed(_typingFor(msg1));
    if (_disposed) return;
    typing = false;
    thread.add(AiMsgItem(msg1));
    _notify();
    await Future.delayed(_pauseFor(msg1));
    if (_disposed) return;
    typing = true;
    _notify();
    const msg2 = 'Bora completar o que falta pra deixar seu currículo redondo?';
    await Future.delayed(_typingFor(msg2));
    if (_disposed) return;
    typing = false;
    thread.add(const AiMsgItem(msg2));
    _notify();
    await Future.delayed(_pauseFor(msg2));
    if (_disposed) return;
    await _enterConverse(); // monta a sessão (só as lacunas) e revela o 1º passo
  }

  /// Junta rótulos numa lista natural pt-BR: [a] → "a"; [a,b] → "a e b";
  /// [a,b,c] → "a, b e c".
  static String _humanJoin(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    if (items.length == 2) return '${items[0]} e ${items[1]}';
    return '${items.sublist(0, items.length - 1).join(', ')} e ${items.last}';
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
    // Na volta, a saudação do passo de abertura ('intro') repetiria o que a
    // msg1+msg2 já disseram → revela o passo direto (só o CTA "Bora começar"),
    // sem bolha nem "typing". Vale uma vez só (a flag zera aqui).
    final skipGreeting = _suppressIntroGreeting && step.id == 'intro';
    _suppressIntroGreeting = false;
    if (skipGreeting) {
      typing = false;
      inputVisible = true;
      _notify();
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

    // Recap dinâmico (a IA mostra o que anotou) tem prioridade sobre o ack fixo.
    final ack = step.recap?.call([for (final e in conv.history) e.answer]) ??
        step.acknowledgement;
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

  /// Texto livre da barra de baixo. Com o assistente OFF (flag): comportamento
  /// de HOJE — passo de TEXTO responde direto; ESCOLHA passa pela interpretação
  /// por IA; sem passo aberto, ignora. Com o assistente ON: roteia por intenção
  /// (atalho local barato → IA), podendo responder, conduzir uma seção ou (Fase
  /// B) alterar. Failure-safe: erro/timeout cai no fluxo roteirizado.
  Future<void> submitFreeText(String text) async {
    if (_busy) return;
    final t = text.trim();
    if (t.isEmpty) return;
    final step = activeStep;

    // Assistente OFF → comportamento de hoje (responder o passo aberto).
    if (!assistEnabled) {
      if (step == null) {
        // Sem passo aberto e sem assistente não há o que responder — mas NÃO
        // engolir a mensagem em silêncio (o botão parecia morto: sumia o texto
        // e baixava o teclado). Mostra o que a pessoa disse e ensina a editar o
        // que já está preenchido.
        thread.add(UserMsgItem(t));
        _pushAi('Pra mudar algo que você já preencheu, é só tocar na seção lá '
            'em cima 👆 (ou no ✏️ de uma resposta).');
        return;
      }
      _busy = true;
      try {
        await _routeToStep(step, t);
      } finally {
        _busy = false;
      }
      return;
    }

    _busy = true;
    try {
      // Fase C (proativo): acabei de SUGERIR uma seção e a pessoa topou ("quero",
      // "bora") → entra direto nela, sem gastar uma chamada de IA.
      final suggested = _suggestedSection;
      _suggestedSection = null;
      if (suggested != null && _isAffirmative(t)) {
        thread.add(UserMsgItem(t));
        _notify();
        final ok = await _injectSection(suggested, 'Boa, bora! 👇');
        if (!ok) _pushAi('Beleza! O que você quer preencher?');
        return;
      }

      // Nível 0 — atalho local (sem IA): passo de TEXTO aberto + mensagem sem
      // cara de comando ⇒ resposta direta (custo/latência zero, = hoje). Um
      // textão colado (várias infos) NÃO é resposta do passo — vai pra IA.
      if (step != null &&
          step.input is GuidedTextInput &&
          !_looksLikeCommand(t) &&
          !_looksLikePaste(t)) {
        // ignore: unawaited_futures
        Analytics.shared.track(evTrilhaAssistMessageSent, props: {
          'char_count': t.length,
          'has_active_step': true,
          'route': 'fast_lane',
        });
        await _doSubmit(StepAnswer.text(step.id, t));
        return;
      }
      // Nível 1 — a IA roteia.
      await _runAssistant(t, step);
    } finally {
      _busy = false;
    }
  }

  /// Comportamento roteirizado de hoje (assistente OFF ou fallback).
  Future<void> _routeToStep(ConversationStep step, String t) async {
    final input = step.input;
    if (input is GuidedTextInput) {
      await _doSubmit(StepAnswer.text(step.id, t));
      return;
    }
    if (input is ChoiceInput) {
      await _interpretChoice(step, input, t);
      return;
    }
    // Mês/ano e typeahead (cidade/instituição) precisam do widget.
    _pushAi('Pra essa aqui, toca numa das opções acima 🙂');
  }

  // ── Assistente: roteia a mensagem por intenção e executa a ferramenta ──────

  Future<void> _runAssistant(String message, ConversationStep? step) async {
    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaAssistMessageSent, props: {
      'char_count': message.length,
      'has_active_step': step != null,
      'route': 'assistant',
    });
    // Mostra a fala do usuário no fio (respostas de passo já viram card).
    thread.add(UserMsgItem(message));
    inputVisible = false;
    typing = true;
    _notify();

    Map<String, dynamic> context = const {};
    try {
      context = await assistContextLoader?.call() ?? const {};
    } catch (_) {/* grounding é best-effort */}
    if (_disposed) return;

    final fn = assistantTurn ?? AIService().assistantTurn;
    AssistantTurn? turn;
    try {
      turn = await fn(
        message: message,
        openStep: step == null ? null : _serializeStep(step),
        context: context,
        history: _recentHistory(),
      );
    } catch (_) {
      turn = null;
    }
    if (_disposed) return;
    typing = false;

    if (turn == null) {
      // Failure-safe: sem re-chamar IA. Passo aberto ⇒ mantém o widget; senão
      // ⇒ nota gentil.
      // ignore: unawaited_futures
      Analytics.shared
          .track(evTrilhaAssistError, props: {'stage': 'classify'});
      if (step != null) {
        inputVisible = true;
        _pushAi(
            'Não peguei bem 🤔 Toca numa opção aí em cima, ou tenta de outro jeito.');
      } else {
        _pushAi('Não consegui agora 🤔 Tenta de novo daqui a pouco.');
      }
      _notify();
      return;
    }

    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaAssistIntentClassified, props: {
      'intent': turn.tool,
      'tool': turn.tool,
      'prompt_version': turn.promptVersion,
    });
    await _executeTool(turn, step);
  }

  Future<void> _executeTool(AssistantTurn turn, ConversationStep? step) async {
    final reply = turn.reply.trim();
    switch (turn.tool) {
      case 'answer_current_step':
        await _applyAnswerCurrentStep(turn, step);
        return;
      case 'start_section':
        await _handleStartSection(turn, step);
        return;
      case 'update_field':
        await _proposeUpdateField(turn, step);
        return;
      case 'add_item':
        await _proposeAddItem(turn, step);
        return;
      case 'remove_item':
        await _proposeRemoveItem(turn, step);
        return;
      case 'rewrite_summary':
        await _proposeRewriteSummary(turn, step);
        return;
      case 'improve_bullet':
        await _proposeImproveBullet(turn, step);
        return;
      case 'extract_profile':
        await _proposeExtract(turn, step);
        return;
      case 'edit_skills':
        await _proposeSkillsEditor(turn);
        return;
      case 'skip_step':
        if (step != null && _stepIsOptional(step)) {
          if (reply.isNotEmpty) _pushAi(reply);
          await _doSubmit(StepAnswer(
              stepId: step.id, value: '', displayText: 'Pular'));
        } else {
          _pushAi(reply.isEmpty ? 'Essa aqui não dá pra pular 🙂' : reply);
          if (step != null) inputVisible = true;
          _notify();
        }
        return;
      case 'out_of_scope':
        // ignore: unawaited_futures
        Analytics.shared.track(evTrilhaAssistOutOfScope,
            props: {'category': turn.args['category']?.toString() ?? 'other'});
        _replyAndKeepStep(reply, step);
        return;
      case 'clarify':
        // ignore: unawaited_futures
        Analytics.shared.track(evTrilhaAssistClarifyRequested,
            props: {'reason': 'ambiguous'});
        _replyAndKeepStep(reply, step);
        return;
      case 'show_gaps':
      case 'show_profile_summary':
        // ignore: unawaited_futures
        Analytics.shared.track(evTrilhaAssistAnswerReturned,
            props: {'grounded_in': 'profile_gaps', 'used_llm': true});
        _replyAndKeepStep(reply, step);
        return;
      case 'answer_question':
      case 'explain_step':
      default:
        // ignore: unawaited_futures
        Analytics.shared.track(evTrilhaAssistAnswerReturned,
            props: {'grounded_in': 'llm', 'used_llm': true});
        _replyAndKeepStep(reply, step);
        return;
    }
  }

  /// Empurra a fala e, se há passo aberto, re-exibe o widget (a conversa segue).
  void _replyAndKeepStep(String reply, ConversationStep? step) {
    if (reply.isNotEmpty) _pushAi(reply);
    if (step != null) inputVisible = true;
    _notify();
  }

  /// `answer_current_step`: aplica a resposta da IA ao passo aberto (texto ou
  /// ids de opção, validados contra as opções reais). Sem match ⇒ pede toque.
  Future<void> _applyAnswerCurrentStep(
      AssistantTurn turn, ConversationStep? step) async {
    if (step == null) {
      _replyAndKeepStep(turn.reply.trim(), null);
      return;
    }
    final input = step.input;
    if (input is GuidedTextInput) {
      final text = (turn.args['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) {
        _replyAndKeepStep('Manda o texto que eu anoto 🙂', step);
        return;
      }
      await _doSubmit(StepAnswer.text(step.id, text));
      return;
    }
    if (input is ChoiceInput) {
      final rawIds = turn.args['option_ids'];
      final ids = rawIds is List
          ? rawIds.map((e) => e.toString()).toSet()
          : <String>{};
      final matched = input.options.where((o) => ids.contains(o.id)).toList();
      if (matched.isEmpty) {
        _replyAndKeepStep(
            'Não tenho certeza 🤔 Toca numa opção aí em cima.', step);
        return;
      }
      final selected = input.multi ? matched : [matched.first];
      await _doSubmit(StepAnswer.choice(step.id, selected));
      return;
    }
    // Mês/ano e typeahead precisam do widget.
    _replyAndKeepStep('Pra essa aqui, toca na opção acima 🙂', step);
  }

  /// `start_section`: injeta os passos reais da seção no fio (o app fornece via
  /// [assistSectionSteps]) e revela o primeiro. O passo que estava aberto
  /// RETOMA depois (a fila cuida disso — ver ConversationController.injectNext).
  Future<void> _handleStartSection(
      AssistantTurn turn, ConversationStep? step) async {
    final section = turn.args['section']?.toString() ?? '';
    if (step != null) {
      // ignore: unawaited_futures
      Analytics.shared.track(evTrilhaAssistStepConflict, props: {
        'active_step_id': step.id,
        'resolution': 'deferred',
      });
    }
    final ok = await _injectSection(section, turn.reply.trim());
    if (!ok) _replyAndKeepStep(turn.reply.trim(), step); // cai em conversa
  }

  /// Injeta os passos reais de uma seção no fio e revela o 1º. Reusado pelo
  /// `start_section` E pela sugestão proativa (Fase C). false ⇒ não deu (sem
  /// handoff/seção desconhecida). Reabre a trilha se estava concluída.
  Future<bool> _injectSection(String section, String reply) async {
    final builder = assistSectionSteps;
    final steps = builder == null ? const <ConversationStep>[] : builder(section);
    final conv = _conv;
    if (steps.isEmpty || conv == null) return false;
    if (reply.isNotEmpty) _pushAi(reply);
    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaAssistSectionHandoff,
        props: {'lacuna_key': section, 'steps_enqueued': steps.length});
    finished = false; // reabre se estava concluída (proativo pós-conclusão)
    conv.injectNext(steps);
    await _reveal();
    return true;
  }

  // ── Mutações (Fase B): propõe → confirma → aplica → desfaz ──────────────────

  final Map<String, AssistEditItem> _pendingEdits = {};
  int _editSeq = 0;

  /// `update_field`: NÃO grava direto — lê o valor atual, mostra um card de
  /// confirmação (Aplicar/Cancelar) e só grava no [confirmEdit]. Campo não
  /// editável / sem leitor-gravador ⇒ cai em conversa.
  Future<void> _proposeUpdateField(
      AssistantTurn turn, ConversationStep? step) async {
    final field = turn.args['field']?.toString() ?? '';
    final value = turn.args['value']?.toString().trim() ?? '';
    final valueLabel =
        turn.args['value_label']?.toString().trim() ?? (value.isEmpty ? '' : value);
    final reader = assistReadField;
    if (field.isEmpty ||
        value.isEmpty ||
        reader == null ||
        assistWriteField == null) {
      _replyAndKeepStep(
          turn.reply.trim().isEmpty
              ? 'Não peguei o que você quer mudar 🤔'
              : turn.reply.trim(),
          step);
      return;
    }
    AssistFieldValue? current;
    try {
      current = await reader(field);
    } catch (_) {
      current = null;
    }
    if (_disposed) return;
    if (current == null) {
      _replyAndKeepStep('Essa eu ainda não consigo mudar por aqui 🙂', step);
      return;
    }
    if (turn.reply.trim().isNotEmpty) _pushAi(turn.reply.trim());
    final id = 'edit_${_editSeq++}';
    final item = AssistEditItem(
      id: id,
      field: field,
      fieldLabel: current.label,
      beforeRaw: current.raw,
      beforeText: current.text,
      afterText: valueLabel,
      value: value,
    );
    _pendingEdits[id] = item;
    thread.add(item);
    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaAssistEditProposed,
        props: {'lacuna_key': field, 'op': 'update'});
    if (step != null) inputVisible = true;
    _notify();
  }

  /// `add_item`: propõe ADICIONAR um item de lista (skill/idioma). Confirma
  /// antes de gravar (postura da Fase B).
  Future<void> _proposeAddItem(AssistantTurn turn, ConversationStep? step) async {
    final kind = turn.args['kind']?.toString() ?? '';
    final value = turn.args['value']?.toString().trim() ?? '';
    if (kind.isEmpty || value.isEmpty || assistItemAdder == null) {
      _replyAndKeepStep(
          turn.reply.trim().isEmpty ? 'O que você quer adicionar? 🙂' : turn.reply.trim(),
          step);
      return;
    }
    if (turn.reply.trim().isNotEmpty) _pushAi(turn.reply.trim());
    _pushEdit(
        AssistEditItem(
          id: 'edit_${_editSeq++}',
          op: AssistEditOp.add,
          field: kind,
          fieldLabel: _kindLabel(kind),
          afterText: value,
          value: value,
        ),
        step,
        opName: 'add');
  }

  /// `remove_item`: resolve QUAL item (desambigua se preciso) e propõe REMOVER
  /// (destrutivo → confirma).
  Future<void> _proposeRemoveItem(
      AssistantTurn turn, ConversationStep? step) async {
    final kind = turn.args['kind']?.toString() ?? '';
    final query = turn.args['query']?.toString().trim() ?? '';
    final resolver = assistItemResolver;
    if (kind.isEmpty ||
        query.isEmpty ||
        resolver == null ||
        (assistItemRemover == null && assistReversibleRemover == null)) {
      _replyAndKeepStep(
          turn.reply.trim().isEmpty ? 'O que você quer remover? 🙂' : turn.reply.trim(),
          step);
      return;
    }
    List<String> matches;
    try {
      matches = await resolver(kind, query);
    } catch (_) {
      matches = const [];
    }
    if (_disposed) return;
    if (matches.isEmpty) {
      // ignore: unawaited_futures
      Analytics.shared.track(evTrilhaAssistClarifyRequested,
          props: {'reason': 'no_match'});
      _replyAndKeepStep('Não achei "$query" em ${_kindLabel(kind)} 🤔', step);
      return;
    }
    if (matches.length > 1) {
      // ignore: unawaited_futures
      Analytics.shared.track(evTrilhaAssistClarifyRequested,
          props: {'reason': 'multi_target'});
      _replyAndKeepStep('Qual você quer remover: ${matches.join(', ')}?', step);
      return;
    }
    if (turn.reply.trim().isNotEmpty) _pushAi(turn.reply.trim());
    _pushEdit(
        AssistEditItem(
          id: 'edit_${_editSeq++}',
          op: AssistEditOp.remove,
          field: kind,
          fieldLabel: _kindLabel(kind),
          afterText: matches.first,
          value: matches.first,
        ),
        step,
        opName: 'remove');
  }

  void _pushEdit(AssistEditItem item, ConversationStep? step,
      {required String opName}) {
    _pendingEdits[item.id] = item;
    thread.add(item);
    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaAssistEditProposed,
        props: {'lacuna_key': item.field, 'op': opName});
    if (step != null) inputVisible = true;
    _notify();
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'skill':
        return 'suas skills';
      case 'language':
        return 'seus idiomas';
      case 'experience':
        return 'suas experiências';
      case 'project':
        return 'seus projetos';
    }
    return kind;
  }

  /// `rewrite_summary`: a IA já mandou a nova versão (new_summary). Lê o resumo
  /// atual, mostra ANTES→DEPOIS e confirma antes de gravar (é um update do campo
  /// 'summary' cujo valor veio da IA, não do usuário).
  Future<void> _proposeRewriteSummary(
      AssistantTurn turn, ConversationStep? step) async {
    final newSummary = turn.args['new_summary']?.toString().trim() ?? '';
    final reader = assistReadField;
    if (newSummary.isEmpty || reader == null || assistWriteField == null) {
      _replyAndKeepStep(
          turn.reply.trim().isEmpty
              ? 'Não consegui reescrever agora 🤔'
              : turn.reply.trim(),
          step);
      return;
    }
    AssistFieldValue? current;
    try {
      current = await reader('summary');
    } catch (_) {
      current = null;
    }
    if (_disposed) return;
    final before = current ??
        const AssistFieldValue(raw: '', text: '—', label: 'Resumo');
    if (turn.reply.trim().isNotEmpty) _pushAi(turn.reply.trim());
    _pushEdit(
        AssistEditItem(
          id: 'edit_${_editSeq++}',
          op: AssistEditOp.update,
          field: 'summary',
          fieldLabel: before.label,
          beforeRaw: before.raw,
          beforeText: before.text,
          afterText: newSummary,
          value: newSummary,
        ),
        step,
        opName: 'update');
  }

  /// `improve_bullet`: a IA mandou bullet_id + a versão melhorada (new_bullet).
  /// Lê o bullet atual (pro antes→depois e undo) e confirma antes de gravar.
  Future<void> _proposeImproveBullet(
      AssistantTurn turn, ConversationStep? step) async {
    final bulletId = turn.args['bullet_id']?.toString().trim() ?? '';
    final newText = turn.args['new_bullet']?.toString().trim() ?? '';
    final reader = assistBulletReader;
    if (bulletId.isEmpty ||
        newText.isEmpty ||
        reader == null ||
        assistBulletWriter == null) {
      _replyAndKeepStep(
          turn.reply.trim().isEmpty
              ? 'Qual bullet você quer que eu melhore? 🙂'
              : turn.reply.trim(),
          step);
      return;
    }
    AssistFieldValue? current;
    try {
      current = await reader(bulletId);
    } catch (_) {
      current = null;
    }
    if (_disposed) return;
    if (current == null) {
      _replyAndKeepStep('Não achei esse bullet 🤔 De qual experiência é?', step);
      return;
    }
    if (turn.reply.trim().isNotEmpty) _pushAi(turn.reply.trim());
    _pushEdit(
        AssistEditItem(
          id: 'edit_${_editSeq++}',
          op: AssistEditOp.bullet,
          field: 'bullet',
          fieldLabel: current.label, // a experiência ("Ambev")
          beforeRaw: current.raw,
          beforeText: current.text,
          afterText: newText,
          value: newText,
          refId: bulletId,
        ),
        step,
        opName: 'bullet');
  }

  /// Confirma uma alteração proposta (toque em "Aplicar"/"Remover"). Grava e
  /// vira card "✓ … [Desfazer]".
  Future<void> confirmAssistEdit(String id) async {
    final item = _pendingEdits[id];
    if (item == null || item.status != AssistEditStatus.pending) return;
    final ok = await _applyEditOp(item, item.op);
    if (!ok || _disposed) return;
    item.status = AssistEditStatus.applied;
    _pendingEdits.remove(id);
    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaAssistEditApplied,
        props: {'lacuna_key': item.field, 'op': item.op.name});
    _notify();
  }

  /// Cancela uma alteração proposta (toque em "Cancelar") — não grava nada.
  void cancelAssistEdit(String id) {
    final item = _pendingEdits.remove(id);
    if (item == null || item.status != AssistEditStatus.pending) return;
    item.status = AssistEditStatus.cancelled;
    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaAssistEditCancelled,
        props: {'lacuna_key': item.field, 'op': item.op.name});
    _notify();
  }

  /// Desfaz uma alteração já aplicada (toque em "Desfazer") — aplica a operação
  /// INVERSA (add↔remove; update regrava o valor anterior). Savers idempotentes.
  Future<void> undoAssistEdit(String id) async {
    AssistEditItem? item;
    for (final it in thread) {
      if (it is AssistEditItem && it.id == id) {
        item = it;
        break;
      }
    }
    if (item == null || item.status != AssistEditStatus.applied) return;
    // Undo CAPTURADO (ex.: re-inserir a experiência removida) tem prioridade.
    final captured = item.capturedUndo;
    bool ok;
    if (captured != null) {
      try {
        await captured();
        ok = true;
      } catch (_) {
        ok = false;
        if (!_disposed) {
          _pushAi('Não consegui desfazer agora 🤔');
          _notify();
        }
      }
    } else {
      final inverse = switch (item.op) {
        AssistEditOp.update => AssistEditOp.update, // regrava beforeRaw
        AssistEditOp.add => AssistEditOp.remove, // desfaz add = remove
        AssistEditOp.remove => AssistEditOp.add, // desfaz remove = add
        AssistEditOp.bullet => AssistEditOp.bullet, // regrava o bullet antigo
      };
      ok = await _applyEditOp(item, inverse, undo: true);
    }
    if (!ok || _disposed) return;
    item.status = AssistEditStatus.undone;
    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaAssistEditUndone,
        props: {'lacuna_key': item.field, 'op': item.op.name});
    _notify();
  }

  /// Aplica uma operação de mutação reusando os writers injetados. false (com
  /// aviso) se falhou. Undo de update usa beforeRaw.
  Future<bool> _applyEditOp(AssistEditItem item, AssistEditOp op,
      {bool undo = false}) async {
    try {
      switch (op) {
        case AssistEditOp.update:
          final w = assistWriteField;
          if (w == null) return false;
          await w(item.field, undo ? item.beforeRaw : item.value);
          break;
        case AssistEditOp.add:
          final a = assistItemAdder;
          if (a == null) return false;
          await a(item.field, item.value);
          break;
        case AssistEditOp.remove:
          // Item multi-campo (experiência/projeto): remoção reversível (captura
          // o restore pro undo). Se não for tratado ali, cai no remover simples.
          final rev = assistReversibleRemover;
          if (rev != null) {
            final restore = await rev(item.field, item.value);
            if (restore != null) {
              item.capturedUndo = restore;
              break;
            }
          }
          final r = assistItemRemover;
          if (r == null) return false;
          await r(item.field, item.value);
          break;
        case AssistEditOp.bullet:
          final bw = assistBulletWriter;
          if (bw == null) return false;
          await bw(item.refId, undo ? item.beforeRaw : item.value);
          break;
      }
      return true;
    } catch (_) {
      if (_disposed) return false;
      _pushAi(undo
          ? 'Não consegui desfazer agora 🤔'
          : 'Ops, não consegui salvar agora 🤔');
      _notify();
      return false;
    }
  }

  // ── Extração de textão (Fase C): batch confirmar → aplica cada → desfaz tudo ─

  final Map<String, AssistExtractItem> _pendingExtracts = {};

  /// `extract_profile`: a IA extraiu vários campos de um textão. Mostra um card
  /// "Peguei isto 👇" — nada grava até confirmar. Só kinds de apply/undo limpos
  /// (skill/idioma/cargo); complexos (experiência/educação) a IA sugere na fala.
  Future<void> _proposeExtract(AssistantTurn turn, ConversationStep? step) async {
    final raw = turn.args['items'];
    final entries = <AssistExtractEntry>[];
    if (raw is List) {
      for (final it in raw) {
        if (it is! Map) continue;
        final kind = it['kind']?.toString() ?? '';
        final value = it['value']?.toString().trim() ?? '';
        if (value.isEmpty) continue;
        if (kind == 'skill' || kind == 'language' || kind == 'desired_position') {
          entries.add(AssistExtractEntry(
              kind: kind, value: value, label: _extractLabel(kind, value)));
        }
      }
    }
    if (entries.isEmpty) {
      _replyAndKeepStep(
          turn.reply.trim().isEmpty ? 'Não consegui pegar nada 🤔' : turn.reply.trim(),
          step);
      return;
    }
    if (turn.reply.trim().isNotEmpty) _pushAi(turn.reply.trim());
    final item =
        AssistExtractItem(id: 'edit_${_editSeq++}', entries: entries);
    _pendingExtracts[item.id] = item;
    thread.add(item);
    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaAssistEditProposed,
        props: {'lacuna_key': 'extract', 'op': 'add'});
    if (step != null) inputVisible = true;
    _notify();
  }

  String _extractLabel(String kind, String value) {
    switch (kind) {
      case 'skill':
        return 'Skill: $value';
      case 'language':
        return 'Idioma: $value';
      case 'desired_position':
        return 'Cargo: $value';
    }
    return value;
  }

  /// Aplica TODOS os itens extraídos (toque em "Aplicar tudo") e guarda o undo
  /// de cada um (o Desfazer reverte o lote).
  Future<void> confirmExtract(String id) async {
    final item = _pendingExtracts[id];
    if (item == null || item.status != AssistEditStatus.pending) return;
    final adder = assistItemAdder;
    final remover = assistItemRemover;
    final writer = assistWriteField;
    final reader = assistReadField;
    for (final e in item.entries) {
      try {
        if (e.kind == 'skill' || e.kind == 'language') {
          if (adder == null) continue;
          await adder(e.kind, e.value);
          if (remover != null) item.undos.add(() => remover(e.kind, e.value));
        } else if (e.kind == 'desired_position') {
          if (writer == null) continue;
          final before =
              (reader == null ? null : await reader('desired_position'))?.raw ??
                  '';
          await writer('desired_position', e.value);
          item.undos.add(() => writer('desired_position', before));
        }
      } catch (_) {/* best-effort por item; os outros seguem */}
    }
    if (_disposed) return;
    item.status = AssistEditStatus.applied;
    _pendingExtracts.remove(id);
    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaAssistEditApplied,
        props: {'lacuna_key': 'extract', 'op': 'add'});
    _notify();
  }

  void cancelExtract(String id) {
    final item = _pendingExtracts.remove(id);
    if (item == null || item.status != AssistEditStatus.pending) return;
    item.status = AssistEditStatus.cancelled;
    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaAssistEditCancelled,
        props: {'lacuna_key': 'extract', 'op': 'add'});
    _notify();
  }

  Future<void> undoExtract(String id) async {
    AssistExtractItem? item;
    for (final it in thread) {
      if (it is AssistExtractItem && it.id == id) {
        item = it;
        break;
      }
    }
    if (item == null || item.status != AssistEditStatus.applied) return;
    for (final u in item.undos.reversed) {
      try {
        await u();
      } catch (_) {/* best-effort */}
    }
    if (_disposed) return;
    item.status = AssistEditStatus.undone;
    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaAssistEditUndone,
        props: {'lacuna_key': 'extract', 'op': 'add'});
    _notify();
  }

  // ── Editor visual de skills (Fase C) ───────────────────────────────────────

  final Map<String, SkillsEditorItem> _pendingSkillEditors = {};

  /// `edit_skills`: abre o editor visual com as skills atuais. Sem skills ainda
  /// ⇒ editar não faz sentido → cai na COLETA (start_section 'skills').
  Future<void> _proposeSkillsEditor(AssistantTurn turn) async {
    final loader = assistSkillsLoader;
    List<String> current = const [];
    if (loader != null) {
      try {
        current = await loader();
      } catch (_) {/* best-effort */}
    }
    if (_disposed) return;
    if (current.isEmpty) {
      final reply = turn.reply.trim();
      final ok = await _injectSection('skills',
          reply.isEmpty ? 'Você ainda não tem skills — bora adicionar? 👇' : reply);
      if (!ok) _pushAi('Bora adicionar suas skills? Me conta uma que você manja.');
      return;
    }
    // Sugestões pra adicionar (pela área) — best-effort, tira as que já tem.
    var suggestions = const <String>[];
    final suggester = assistSkillSuggester;
    if (suggester != null) {
      try {
        final lower = current.map((s) => s.toLowerCase()).toSet();
        suggestions = (await suggester())
            .where((s) => !lower.contains(s.toLowerCase()))
            .take(8)
            .toList();
      } catch (_) {/* best-effort */}
    }
    if (_disposed) return;
    if (turn.reply.trim().isNotEmpty) _pushAi(turn.reply.trim());
    final item = SkillsEditorItem(
        id: 'edit_${_editSeq++}', initial: current, suggestions: suggestions);
    _pendingSkillEditors[item.id] = item;
    thread.add(item);
    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaAssistEditProposed,
        props: {'lacuna_key': 'skills', 'op': 'edit'});
    _notify();
  }

  /// "Salvar" no editor: aplica o líquido (adds + removes via os callbacks de
  /// item) e guarda o undo do LOTE. Sem mudança ⇒ fecha como cancelado.
  Future<void> applySkillsEditor(String id,
      {required List<String> added, required List<String> removed}) async {
    final item = _pendingSkillEditors[id];
    if (item == null || item.status != AssistEditStatus.pending) return;
    if (added.isEmpty && removed.isEmpty) {
      cancelSkillsEditor(id);
      return;
    }
    final adder = assistItemAdder;
    final remover = assistItemRemover;
    for (final s in added) {
      if (adder == null) continue;
      try {
        await adder('skill', s);
        if (remover != null) item.undos.add(() => remover('skill', s));
      } catch (_) {/* best-effort por item */}
    }
    for (final s in removed) {
      if (remover == null) continue;
      try {
        await remover('skill', s);
        if (adder != null) item.undos.add(() => adder('skill', s));
      } catch (_) {/* best-effort por item */}
    }
    if (_disposed) return;
    item.addedApplied = added;
    item.removedApplied = removed;
    item.status = AssistEditStatus.applied;
    _pendingSkillEditors.remove(id);
    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaAssistEditApplied,
        props: {'lacuna_key': 'skills', 'op': 'edit'});
    _notify();
  }

  void cancelSkillsEditor(String id) {
    final item = _pendingSkillEditors.remove(id);
    if (item == null || item.status != AssistEditStatus.pending) return;
    item.status = AssistEditStatus.cancelled;
    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaAssistEditCancelled,
        props: {'lacuna_key': 'skills', 'op': 'edit'});
    _notify();
  }

  Future<void> undoSkillsEditor(String id) async {
    SkillsEditorItem? item;
    for (final it in thread) {
      if (it is SkillsEditorItem && it.id == id) {
        item = it;
        break;
      }
    }
    if (item == null || item.status != AssistEditStatus.applied) return;
    for (final u in item.undos.reversed) {
      try {
        await u();
      } catch (_) {/* best-effort */}
    }
    if (_disposed) return;
    item.status = AssistEditStatus.undone;
    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaAssistEditUndone,
        props: {'lacuna_key': 'skills', 'op': 'edit'});
    _notify();
  }

  /// Serializa o passo aberto pro grounding do assistente (sem PII sensível).
  Map<String, dynamic> _serializeStep(ConversationStep step) {
    final input = step.input;
    var kind = 'other';
    var multi = false;
    var optional = false;
    var options = const <Map<String, String>>[];
    if (input is ChoiceInput) {
      kind = 'choice';
      multi = input.multi;
      options = [for (final o in input.options) {'id': o.id, 'label': o.label}];
    } else if (input is GuidedTextInput) {
      kind = 'text';
      optional = input.optional;
    } else if (input is MonthYearInput) {
      kind = 'month_year';
      optional = input.optional;
    } else if (input is SuggestPickInput || input is AsyncSuggestInput) {
      kind = 'suggest';
    } else if (input is AsyncPickInput) {
      kind = 'search';
    } else if (input is ExperienceTypeInput) {
      kind = 'experience_type';
    }
    return {
      'id': step.id,
      'question': step.aiMessages.join(' ').trim(),
      'inputKind': kind,
      'options': options,
      'multi': multi,
      'optional': optional,
    };
  }

  /// Últimas ~6 falas do fio (role+texto) — contexto curto pro assistente.
  List<Map<String, dynamic>> _recentHistory() {
    final out = <Map<String, dynamic>>[];
    for (final item in thread) {
      if (item is AiMsgItem) {
        out.add({'role': 'ai', 'text': item.text});
      } else if (item is AnsweredItem) {
        out.add({'role': 'user', 'text': item.exchange.answer.displayText});
      }
    }
    return out.length <= 6 ? out : out.sublist(out.length - 6);
  }

  bool _stepIsOptional(ConversationStep step) {
    final i = step.input;
    if (i is GuidedTextInput) return i.optional;
    if (i is MonthYearInput) return i.optional;
    return false;
  }

  /// Heurística LOCAL e conservadora: a mensagem tem cara de COMANDO (e não de
  /// resposta ao passo de texto aberto)? Só é usada pra decidir o ATALHO local
  /// (Nível 0); falso-positivo apenas manda pro assistente (que reinterpreta).
  static final RegExp _cmdVerbs = RegExp(
      r'^(adiciona|adicionar|add|tira|tirar|remove|remover|apaga|apagar|muda|mudar|troca|trocar|corrige|corrigir|edita|editar|reescreve|reescrever|melhora|melhorar|refor[çc]a|refor[çc]ar|pula|pular|mostra|mostrar|explica|explicar|ajuda|quero|como|o que|qual|quais|por que|porque|pq)\b',
      caseSensitive: false);
  static final RegExp _sectionWords = RegExp(
      r'\b(skill|habilidade|experi[eê]ncia|resumo|bullet|cidade|cargo|[aá]rea|idioma|projeto|forma[cç][aã]o|linkedin|certifica|pr[eê]mio|disponibilidade|interesse|perfil|curr[ií]culo)',
      caseSensitive: false);
  bool _looksLikeCommand(String t) {
    final s = t.trim();
    if (s.endsWith('?')) return true;
    if (_cmdVerbs.hasMatch(s)) return true;
    if (_sectionWords.hasMatch(s)) return true;
    return false;
  }

  /// Um textão colado (várias infos de uma vez) não é resposta de um passo —
  /// deve ir pra IA extrair. Heurística: quebra de linha, ou longo com ≥2
  /// vírgulas (enumeração "curso X, falo Y, sei Z").
  bool _looksLikePaste(String t) {
    final s = t.trim();
    if (s.contains('\n')) return true;
    if (s.length > 140 && ','.allMatches(s).length >= 2) return true;
    return false;
  }

  // ── Fase C: sugestão proativa do próximo ganho ─────────────────────────────

  /// Seção sugerida no último nudge (pra o atalho "quero" cair direto nela).
  String? _suggestedSection;

  static final RegExp _affirmative = RegExp(
      r'^(sim|claro|quero|quer[ ]?sim|bora|pode|podemos|vamos|vam[uo]s|partiu|com certeza|isso|manda|ok|beleza|blz|t[aá]|uhum|s)\b',
      caseSensitive: false);
  bool _isAffirmative(String t) {
    final s = t.trim();
    return s == '👍' || _affirmative.hasMatch(s);
  }

  /// Ao CONCLUIR, sugere reforçar a maior lacuna que resta. A pessoa aceita com
  /// "quero/bora" (atalho) ou pedindo a seção. No-op se a flag OFF / sem loader.
  Future<void> _maybeSuggestNextGap() async {
    if (!assistEnabled) return;
    final loader = assistProactiveLoader;
    if (loader == null) return;
    Map<String, String>? gap;
    try {
      gap = await loader();
    } catch (_) {
      gap = null;
    }
    if (_disposed || gap == null) return;
    final section = gap['section'] ?? '';
    final label = gap['label'] ?? '';
    if (section.isEmpty || label.isEmpty) return;
    _suggestedSection = section;
    _pushAi('Se quiser deixar ainda mais forte, o que mais pesa agora é: '
        '$label. Quer preencher? (é só dizer "quero" 😉)');
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
    if (fn != null) {
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
    // Fase C: depois do resumo (ou direto, se não há finalize), sugere o
    // próximo ganho — se ainda falta algo que o assistente sabe conduzir.
    await _maybeSuggestNextGap();
  }
}
