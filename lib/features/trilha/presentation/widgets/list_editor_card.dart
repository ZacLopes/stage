// Editor VISUAL de lista simples no fio da conversa (assistente, Fase C): serve
// SKILLS e INTERESSES (o `kind`/`title` vêm do ListEditorItem). Mostra os itens
// atuais em chips com ✕ pra tirar, um campo + sugestões pra adicionar, e um
// "Salvar" que aplica o líquido (adds + removes) deixando um Desfazer. O estado
// de edição é local; ao salvar, o controller aplica e o item vira `applied`
// (resumo + Desfazer). Idiomas têm nível → editor próprio (languages_editor_card).

import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart';
import '../trilha_chat_controller.dart' show ListEditorItem, AssistEditStatus;

class ListEditorCard extends StatefulWidget {
  const ListEditorCard({
    super.key,
    required this.item,
    required this.onApply,
    required this.onCancel,
    required this.onUndo,
  });

  final ListEditorItem item;

  /// Aplica o líquido: (novas, removidas). O controller grava e marca applied.
  final Future<void> Function(List<String> added, List<String> removed) onApply;
  final VoidCallback onCancel;
  final VoidCallback onUndo;

  @override
  State<ListEditorCard> createState() => _ListEditorCardState();
}

class _ListEditorCardState extends State<ListEditorCard> {
  final Set<String> _removed = {}; // skills iniciais marcadas pra tirar
  final List<String> _added = []; // novas
  final TextEditingController _addCtrl = TextEditingController();
  bool _saving = false;

  static const _margin = EdgeInsets.only(left: 34 + AppSpacing.sm);

  bool get _hasChanges => _removed.isNotEmpty || _added.isNotEmpty;

  String get _noun => widget.item.kind == 'skill' ? 'skills' : 'interesses';
  String get _singular =>
      widget.item.kind == 'skill' ? 'habilidade' : 'interesse';

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  void _toggleRemove(String s) {
    setState(() {
      if (!_removed.remove(s)) _removed.add(s);
    });
  }

  void _addSkill(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return;
    final lower = s.toLowerCase();
    final alreadyThere = widget.item.initial
            .any((x) => x.toLowerCase() == lower && !_removed.contains(x)) ||
        _added.any((x) => x.toLowerCase() == lower);
    if (alreadyThere) {
      _addCtrl.clear();
      return;
    }
    setState(() {
      _added.add(s);
      _addCtrl.clear();
    });
  }

