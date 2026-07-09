// Motor da conversa da Trilha de Coleta (PLANO-FASE-6 T6.3), extraído da
// ConversationScreen pra ser reusável em dois "chromes":
//
//  - PUSHADO (ConversationScreen): Scaffold + SafeArea + header com X/progresso
//    + PopScope de confirmação de saída. É o que o convite pós-onboarding e o
//    modo dev empurram via Navigator.
//  - EMBUTIDO (aba Currículo): sem header/X/PopScope; o chat fica aberto dentro
//    da aba, e o stepper/progresso vive no shell da aba. "Concluir" não dá pop.
//
// Mantém TODA a lógica de ritmo (digitando → falas da IA → entrada inline →
// resposta → reação → próximo passo → conclusão + finalização por IA). Os flags
// de chrome têm defaults que preservam EXATAMENTE o comportamento pushado — por
// isso os widget tests da ConversationScreen continuam verdes sem mudança.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/widgets.dart';
import '../../application/conversation_controller.dart';
import '../../domain/conversation_step.dart';
import 'chat_bubbles.dart';
import 'step_input_view.dart';

/// Ritmo da conversa (ajustável). Curto o bastante pra não cansar, longo o
/// bastante pra parecer que a IA "pensa".
Duration _typingFor(String msg) =>
    Duration(milliseconds: (msg.length * 16).clamp(420, 1200).toInt());

/// Micro-pausa depois de cada fala, também proporcional ao tamanho.
Duration _pauseFor(String msg) =>
    Duration(milliseconds: (msg.length * 4).clamp(200, 460).toInt());

enum _ItemKind { ai, user }

class _ChatItem {
  final _ItemKind kind;
  final String text;
  const _ChatItem(this.kind, this.text);
}

/// O corpo da conversa (header opcional + fio de bolhas + dock de entrada).
/// Parametrizado por chrome pra servir tanto pushado quanto embutido na aba.
class ChatThreadView extends StatefulWidget {
  const ChatThreadView({
    super.key,
    required this.controller,
    this.title = 'Vamos completar seu perfil',
    this.onCompleted,
    this.onAbandoned,
    this.onFinalize,
    // ---- chrome (defaults = comportamento pushado, preserva testes) ----
    this.showHeader = true,
    this.showCloseButton = true,
    this.showProgressBar = true,
    this.enablePopScope = true,
    this.popOnComplete = true,
    this.emitAbandonOnDispose = true,
    this.footerUsesScaffoldInset = true,
  });

  final ConversationController controller;
  final String title;

  /// Chamado quando a trilha termina (todos os passos respondidos).
  final VoidCallback? onCompleted;

  /// Chamado se a tela fecha ANTES de concluir (com ao menos 1 resposta dada).
  final void Function(int answered, int total)? onAbandoned;

  /// Roda na conclusão (ex.: a IA monta o resumo do perfil). Retorna o resumo
  /// gerado pra prévia, ou null. FAILURE-SAFE: erro não trava a conclusão.
  final Future<String?> Function()? onFinalize;

  /// Header com título + (X opcional) + (progresso opcional) + undo.
  final bool showHeader;

  /// Botão X de fechar no header (só faz sentido pushado).
  final bool showCloseButton;

  /// Barra de progresso no header (no embutido, o stepper da aba substitui).
  final bool showProgressBar;

  /// Intercepta o pop pra confirmar saída quando há progresso (só pushado).
  final bool enablePopScope;

  /// "Concluir" dá `Navigator.maybePop()` (pushado) ou só chama onCompleted
  /// (embutido — não há rota pra fechar; a aba persiste).
  final bool popOnComplete;

  /// Dispara `onAbandoned` no dispose. No embutido fica FALSE: a aba é
  /// kept-alive, e o dispose acontece no fechamento do app, não na saída do
  /// usuário — senão registraria abandono falso a cada teardown.
  final bool emitAbandonOnDispose;

