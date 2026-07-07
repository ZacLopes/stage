// View do chat da trilha v2 (PLANO chat v2 — F2 + F3).
//
// Renderiza o FIO (bolhas da IA + cards de resposta editáveis + o widget inline
// do passo atual + o gate de import + bolha de arquivo + card-resumo) e a BARRA
// inferior fixa (texto + 📎 anexar + ▶ enviar). Observa o [TrilhaChatController].
// Sem doca que sobe: os widgets vivem no fio; o teclado só na barra (texto livre).

import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../services/cv_import_service.dart';
import '../application/trilha_hub_status.dart';
import '../application/trilha_section.dart';
import 'trilha_chat_controller.dart';
import 'widgets/chat_bubbles.dart';
import 'widgets/inline/inline_step_input.dart';
import 'widgets/inline/trilha_answer_card.dart';

class TrilhaChatView extends StatefulWidget {
  const TrilhaChatView({
    super.key,
    required this.controller,
    this.onVerifySection,
    this.hubStatus,
  });

  final TrilhaChatController controller;

  /// Toque num tile do resumo do import → abre o sheet de verificação daquela
  /// seção (null = tiles não-tocáveis).
  final void Function(TrilhaSection section)? onVerifySection;

  /// Força honesta do perfil pro card de conclusão (força real + próximo ganho,
  /// nunca "forte" com lacuna aberta). Null ⇒ cai no texto genérico.
  final TrilhaHubStatus? hubStatus;

  @override
  State<TrilhaChatView> createState() => _TrilhaChatViewState();
}

