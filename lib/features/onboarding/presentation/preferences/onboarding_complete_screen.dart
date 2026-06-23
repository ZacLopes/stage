// OnboardingCompleteScreen — tela final do onboarding novo.
//
// Crítico (Semana 2): ao tocar "Começar", chama createCampaign(isSkipped: true)
// e onboardingCompleted ANTES de fechar o stack. Sem isso, AuthGate
// (Consumer<UserViewModel>) não detecta hasCampaign=true e fica em loop
// voltando pra signup. Mesma técnica usada na CompletionScreen legacy.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../services/analytics_service.dart';
import '../../../../services/analytics_events.dart';
import '../../../../services/facebook_events_service.dart';
import '../../../auth/user_viewmodel.dart';
import '../../../../services/feature_flags_service.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../trilha/presentation/trilha_loader_screen.dart';
import '../onboarding_scaffold.dart';
import '../../../../core/theme/theme.dart';

class OnboardingCompleteScreen extends StatefulWidget {
  /// Callback opcional pra rotina pós-finish. Se null, o default é
  /// simplesmente fechar todo o stack (popUntil isFirst) — AuthGate
  /// re-renderiza HomeScreen automaticamente porque hasCampaign virou true.
  final VoidCallback? onFinish;

  const OnboardingCompleteScreen({super.key, this.onFinish});

  @override
  State<OnboardingCompleteScreen> createState() => _OnboardingCompleteScreenState();
}

class _OnboardingCompleteScreenState extends State<OnboardingCompleteScreen> {
  bool _finishing = false;
  bool _inviteTrilha = false;

  @override
  void initState() {
    super.initState();
    // QA Dia 6 fix: raw track('onboarding_completed') foi removido daqui
    // (era double-emission com `_handleFinish` abaixo, e não trazia
    // door/duration/flow_version). O `onboarding_completed` fica só
    // no tap "Começar". `onboarding_all_set_shown` é da AllSetScreen
    // (transição entre masking e review) — não desta tela final.
    _resolveInvite();
  }

  // 5b: pra quem NÃO importou CV (door='trail') e com a flag `trilha_coleta_v1`
  // ligada, oferecemos a trilha de coleta no momento mais quente — logo após o
  // onboarding. Importadores já saem com perfil rico, então não recebem o convite.
  Future<void> _resolveInvite() async {
    final door = await Analytics.shared.resolveOnboardingDoor();
    if (!mounted) return;
    final userId = context.read<UserViewModel>().user?.id;
    final flagOn = FeatureFlagsService.instance
        .isEnabledForUser(FeatureFlagKeys.trilhaColetaV1, userId);
    if (door == 'trail' && flagOn) {
      setState(() => _inviteTrilha = true);
      // ignore: unawaited_futures
      Analytics.shared.track(evTrilhaColetaInviteShown);
    }
  }

  /// Marca o onboarding como concluído + analytics + guards anti-loop.
  /// Retorna true em sucesso (a navegação fica por conta do chamador).
  Future<bool> _markComplete() async {
    if (_finishing) return false;
    setState(() => _finishing = true);

    final userVm = context.read<UserViewModel>();

    // Fase 1 T1.7: marca onboarding_completed_at direto (fonte única do
    // gate) — 2.3.0 NÃO cria mais campaign (builds antigas seguem criando
    // e a bridge no banco converte). Sem isso, AuthGate fica em loop.
    try {
      await userVm.markOnboardingCompleted();
      debugPrint('[OnboardingCompleteScreen] onboarding marcado: '
          'hasCompletedOnboarding=${userVm.hasCompletedOnboarding}');
    } catch (e) {
      debugPrint('[OnboardingCompleteScreen] markOnboardingCompleted FAILED: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao finalizar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _finishing = false);
      }
      return false;
    }

    if (!mounted) return false;
    // Door resolvida pela TwoDoorsScreen (persistida em SharedPrefs).
    // Fallback 'upload_cv' pra fluxos sem TwoDoors (não deve acontecer
    // pós-cutover) — evita None se SharedPrefs estiver vazio.
    final door =
        await Analytics.shared.resolveOnboardingDoor() ?? 'upload_cv';
    if (!mounted) return false;
    // ignore: unawaited_futures
    Analytics.shared.onboardingCompleted(door: door);

    // Facebook Lead — sinal "user qualificado". Dedupado por user_id.
    // ignore: unawaited_futures
    FacebookEventsService.shared.logLeadOnce(userId: userVm.user?.id);

    if (!userVm.hasCompletedOnboarding) {
      // Defensiva: se markOnboardingCompleted rodou sem exception mas o gate
      // continua false, não fecha o stack pra evitar loop. Mostra erro.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível finalizar. Tenta novamente.'),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _finishing = false);
      return false;
    }
    return true;
  }

  /// "Começar" / "Agora não": finaliza e vai pra Home.
  Future<void> _handleFinish() async {
    if (_inviteTrilha) {
      // ignore: unawaited_futures
      Analytics.shared.track(evTrilhaColetaInviteDismissed);
    }
    if (await _markComplete()) _goHome();
  }

  /// "Completar com a IA" (convite 5b): finaliza, limpa o stack do onboarding
  /// até a Home e abre a trilha por cima — fechar a trilha volta pra Home.
  Future<void> _handleCompleteWithAI() async {
    // ignore: unawaited_futures
    Analytics.shared.track(evTrilhaColetaInviteAccepted);
    final nav = Navigator.of(context);
    if (!await _markComplete()) return;
    nav.popUntil((route) => route.isFirst);
    nav.push(MaterialPageRoute(
        builder: (_) => const TrilhaLoaderScreen(source: 'post_onboarding')));
  }

  void _goHome() {
    if (widget.onFinish != null) {
      widget.onFinish!();
    } else {
      // Volta pro AuthGate (rota raiz). O Consumer<UserViewModel> dele detecta
      // a conclusão e re-renderiza HomeScreen. ⚠️ Não usar
      // pushAndRemoveUntil(AuthGate) aqui — cria 2 AuthGate/HomeScreen e
      // GlobalKeys duplicadas (TutorialKeys do jobs_swipe_screen colide).
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_inviteTrilha) {
      return OnboardingScaffold(
        progress: 1.0,
        showBack: false,
        onContinue: null,
        customFooter: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrimaryButton(
              label: _finishing ? 'Carregando…' : 'Completar com a IA',
              onPressed: _finishing ? null : _handleCompleteWithAI,
            ),
            const SizedBox(height: AppSpacing.sm),
            GhostButton(
              label: 'Agora não',
              onPressed: _finishing ? null : _handleFinish,
            ),
          ],
        ),
        child: _body(
          title: 'Perfil criado! 🎉',
          subtitle:
              'Quer responder umas perguntas rápidas pra aparecer pra mais '
              'empresas? Leva uns 2 min.',
        ),
      );
    }
    return OnboardingScaffold(
      progress: 1.0,
      showBack: false,
      onContinue: _finishing ? null : _handleFinish,
      continueLabel: _finishing ? 'Carregando…' : 'Começar',
      child: _body(
        title: 'Pronto!',
        subtitle: 'Vamos te mostrar vagas que combinam com você.',
      ),
    );
  }

  Widget _body({required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.brandCyan.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.celebration,
                  color: AppColors.brandCyan, size: 64),
            ),
            const SizedBox(height: 28),
            Text(
              title,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppColors.textTertiary, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
