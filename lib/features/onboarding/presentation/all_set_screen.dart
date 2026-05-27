// AllSetScreen — transição entre as 7 masking questions e as telas de
// revisão (ReviewPersonalInfoScreen + ReviewResumeScreen).
//
// Função: respiro psicológico — "tudo pronto, agora confere se ficou certo".
// Não persiste nada, só navega. Sem dados, sem rede.
//
// Só é exibida no caminho Upload (com CV). No Trail, a AgeRangeScreen
// pula essa tela e vai direto pras preferências — sem CV não há nada
// extraído pra "conferir", então a tela ficaria prometendo algo vazio.

import 'package:flutter/material.dart';
import '../../../services/analytics_service.dart';
import 'onboarding_scaffold.dart';
import 'review_personal_info_screen.dart';

class AllSetScreen extends StatefulWidget {
  const AllSetScreen({super.key});

  @override
  State<AllSetScreen> createState() => _AllSetScreenState();
}

class _AllSetScreenState extends State<AllSetScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    AnalyticsService.shared.track('onboarding_all_set_shown');
    _controller = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _scale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.2, 1.0)),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continue() {
    AnalyticsService.shared.track('onboarding_all_set_continued');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReviewPersonalInfoScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      progress: 0.53,
      showBack: false,
      onContinue: _continue,
      continueLabel: 'Continuar',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              ScaleTransition(
                scale: _scale,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF29B6D2).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: Color(0xFF29B6D2),
                    size: 64,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              FadeTransition(
                opacity: _fade,
                child: const Text(
                  'Tudo pronto!',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              FadeTransition(
                opacity: _fade,
                child: const Text(
                  'Agora é só conferir se ficou tudo certinho.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
