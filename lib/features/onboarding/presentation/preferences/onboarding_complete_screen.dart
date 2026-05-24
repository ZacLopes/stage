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
import '../../../splash/splash_screen.dart';
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

    final userVm = context.read<UserViewModel>();
    debugPrint('[OnboardingCompleteScreen] before createCampaign: hasCampaign=${userVm.hasCampaign}');

    // Cria campaign skipped — mesma técnica da CompletionScreen legacy.
    // Sem isso, AuthGate não detecta hasCampaign=true e fica em loop.
    bool campaignOk = false;
    try {
      await userVm.createCampaign(isSkipped: true);
      campaignOk = userVm.hasCampaign;
      debugPrint('[OnboardingCompleteScreen] after createCampaign: hasCampaign=$campaignOk');
    } catch (e) {
      debugPrint('[OnboardingCompleteScreen] createCampaign FAILED: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao finalizar: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
        setState(() => _finishing = false);
      }
      return;
    }

    if (!mounted) return;
    Analytics.shared.onboardingCompleted();

    if (!campaignOk) {
      // Defensiva: se createCampaign rodou sem exception mas hasCampaign ficou false,
      // não fecha o stack pra evitar loop. Mostra erro pro user.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível finalizar. Tenta novamente.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      setState(() => _finishing = false);
      return;
    }

    if (widget.onFinish != null) {
      widget.onFinish!();
    } else {
      // pushAndRemoveUntil(AuthGate, false): força AuthGate como única rota
      // na stack, ignorando o histórico. Necessário porque algumas telas do
      // auth flow usam pushReplacement antes de chegar aqui (ex:
      // profile_setup_screen → TwoDoors), o que remove AuthGate da stack.
      // popUntil isFirst nessas situações cai numa tela do onboarding em
      // vez de AuthGate → loop. Reset explícito resolve.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
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
                  color: const Color(0xFF29B6D2).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.celebration, color: Color(0xFF29B6D2), size: 64),
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
