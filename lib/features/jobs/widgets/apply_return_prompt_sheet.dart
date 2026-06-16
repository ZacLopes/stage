import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/theme.dart';
import '../utils/pending_apply.dart';

/// Resultado do prompt de retorno (FASE 3 T3.2).
sealed class ApplyPromptOutcome {
  const ApplyPromptOutcome();
}

/// "Sim" — confirmou a candidatura.
class ApplyConfirmed extends ApplyPromptOutcome {
  const ApplyConfirmed();
}

/// "Não" + motivo de abandono (fricção por fonte).
class ApplyAbandoned extends ApplyPromptOutcome {
  final ApplyAbandonReason reason;
  const ApplyAbandoned(this.reason);
}

/// "Depois" — re-pergunta única em 24h.
class ApplyLater extends ApplyPromptOutcome {
  const ApplyLater();
}

/// Abre o prompt "Você se candidatou para {título}?". Retorna o desfecho, ou
/// null se foi dispensado (tap fora) — o caller trata null como "Depois leve"
/// (mantém o pending até expirar a janela).
Future<ApplyPromptOutcome?> showApplyReturnPrompt(
  BuildContext context, {
  required PendingApply pending,
}) {
  return showModalBottomSheet<ApplyPromptOutcome>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ApplyReturnPromptSheet(pending: pending),
  );
}

class _ApplyReturnPromptSheet extends StatefulWidget {
  final PendingApply pending;
  const _ApplyReturnPromptSheet({required this.pending});

  @override
  State<_ApplyReturnPromptSheet> createState() =>
      _ApplyReturnPromptSheetState();
}

class _ApplyReturnPromptSheetState extends State<_ApplyReturnPromptSheet> {
  bool _showReasons = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.pending;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!_showReasons)
            ..._buildAskView(context, p)
          else
            ..._buildReasonsView(context),
        ],
      ),
    );
  }

  List<Widget> _buildAskView(BuildContext context, PendingApply p) {
    final titleText =
        p.title.isNotEmpty ? p.title : 'a vaga';
    return [
      Text(
        'Você se candidatou?',
        style: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        p.company.isNotEmpty ? '$titleText · ${p.company}' : titleText,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop(const ApplyConfirmed());
          },
          child: const Text('Sim, me candidatei',
              style: TextStyle(
                  fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => setState(() => _showReasons = true),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: BorderSide(color: AppColors.border),
          ),
          child: Text('Não',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => Navigator.of(context).pop(const ApplyLater()),
        child: Text('Depois',
            style: TextStyle(
                fontFamily: 'Inter', fontSize: 14, color: AppColors.textTertiary)),
      ),
    ];
  }

  List<Widget> _buildReasonsView(BuildContext context) {
    return [
      Text(
        'O que te fez desistir?',
        style: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 16),
      for (final reason in ApplyAbandonReason.values) ...[
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop(ApplyAbandoned(reason));
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              alignment: Alignment.centerLeft,
              side: BorderSide(color: AppColors.border),
            ),
            child: Text(reason.label,
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
        ),
        const SizedBox(height: 8),
      ],
    ];
  }
}
