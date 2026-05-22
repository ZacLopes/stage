// ExtractionInProgressScreen — "Currículo recebido! Estamos analisando..."
//
// Mostrada após confirmar upload, enquanto extract-profile roda em background.
// Mínimo de 2s exibida pra reforçar percepção de progresso. Após user tocar
// Continue, navega pras 7 perguntas mascarando latência.

import 'package:flutter/material.dart';
import 'onboarding_scaffold.dart';
import 'masking_questions/attribution_screen.dart';

class ExtractionInProgressScreen extends StatefulWidget {
  const ExtractionInProgressScreen({super.key});

  @override
  State<ExtractionInProgressScreen> createState() => _ExtractionInProgressScreenState();
}

class _ExtractionInProgressScreenState extends State<ExtractionInProgressScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _canContinue = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    // Mínimo 2s exibida
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _canContinue = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continue() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AttributionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      progress: 0.06,
      showBack: false,
      onContinue: _canContinue ? _continue : null,
      continueLabel: 'Continuar',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                  CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
                ),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C27A).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: Color(0xFF00C27A),
                    size: 64,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Currículo recebido!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Estamos analisando enquanto você continua.',
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
