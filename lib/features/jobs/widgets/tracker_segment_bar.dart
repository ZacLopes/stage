import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../models/application.dart';

/// FASE 3 (T3.1 redesign): barra de segmentos da aba Candidaturas. Pílulas
/// roláveis com contagem; a selecionada anima cor/elevação. Substitui as 4
/// seções empilhadas por um filtro no topo (UX mais limpa + animada).
class TrackerSegmentBar extends StatelessWidget {
  final ApplicationSegment selected;
  final Map<ApplicationSegment, int> counts;
  final ValueChanged<ApplicationSegment> onSelected;

  const TrackerSegmentBar({
    super.key,
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        children: [
          for (final seg in ApplicationSegment.values) ...[
            _SegmentPill(
              label: seg.label,
              count: counts[seg] ?? 0,
              isSelected: seg == selected,
              onTap: () => onSelected(seg),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _SegmentPill extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _SegmentPill({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isSelected ? Colors.white : AppColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
