import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Chip padronizado — substitui os `AnimatedContainer` + `BoxDecoration`
/// inline em BadgeMultiSelectWidget e outros.
///
/// 3 estados visuais: unselected / selected / disabled.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.disabled = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color border;
    final Color fg;

    if (disabled) {
      bg = AppColors.surfaceMuted;
      border = AppColors.border;
      fg = AppColors.textDisabled;
    } else if (selected) {
      bg = AppColors.primarySoft;
      border = AppColors.primary;
      fg = AppColors.primary;
    } else {
      bg = AppColors.surface;
      border = AppColors.borderStrong;
      fg = AppColors.textSecondary;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.brPill,
        border: Border.all(color: border, width: selected ? 1.5 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.brPill,
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: AppRadius.brPill,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: fg),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(
                  label,
                  style: AppTextStyles.labelMd.copyWith(color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