class _TrilhaChatViewState extends State<TrilhaChatView>
    with WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _text = TextEditingController();

  TrilhaChatController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.addListener(_onTick);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.removeListener(_onTick);
    _scroll.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onTick() => _scrollToEnd();

  @override
  void didChangeMetrics() {
    if (mounted) _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if ((target - _scroll.offset).abs() < 1) return;
      _scroll.animateTo(target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic);
    });
  }

  void _sendText() {
    final t = _text.text;
    if (t.trim().isEmpty) return;
    _text.clear();
    // ignore: unawaited_futures
    _c.submitFreeText(t);
  }

  /// Anexar/importar CV — reaproveita o pipeline existente; UI nova.
  Future<void> _import() async {
    final result = await CvImportService.pickAndImport(context);
    if (!mounted) return;
    if (result.success) {
      // Mesmo sem texto usável (PDF salvo, extração não roda): segue o fluxo —
      // o controller cai na conversa (extractionExpected=false pula o poll).
      // Sem isso, o gate ficaria preso num no-op silencioso.
      // Bolha mostra o NOME REAL do arquivo (não o título da biblioteca).
      // ignore: unawaited_futures
      _c.onCvUploaded(result.fileName ?? result.title ?? 'currículo.pdf',
          extractionExpected: result.textWasUsable);
    } else if (result.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.errorMessage!),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Column(
          children: [
            Expanded(child: _thread()),
            _bottomBar(),
          ],
        );
      },
    );
  }

  Widget _thread() {
    final c = _c;
    final children = <Widget>[];

    for (var i = 0; i < c.thread.length; i++) {
      final item = c.thread[i];
      if (item is AiMsgItem) {
        final prevIsAi = i > 0 && c.thread[i - 1] is AiMsgItem;
        children.add(Padding(
          key: ValueKey('ai-$i'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: AiBubble(text: item.text, showAvatar: !prevIsAi),
        ));
      } else if (item is FileBubbleItem) {
        children.add(Padding(
          key: ValueKey('file-$i'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _fileBubble(item.name),
        ));
      } else if (item is ImportSummaryItem) {
        children.add(Padding(
          key: ValueKey('summary-$i'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _importSummary(item.summary),
        ));
      } else if (item is AnsweredItem) {
        if (c.editingIndex == i && c.activeStep != null) {
          children.add(Padding(
            key: ValueKey('edit-$i'),
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: InlineStepInput(step: c.activeStep!, onSubmit: c.submit),
          ));
        } else {
          children.add(KeyedSubtree(
            key: ValueKey('ans-$i'),
            child: TrilhaAnswerCard(
              exchange: item.exchange,
              onEdit: item.exchange.step.reversible
                  ? () => c.beginEdit(item)
                  : null,
            ),
          ));
        }
      }
    }

    // Gate de import (abertura).
    if (c.phase == ChatPhase.gate) {
      children.add(Padding(
        key: const ValueKey('gate'),
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: _gateChoice(),
      ));
    }

    // Passo atual (conversa): widget inline no fim do fio.
    if (c.phase == ChatPhase.converse &&
        c.inputVisible &&
        !c.isEditing &&
        c.activeStep != null) {
      children.add(Padding(
        key: ValueKey('current-${c.activeStep!.id}'),
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: InlineStepInput(step: c.activeStep!, onSubmit: c.submit),
      ));
    }

    if (c.typing) {
      children.add(const Padding(
        key: ValueKey('typing'),
        padding: EdgeInsets.only(bottom: AppSpacing.md),
        child: TypingBubble(),
      ));
    }

    if (c.finished) children.add(_completionCard(c));

    return ListView(
      controller: _scroll,
      padding: AppSpacing.allBase,
      children: children,
    );
  }

  // ── Gate de import ──────────────────────────────────────────────────────────

  Widget _gateChoice() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          label: 'Começar do zero',
          icon: Icons.add_rounded,
          onPressed: () {
            // ignore: unawaited_futures
            _c.chooseZero();
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        SecondaryButton(
          label: 'Já tenho um currículo',
          icon: Icons.upload_rounded,
          onPressed: _import,
        ),
      ],
    );
  }

  // ── Bolha de arquivo ────────────────────────────────────────────────────────

  Widget _fileBubble(String name) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: AppSpacing.allSm,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.onPrimary.withValues(alpha: 0.18),
                borderRadius: AppRadius.brSm,
              ),
              child: const Icon(Icons.description_rounded,
                  size: 18, color: AppColors.onPrimary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMd
                      .copyWith(color: AppColors.onPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Card-resumo da extração ─────────────────────────────────────────────────

  Widget _importSummary(ImportSummary s) {
    final cells = <(int, String, TrilhaSection)>[
      (s.experiences, 'experiências', TrilhaSection.experiencia),
      (s.skills, 'habilidades', TrilhaSection.skills),
      (s.languages, 'idiomas', TrilhaSection.idiomas),
      (s.education, 'formação', TrilhaSection.formacao),
    ].where((c) => c.$1 > 0).toList();

    return Container(
      // Alinha com o texto das bolhas da IA: avatar (34) + gap (AppSpacing.sm).
      margin: const EdgeInsets.only(left: 34 + AppSpacing.sm),
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('O que encontrei', style: AppTextStyles.overline),
          const SizedBox(height: 2),
          Text('Toque pra conferir cada um 👇',
              style: AppTextStyles.bodySm
                  .copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [for (final c in cells) _summaryTile(c.$1, c.$2, c.$3)],
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: 'Revisar e confirmar',
            onPressed: () {
              // ignore: unawaited_futures
              _c.confirmImport();
            },
          ),
        ],
      ),
    );
  }

  Widget _summaryTile(int count, String label, TrilhaSection section) {
    final onVerify = widget.onVerifySection;
    return InkWell(
      onTap: onVerify == null ? null : () => onVerify(section),
      borderRadius: AppRadius.brMd,
      child: Container(
        width: 132,
        padding: AppSpacing.allMd,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: AppRadius.brMd,
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('$count',
                    style: AppTextStyles.headlineMd
                        .copyWith(color: AppColors.primary)),
                const Spacer(),
                if (onVerify != null)
                  Icon(Icons.visibility_outlined,
                      size: 15,
                      color: AppColors.primary.withValues(alpha: 0.7)),
              ],
            ),
            Text(label,
                style: AppTextStyles.bodySm
                    .copyWith(color: AppColors.textTertiary)),
          ],
        ),
      ),
    );
  }

  // ── Card de conclusão ───────────────────────────────────────────────────────

  Widget _completionCard(TrilhaChatController c) {
    return Padding(
      key: const ValueKey('done-card'),
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: AppCard(
        variant: AppCardVariant.gradient,
        child: c.finalizing
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const TypingDots(color: AppColors.onPrimary),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: Text('Montando seu resumo com a IA…',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMd
                            .copyWith(color: AppColors.onPrimary)),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                      widget.hubStatus?.level == HubLevel.building
                          ? Icons.trending_up_rounded
                          : Icons.celebration_rounded,
                      color: AppColors.onPrimary,
                      size: 36),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                        widget.hubStatus?.title ?? 'Perfil mais forte! 🎉',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.titleMd
                            .copyWith(color: AppColors.onPrimary)),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    // Honesto: o próximo ganho (força real) — não "está tudo forte".
                    widget.hubStatus?.message ??
                        (c.generatedSummary != null
                            ? 'A IA criou um resumo pro seu perfil:'
                            : 'Quanto mais completo, mais empresas conseguem te achar.'),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMd
                        .copyWith(color: AppColors.onPrimary),
                  ),
                  if (c.generatedSummary != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    // Com o hub honesto, o subtítulo virou o "próximo ganho" —
                    // então rotula o bloco do resumo pra não ficar solto.
                    if (widget.hubStatus != null) ...[
                      SizedBox(
                        width: double.infinity,
                        child: Text('Resumo que a IA montou:',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodySm.copyWith(
                                color: AppColors.onPrimary
                                    .withValues(alpha: 0.9))),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    Container(
                      width: double.infinity,
                      padding: AppSpacing.allMd,
                      decoration: BoxDecoration(
                        color: AppColors.onPrimary.withValues(alpha: 0.15),
                        borderRadius: AppRadius.brMd,
                      ),
                      child: Text(c.generatedSummary!,
                          style: AppTextStyles.bodySm
                              .copyWith(color: AppColors.onPrimary)),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  // ── Barra inferior ──────────────────────────────────────────────────────────

  Widget _bottomBar() {
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md,
          AppSpacing.sm + bottomSafe),
      child: Row(
        children: [
          // 📎 só no GATE: importar é ação de abertura. Depois, re-importar
          // reconstruiria a sessão e perderia o progresso (ver onCvUploaded).
          if (_c.phase == ChatPhase.gate) ...[
            _circleButton(
              icon: Icons.attach_file_rounded,
              filled: false,
              onTap: _import,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: AppRadius.brPill,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                      style: AppTextStyles.bodyMd
                          .copyWith(color: AppColors.textPrimary),
                      // Sem o fill/borda do tema global (que desenhava um
                      // "retângulo dentro" da pílula) — só o texto.
                      decoration: InputDecoration(
                        hintText: 'Escreva uma mensagem…',
                        hintStyle: AppTextStyles.bodyMd
                            .copyWith(color: AppColors.textTertiary),
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _circleButton(
            icon: Icons.send_rounded,
            filled: true,
            onTap: _sendText,
          ),
        ],
      ),
    );
  }

  Widget _circleButton(
      {required IconData icon,
      required bool filled,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: filled ? AppColors.primary : AppColors.surface,
          shape: BoxShape.circle,
          border: filled ? null : Border.all(color: AppColors.border),
        ),
        child: Icon(icon,
            size: 20,
            color: filled ? AppColors.onPrimary : AppColors.textTertiary),
      ),
    );
  }
}
