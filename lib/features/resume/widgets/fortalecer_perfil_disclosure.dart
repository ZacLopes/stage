// Entrada compacta e expansível do progresso de perfil na aba Assistente.
// Fechada por padrão para a conversa ser a superfície principal; ao abrir,
// revela o stepper completo e mantém o acesso a cada seção.

import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';

class FortalecerPerfilDisclosure extends StatefulWidget {
  const FortalecerPerfilDisclosure({
    super.key,
    required this.completedCount,
    required this.totalCount,
    required this.child,
  }) : assert(totalCount > 0),
       assert(completedCount >= 0),
       assert(completedCount <= totalCount);

  final int completedCount;
  final int totalCount;
  final Widget child;

  @override
  State<FortalecerPerfilDisclosure> createState() =>
      _FortalecerPerfilDisclosureState();
}

class _FortalecerPerfilDisclosureState
    extends State<FortalecerPerfilDisclosure> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final progressLabel =
        '${widget.completedCount} de ${widget.totalCount} etapas concluídas';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            container: true,
            button: true,
            label: 'Fortalecer perfil',
            value: progressLabel,
            expanded: _expanded,
            onTap: _toggle,
            child: ExcludeSemantics(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _toggle,
                  borderRadius: AppRadius.brLg,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.base,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: AppColors.primarySoft,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.trending_up_rounded,
                              size: 20,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Fortalecer perfil',
                                  style: AppTextStyles.labelLg.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  progressLabel,
                                  style: AppTextStyles.labelSm.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.base,
                        0,
                        AppSpacing.base,
                        AppSpacing.base,
                      ),
                      child: widget.child,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}
