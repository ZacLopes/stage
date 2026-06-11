import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';

/// Badge "Expirada" da aba Curtidas (Fase 1 T1.4 / auditoria E5).
///
/// Aparece quando a vaga salva saiu do ar — `jobs.is_active=false` (sync
/// desativou) ou deadline vencida. 69% dos applied históricos apontavam pra
/// vaga morta sem nenhum aviso; o badge comunica que o link externo pode
/// estar morto e que a ação esperada é arquivar.
class ExpiredJobBadge extends StatelessWidget {
  const ExpiredJobBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_busy_outlined,
              size: 12, color: AppColors.textTertiary),
          const SizedBox(width: 4),
          Text(
            'Expirada',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
