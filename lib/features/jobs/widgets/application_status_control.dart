import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../../core/theme/theme.dart';
import '../models/application.dart';

/// Chip compacto que abre um seletor mobile para as transições válidas da
/// candidatura. Sem opções, continua sendo apenas um indicador de status.
class ApplicationStatusControl extends StatefulWidget {
  final ApplicationStatus status;
  final List<ApplicationStatus> options;
  final ValueChanged<ApplicationStatus> onSelected;

  const ApplicationStatusControl({
    super.key,
    required this.status,
    required this.options,
    required this.onSelected,
  });

  @override
  State<ApplicationStatusControl> createState() =>
      _ApplicationStatusControlState();
}

class _ApplicationStatusControlState extends State<ApplicationStatusControl> {
  bool _isOpen = false;

  Future<void> _openPicker() async {
    if (_isOpen || widget.options.isEmpty) return;

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final navigator = Navigator.of(context);
    final controller = AnimationController(
      vsync: navigator,
      duration: reduceMotion
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 360),
      reverseDuration: reduceMotion
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 240),
    );

    HapticFeedback.lightImpact();
    setState(() => _isOpen = true);

    ApplicationStatus? selected;
    try {
      selected = await showModalBottomSheet<ApplicationStatus>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: AppColors.textPrimary.withValues(alpha: 0.46),
        transitionAnimationController: controller,
        builder: (sheetContext) => _StatusPickerSheet(
          currentStatus: widget.status,
          options: widget.options,
          reduceMotion: reduceMotion,
        ),
      );
      // O Future da rota devolve o resultado no início do pop, antes de a
      // transição reversa terminar. Como o controller é nosso, descartá-lo
      // nesse instante congela o sheet no último frame. Aguardamos o estado
      // dismissed para garantir uma saída completa e sem salto.
      if (controller.status != AnimationStatus.dismissed) {
        await controller.reverse();
      }
    } finally {
      controller.dispose();
      if (mounted) setState(() => _isOpen = false);
    }

    if (mounted && selected != null) widget.onSelected(selected);
  }

  @override
  Widget build(BuildContext context) {
    final presentation = _presentationFor(widget.status);
    final canEdit = widget.options.isNotEmpty;

    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      height: 36,
      padding: EdgeInsets.fromLTRB(5, 4, canEdit ? 5 : 10, 4),
      decoration: BoxDecoration(
        color: _isOpen ? presentation.softColor : AppColors.surface,
        borderRadius: AppRadius.brPill,
        border: Border.all(
          color: presentation.color.withValues(alpha: _isOpen ? 0.42 : 0.24),
        ),
        boxShadow: _isOpen ? AppShadows.brand : AppShadows.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: presentation.softColor,
              shape: BoxShape.circle,
            ),
            child: Icon(presentation.icon, size: 14, color: presentation.color),
          ),
          const SizedBox(width: 7),
          Text(
            widget.status.label,
            style: AppTextStyles.labelSm.copyWith(
              fontWeight: FontWeight.w700,
              color: presentation.color,
            ),
          ),
          if (canEdit) ...[
            const SizedBox(width: 5),
            AnimatedRotation(
              turns: _isOpen ? 0.5 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: presentation.color,
              ),
            ),
          ],
        ],
      ),
    );

    if (!canEdit) return chip;

    return Semantics(
      button: true,
      label: 'Etapa atual: ${widget.status.label}. Atualizar etapa.',
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.brPill,
        child: InkWell(
          key: const ValueKey('application-status-trigger'),
          onTap: _openPicker,
          borderRadius: AppRadius.brPill,
          child: chip,
        ),
      ),
    );
  }
}

class _StatusPickerSheet extends StatefulWidget {
  final ApplicationStatus currentStatus;
  final List<ApplicationStatus> options;
  final bool reduceMotion;

  const _StatusPickerSheet({
    required this.currentStatus,
    required this.options,
    required this.reduceMotion,
  });

  @override
  State<_StatusPickerSheet> createState() => _StatusPickerSheetState();
}