  Future<void> _save() async {
    if (!_hasChanges || _saving) return;
    setState(() => _saving = true);
    await widget.onApply(List.of(_added), _removed.toList());
    // O controller marca o item applied → o build passa a mostrar o resumo.
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.item.status) {
      case AssistEditStatus.cancelled:
        return _muted('Beleza, não mexi nos seus $_noun.');
      case AssistEditStatus.undone:
        return _muted('Desfeito — seus $_noun voltaram como estavam.');
      case AssistEditStatus.applied:
        return _appliedCard();
      case AssistEditStatus.pending:
        return _editorCard();
    }
  }

  Widget _muted(String text) => Container(
        margin: _margin,
        child: Row(children: [
          const Icon(Icons.check_rounded, size: 15, color: AppColors.textTertiary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                style: AppTextStyles.bodySm
                    .copyWith(color: AppColors.textTertiary)),
          ),
        ]),
      );

  // ── Estado APLICADO: resumo + Desfazer ──────────────────────────────────────
  Widget _appliedCard() {
    final added = widget.item.addedApplied;
    final removed = widget.item.removedApplied;
    return Container(
      margin: _margin,
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.check_circle_rounded,
                size: 15, color: AppColors.success),
            const SizedBox(width: 6),
            Text(
                widget.item.kind == 'skill'
                    ? 'Skills atualizadas'
                    : 'Interesses atualizados',
                style: AppTextStyles.overline.copyWith(color: AppColors.success)),
          ]),
          if (added.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _summaryLine('Adicionei', added, AppColors.primary),
          ],
          if (removed.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _summaryLine('Tirei', removed, AppColors.textTertiary),
          ],
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: _pill(
              icon: Icons.undo_rounded,
              label: 'Desfazer',
              onTap: widget.onUndo,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, List<String> items, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTextStyles.labelSm.copyWith(color: AppColors.textTertiary)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final s in items) _staticChip(s, color)],
        ),
      ],
    );
  }

  Widget _staticChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: AppRadius.brPill,
        ),
        child: Text(label,
            style: AppTextStyles.labelMd
                .copyWith(color: color, fontWeight: FontWeight.w600)),
      );

  // ── Estado PENDENTE: editor interativo ──────────────────────────────────────
  Widget _editorCard() {
    final suggestions = widget.item.suggestions.where((s) {
      final lower = s.toLowerCase();
      final inCurrent = widget.item.initial
          .any((x) => x.toLowerCase() == lower && !_removed.contains(x));
      final inAdded = _added.any((x) => x.toLowerCase() == lower);
      return !inCurrent && !inAdded;
    }).toList();

    return Container(
      margin: _margin,
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.tune_rounded, size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(widget.item.title,
                style: AppTextStyles.overline.copyWith(color: AppColors.primary)),
          ]),
          const SizedBox(height: AppSpacing.xs),
          Text('Toca no ✕ pra tirar, ou adiciona novas embaixo.',
              style:
                  AppTextStyles.bodySm.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in widget.item.initial)
                _editableChip(
                  label: s,
                  removed: _removed.contains(s),
                  onTap: () => _toggleRemove(s),
                ),
              for (final s in _added)
                _editableChip(
                  label: s,
                  added: true,
                  onTap: () => setState(() => _added.remove(s)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _addField(),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Sugestões',
                style: AppTextStyles.labelSm
                    .copyWith(color: AppColors.textTertiary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in suggestions) _suggestionChip(s),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _primaryButton(
                  label: _saving ? 'Salvando…' : 'Salvar alterações',
                  enabled: _hasChanges && !_saving,
                  onTap: _save,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _pill(label: 'Cancelar', onTap: widget.onCancel),
            ],
          ),
        ],
      ),
    );
  }

  /// Chip de skill editável. `removed` = marcada pra tirar (riscada, ✕→↺);
  /// `added` = nova (tinta da marca, ✕ remove da lista de novas).
  Widget _editableChip({
    required String label,
    required VoidCallback onTap,
    bool removed = false,
    bool added = false,
  }) {
    final Color bg;
    final Color fg;
    final Color border;
    if (removed) {
      bg = AppColors.surfaceVariant;
      fg = AppColors.textTertiary;
      border = AppColors.border;
    } else if (added) {
      bg = AppColors.primary.withValues(alpha: 0.12);
      fg = AppColors.primary;
      border = AppColors.primary.withValues(alpha: 0.35);
    } else {
      bg = AppColors.surface;
      fg = AppColors.textPrimary;
      border = AppColors.border;
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 7, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadius.brPill,
          border: Border.all(color: border, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTextStyles.labelMd.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
                decoration: removed ? TextDecoration.lineThrough : null,
              ),
            ),
            const SizedBox(width: 5),
            Icon(removed ? Icons.refresh_rounded : Icons.close_rounded,
                size: 15, color: fg),
          ],
        ),
      ),
    );
  }

  Widget _suggestionChip(String label) => GestureDetector(
        onTap: () => _addSkill(label),
        child: Container(
          padding: const EdgeInsets.only(left: 7, right: 12, top: 6, bottom: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.brPill,
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.30), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, size: 15, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(label,
                  style: AppTextStyles.labelMd.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  Widget _addField() {
    return Container(
      padding: const EdgeInsets.only(left: AppSpacing.base, right: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brPill,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _addCtrl,
              textInputAction: TextInputAction.done,
              onSubmitted: _addSkill,
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Adicionar $_singular…',
                hintStyle: AppTextStyles.bodyMd
                    .copyWith(color: AppColors.textTertiary),
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _addSkill(_addCtrl.text),
              child: const Padding(
                padding: EdgeInsets.all(7),
                child: Icon(Icons.add_rounded, size: 20, color: AppColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton(
      {required String label,
      required bool enabled,
      required VoidCallback onTap}) {
    return Material(
      color: enabled ? AppColors.primary : AppColors.primary.withValues(alpha: 0.4),
      borderRadius: AppRadius.brMd,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: AppRadius.brMd,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          child: Text(label,
              style: AppTextStyles.labelLg.copyWith(color: AppColors.onPrimary)),
        ),
      ),
    );
  }

  Widget _pill({IconData? icon, required String label, required VoidCallback onTap}) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.brPill,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brPill,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base, vertical: 12),
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
}
