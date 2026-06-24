// Tela de entrada da trilha (PLANO-FASE-6 T6.3, Increment 2c).
//
// Resolve o usuário atual, monta a sessão (perfil → lacunas → plano +
// write-back) e mostra a conversa. Se não há nada a coletar (perfil já
// completo dentro do que esta fase cobre), mostra um estado de "tudo certo".

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/ai_service.dart';
import '../../../services/analytics_events.dart';
import '../../../services/analytics_service.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../application/conversation_controller.dart';
import '../application/trilha_session.dart';
import 'conversation_screen.dart';

class TrilhaLoaderScreen extends StatefulWidget {
  const TrilhaLoaderScreen({
    super.key,
    this.userId,
    this.onCompleted,
    this.source = 'hub',
  });

  /// Se nulo, usa o usuário autenticado atual.
  final String? userId;
  final VoidCallback? onCompleted;

  /// De onde a trilha foi aberta (telemetria): hub | post_onboarding | dev.
  final String source;

  @override
  State<TrilhaLoaderScreen> createState() => _TrilhaLoaderScreenState();
}

class _TrilhaLoaderScreenState extends State<TrilhaLoaderScreen> {
  late Future<ConversationController> _future;

  @override
  void initState() {
    super.initState();
    _future = _load().then((controller) {
      if (controller.totalSteps > 0) {
        // ignore: unawaited_futures
        Analytics.shared.track(evTrilhaColetaStarted, props: {
          'source': widget.source,
          'total_steps': controller.totalSteps,
        });
      }
      return controller;
    });
  }

  Future<ConversationController> _load() {
    final uid =
        widget.userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      return Future.error(StateError('Sem usuário autenticado'));
    }
    return buildTrilhaController(uid);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ConversationController>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _scaffold(_loading());
        }
        if (snap.hasError) {
          return _scaffold(_error());
        }
        final controller = snap.data!;
        if (controller.totalSteps == 0) {
          return _scaffold(_allSet());
        }
        return ConversationScreen(
          controller: controller,
          onCompleted: () {
            // ignore: unawaited_futures
            Analytics.shared.track(evTrilhaColetaCompleted,
                props: {'answered': controller.answeredCount});
            widget.onCompleted?.call();
          },
          onAbandoned: (answered, total) {
            // ignore: unawaited_futures
            Analytics.shared.track(evTrilhaColetaAbandoned,
                props: {'answered': answered, 'total': total});
          },
          // Ao concluir, a IA monta o resumo+headline do perfil (failure-safe).
          onFinalize: () => AIService().generateProfileSummary(),
        );
      },
    );
  }

  Widget _scaffold(Widget body) => Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(child: body),
      );

  Widget _loading() => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: AppSpacing.base),
            Text('Preparando sua trilha…', style: AppTextStyles.bodyMd),
          ],
        ),
      );

  Widget _error() => Center(
        child: Padding(
          padding: AppSpacing.allXl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.textTertiary, size: 40),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Não consegui carregar sua trilha agora. Tenta de novo daqui a pouco.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              SecondaryButton(
                label: 'Voltar',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      );

  Widget _allSet() => Center(
        child: Padding(
          padding: AppSpacing.allXl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_rounded,
                  color: AppColors.success, size: 48),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Seu perfil já está ótimo! 🎉',
                textAlign: TextAlign.center,
                style: AppTextStyles.titleMd.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Você já preencheu o essencial pras empresas te encontrarem. '
                'Em breve a trilha vai sugerir experiências e um resumo pra '
                'deixar ainda mais forte.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Voltar',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      );
}
