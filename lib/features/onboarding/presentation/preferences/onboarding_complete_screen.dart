// OnboardingCompleteScreen — tela final do onboarding novo.
//
// Crítico (Semana 2): ao tocar "Começar", chama createCampaign(isSkipped: true)
// e onboardingCompleted ANTES de fechar o stack. Sem isso, AuthGate
// (Consumer<UserViewModel>) não detecta hasCampaign=true e fica em loop
// voltando pra signup. Mesma técnica usada na CompletionScreen legacy.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../services/analytics_service.dart';
import '../../../auth/user_viewmodel.dart';
import '../onboarding_scaffold.dart';

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
    AnalyticsService.shared.track('onboarding_completed', props: {'via': 'profile_first_v2'});
  }

  Future<void> _handleFinish() async {
    if (_finishing) return;
    setState(() => _finishing = true);

    // Cria campaign skipped — mesma técnica da CompletionScreen legacy.
    // Sem isso, AuthGate não detecta hasCampaign=true e fica em loop.
    try {
      await context.read<UserViewModel>().createCampaign(isSkipped: true);
    } catch (e) {
      debugPrint('[OnboardingCompleteScreen] createCampaign failed (non-blocking): $e');
    }

    if (!mounted) return;
    Analytics.shared.onboardingCompleted();

    if (widget.onFinish != null) {
      widget.onFinish!();
    } else {
      // Default: fecha todo o stack. AuthGate (Consumer<UserViewModel>)
      // detecta hasCampaign=true e re-renderiza HomeScreen automaticamente.
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
                  color: const Color(0xFF00C27A).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.celebration, color: Color(0xFF00C27A), size: 64),
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
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
