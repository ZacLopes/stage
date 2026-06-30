// Stepper de seções da aba Currículo (PLANO-FASE-6): Formação → Experiência →
// Skills → Idiomas → Interesses, refletindo o progresso da trilha conversacional.
//
// Não há stepper no design-system; construído só com tokens Stage. Status por
// seção vem de [sectionStatuses] (lógica pura). done = verde (success) com check;
// current = azul (primary) destacado; pending = neutro.

import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../../trilha/application/trilha_section.dart';

class CurriculoSectionStepper extends StatelessWidget {
  const CurriculoSectionStepper({
    super.key,
    required this.statuses,
    this.onSectionTap,
  });

  final Map<TrilhaSection, SectionStatus> statuses;

  /// Toque numa seção — abre o sheet de verificação (null = não-tocável).
  final void Function(TrilhaSection section)? onSectionTap;

  @override
  Widget build(BuildContext context) {
    final sections = kStepperSections;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < sections.length; i++)
          Expanded(
            child: onSectionTap == null
                ? _cell(i, sections)
                : InkWell(
                    onTap: () => onSectionTap!(sections[i]),
                    borderRadius: AppRadius.brMd,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: _cell(i, sections),
                    ),
                  ),
          ),
      ],
    );
  }

  Widget _cell(int i, List<TrilhaSection> sections) {
    final section = sections[i];
    final status = statuses[section] ?? SectionStatus.pending;
    final isFirst = i == 0;
    final isLast = i == sections.length - 1;

    // O conector entre (i-1) e (i) fica "preenchido" quando a seção i-1 já está
    // concluída — a linha enche até a seção mais avançada já abordada.
    final leftFilled =
        i > 0 && statuses[sections[i - 1]] == SectionStatus.done;
    final rightFilled = status == SectionStatus.done;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: isFirst ? const SizedBox() : _connector(leftFilled)),
            _circle(i, status),
            Expanded(child: isLast ? const SizedBox() : _connector(rightFilled)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          trilhaSectionLabel(section),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTextStyles.labelSm.copyWith(
            fontSize: 10,
            color: status == SectionStatus.pending
                ? AppColors.textDisabled
                : AppColors.textSecondary,
            fontWeight: status == SectionStatus.current
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _connector(bool filled) => Container(
        height: 2,
        color: filled ? AppColors.success : AppColors.border,
      );

  Widget _circle(int i, SectionStatus status) {
    switch (status) {
      case SectionStatus.done:
        return Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(
            color: AppColors.success,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded,
              size: 15, color: AppColors.onPrimary),
        );
      case SectionStatus.current:
        return Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            '${i + 1}',
            style: AppTextStyles.labelSm.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        );
      case SectionStatus.pending:
        return Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(
            color: AppColors.background,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '${i + 1}',
            style: AppTextStyles.labelSm.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textDisabled,
            ),
          ),
        );
    }
  }
}
