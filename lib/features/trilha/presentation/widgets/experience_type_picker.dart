// Seletor de TIPOS de experiência (abertura da seção Experiência da trilha).
//
// Tiles ricos (ícone + rótulo + subtítulo) em MULTISSELEÇÃO com CONTADOR: tocar
// no tile soma +1 (dá pra ter 2 estágios), o "−" tira um. "Outro" é só mais um
// tile (o nome do tipo é perguntado depois, no fluxo do item). "Ainda não tenho"
// é a saída honesta (submete vazio). Ao confirmar, emite a lista ORDENADA de
// kinds escolhidos (repetição = contagem). Design system Stage; sem lógica de
// fluxo (só coleta e devolve o StepAnswer) → serve às duas superfícies da trilha.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../../../core/theme/theme.dart';
import '../../domain/conversation_step.dart';

class ExperienceTypePicker extends StatefulWidget {
  const ExperienceTypePicker({
    super.key,
    required this.stepId,
    required this.input,
    required this.onSubmit,
    this.enabled = true,
    this.initialAnswer,
  });

  final String stepId;
  final ExperienceTypeInput input;
  final ValueChanged<StepAnswer> onSubmit;
  final bool enabled;

  /// Edição: reabre com os tipos já escolhidos (lista de kinds, repetição = nº).
  final StepAnswer? initialAnswer;

  @override
  State<ExperienceTypePicker> createState() => _ExperienceTypePickerState();
}

class _ExperienceTypePickerState extends State<ExperienceTypePicker> {
  /// Seleção ORDENADA, com repetição = contagem (kind por ocorrência).
  final List<String> _selected = [];

  @override
  void initState() {
    super.initState();
    final init = widget.initialAnswer?.value;
    if (init is List) _selected.addAll(init.map((e) => e.toString()));
  }

  int _countOf(String id) => _selected.where((s) => s == id).length;

  void _add(String id) {
    if (!widget.enabled) return;
    HapticFeedback.lightImpact();
    setState(() => _selected.add(id));
  }

  void _removeOne(String id) {
    if (!widget.enabled) return;
    final i = _selected.lastIndexOf(id);
    if (i < 0) return;
    HapticFeedback.selectionClick();
    setState(() => _selected.removeAt(i));
  }

  void _confirm() {
    widget.onSubmit(StepAnswer(
      stepId: widget.stepId,
      value: List<String>.from(_selected),
      displayText: _summaryText(),
    ));
  }

  void _skip() {
    if (!widget.enabled) return;
    widget.onSubmit(StepAnswer(
      stepId: widget.stepId,
      value: const <String>[],
      displayText: widget.input.skipLabel,
    ));
  }

  String _labelFor(String id) {
    for (final t in widget.input.types) {
      if (t.id == id) return t.label;
    }
    return id;
  }

  String _summaryText() {
    final seen = <String>{};
    final parts = <String>[];
    for (final s in _selected) {
      if (seen.contains(s)) continue;
      seen.add(s);
      final n = _countOf(s);
      parts.add(n > 1 ? '${_labelFor(s)} ×$n' : _labelFor(s));
    }
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final total = _selected.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.input.types.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _TypeTile(
            option: widget.input.types[i],
            count: _countOf(widget.input.types[i].id),
            enabled: widget.enabled,
            onAdd: () => _add(widget.input.types[i].id),
            onRemoveOne: () => _removeOne(widget.input.types[i].id),
          ),
        ],
        const SizedBox(height: AppSpacing.base),
        _Cta(
          label: total == 0 ? 'Escolha ao menos uma' : 'Continuar ($total)',
          onTap: (widget.enabled && total > 0) ? _confirm : null,
        ),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: TextButton(
            onPressed: widget.enabled ? _skip : null,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(widget.input.skipLabel,
                style: AppTextStyles.labelMd
                    .copyWith(color: AppColors.textTertiary)),
          ),
        ),
      ],
    );
  }
}

// ── Tile de um tipo ─────────────────────────────────────────────────────────

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.option,
    required this.count,
    required this.enabled,
    required this.onAdd,
    required this.onRemoveOne,
  });

  final ExperienceTypeOption option;
  final int count;
  final bool enabled;
  final VoidCallback onAdd;
  final VoidCallback onRemoveOne;

  @override
  Widget build(BuildContext context) {
    final selected = count > 0;
    return GestureDetector(
      onTap: enabled ? onAdd : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primarySoft.withValues(alpha: 0.5)
              : AppColors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.primarySoft,
                borderRadius: AppRadius.brMd,
              ),
              child: Icon(_iconFor(option.icon),
                  size: 21,
                  color: selected ? AppColors.onPrimary : AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(option.label,
                      style: AppTextStyles.titleSm
                          .copyWith(color: AppColors.textPrimary)),
                  if (option.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(option.subtitle,
                        style: AppTextStyles.bodySm
                            .copyWith(color: AppColors.textTertiary)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (selected)
              _CountStepper(
                count: count,
                enabled: enabled,
                onMinus: onRemoveOne,
                onPlus: onAdd,
              )
            else
              Icon(Icons.add_circle_outline_rounded,
                  size: 24,
                  color: enabled ? AppColors.primary : AppColors.textDisabled),
          ],
        ),
      ),
    );
  }
}

/// Contador − N + (aparece no tile já escolhido).
class _CountStepper extends StatelessWidget {
  const _CountStepper({
    required this.count,
    required this.enabled,
    required this.onMinus,
    required this.onPlus,
  });
  final int count;
  final bool enabled;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: AppRadius.brPill,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepBtn(Icons.remove_rounded, enabled ? onMinus : null),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('$count',
                style: AppTextStyles.labelMd.copyWith(
                    color: AppColors.onPrimary, fontWeight: FontWeight.w700)),
          ),
          _stepBtn(Icons.add_rounded, enabled ? onPlus : null),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 18, color: AppColors.onPrimary),
        ),
      );
}

class _Cta extends StatelessWidget {
  const _Cta({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color:
            on ? AppColors.primary : AppColors.primary.withValues(alpha: 0.4),
        borderRadius: AppRadius.brMd,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.brMd,
          child: Container(
            height: 46,
            alignment: Alignment.center,
            child: Text(label,
                style: AppTextStyles.labelLg
                    .copyWith(color: AppColors.onPrimary)),
          ),
        ),
      ),
    );
  }
}

// Ícones: mantém o domínio livre de Flutter (recebe nome, resolve aqui).
IconData _iconFor(String name) {
  switch (name) {
    case 'work':
      return Icons.work_outline_rounded;
    case 'school':
      return Icons.school_outlined;
    case 'menu_book':
      return Icons.menu_book_rounded;
    case 'volunteer':
      return Icons.volunteer_activism_outlined;
    case 'groups':
      return Icons.groups_outlined;
    case 'rocket':
      return Icons.rocket_launch_outlined;
    case 'store':
      return Icons.storefront_outlined;
    case 'more':
      return Icons.more_horiz_rounded;
    default:
      return Icons.work_outline_rounded;
  }
}