class _StatusPickerSheetState extends State<_StatusPickerSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  ApplicationStatus? _selected;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    if (widget.reduceMotion) {
      _entryController.value = 1;
    } else {
      _entryController.forward();
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  Future<void> _select(ApplicationStatus status) async {
    if (_selected != null) return;

    HapticFeedback.selectionClick();
    setState(() => _selected = status);

    if (!widget.reduceMotion) {
      await Future<void>.delayed(const Duration(milliseconds: 140));
    }
    if (mounted) Navigator.of(context).pop(status);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final current = _presentationFor(widget.currentStatus);

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: mediaQuery.size.height * 0.88,
        ),
        child: Material(
          color: AppColors.surface,
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: 40,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: AppColors.borderStrong,
                    borderRadius: AppRadius.brPill,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.base,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: AppColors.primarySoft,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.route_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Atualizar etapa',
                              style: AppTextStyles.titleLg.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text.rich(
                              TextSpan(
                                text: 'Agora: ',
                                children: [
                                  TextSpan(
                                    text: widget.currentStatus.label,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: current.color,
                                    ),
                                  ),
                                  const TextSpan(
                                    text: '. Selecione o que aconteceu depois.',
                                  ),
                                ],
                              ),
                              style: AppTextStyles.bodySm,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: () => Navigator.of(context).pop(),
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surfaceVariant,
                          foregroundColor: AppColors.textSecondary,
                        ),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.divider),
                Flexible(
                  child: ListView.separated(
                    key: const ValueKey('application-status-options'),
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.base,
                      AppSpacing.md,
                      AppSpacing.base,
                      AppSpacing.lg,
                    ),
                    itemCount: widget.options.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) => _AnimatedStatusOption(
                      index: index,
                      animation: _entryController,
                      reduceMotion: widget.reduceMotion,
                      status: widget.options[index],
                      selected: _selected == widget.options[index],
                      disabled: _selected != null,
                      onTap: () => _select(widget.options[index]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedStatusOption extends StatelessWidget {
  final int index;
  final Animation<double> animation;
  final bool reduceMotion;
  final ApplicationStatus status;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  const _AnimatedStatusOption({
    required this.index,
    required this.animation,
    required this.reduceMotion,
    required this.status,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final presentation = _presentationFor(status);
    final start = 0.18 + (index * 0.045);
    final end = (start + 0.44).clamp(0.0, 1.0);
    final entryAnimation = reduceMotion
        ? const AlwaysStoppedAnimation<double>(1)
        : CurvedAnimation(
            parent: animation,
            curve: Interval(
              start.clamp(0.0, 0.95),
              end,
              curve: Curves.easeOutCubic,
            ),
          );

    return AnimatedBuilder(
      animation: entryAnimation,
      builder: (context, child) => Opacity(
        opacity: entryAnimation.value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - entryAnimation.value)),
          child: child,
        ),
      ),
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? presentation.softColor : AppColors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(
            color: selected
                ? presentation.color.withValues(alpha: 0.55)
                : AppColors.border,
          ),
          boxShadow: selected ? AppShadows.brand : const [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: AppRadius.brLg,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('application-status-option-${status.db}'),
            onTap: disabled ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: presentation.softColor,
                      borderRadius: AppRadius.brMd,
                    ),
                    child: Icon(
                      presentation.icon,
                      size: 22,
                      color: presentation.color,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          presentation.actionLabel,
                          style: AppTextStyles.labelLg.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          presentation.description,
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeOut,
                    child: selected
                        ? Container(
                            key: const ValueKey('selected'),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: presentation.color,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            Icons.arrow_forward_ios_rounded,
                            key: const ValueKey('arrow'),
                            size: 15,
                            color: presentation.color.withValues(alpha: 0.72),
                          ),
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

class _StatusPresentation {
  final String actionLabel;
  final String description;
  final IconData icon;
  final Color color;
  final Color softColor;

  const _StatusPresentation({
    required this.actionLabel,
    required this.description,
    required this.icon,
    required this.color,
    required this.softColor,
  });
}

_StatusPresentation _presentationFor(ApplicationStatus status) =>
    switch (status) {
      ApplicationStatus.submitted => const _StatusPresentation(
        actionLabel: 'Candidatura enviada',
        description: 'A empresa ainda não respondeu.',
        icon: Icons.send_rounded,
        color: AppColors.brandBlue,
        softColor: AppColors.brandSoft,
      ),
      ApplicationStatus.inReview => const _StatusPresentation(
        actionLabel: 'Está em análise',
        description: 'A empresa está avaliando seu perfil.',
        icon: Icons.manage_search_rounded,
        color: AppColors.info,
        softColor: AppColors.infoSoft,
      ),
      ApplicationStatus.shortlisted => const _StatusPresentation(
        actionLabel: 'Avançou na seleção',
        description: 'Seu perfil passou para a próxima etapa.',
        icon: Icons.trending_up_rounded,
        color: Color(0xFF7C3AED),
        softColor: Color(0xFFF3EEFF),
      ),
      ApplicationStatus.interview => const _StatusPresentation(
        actionLabel: 'Entrevista agendada',
        description: 'Você chegou à etapa de conversa.',
        icon: Icons.event_available_rounded,
        color: AppColors.warning,
        softColor: AppColors.warningSoft,
      ),
      ApplicationStatus.offer => const _StatusPresentation(
        actionLabel: 'Proposta recebida',
        description: 'A empresa enviou uma oferta.',
        icon: Icons.workspace_premium_rounded,
        color: AppColors.primary,
        softColor: AppColors.primarySoft,
      ),
      ApplicationStatus.hired => const _StatusPresentation(
        actionLabel: 'Candidatura aprovada',
        description: 'Você conquistou a vaga.',
        icon: Icons.celebration_rounded,
        color: AppColors.success,
        softColor: AppColors.successSoft,
      ),
      ApplicationStatus.rejected => const _StatusPresentation(
        actionLabel: 'Processo encerrado',
        description: 'A empresa não seguiu com a candidatura.',
        icon: Icons.cancel_outlined,
        color: AppColors.error,
        softColor: AppColors.errorSoft,
      ),
      ApplicationStatus.withdrawn => const _StatusPresentation(
        actionLabel: 'Candidatura retirada',
        description: 'Você decidiu sair do processo.',
        icon: Icons.exit_to_app_rounded,
        color: AppColors.textTertiary,
        softColor: AppColors.background,
      ),
      ApplicationStatus.expired => const _StatusPresentation(
        actionLabel: 'Vaga expirada',
        description: 'O prazo desta vaga terminou.',
        icon: Icons.schedule_rounded,
        color: AppColors.textTertiary,
        softColor: AppColors.background,
      ),
    };
