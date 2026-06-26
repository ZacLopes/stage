// Toggle segmentado "Conversa / Currículo" da aba Currículo (PLANO-FASE-6).
//
// Não há segmented-control no design-system; este é um pill segmentado leve
// construído só com tokens Stage. A "bolinha" selecionada desliza (Animated).

import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';

class CurriculoToggle extends StatelessWidget {
  const CurriculoToggle({
    super.key,
    required this.index,
    required this.onChanged,
    this.leftLabel = 'Conversa',
    this.rightLabel = 'Currículo',
  });

  /// 0 = esquerda (Conversa), 1 = direita (Currículo).
  final int index;
  final ValueChanged<int> onChanged;
  final String leftLabel;
  final String rightLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadius.brMd,
      ),
      child: Row(
        children: [
          Expanded(child: _segment(leftLabel, 0)),
          Expanded(child: _segment(rightLabel, 1)),
        ],
      ),
    );
  }

  Widget _segment(String label, int i) {
    final selected = index == i;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!selected) onChanged(i);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: AppRadius.brSm,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.30),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppTextStyles.labelMd.copyWith(
            color: selected ? AppColors.onPrimary : AppColors.textTertiary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
