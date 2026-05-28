import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Botão "fantasma" — só texto, sem fundo nem borda.
///
/// Use pra ações terciárias: "Cancelar", "Agora não", "Pular".
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = GhostButtonTone.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final GhostButtonTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      GhostButtonTone.primary => AppColors.primary,
      GhostButtonTone.neutral => AppColors.textSecondary,
      GhostButtonTone.danger => AppColors.error,
    };

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: AppTextStyles.labelMd.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

enum GhostButtonTone { primary, neutral, danger }
