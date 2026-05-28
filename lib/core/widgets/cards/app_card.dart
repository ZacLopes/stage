import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Container padrão de card do app, em 3 variantes:
/// - `flat`: borda fina cinza, sem sombra (lista de itens)
/// - `elevated`: sombra suave, sem borda (destaque)
/// - `gradient`: gradient da marca como fundo (heros)
///
/// Substitui ~25 `Container` + `BoxDecoration` inline espalhados pelo app.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.variant = AppCardVariant.flat,
    this.padding = AppSpacing.allBase,
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.borderRadius,
  });

  final Widget child;
  final AppCardVariant variant;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? AppRadius.brLg;

    final decoration = switch (variant) {
      AppCardVariant.flat => BoxDecoration(
          color: AppColors.surface,
          borderRadius: radius,
          border: Border.all(color: AppColors.border),
        ),
      AppCardVariant.elevated => BoxDecoration(
          color: AppColors.surface,
          borderRadius: radius,
          boxShadow: AppShadows.md,
        ),
      AppCardVariant.gradient => BoxDecoration(
          gradient: AppGradients.brand,
          borderRadius: radius,
          boxShadow: AppShadows.brand,
        ),
    };

    final container = Container(
      margin: margin,
      decoration: decoration,
      child: ClipRRect(
        borderRadius: radius,
        child: Padding(padding: padding, child: child),
      ),
    );

    if (onTap == null) return container;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: container,
      ),
    );
  }
}

enum AppCardVariant { flat, elevated, gradient }
