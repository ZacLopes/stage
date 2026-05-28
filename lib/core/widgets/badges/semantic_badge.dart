import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Badge semântico — fundo "soft" da cor + texto/ícone na cor base.
///
/// 4 tons: success / warning / error / info. Use pra status, tags,
/// indicadores ("Aplicada", "Em análise", "Erro", "Nova").
class SemanticBadge extends StatelessWidget {
  const SemanticBadge({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
  });

  final String label;
  final SemanticTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(tone);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: AppRadius.brPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: palette.fg),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: AppTextStyles.labelSm.copyWith(
              color: palette.fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

enum SemanticTone { success, warning, error, info, neutral, brand }

class _BadgePalette {
  const _BadgePalette(this.bg, this.fg);
  final Color bg;
  final Color fg;
}

_BadgePalette _paletteFor(SemanticTone tone) {
  return switch (tone) {
    SemanticTone.success =>
      const _BadgePalette(AppColors.successSoft, AppColors.success),
    SemanticTone.warning =>
      const _BadgePalette(AppColors.warningSoft, AppColors.warning),
    SemanticTone.error =>
      const _BadgePalette(AppColors.errorSoft, AppColors.error),
    SemanticTone.info => const _BadgePalette(AppColors.infoSoft, AppColors.info),
    SemanticTone.neutral =>
      const _BadgePalette(AppColors.surfaceMuted, AppColors.textSecondary),
    SemanticTone.brand =>
      const _BadgePalette(AppColors.primarySoft, AppColors.primary),
  };
}
