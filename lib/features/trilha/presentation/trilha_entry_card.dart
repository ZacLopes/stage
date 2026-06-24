// Card de entrada da trilha no hub do Perfil (PLANO-FASE-6 T6.3, Increment 5a).
//
// "Completar com a IA" → abre a trilha de coleta. Auto-gateado pela flag
// estrutural `trilha_coleta_v1` (default OFF → escondido; failure-safe: flag
// ausente/não-carregada ⇒ não aparece). Rollout 10→50→100 via app_feature_flags.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../services/feature_flags_service.dart';
import '../../profile/application/profile_editor_view_model.dart';
import 'trilha_loader_screen.dart';

class TrilhaEntryCard extends StatelessWidget {
  const TrilhaEntryCard({super.key});

  /// Lê o user atual sem quebrar em testes (Supabase pode não estar init).
  String? _currentUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = FeatureFlagsService.instance.isEnabledForUser(
      FeatureFlagKeys.trilhaColetaV1,
      _currentUserId(),
    );
    if (!enabled) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.base),
      child: AppCard(
        variant: AppCardVariant.gradient,
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TrilhaLoaderScreen()),
          );
          // Ao voltar, recarrega o Perfil pra mostrar o que a trilha preencheu
          // (resumo, headline, experiências…). Failure-safe: fora do Perfil o
          // provider não existe — não pode quebrar.
          if (context.mounted) {
            try {
              await context.read<ProfileEditorViewModel>().load();
            } catch (_) {/* sem o provider no contexto: ignora */}
          }
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.onPrimary.withValues(alpha: 0.18),
                borderRadius: AppRadius.brMd,
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: AppColors.onPrimary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Completar com a IA',
                    style: AppTextStyles.titleSm
                        .copyWith(color: AppColors.onPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Responda umas perguntas rápidas e apareça pra mais empresas.',
                    style: AppTextStyles.bodySm
                        .copyWith(color: AppColors.onPrimary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: AppColors.onPrimary),
          ],
        ),
      ),
    );
  }
}
