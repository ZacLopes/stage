import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Botão principal do app — fundo azul Stage (`AppColors.primary`).
///
/// Suporta loading state (mostra spinner branco e desabilita ação).
/// Use pra ações primárias: "Continuar", "Salvar", "Aplicar", "Enviar".
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    this.size = PrimaryButtonSize.md,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool expand;
  final PrimaryButtonSize size;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    final dims = _dimensionsFor(size);

    final child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: isLoading
          ? SizedBox(
              key: const ValueKey('loading'),
              height: dims.iconSize,
              width: dims.iconSize,
              child: const CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.onPrimary),
              ),
            )
          : Row(
              key: const ValueKey('content'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: dims.iconSize),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Text(label, style: dims.textStyle),
              ],
            ),
    );

    final button = ElevatedButton(
      onPressed: disabled ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
        foregroundColor: AppColors.onPrimary,
        disabledForegroundColor: AppColors.onPrimary.withValues(alpha: 0.7),
        elevation: 0,
        padding: dims.padding,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        minimumSize: Size(0, dims.height),
      ),
      child: child,
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

enum PrimaryButtonSize { sm, md, lg }

class _ButtonDims {
  const _ButtonDims({
    required this.height,
    required this.padding,
    required this.textStyle,
    required this.iconSize,
  });
  final double height;
  final EdgeInsets padding;
  final TextStyle textStyle;
  final double iconSize;
}

_ButtonDims _dimensionsFor(PrimaryButtonSize size) {
  switch (size) {
    case PrimaryButtonSize.sm:
      return _ButtonDims(
        height: 40,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.sm,
        ),
        textStyle: AppTextStyles.labelMd.copyWith(color: AppColors.onPrimary),
        iconSize: 16,
      );
    case PrimaryButtonSize.md:
      return _ButtonDims(
        height: 48,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        textStyle: AppTextStyles.labelLg.copyWith(color: AppColors.onPrimary),
        iconSize: 18,
      );
    case PrimaryButtonSize.lg:
      return _ButtonDims(
        height: 56,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.base,
        ),
        textStyle: AppTextStyles.labelLg.copyWith(
          color: AppColors.onPrimary,
          fontSize: 16,
        ),
        iconSize: 20,
      );
  }
}
