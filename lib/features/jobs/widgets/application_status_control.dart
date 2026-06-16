import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../models/application.dart';

/// FASE 3 (T3.1): chip de status da candidatura com menu das transições
/// válidas (o caller filtra por `canTransition`). O usuário move o próprio
/// pipeline em type manual/external_confirmed; sem opções → chip estático.
class ApplicationStatusControl extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timeline_rounded, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          if (options.isNotEmpty) ...[
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 16, color: AppColors.primary),
          ],
        ],
      ),
    );

    if (options.isEmpty) return chip;

    return PopupMenuButton<ApplicationStatus>(
      tooltip: 'Atualizar status',
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final s in options)
          PopupMenuItem<ApplicationStatus>(
            value: s,
            child: Text(s.label,
                style: const TextStyle(fontFamily: 'Inter', fontSize: 14)),
          ),
      ],
      child: chip,
    );
  }
}
