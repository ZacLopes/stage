// Card "o CV diz X × você tem Y" (widget de conflito de import de CV).
// Cada linha: ADIÇÃO (aceitar/ignorar) ou CONFLITO (usar do CV / manter o seu),
// com edição inline opcional. "Aplicar seleção" grava as aceitas + Desfazer.

import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/widgets.dart';
import '../../application/cv_conflict.dart';
import '../trilha_chat_controller.dart'
    show ImportConflictItem, ConflictChoice, AssistEditStatus;

class ImportConflictCard extends StatefulWidget {
  const ImportConflictCard({
    super.key,
    required this.item,
    required this.onToggle,
    required this.onEdit,
    required this.onApply,
    required this.onCancel,
    required this.onUndo,
    this.canUndo = false,
  });

  final ImportConflictItem item;
  final void Function(String rowId, bool accepted) onToggle;
  final void Function(String rowId, String value) onEdit;
  final VoidCallback onApply;
  final VoidCallback onCancel;
  final VoidCallback onUndo;

  /// Só mostra "Desfazer" quando há reversão real fiada (Gate 3.0I) — sem ela,
  /// nada de falso affordance.
  final bool canUndo;

  @override
  State<ImportConflictCard> createState() => _ImportConflictCardState();
}

class _ImportConflictCardState extends State<ImportConflictCard> {
  // Alinha com o texto das bolhas da IA (avatar 34 + gap).
  static const _margin = EdgeInsets.only(left: 34 + AppSpacing.sm);

