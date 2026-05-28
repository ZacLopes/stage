import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Estado vazio padronizado — ícone grande circular, título, descrição
/// opcional, ação opcional.
///
/// Use em listas vazias: "Nenhuma vaga curtida ainda", "Sem currículos
/// salvos", "Caixa de mensagens vazia".
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.tone = SemanticEmptyTone.neutral,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final SemanticEmptyTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(tone);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xl2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: palette.bg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: palette.fg),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              title,
              style: AppTextStyles.titleMd,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                style: AppTextStyles.bodyMd,
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

enum SemanticEmptyTone { neutral, brand, success, warning }

class _Palette {
  const _Palette(this.bg, this.fg);
  final Color bg;
  final Color fg;
}

_Palette _paletteFor(SemanticEmptyTone tone) {
  return switch (tone) {
    SemanticEmptyTone.neutral =>
      const _Palette(AppColors.surfaceMuted, AppColors.textTertiary),
    SemanticEmptyTone.brand =>
      const _Palette(AppColors.primarySoft, AppColors.primary),
    SemanticEmptyTone.success =>
      const _Palette(AppColors.successSoft, AppColors.success),
    SemanticEmptyTone.warning =>
      const _Palette(AppColors.warningSoft, AppColors.warning),
  };
}
