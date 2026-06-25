// Tela da Trilha de Coleta conversacional (PLANO-FASE-6 T6.3).
//
// Orquestra o RITMO de conversa: digitando → fala(s) da IA → entrada inline →
// resposta do usuário → reação da IA → próximo passo. O [ConversationController]
// é a fonte da verdade da progressão; esta tela traduz isso num fio de bolhas
// que aparece com timing humano (indicador de digitação, revelação gradual).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../application/conversation_controller.dart';
import '../domain/conversation_step.dart';
import 'widgets/chat_bubbles.dart';
import 'widgets/step_input_view.dart';

/// Ritmo da conversa (ajustável). Curto o bastante pra não cansar, longo o
/// bastante pra parecer que a IA "pensa".
/// Tempo de "digitando" proporcional ao tamanho da fala (parece que a IA
/// realmente escreve aquilo) — piso/teto curtos pra não cansar.
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

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.controller,
    this.title = 'Vamos completar seu perfil',
    this.onCompleted,
    this.onAbandoned,
    this.onFinalize,
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

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    if (!_finished && _c.answeredCount > 0) {
      widget.onAbandoned?.call(_c.answeredCount, _c.totalSteps);
    }
    _scroll.dispose();
    super.dispose();
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

    // Reação da IA ao que foi respondido.
    final ack = step.acknowledgement;
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

  @override
  Widget build(BuildContext context) {
    final step = _c.current;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        // O footer cuida do inset de baixo (preenche o branco até a borda) —
        // senão sobra uma faixa cinza embaixo dos botões.
        bottom: false,
        child: Column(
          children: [
            _header(),
            Expanded(child: _thread()),
            _footer(step),
          ],
        ),
      ),
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
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: AppColors.textTertiary),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'Fechar',
              ),
              Expanded(
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.titleMd
                      .copyWith(color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // Anima suave até o novo valor (não pula em degraus).
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: _finished ? 1.0 : _shownProgress),
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
      ),
    );
  }

  Widget _thread() {
    final children = <Widget>[
      for (var i = 0; i < _items.length; i++)
        Padding(
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
    return Column(
      key: const ValueKey('finalizing'),
      children: [
        const TypingDots(color: AppColors.onPrimary),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Montando seu resumo com a IA…',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMd.copyWith(color: AppColors.onPrimary),
        ),
      ],
    );
  }

  Widget _doneBlock() {
    return Column(
      key: const ValueKey('done'),
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
        Text(
          'Perfil mais forte! 🎉',
          style: AppTextStyles.titleMd.copyWith(color: AppColors.onPrimary),
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
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final dockPadding = EdgeInsets.fromLTRB(
        AppSpacing.base, AppSpacing.base, AppSpacing.base, AppSpacing.lg + bottomSafe);
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
        child: StepInputView(
          key: ValueKey(step.id),
          step: step,
          enabled: !_c.isSaving,
          onSubmit: _onSubmit,
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
                  Navigator.of(context).maybePop();
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
            position: Tween<Offset>(
                    begin: const Offset(0, 0.06), end: Offset.zero)
                .animate(anim),
            child: child,
          ),
        ),
        child: content,
      ),
    );
  }
}
