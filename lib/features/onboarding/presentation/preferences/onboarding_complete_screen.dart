// OnboardingCompleteScreen — tela final do onboarding novo.
//
// Crítico (Semana 2): ao tocar "Começar", chama createCampaign(isSkipped: true)
// e onboardingCompleted ANTES de fechar o stack. Sem isso, AuthGate
// (Consumer<UserViewModel>) não detecta hasCampaign=true e fica em loop
// voltando pra signup. Mesma técnica usada na CompletionScreen legacy.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../services/analytics_service.dart';
import '../../../../services/facebook_events_service.dart';
import '../../../auth/user_viewmodel.dart';
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

  @override
  void initState() {
    super.initState();
    // QA Dia 6 fix: raw track('onboarding_completed') foi removido daqui
    // (era double-emission com `_handleFinish` abaixo, e não trazia
    // door/duration/flow_version). O `onboarding_completed` fica só
    // no tap "Começar". `onboarding_all_set_shown` é da AllSetScreen
    // (transição entre masking e review) — não desta tela final.
  }

  Future<void> _handleFinish() async {
    if (_finishing) return;
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
      return;
    }

    if (!mounted) return;
    // Door resolvida pela TwoDoorsScreen (persistida em SharedPrefs).
    // Fallback 'upload_cv' pra fluxos sem TwoDoors (não deve acontecer
    // pós-cutover) — evita None se SharedPrefs estiver vazio.
    final door =
        await Analytics.shared.resolveOnboardingDoor() ?? 'upload_cv';
    if (!mounted) return;
    // ignore: unawaited_futures
    Analytics.shared.onboardingCompleted(door: door);

    // Facebook Lead — sinal "user qualificado" (perfil populado + campaign
    // criada). Mais forte que CompletedRegistration sozinho pra otimização
    // de campanha. Dedupado por user_id em SharedPreferences.
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
      return;
    }

    if (widget.onFinish != null) {
      widget.onFinish!();
    } else {
      // Volta pro AuthGate (rota raiz). O Consumer<UserViewModel> dele
      // detecta hasCampaign=true e re-renderiza HomeScreen
      // automaticamente. Todo o onboarding (Upload e Trail) usa push
      // regular, então AuthGate sempre está no fundo do stack como
      // isFirst.
      //
      // ⚠️ Não usar pushAndRemoveUntil(AuthGate) aqui — cria uma SEGUNDA
      // instância de AuthGate enquanto a antiga ainda existe no widget
      // tree, gerando 2 HomeScreens e GlobalKeys duplicadas (TutorialKeys
      // do jobs_swipe_screen colide).
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      progress: 1.0,
      showBack: false,
      onContinue: _finishing ? null : _handleFinish,
      continueLabel: _finishing ? 'Carregando…' : 'Começar',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  color: AppColors.brandCyan.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.celebration, color: AppColors.brandCyan, size: 64),
              ),
              const SizedBox(height: 28),
              const Text(
                'Pronto!',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Vamos te mostrar vagas que combinam com você.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textTertiary, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
