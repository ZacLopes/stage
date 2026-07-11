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
import 'widgets/languages_editor_card.dart';
import 'widgets/list_editor_card.dart';
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

  /// FocusNode ESTÁVEL da barra de digitar. Sem ele, o TextField usa um node
  /// interno que, nesta subárvore muito re-buildada (watch do VM + 2
  /// AnimatedBuilder + reflow do teclado), pode ficar destacado no frame do
  /// toque — aí o guard global de "tocar fora fecha o teclado" (main.dart) lê
  /// "nenhum campo focado" e FECHA o teclado ao tocar na própria barra (ex.:
  /// pra colar). Um node próprio do State persiste e mantém o foco estável.
  final FocusNode _inputFocus = FocusNode();

  /// Âncora do card em edição — pra rolar ATÉ ele (e não pro fim do fio) quando
  /// o usuário toca no lápis de uma resposta lá em cima.
  final GlobalKey _editAnchorKey = GlobalKey();

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
    _inputFocus.dispose();
    super.dispose();
  }

  void _onTick() => _syncScroll();

  @override
  void didChangeMetrics() {
    if (mounted) _syncScroll();
  }

  // Editando um card lá em cima? Traz ELE pra vista (perto do topo) e o mantém
  // visível quando o teclado sobe — em vez de colar no fim do fio. Fora de
  // edição: acompanha sempre a última bolha.
  void _syncScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_c.isEditing) {
        final ctx = _editAnchorKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            // Encosta o card perto do topo, deixando a pergunta logo acima à
            // mostra e o widget inteiro acima do teclado.
            alignment: 0.15,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
        return;
      }
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
      } else if (item is UserMsgItem) {
        children.add(Padding(
          key: ValueKey('user-$i'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _userBubble(item.text),
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
      } else if (item is AssistEditItem) {
        children.add(Padding(
          key: ValueKey('edit-item-${item.id}'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _assistEditCard(item),
        ));
      } else if (item is AssistExtractItem) {
        children.add(Padding(
          key: ValueKey('extract-${item.id}'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _assistExtractCard(item),
        ));
      } else if (item is ListEditorItem) {
        children.add(Padding(
          key: ValueKey('list-editor-${item.id}'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: ListEditorCard(
            item: item,
            onApply: (added, removed) =>
                _c.applyListEditor(item.id, added: added, removed: removed),
            onCancel: () => _c.cancelListEditor(item.id),
            onUndo: () => _c.undoListEditor(item.id),
          ),
        ));
      } else if (item is LanguagesEditorItem) {
        children.add(Padding(
          key: ValueKey('lang-editor-${item.id}'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: LanguagesEditorCard(
            item: item,
            onApply: (added, removed, changed) => _c.applyLanguagesEditor(
                item.id, added: added, removed: removed, changed: changed),
            onCancel: () => _c.cancelLanguagesEditor(item.id),
            onUndo: () => _c.undoLanguagesEditor(item.id),
          ),
        ));
      } else if (item is JobsCardItem) {
        children.add(Padding(
          key: ValueKey('jobs-$i'),
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _jobsCard(item),
        ));
      } else if (item is AnsweredItem) {
        if (c.editingIndex == i && c.activeStep != null) {
          children.add(Padding(
            key: ValueKey('edit-$i'),
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _EditFrame(
              key: _editAnchorKey,
              onCancel: c.cancelEdit,
              // initialAnswer → o widget reabre com o que já estava escrito.
              child: InlineStepInput(
                step: c.activeStep!,
                initialAnswer: item.exchange.answer,
                onSubmit: c.submit,
              ),
            ),
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

  Widget _userBubble(String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base, vertical: 11),
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(text,
            style: AppTextStyles.bodyMd.copyWith(color: AppColors.onPrimary)),
      ),
    );
  }

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

  // ── Card de vagas reais (Grande: consulta ao feed) ────────────────────────

  Widget _jobsCard(JobsCardItem item) {
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
          Text('Vagas pra você', style: AppTextStyles.overline),
          const SizedBox(height: 2),
          Text(
            item.hasResume
                ? 'As que mais combinam com seu perfil 👇'
                : 'Preenche seu currículo pra eu calcular o match 👇',
            style:
                AppTextStyles.bodySm.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final j in item.jobs) _jobRow(j),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            label: 'Ver na aba Vagas',
            icon: Icons.work_outline_rounded,
            onPressed: () {
              // ignore: unawaited_futures
              _c.openTabFromCard('vagas');
            },
          ),
        ],
      ),
    );
  }

  Widget _jobRow(AssistJobRow j) {
    final sub = [j.company, if (j.area.isNotEmpty) j.area].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(j.title,
                    style: AppTextStyles.bodyMd
                        .copyWith(fontWeight: FontWeight.w600)),
                if (sub.isNotEmpty)
                  Text(sub,
                      style: AppTextStyles.bodySm
                          .copyWith(color: AppColors.textTertiary)),
              ],
            ),
          ),
          if (j.hasScore) ...[
            const SizedBox(width: AppSpacing.sm),
            _matchBadge(j.score),
          ],
        ],
      ),
    );
  }

  Widget _matchBadge(int score) {
    // Baldes iguais aos do detalhe da vaga: ≥70 forte, ≥40 médio, senão fraco.
    final strong = score >= 70;
    final mid = score >= 40;
    final color = strong
        ? AppColors.success
        : (mid ? AppColors.primary : AppColors.textTertiary);
    final bg = strong
        ? AppColors.successSoft
        : (mid ? AppColors.primarySoft : AppColors.surfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.brSm),
      child: Text('$score%',
          style: AppTextStyles.labelSm.copyWith(color: color)),
    );
  }

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

  // ── Card de alteração do assistente (Fase B): confirmar → aplicado → desfazer

  Widget _assistEditCard(AssistEditItem item) {
    // Alinha com o texto das bolhas da IA (avatar 34 + gap).
    const margin = EdgeInsets.only(left: 34 + AppSpacing.sm);
    final isRemove = item.op == AssistEditOp.remove;
    final isAdd = item.op == AssistEditOp.add;

    if (item.status == AssistEditStatus.cancelled) {
      return Container(
        margin: margin,
        child: Text('Cancelado.',
            style: AppTextStyles.bodySm.copyWith(color: AppColors.textTertiary)),
      );
    }
    if (item.status == AssistEditStatus.undone) {
      final txt = switch (item.op) {
        AssistEditOp.update =>
          '${item.fieldLabel} voltou pra ${item.beforeText.isEmpty ? '—' : item.beforeText}.',
        AssistEditOp.add => '${item.afterText} removido de novo.',
        AssistEditOp.remove => '${item.afterText} voltou pra ${item.fieldLabel}.',
        AssistEditOp.bullet => 'Bullet (${item.fieldLabel}) voltou ao original.',
      };
      return Container(
        margin: margin,
        child: Row(children: [
          const Icon(Icons.undo_rounded, size: 15, color: AppColors.textTertiary),
          const SizedBox(width: 6),
          Flexible(
              child: Text(txt,
                  style: AppTextStyles.bodySm
                      .copyWith(color: AppColors.textTertiary))),
        ]),
      );
    }

    final applied = item.status == AssistEditStatus.applied;
    // Cor de acento: destrutivo (remove) usa warning; resto usa primary.
    final accent = isRemove ? AppColors.warning : AppColors.primary;
    final headerTitle = applied
        ? (isRemove ? 'Removi' : isAdd ? 'Adicionei' : 'Alterei no seu perfil')
        : (isRemove ? 'Confirmar remoção' : 'Confirmar alteração');
    final headerIcon = applied
        ? Icons.check_circle_rounded
        : (isRemove ? Icons.delete_outline_rounded : Icons.edit_rounded);

    return Container(
      margin: margin,
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: applied
            ? AppColors.surface
            : accent.withValues(alpha: isRemove ? 0.10 : 0.14),
        borderRadius: AppRadius.brLg,
        border: Border.all(
            color: applied ? AppColors.border : accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(headerIcon,
                  size: 15, color: applied ? AppColors.success : accent),
              const SizedBox(width: 6),
              Text(headerTitle,
                  style: AppTextStyles.overline
                      .copyWith(color: applied ? AppColors.success : accent)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            switch (item.op) {
              AssistEditOp.bullet => 'Bullet · ${item.fieldLabel}',
              AssistEditOp.remove => 'Remover de ${item.fieldLabel}',
              AssistEditOp.add => 'Adicionar em ${item.fieldLabel}',
              AssistEditOp.update => item.fieldLabel,
            },
            style: AppTextStyles.labelSm.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: 4),
          // Texto longo (resumo/bullet) → antes/depois EMPILHADO; curto → inline.
          if ((item.op == AssistEditOp.update || item.op == AssistEditOp.bullet) &&
              (item.field == 'summary' ||
                  item.op == AssistEditOp.bullet ||
                  item.afterText.length > 60 ||
                  item.beforeText.length > 60)) ...[
            if (item.beforeText.isNotEmpty && item.beforeText != '—') ...[
              _summaryBlock('Antes', item.beforeText, muted: true),
              const SizedBox(height: AppSpacing.sm),
            ],
            _summaryBlock('Depois', item.afterText, muted: false),
          ] else
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                if (item.op == AssistEditOp.update &&
                    item.beforeText.isNotEmpty &&
                    item.beforeText != '—') ...[
                  Text(item.beforeText,
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.textTertiary,
                        decoration: TextDecoration.lineThrough,
                      )),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 15, color: AppColors.textTertiary),
                ],
                Text(item.afterText,
                    style: AppTextStyles.titleSm.copyWith(
                      color: AppColors.textPrimary,
                      decoration: (applied && isRemove)
                          ? TextDecoration.lineThrough
                          : null,
                    )),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          if (applied)
            Align(
              alignment: Alignment.centerLeft,
              child: _editPill(
                icon: Icons.undo_rounded,
                label: 'Desfazer',
                onTap: () => _c.undoAssistEdit(item.id),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _confirmButton(
                    label: isRemove ? 'Remover' : 'Aplicar',
                    color: isRemove ? AppColors.error : AppColors.primary,
                    onTap: () => _c.confirmAssistEdit(item.id),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _editPill(
                  label: 'Cancelar',
                  onTap: () => _c.cancelAssistEdit(item.id),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // Card "Peguei isto 👇": vários campos simples extraídos de um textão colado,
  // confirmados de uma vez; espelha o ImportSummaryItem (lista + aplicar/desfazer).
  Widget _assistExtractCard(AssistExtractItem item) {
    const margin = EdgeInsets.only(left: 34 + AppSpacing.sm);

    if (item.status == AssistEditStatus.cancelled) {
      return Container(
        margin: margin,
        child: Text('Cancelado.',
            style: AppTextStyles.bodySm.copyWith(color: AppColors.textTertiary)),
      );
    }
    if (item.status == AssistEditStatus.undone) {
      return Container(
        margin: margin,
        child: Row(children: [
          const Icon(Icons.undo_rounded, size: 15, color: AppColors.textTertiary),
          const SizedBox(width: 6),
          Flexible(
              child: Text('Desfeito — não adicionei nada.',
                  style: AppTextStyles.bodySm
                      .copyWith(color: AppColors.textTertiary))),
        ]),
      );
    }

    final applied = item.status == AssistEditStatus.applied;
    final accent = AppColors.primary;

    return Container(
      margin: margin,
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: applied ? AppColors.surface : accent.withValues(alpha: 0.14),
        borderRadius: AppRadius.brLg,
        border: Border.all(
            color: applied ? AppColors.border : accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(applied ? Icons.check_circle_rounded : Icons.auto_awesome_rounded,
                  size: 15, color: applied ? AppColors.success : accent),
              const SizedBox(width: 6),
              Text(applied ? 'Adicionei ao seu currículo' : 'Peguei isto 👇',
                  style: AppTextStyles.overline
                      .copyWith(color: applied ? AppColors.success : accent)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final e in item.entries) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_extractIcon(e.kind),
                    size: 15, color: AppColors.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(e.label,
                      style: AppTextStyles.bodyMd
                          .copyWith(color: AppColors.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: AppSpacing.xs),
          if (applied)
            Align(
              alignment: Alignment.centerLeft,
              child: _editPill(
                icon: Icons.undo_rounded,
                label: 'Desfazer',
                onTap: () => _c.undoExtract(item.id),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _confirmButton(
                    label: 'Aplicar tudo',
                    color: AppColors.primary,
                    onTap: () => _c.confirmExtract(item.id),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _editPill(
                  label: 'Cancelar',
                  onTap: () => _c.cancelExtract(item.id),
                ),
              ],
            ),
        ],
      ),
    );
  }

  IconData _extractIcon(String kind) {
    switch (kind) {
      case 'skill':
        return Icons.bolt_rounded;
      case 'language':
        return Icons.translate_rounded;
      case 'desired_position':
        return Icons.work_outline_rounded;
      default:
        return Icons.check_rounded;
    }
  }

  Widget _summaryBlock(String label, String text, {required bool muted}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTextStyles.overline.copyWith(
                color: muted ? AppColors.textTertiary : AppColors.primary)),
        const SizedBox(height: 2),
        Container(
          width: double.infinity,
          padding: AppSpacing.allSm,
          decoration: BoxDecoration(
            color: muted ? AppColors.surfaceVariant : AppColors.surface,
            borderRadius: AppRadius.brMd,
            border: Border.all(
                color: muted
                    ? AppColors.border
                    : AppColors.primary.withValues(alpha: 0.25)),
          ),
          child: Text(text,
              style: AppTextStyles.bodySm.copyWith(
                  color: muted ? AppColors.textTertiary : AppColors.textPrimary,
                  decoration:
                      muted ? TextDecoration.lineThrough : null)),
        ),
      ],
    );
  }

  Widget _confirmButton(
      {required String label,
      required Color color,
      required VoidCallback onTap}) {
    return Material(
      color: color,
      borderRadius: AppRadius.brMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brMd,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          child: Text(label,
              style:
                  AppTextStyles.labelLg.copyWith(color: AppColors.onPrimary)),
        ),
      ),
    );
  }

  Widget _editPill({IconData? icon, required String label, required VoidCallback onTap}) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.brPill,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brPill,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: AppRadius.brPill,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 5),
              ],
              Text(label,
                  style: AppTextStyles.labelMd
                      .copyWith(color: AppColors.textSecondary)),
            ],
          ),
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
                      focusNode: _inputFocus,
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

/// Moldura do modo EDIÇÃO: um realce azul-claro em volta do card sendo
/// reeditado + um "Cancelar" que sai da edição SEM mexer no que já estava
/// gravado. Uniforme pra qualquer widget (texto, chips, roda, slider…), então
/// todo passo editável ganha a saída "não quero mais editar" de graça.
class _EditFrame extends StatelessWidget {
  const _EditFrame({super.key, required this.child, required this.onCancel});

  final Widget child;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.allSm,
      decoration: BoxDecoration(
        color: AppColors.primarySoft.withValues(alpha: 0.5),
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs, 2, AppSpacing.xs, AppSpacing.sm),
            child: Row(
              children: [
                const Icon(Icons.edit_rounded,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Text('Editando',
                    style: AppTextStyles.labelSm.copyWith(
                        color: AppColors.primary, fontWeight: FontWeight.w700)),
                const Spacer(),
                // "Cancelar" = sair da edição e manter a resposta anterior.
                InkWell(
                  onTap: onCancel,
                  borderRadius: AppRadius.brPill,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.close_rounded,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('Cancelar',
                            style: AppTextStyles.labelSm.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}
