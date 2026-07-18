// Editor VISUAL de IDIOMAS no fio da conversa (assistente, Fase C): como o
// list_editor_card, mas cada item tem NÍVEL. Mostra os idiomas atuais em chips
// "Inglês · Avançado" com um seletor de nível (toque no chip) e ✕ pra tirar; um
// bloco pra adicionar dos idiomas canônicos que faltam; e "Salvar" que aplica o
// líquido (adicionados c/ nível, nível alterado, removidos) deixando um Desfazer.

import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart';
import '../../../profile/domain/entities/simple_lists.dart'
    show kLanguageLevelsAscending, languageLevelLabel;
import '../trilha_chat_controller.dart'
    show LangEntry, LanguagesEditorItem, AssistEditStatus;

/// Nível padrão de um idioma recém-adicionado (a pessoa ajusta no chip).
const String _kDefaultLevel = 'intermediate';

class LanguagesEditorCard extends StatefulWidget {
  const LanguagesEditorCard({
    super.key,
    required this.item,
    required this.onApply,
    required this.onCancel,
    required this.onUndo,
  });

  final LanguagesEditorItem item;

  /// Aplica o líquido: (adicionados, removidos[nomes], nível-alterado).
  final Future<void> Function(
      List<LangEntry> added, List<String> removed, List<LangEntry> changed) onApply;
  final VoidCallback onCancel;
  final VoidCallback onUndo;

  @override
  State<LanguagesEditorCard> createState() => _LanguagesEditorCardState();
}

class _LanguagesEditorCardState extends State<LanguagesEditorCard> {
  /// Nível atual escolhido por idioma (inicial + adicionados). name → nível.
  final Map<String, String?> _levels = {};
  final Set<String> _removed = {}; // nomes iniciais marcados pra tirar
  final List<String> _added = []; // idiomas novos
  bool _saving = false;

  static const _margin = EdgeInsets.only(left: 34 + AppSpacing.sm);

  @override
  void initState() {
    super.initState();
    for (final e in widget.item.initial) {
      _levels[e.name] = e.level;
    }
  }

  List<LangEntry> get _addedEntries =>
      [for (final n in _added) LangEntry(n, _levels[n] ?? _kDefaultLevel)];

  List<LangEntry> get _changedEntries => [
        for (final e in widget.item.initial)
          if (!_removed.contains(e.name) && _levels[e.name] != e.level)
            LangEntry(e.name, _levels[e.name])
      ];

  bool get _hasChanges =>
      _removed.isNotEmpty || _added.isNotEmpty || _changedEntries.isNotEmpty;

  bool get _editingLocked =>
      _saving ||
      widget.item.applying ||
      widget.item.undoing ||
      widget.item.hasUnconfirmedChanges;

  void _addLanguage(String name) {
    if (_editingLocked) return;
    if (_added.any((n) => n.toLowerCase() == name.toLowerCase())) return;
    setState(() {
      _added.add(name);
      _levels[name] = _kDefaultLevel;
    });
  }

