// Tela da Trilha de Coleta conversacional (PLANO-FASE-6 T6.3).
//
// Orquestra o RITMO de conversa: digitando → fala(s) da IA → entrada inline →
// resposta do usuário → reação da IA → próximo passo. O [ConversationController]
// é a fonte da verdade da progressão; esta tela traduz isso num fio de bolhas
// que aparece com timing humano (indicador de digitação, revelação gradual).

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
const Duration _typingDuration = Duration(milliseconds: 750);
const Duration _betweenMessages = Duration(milliseconds: 320);

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
  });

  final ConversationController controller;
  final String title;

  /// Chamado quando a trilha termina (todos os passos respondidos).
  final VoidCallback? onCompleted;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final ScrollController _scroll = ScrollController();
  final List<_ChatItem> _items = [];
  bool _typing = false;
  bool _inputVisible = false;
  bool _finished = false;

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
    await Future.delayed(_typingDuration);
    if (!mounted) return;
    setState(() => _typing = false);

    for (final msg in step.aiMessages) {
      if (!mounted) return;
      setState(() => _items.add(_ChatItem(_ItemKind.ai, msg)));
      _scrollToEnd();
      await Future.delayed(_betweenMessages);
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
      await Future.delayed(_typingDuration);
      if (!mounted) return;
      setState(() {
        _typing = false;
        _items.add(_ChatItem(_ItemKind.ai, ack));
      });
      _scrollToEnd();
      await Future.delayed(_betweenMessages);
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
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final step = _c.current;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
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
          ClipRRect(
            borderRadius: AppRadius.brPill,
            child: LinearProgressIndicator(
              value: _finished ? 1.0 : _shownProgress,
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.success),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thread() {
    final children = <Widget>[
      for (final item in _items)
        item.kind == _ItemKind.ai
            ? AiBubble(text: item.text)
            : UserBubble(text: item.text),
      if (_typing) const TypingBubble(),
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
      child: AppCard(
        variant: AppCardVariant.gradient,
        child: Column(
          children: [
            const Icon(Icons.celebration_rounded,
                color: AppColors.onPrimary, size: 36),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Perfil mais forte! 🎉',
              style: AppTextStyles.titleMd.copyWith(color: AppColors.onPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Quanto mais completo, mais empresas conseguem te achar.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.onPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(ConversationStep? step) {
    final showInput = _inputVisible && step != null && !_typing && !_finished;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: showInput
          ? Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(color: AppColors.border),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.base,
                AppSpacing.base,
                AppSpacing.base,
                AppSpacing.lg,
              ),
              child: StepInputView(
                key: ValueKey(step.id),
                step: step,
                enabled: !_c.isSaving,
                onSubmit: _onSubmit,
              ),
            )
          : _finished
              ? Container(
                  width: double.infinity,
                  color: AppColors.surface,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.base,
                    AppSpacing.base,
                    AppSpacing.base,
                    AppSpacing.lg,
                  ),
                  child: PrimaryButton(
                    label: 'Concluir',
                    onPressed: () {
                      widget.onCompleted?.call();
                      Navigator.of(context).maybePop();
                    },
                  ),
                )
              : const SizedBox(width: double.infinity),
    );
  }
}
