// ExtractionInProgressScreen — "Currículo recebido! Estamos analisando..."
//
// Mostrada após confirmar upload, enquanto extract-profile roda em background.
// Estratégia:
//   - Habilita Continue quando a extração completar (typical 8-12s)
//   - Timeout máximo de 10s: se a extração não terminar, libera assim mesmo
//     pra não prender o user. Próximas telas ainda escutam o status.
//   - Mensagens rotativas pra dar sensação de progresso e não parecer
//     que a tela está congelada.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../profile/application/extraction_status_view_model.dart';
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
  bool _timeoutReached = false;
  bool _navigated = false;
  bool _autoNavScheduled = false;
  int _messageIndex = 0;

  static const _messages = [
    'Lendo seu currículo…',
    'Identificando suas experiências…',
    'Organizando suas informações…',
    'Quase lá!',
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    // Timeout fallback: se a extração demorar mais que 10s, libera o
    // Continue assim mesmo. Próximas telas (first_name etc) ainda esperam
    // o status completar pra hidratar os campos.
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) setState(() => _timeoutReached = true);
    });

    // Rotaciona mensagens a cada 2.5s pra dar sensação de progresso.
    _rotateMessages();
  }

  void _rotateMessages() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 2500));
      if (!mounted) return;
      // Trava na última mensagem se já chegou no fim
      if (_messageIndex < _messages.length - 1) {
        setState(() => _messageIndex++);
      } else {
        return;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continue() {
    if (_navigated) return;
    _navigated = true;
    // Push regular pra manter AuthGate no fundo do stack (ver comentário
    // similar em upload_preview_sheet.dart).
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AttributionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final extraction = context.watch<ExtractionStatusViewModel>();
    final extractionDone = extraction.status == ExtractionStatus.completed ||
        extraction.status == ExtractionStatus.failed;
    final canContinue = extractionDone || _timeoutReached;

    // Auto-navega assim que a extração completar com sucesso. Pequeno
    // delay (800ms) pra dar tempo do user ver o "Tudo pronto!" antes da
    // tela trocar. _autoNavScheduled previne re-agendamento a cada build,
    // _navigated previne dupla navegação caso user clique Continue antes
    // do delay terminar.
    if (extraction.status == ExtractionStatus.completed && !_autoNavScheduled) {
      _autoNavScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) _continue();
        });
      });
    }

    final isReady = extraction.status == ExtractionStatus.completed;
    final title = isReady ? 'Tudo pronto!' : 'Currículo recebido!';
    final subtitle = isReady
        ? 'Encontramos suas informações.'
        : _messages[_messageIndex];

    return OnboardingScaffold(
      progress: 0.06,
      showBack: false,
      onContinue: canContinue ? _continue : null,
      continueLabel: isReady ? 'Continuar' : 'Aguarde…',
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
                    color: const Color(0xFF29B6D2).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: isReady
                      ? const Icon(
                          Icons.check_circle,
                          color: Color(0xFF29B6D2),
                          size: 64,
                        )
                      : const Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xFF29B6D2),
                          size: 56,
                        ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  subtitle,
                  key: ValueKey(subtitle),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF6B7280), fontSize: 15),
                ),
              ),
              const SizedBox(height: 24),
              if (!isReady)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Color(0xFF29B6D2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
