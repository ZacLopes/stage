// Card de RESPOSTA preenchida e editável (PLANO chat v2 — F1).
//
// Depois que o usuário responde um passo, o widget inline colapsa neste card:
// mostra o que foi respondido (chips pra escolhas, texto pro resto) e, se o
// passo é reversível, um lápis (✎) que reabre o passo pra editar. Fica no fio
// (decisão do fundador: "card editável que permanece").

import 'package:flutter/material.dart';

import '../../../../../core/theme/theme.dart';
import '../../../application/conversation_controller.dart';

class TrilhaAnswerCard extends StatelessWidget {
  const TrilhaAnswerCard({super.key, required this.exchange, this.onEdit});

  final ConversationExchange exchange;

  /// Null = não editável (passo cujo write-back INSERE linha — voltar duplica).
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final answer = exchange.answer;
    final isList = answer.value is List;
    final pulou = answer.displayText.trim().isEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.md, AppSpacing.sm, AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2, right: AppSpacing.sm),
            child: Icon(Icons.check_circle_rounded,
                size: 18, color: AppColors.success),
          ),
          Expanded(
            child: pulou
                ? Text('Pulado',
                    style: AppTextStyles.bodyMd
                        .copyWith(color: AppColors.textTertiary))
                : isList
                    ? Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final label in _labels(answer.displayText))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primarySoft,
                                borderRadius: AppRadius.brPill,
                              ),
                              child: Text(label,
                                  style: AppTextStyles.labelSm
                                      .copyWith(color: AppColors.primary)),
                            ),
                        ],
                      )
                    : Text(
                        answer.displayText,
                        style: AppTextStyles.bodyMd
                            .copyWith(color: AppColors.textPrimary),
                      ),
          ),
          if (onEdit != null)
            InkWell(
              onTap: onEdit,
              borderRadius: AppRadius.brSm,
              child: const Padding(
                padding: EdgeInsets.all(AppSpacing.xs),
                child: Icon(Icons.edit_rounded,
                    size: 16, color: AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }

  List<String> _labels(String displayText) => displayText
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}