  /// Soma `MediaQuery.padding.bottom` (home indicator) no dock. No embutido a
  /// aba já está dentro do SafeArea da HomeScreen → fica FALSE.
  final bool footerUsesScaffoldInset;

  @override
  State<ChatThreadView> createState() => _ChatThreadViewState();
}

class _ChatThreadViewState extends State<ChatThreadView>
    with WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();
  final List<_ChatItem> _items = [];
  bool _typing = false;
  bool _inputVisible = false;
  bool _finished = false;

  /// Finalização (resumo por IA): roda 1x ao concluir.
  bool _finalizing = false;
  String? _generatedSummary;

  /// Re-scroll agendado pra depois das animações de layout assentarem.
  Timer? _settleTimer;

  /// Progresso exibido — NUNCA regride. A trilha é dinâmica (passos são
  /// injetados no loop de experiência), então o denominador cresce; sem isso a
  /// barra pularia pra trás. Mantemos o máximo já atingido.
  double _shownProgress = 0.0;

  ConversationController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settleTimer?.cancel();
    if (widget.emitAbandonOnDispose && !_finished && _c.answeredCount > 0) {
      widget.onAbandoned?.call(_c.answeredCount, _c.totalSteps);
    }
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Teclado abriu/fechou (ou rotação): re-fixa o fio no fim — a última
    // pergunta da IA nunca pode ficar atrás do dock de entrada. O re-scroll
    // roda pós-frame (já com o novo inset) e é animado (suave).
    if (!mounted) return;
    if (_inputVisible || _typing || _finished) _scrollToEnd();
  }

  // Revela o passo atual: digitando → bolhas da IA → libera a entrada.
  Future<void> _revealCurrent() async {
    final step = _c.current;
    if (step == null) {
      _onDone();
      return;
    }
    if (!mounted) return;
    setState(() {
      _inputVisible = false;
      _typing = true;
    });
    _scrollToEnd();
    await Future.delayed(
        _typingFor(step.aiMessages.isNotEmpty ? step.aiMessages.first : ''));
    if (!mounted) return;
    setState(() => _typing = false);

    for (final msg in step.aiMessages) {
      if (!mounted) return;
      setState(() => _items.add(_ChatItem(_ItemKind.ai, msg)));
      _scrollToEnd();
      await Future.delayed(_pauseFor(msg));
    }
    if (!mounted) return;
    setState(() => _inputVisible = true);
    _scrollToEnd();
  }

  Future<void> _onSubmit(StepAnswer answer) async {
    final step = _c.current;
    if (step == null) return;

    // Eco imediato da resposta + esconde a entrada.
    setState(() {
      _inputVisible = false;
      _items.add(_ChatItem(_ItemKind.user, answer.displayText));
    });
    _scrollToEnd();

    // Write-back (defensivo no controller).
    await _c.submit(answer);
    if (!mounted) return;
    _shownProgress = math.max(_shownProgress, _c.progress);

    // Reação da IA ao que foi respondido (recap dinâmico > ack fixo).
    final ack = step.recap?.call([for (final e in _c.history) e.answer]) ??
        step.acknowledgement;
    if (ack != null && ack.trim().isNotEmpty) {
      setState(() => _typing = true);
      _scrollToEnd();
      await Future.delayed(_typingFor(ack));
      if (!mounted) return;
      setState(() {
        _typing = false;
        _items.add(_ChatItem(_ItemKind.ai, ack));
      });
      _scrollToEnd();
      await Future.delayed(_pauseFor(ack));
      if (!mounted) return;
    }

    _revealCurrent();
  }

  /// Volta um passo: reverte o controller e RECONSTRÓI o fio a partir do
  /// histórico (determinístico — sem corrida com as animações incrementais),
  /// re-mostrando a pergunta do passo pro qual voltou. Não duplica dado: o
  /// controller só deixa voltar em passos reversíveis (ver canGoBack).
  Future<void> _undoLast() async {
    if (!_c.canGoBack) return;
    _settleTimer?.cancel();
    _c.goBack();
    final cur = _c.current;
    setState(() {
      _typing = false;
      _items
        ..clear()
        ..addAll(_threadFromHistory());
      if (cur != null) {
        for (final m in cur.aiMessages) {
          _items.add(_ChatItem(_ItemKind.ai, m));
        }
      }
      _inputVisible = cur != null;
      _shownProgress = _c.progress; // recua junto (voltou um passo de fato)
    });
    _scrollToEnd();
  }

  /// Reconstrói as bolhas a partir das trocas já concluídas (pergunta da IA →
  /// resposta do usuário → reação da IA), na ordem do fio.
  List<_ChatItem> _threadFromHistory() {
    final out = <_ChatItem>[];
    for (final ex in _c.history) {
      for (final m in ex.step.aiMessages) {
        out.add(_ChatItem(_ItemKind.ai, m));
      }
      out.add(_ChatItem(_ItemKind.user, ex.answer.displayText));
      final ack = ex.step.recap?.call([for (final e in _c.history) e.answer]) ??
          ex.step.acknowledgement;
      if (ack != null && ack.trim().isNotEmpty) {
        out.add(_ChatItem(_ItemKind.ai, ack));
      }
    }
    return out;
  }

  void _onDone() {
    setState(() {
      _inputVisible = false;
      _typing = false;
      _finished = true;
    });
    _scrollToEnd();
    _runFinalize();
  }

  /// Roda a finalização (resumo por IA) 1x. Failure-safe: erro/null só não
  /// mostra a prévia — a conclusão segue normal.
  Future<void> _runFinalize() async {
    final fn = widget.onFinalize;
    if (fn == null) return;
    setState(() => _finalizing = true);
    _scrollToEnd();
    String? summary;
    try {
      summary = await fn();
    } catch (_) {
      summary = null;
    }
    if (!mounted) return;
    setState(() {
      _finalizing = false;
      _generatedSummary = summary;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    void doScroll() {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      final delta = (target - _scroll.offset).abs();
      if (delta < 1) return; // já no fim — evita re-scroll redundante
      final ms = (200 + delta * 0.5).clamp(220, 440).toInt();
      _scroll.animateTo(
        target,
        duration: Duration(milliseconds: ms),
        curve: Curves.easeOutCubic,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => doScroll());
    // Re-scroll depois que as animações de layout (footer expandindo ao mostrar
    // os botões) assentam — senão a última pergunta fica tampada e o usuário
    // teria que rolar pra ver. Timer cancelável (some no dispose / re-agenda).
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 320), () {
      if (mounted) doScroll();
    });
  }

  /// Fixa o fio no fim IMEDIATAMENTE (sem animação) — disparado quando o FOOTER
  /// muda de altura (ex.: vira o seletor de data, bem mais alto). Acompanha o
  /// crescimento do footer frame a frame, então a última pergunta nunca fica
  /// tampada pelo widget — sem depender de um tempo chutado.
  void _pinToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if ((_scroll.offset - max).abs() > 1) _scroll.jumpTo(max);
    });
  }

  /// Confirma a saída se já houve progresso (e a trilha não acabou). Retorna
  /// true quando pode sair. Failure-safe: sem progresso ou já concluída, sai
  /// direto.
  Future<bool> confirmExit() async {
    if (_finished || _c.answeredCount == 0) return true;
    final n = _c.answeredCount;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.brLg),
        title: Text('Sair da trilha?',
            style: AppTextStyles.titleSm.copyWith(color: AppColors.textPrimary)),
        content: Text(
          'Você já preencheu $n ${n == 1 ? 'resposta' : 'respostas'} — seu '
          'progresso fica salvo e dá pra continuar depois.',
          style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Continuar',
                style:
                    AppTextStyles.labelMd.copyWith(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Sair',
                style: AppTextStyles.labelMd
                    .copyWith(color: AppColors.textTertiary)),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final step = _c.current;
    final core = Column(
      children: [
        if (widget.showHeader) _header(),
        Expanded(child: _thread()),
        // Quando o footer muda de altura (ex.: vira o seletor de data, bem
        // mais alto), gruda o fio no fim — a pergunta não fica tampada pelo
        // widget. Reage ao layout REAL, não a um timer.
        NotificationListener<SizeChangedLayoutNotification>(
          onNotification: (_) {
            _pinToEnd();
            return false;
          },
          child: SizeChangedLayoutNotifier(child: _footer(step)),
        ),
      ],
    );

    if (!widget.enablePopScope) return core;
    return PopScope(
      // Confirma a saída quando há progresso não concluído. O X fica no canto
      // onde o polegar repousa; um toque acidental não pode descartar a sessão.
      canPop: _finished || _c.answeredCount == 0,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await confirmExit();
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: core,
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.base,
        AppSpacing.sm,
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (widget.showCloseButton)
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textTertiary),
                  onPressed: () => Navigator.of(context).maybePop(),
                  tooltip: 'Fechar',
                )
              else
                const SizedBox(width: 48),
              Expanded(
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.titleMd
                      .copyWith(color: AppColors.textPrimary),
                ),
              ),
              // "Voltar" — refaz o passo anterior (só quando é seguro: passo
              // reversível, entrada visível). Errou a cidade/área/semestre? Volta.
              SizedBox(
                width: 48,
                child: (_c.canGoBack && _inputVisible && !_typing && !_finished)
                    ? IconButton(
                        icon: const Icon(Icons.undo_rounded,
                            color: AppColors.textTertiary),
                        onPressed: _undoLast,
                        tooltip: 'Voltar',
                      )
                    : null,
              ),
            ],
          ),
          if (widget.showProgressBar) ...[
            const SizedBox(height: AppSpacing.xs),
            // Anima suave até o novo valor (não pula em degraus).
            TweenAnimationBuilder<double>(
              tween: Tween<double>(
                  begin: 0, end: _finished ? 1.0 : _shownProgress),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => ClipRRect(
                borderRadius: AppRadius.brPill,
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: AppColors.border,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.success),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _thread() {
    final children = <Widget>[
      for (var i = 0; i < _items.length; i++)
        Padding(
          // Key por índice: no undo o fio é reconstruído como um PREFIXO (só
          // encurta no fim), então as bolhas que sobrevivem reusam o widget e
          // não re-animam a entrada.
          key: ValueKey('item-$i'),
          // Respiro: pouco entre falas do MESMO turno, mais quando o turno muda.
          padding: EdgeInsets.only(
            bottom:
                (i < _items.length - 1 && _items[i + 1].kind == _items[i].kind)
                    ? AppSpacing.sm
                    : AppSpacing.lg,
          ),
          child: _items[i].kind == _ItemKind.ai
              // Avatar só na 1ª fala de um bloco da IA (agrupa o turno).
              ? AiBubble(
                  text: _items[i].text,
                  showAvatar: i == 0 || _items[i - 1].kind != _ItemKind.ai,
                )
              : UserBubble(text: _items[i].text),
        ),
      // "Digitando" entra/sai com fade (a bolha já desliza pelo _Entrance).
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: _typing
            ? const Padding(
                key: ValueKey('typing'),
                padding: EdgeInsets.only(bottom: AppSpacing.lg),
                child: TypingBubble(),
              )
            : const SizedBox(key: ValueKey('no-typing')),
      ),
      if (_finished) _completionCard(),
    ];
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
      ),
      children: children,
    );
  }

  Widget _completionCard() {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.base),
      // Entrada de celebração: fade + leve scale.
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
        ),
        child: AppCard(
          variant: AppCardVariant.gradient,
          // Montando → pronto com cross-fade + altura animada.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SizeTransition(
                  sizeFactor: anim, axisAlignment: -1, child: child),
            ),
            child: _finalizing ? _finalizingBlock() : _doneBlock(),
          ),
        ),
      ),
    );
  }

  Widget _finalizingBlock() {
    // `width: double.infinity` no texto força a Column a ocupar a largura toda
    // do card → os pontinhos centralizam de fato (antes a Column encolhia à
    // largura do texto e os dots ficavam tortos, fora do centro do card).
    return Column(
      key: const ValueKey('finalizing'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const TypingDots(color: AppColors.onPrimary),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: Text(
            'Montando seu resumo com a IA…',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMd.copyWith(color: AppColors.onPrimary),
          ),
        ),
      ],
    );
  }

  Widget _doneBlock() {
    return Column(
      key: const ValueKey('done'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // O ícone "estoura" com leve overshoot.
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 460),
          curve: Curves.easeOutBack,
          builder: (context, t, child) =>
              Transform.scale(scale: t.clamp(0.0, 1.2), child: child),
          child: const Icon(Icons.celebration_rounded,
              color: AppColors.onPrimary, size: 36),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: Text(
            'Perfil mais forte! 🎉',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleMd.copyWith(color: AppColors.onPrimary),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _generatedSummary != null
              ? 'A IA criou um resumo pro seu perfil:'
              : 'Quanto mais completo, mais empresas conseguem te achar.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMd.copyWith(color: AppColors.onPrimary),
        ),
        if (_generatedSummary != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: AppSpacing.allMd,
            decoration: BoxDecoration(
              color: AppColors.onPrimary.withValues(alpha: 0.15),
              borderRadius: AppRadius.brMd,
            ),
            child: Text(
              _generatedSummary!,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.onPrimary),
            ),
          ),
        ],
      ],
    );
  }

  Widget _footer(ConversationStep? step) {
    final showInput = _inputVisible && step != null && !_typing && !_finished;
    // Inset do home indicator — somado ao padding de baixo pra o branco do
    // footer ir até a borda inferior (sem faixa cinza embaixo dos botões).
    // No embutido a aba já vive dentro do SafeArea da HomeScreen → não soma.
    final bottomSafe =
        widget.footerUsesScaffoldInset ? MediaQuery.of(context).padding.bottom : 0.0;
    final dockPadding = EdgeInsets.fromLTRB(AppSpacing.base, AppSpacing.base,
        AppSpacing.base, AppSpacing.lg + bottomSafe);
    final Widget content;
    if (showInput) {
      content = Container(
        key: ValueKey('input-${step.id}'),
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: dockPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Undo embutido: sem header, oferece "Voltar" discreto no topo do
            // dock quando é seguro voltar (no pushado o undo fica no header).
            if (!widget.showHeader &&
                _c.canGoBack &&
                !_c.isSaving)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _undoLast,
                  icon: const Icon(Icons.undo_rounded,
                      size: 16, color: AppColors.textTertiary),
                  label: Text('Voltar',
                      style: AppTextStyles.labelSm
                          .copyWith(color: AppColors.textTertiary)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: 0),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            StepInputView(
              key: ValueKey(step.id),
              step: step,
              enabled: !_c.isSaving,
              onSubmit: _onSubmit,
            ),
          ],
        ),
      );
    } else if (_finished) {
      content = Container(
        key: const ValueKey('done'),
        width: double.infinity,
        color: AppColors.surface,
        padding: dockPadding,
        child: PrimaryButton(
          label: _finalizing ? 'Montando seu resumo…' : 'Concluir',
          onPressed: _finalizing
              ? null
              : () {
                  widget.onCompleted?.call();
                  if (widget.popOnComplete) Navigator.of(context).maybePop();
                },
        ),
      );
    } else {
      content = const SizedBox(key: ValueKey('empty'), width: double.infinity);
    }
    // Altura (AnimatedSize) + conteúdo (AnimatedSwitcher: fade + leve slide).
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position:
                Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
                    .animate(anim),
            child: child,
          ),
        ),
        child: content,
      ),
    );
  }
}
