// Opção de escolha ÚNICA "rica" da trilha: um card de largura cheia com título
// (+ subtítulo opcional) e uma seta — tocar já avança. Substitui os chips soltos
// e miúdos quando a pergunta é "escolha uma" com opções que merecem respiro
// (ex.: fit cultural, disponibilidade). Compartilhado pelos dois dispatchers da
// trilha (inline_step_input · step_input_view) pra os dois ficarem iguais.
//
// Feedback de toque: escala suave + tinta/borda da marca + a seta acende, com
// haptic. Tudo no design system (AppColors/AppShadows/AppRadius/AppSpacing).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/theme.dart';

class TrilhaOptionTile extends StatefulWidget {
  const TrilhaOptionTile({
    super.key,
    required this.label,
    this.subtitle,
    this.onTap,
  });

  final String label;
  final String? subtitle;

  /// null = desabilitado (esmaece o toque).
  final VoidCallback? onTap;

  @override
  State<TrilhaOptionTile> createState() => _TrilhaOptionTileState();
}

class _TrilhaOptionTileState extends State<TrilhaOptionTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final subtitle = widget.subtitle;
    final active = _pressed && enabled;

    return AnimatedScale(
      scale: active ? 0.975 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: Colors.transparent,
          borderRadius: AppRadius.brLg,
          child: InkWell(
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    widget.onTap!();
                  }
                : null,
            onHighlightChanged:
                enabled ? (v) => setState(() => _pressed = v) : null,
            borderRadius: AppRadius.brLg,
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primary.withValues(alpha: 0.06)
                    : AppColors.surface,
                borderRadius: AppRadius.brLg,
                border: Border.all(
                  color: active ? AppColors.primary : AppColors.border,
                  width: 1.5,
                ),
                boxShadow: active ? null : AppShadows.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: AppTextStyles.titleSm.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle != null && subtitle.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: AppTextStyles.bodySm
                                .copyWith(color: AppColors.textTertiary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: active ? AppColors.primary : AppColors.textTertiary,
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