  String? _editingRowId;
  final _editCtrl = TextEditingController();

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    switch (item.status) {
      case AssistEditStatus.cancelled:
        return Container(
          margin: _margin,
          child: Text('Beleza, deixei como estava.',
              style:
                  AppTextStyles.bodySm.copyWith(color: AppColors.textTertiary)),
        );
      case AssistEditStatus.undone:
        return Container(
          margin: _margin,
          child: Row(children: [
            const Icon(Icons.undo_rounded, size: 15, color: AppColors.textTertiary),
            const SizedBox(width: 6),
            Flexible(
                child: Text('Desfiz as mudanças do CV.',
                    style: AppTextStyles.bodySm
                        .copyWith(color: AppColors.textTertiary))),
          ]),
        );
      case AssistEditStatus.applied:
        return Container(
          margin: _margin,
          padding: AppSpacing.allBase,
          decoration: BoxDecoration(
            color: AppColors.successSoft,
            borderRadius: AppRadius.brLg,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle_rounded,
                size: 18, color: AppColors.success),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
                child: Text(_appliedMessage(item),
                    style: AppTextStyles.bodyMd)),
            // Só oferece Desfazer quando há reversão real fiada (senão seria um
            // botão que mente — o servidor não desfaz item-a-item).
            if (widget.canUndo)
              TextButton(
                  onPressed: item.applying ? null : widget.onUndo,
                  child: const Text('Desfazer')),
          ]),
        );
      case AssistEditStatus.pending:
        return _pending(item);
    }
  }

  Widget _pending(ImportConflictItem item) {
    final acceptedCount = item.choices.where((c) => c.accepted).length;
    return Container(
      margin: _margin,
      padding: AppSpacing.allBase,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Do seu CV', style: AppTextStyles.overline),
          const SizedBox(height: 2),
          Text('Escolha o que trazer pro seu perfil 👇',
              style: AppTextStyles.bodySm
                  .copyWith(color: AppColors.textTertiary)),
          // Falha dura na última tentativa (rollback global): nada foi aplicado
          // e o card seguiu pendente. Fala a verdade e convida a tentar de novo.
          if (item.outcome?.isHardFailure ?? false) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(children: [
              const Icon(Icons.error_outline_rounded,
                  size: 15, color: AppColors.error),
              const SizedBox(width: 6),
              Flexible(
                  child: Text('Não consegui aplicar agora. Tenta de novo.',
                      style: AppTextStyles.bodySm
                          .copyWith(color: AppColors.error))),
            ]),
          ],
          const SizedBox(height: AppSpacing.sm),
          for (final c in item.choices) _row(c),
          const SizedBox(height: AppSpacing.sm),
          PrimaryButton(
            label: acceptedCount == 0
                ? 'Nada selecionado'
                : 'Aplicar $acceptedCount ${acceptedCount == 1 ? "item" : "itens"}',
            isLoading: item.applying,
            onPressed:
                acceptedCount == 0 || item.applying ? null : widget.onApply,
          ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: TextButton(
                onPressed: widget.onCancel,
                child: Text('Agora não',
                    style: AppTextStyles.bodySm
                        .copyWith(color: AppColors.textTertiary))),
          ),
        ],
      ),
    );
  }

  Widget _row(ConflictChoice c) {
    final isConflict = c.row.kind == ConflictKind.conflict;
    final editable = _isEditable(c.row);
    final editing = _editingRowId == c.row.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Toggle aceitar.
              InkWell(
                onTap: () => widget.onToggle(c.row.id, !c.accepted),
                borderRadius: AppRadius.brSm,
                child: Icon(
                  c.accepted
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color:
                      c.accepted ? AppColors.primary : AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(c.row.label,
                              style: AppTextStyles.bodyMd
                                  .copyWith(fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 6),
                        _kindBadge(isConflict),
                      ],
                    ),
                    if (isConflict) ...[
                      const SizedBox(height: 2),
                      _valLine('CV', c.effectiveValue, AppColors.primary),
                      _valLine('Você', c.row.currentText, AppColors.textTertiary),
                    ] else if (c.effectiveValue != c.row.label) ...[
                      const SizedBox(height: 2),
                      Text(c.effectiveValue,
                          style: AppTextStyles.bodySm
                              .copyWith(color: AppColors.textSecondary)),
                    ],
                  ],
                ),
              ),
              if (editable && !editing)
                InkWell(
                  onTap: () {
                    setState(() {
                      _editingRowId = c.row.id;
                      _editCtrl.text = c.effectiveValue;
                    });
                  },
                  borderRadius: AppRadius.brSm,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.edit_outlined,
                        size: 16, color: AppColors.textTertiary),
                  ),
                ),
            ],
          ),
          if (editing)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _editCtrl,
                      autofocus: true,
                      style: AppTextStyles.bodyMd,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.check_rounded,
                        size: 20, color: AppColors.primary),
                    onPressed: () {
                      widget.onEdit(c.row.id, _editCtrl.text.trim());
                      setState(() => _editingRowId = null);
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Mensagem HONESTA do resultado: além do que entrou, diz o que foi mantido
  // (você já tinha editado) e o que não deu — nunca só um "aplicado" cego.
  String _appliedMessage(ImportConflictItem item) {
    final n = item.appliedCount;
    final base = n == 0
        ? 'Nada novo trazido'
        : 'Trouxe $n ${n == 1 ? "item" : "itens"} do seu CV';
    final o = item.outcome;
    if (o == null) return '$base ✓';
    final extras = <String>[
      if (o.staleCount > 0) '${o.staleCount} você já tinha',
      if (o.rejectedCount > 0) '${o.rejectedCount} não deu pra trazer',
    ];
    return extras.isEmpty ? '$base ✓' : '$base · ${extras.join(' · ')}';
  }

  Widget _valLine(String who, String val, Color color) {
    return Text('$who: $val',
        style: AppTextStyles.bodySm.copyWith(color: color));
  }

  Widget _kindBadge(bool isConflict) {
    final label = isConflict ? 'difere' : 'novo';
    final color = isConflict ? AppColors.warning : AppColors.success;
    final bg = isConflict ? AppColors.warningSoft : AppColors.successSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.brSm),
      child: Text(label,
          style: AppTextStyles.labelSm.copyWith(color: color)),
    );
  }

  // Edição de texto livre só faz sentido onde o apply usa `value`: escalares,
  // skill/interest, e conflito de cargo/curso (title/degree). ADIÇÃO de
  // experiência/formação usa o item CRU do CV (row.cvItem), não o `value` — o
  // edit abriria vazio e seria ignorado; idioma/cert/prêmio/projeto idem.
  bool _isEditable(ConflictRow r) {
    switch (r.section) {
      case ConflictSection.name:
      case ConflictSection.phone:
      case ConflictSection.city:
      case ConflictSection.summary:
      case ConflictSection.linkedin:
      case ConflictSection.website:
      case ConflictSection.skill:
      case ConflictSection.interest:
        return true;
      case ConflictSection.experience:
      case ConflictSection.education:
        return r.kind == ConflictKind.conflict;
      case ConflictSection.language:
      case ConflictSection.certification:
      case ConflictSection.award:
      case ConflictSection.project:
      case ConflictSection.coursework:
        return false;
    }
  }
}
