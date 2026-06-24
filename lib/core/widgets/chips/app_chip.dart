import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/theme.dart';

/// Chip padronizado — substitui os `AnimatedContainer` + `BoxDecoration`
/// inline em BadgeMultiSelectWidget e outros.
///
/// 3 estados visuais: unselected / selected / disabled. Micro-interação: encolhe
/// levemente ao pressionar (mola) + haptic no toque — o feedback físico que dá
/// sensação premium. O ripple do Material sai (a escala é o feedback).
class AppChip extends StatefulWidget {
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
  State<AppChip> createState() => _AppChipState();
}

class _AppChipState extends State<AppChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color border;
    final Color fg;

    if (widget.disabled) {
      bg = AppColors.surfaceMuted;
      border = AppColors.border;
      fg = AppColors.textDisabled;
    } else if (widget.selected) {
      bg = AppColors.primarySoft;
      border = AppColors.primary;
      fg = AppColors.primary;
    } else {
      bg = AppColors.surface;
      border = AppColors.borderStrong;
      fg = AppColors.textSecondary;
    }

    final tappable = !widget.disabled && widget.onTap != null;

    return AnimatedScale(
      scale: _pressed ? 0.95 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadius.brPill,
          border: Border.all(color: border, width: widget.selected ? 1.5 : 1),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: AppRadius.brPill,
          child: InkWell(
            onTap: tappable
                ? () {
                    HapticFeedback.selectionClick();
                    widget.onTap!();
                  }
                : null,
            onHighlightChanged:
                tappable ? (v) => setState(() => _pressed = v) : null,
            borderRadius: AppRadius.brPill,
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 14, color: fg),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Text(
                    widget.label,
                    style: AppTextStyles.labelMd.copyWith(color: fg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