  Future<void> _save() async {
    if (!_hasChanges ||
        _saving ||
        widget.item.applying ||
        widget.item.undoing) {
      return;
    }
    setState(() => _saving = true);
    await widget.onApply(_addedEntries, _removed.toList(), _changedEntries);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.item.status) {
      case AssistEditStatus.cancelled:
        return _muted('Beleza, não mexi nos seus idiomas.');
      case AssistEditStatus.undone:
        return _muted('Desfeito — seus idiomas voltaram como estavam.');
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

  // ── APLICADO: resumo + Desfazer ─────────────────────────────────────────────
  Widget _appliedCard() {
    final added = widget.item.addedApplied;
    final changed = widget.item.changedApplied;
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
            Text('Idiomas atualizados',
                style: AppTextStyles.overline.copyWith(color: AppColors.success)),
          ]),
          if (added.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _summaryLine('Adicionei',
                [for (final e in added) _entryLabel(e)], AppColors.primary),
          ],
          if (changed.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _summaryLine('Ajustei o nível',
                [for (final e in changed) _entryLabel(e)], AppColors.primary),
          ],
          if (removed.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _summaryLine('Tirei', removed, AppColors.textTertiary),
          ],
          if (widget.item.resultMessage.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(widget.item.resultMessage,
                style: AppTextStyles.bodySm.copyWith(
                  color: widget.item.undoAvailable
                      ? AppColors.error
                      : AppColors.textSecondary,
                )),
          ],
          if (widget.item.undoAvailable) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: _pill(
                  icon: Icons.undo_rounded,
                  label: widget.item.undoing ? 'Desfazendo…' : 'Desfazer',
                  onTap: widget.item.undoing ? null : widget.onUndo),
            ),
          ],
        ],
      ),
    );
  }

  String _entryLabel(LangEntry e) {
    final lv = languageLevelLabel(e.level);
    return lv.isEmpty ? e.name : '${e.name} · $lv';
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

  // ── PENDENTE: editor interativo ─────────────────────────────────────────────
  Widget _editorCard() {
    final canAdd = widget.item.options
        .where((o) => !_added.any((a) => a.toLowerCase() == o.toLowerCase()))
        .toList();
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
            const Icon(Icons.translate_rounded, size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
            Text('Seus idiomas',
                style: AppTextStyles.overline.copyWith(color: AppColors.primary)),
          ]),
          const SizedBox(height: AppSpacing.xs),
          Text('Toca no idioma pra mudar o nível, ou no ✕ pra tirar.',
              style: AppTextStyles.bodySm.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in widget.item.initial)
                _langChip(e.name,
                    added: false, removed: _removed.contains(e.name)),
              for (final n in _added) _langChip(n, added: true, removed: false),
            ],
          ),
          if (canAdd.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Adicionar idioma',
                style: AppTextStyles.labelSm
                    .copyWith(color: AppColors.textTertiary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final o in canAdd) _addChip(o)],
            ),
          ],
          if (widget.item.resultMessage.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(widget.item.resultMessage,
                style: AppTextStyles.bodySm.copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _primaryButton(
                  label: (_saving || widget.item.applying)
                      ? 'Salvando…'
                      : widget.item.hasUnconfirmedChanges
                          ? 'Tentar novamente'
                          : 'Salvar alterações',
                  enabled: _hasChanges &&
                      !_saving &&
                      !widget.item.applying &&
                      !widget.item.undoing,
                  onTap: _save,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _pill(
                icon: widget.item.hasUnconfirmedChanges &&
                        widget.item.observedAfter != null
                    ? Icons.undo_rounded
                    : widget.item.hasUnconfirmedChanges
                        ? Icons.info_outline_rounded
                        : null,
                label: widget.item.undoing
                    ? 'Desfazendo…'
                    : widget.item.hasUnconfirmedChanges &&
                            widget.item.observedAfter != null
                        ? 'Desfazer salvos'
                        : widget.item.hasUnconfirmedChanges
                            ? 'Sem confirmação'
                            : 'Cancelar',
                onTap: widget.item.applying || widget.item.undoing
                    ? null
                    : widget.item.hasUnconfirmedChanges
                        ? widget.item.observedAfter != null
                            ? widget.onUndo
                            : null
                        : widget.onCancel,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _langChip(String name, {required bool added, required bool removed}) {
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
    final lv = languageLevelLabel(_levels[name]);
    final labelText = removed
        ? name
        : (lv.isEmpty ? '$name · definir nível' : '$name · $lv');

    final Widget labelPart = removed
        ? Text(name,
            style: AppTextStyles.labelMd.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.lineThrough))
        : PopupMenuButton<String>(
            tooltip: 'Nível',
            enabled: !_editingLocked,
            padding: EdgeInsets.zero,
            onSelected: (lvId) {
              if (_editingLocked) return;
              setState(() => _levels[name] = lvId);
            },
            itemBuilder: (_) => [
              for (final id in kLanguageLevelsAscending)
                PopupMenuItem<String>(
                    value: id, child: Text(languageLevelLabel(id))),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(labelText,
                    style: AppTextStyles.labelMd
                        .copyWith(color: fg, fontWeight: FontWeight.w600)),
                Icon(Icons.arrow_drop_down_rounded, size: 18, color: fg),
              ],
            ),
          );

    return Container(
      padding: EdgeInsets.only(left: 12, right: removed ? 7 : 3, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.brPill,
        border: Border.all(color: border, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          labelPart,
          const SizedBox(width: 3),
          GestureDetector(
            onTap: _editingLocked ? null : () => setState(() {
              if (added) {
                _added.remove(name);
                _levels.remove(name);
              } else if (!_removed.remove(name)) {
                _removed.add(name);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(removed ? Icons.refresh_rounded : Icons.close_rounded,
                  size: 15, color: fg),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addChip(String label) => GestureDetector(
        onTap: () => _addLanguage(label),
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

  Widget _primaryButton(
      {required String label, required bool enabled, required VoidCallback onTap}) {
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

  Widget _pill({IconData? icon, required String label, VoidCallback? onTap}) {
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
