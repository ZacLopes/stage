// ExtractionInProgressScreen — "Currículo recebido! Estamos analisando..."
//
// Mostrada após confirmar upload, enquanto extract-profile roda em background.
// Estratégia:
//   - Habilita Continue quando a extração completar (typical 8-12s)
//   - Timeout máximo de 10s: se a extração não terminar, libera assim mesmo
//     pra não prender o user. Próximas telas ainda escutam o status.
//   - Card de dica rotativo: transforma espera em valor (usuário aprende
//     algo útil sobre currículo enquanto espera).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../profile/application/extraction_status_view_model.dart';
import 'onboarding_scaffold.dart';
import 'masking_questions/attribution_screen.dart';
import '../../../core/theme/theme.dart';

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
  int _tipIndex = 0;

  // Dicas reais voltadas pra audiência entry-level (estagiários/trainees/
  // primeira vaga). Curadas pra: serem acionáveis (user pode aplicar
  // depois), passarem credibilidade (números/comparações concretos) e
  // estarem alinhadas com o que o app ensina (bullets Harvard, CV
  // adaptado por vaga, etc.).
  static const _tips = <_Tip>[
    _Tip(
      icon: '📄',
      text: 'Currículos de 1 página têm 5× mais chance de serem lidos até o fim.',
    ),
    _Tip(
      icon: '✨',
      text: 'Comece cada bullet com verbo de ação: "Liderei", "Implementei", "Criei".',
    ),
    _Tip(
      icon: '📊',
      text: 'Bullets com números marcam mais: "30% de aumento", "200 atendimentos".',
    ),
    _Tip(
      icon: '🎯',
      text: 'Personalize seu CV pra cada vaga — usar palavras-chave da vaga faz '
          'diferença no filtro automático.',
    ),
    _Tip(
      icon: '🔗',
      text: 'LinkedIn atualizado é sua segunda vitrine — 87% dos recrutadores '
          'procuram lá antes da entrevista.',
    ),
    _Tip(
      icon: '📅',
      text: 'Vagas postadas há menos de 3 dias têm 5× mais resposta. Não deixa '
          'pra amanhã quando achar uma boa.',
    ),
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

    // Rotaciona dicas a cada 4s — tempo suficiente pra ler 2 linhas de
    // conforto + pausa visual. Cobre extração de até ~24s (6 dicas × 4s)
    // antes de repetir.
    _rotateTips();
  }

  void _rotateTips() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 4000));
      if (!mounted) return;
      setState(() => _tipIndex = (_tipIndex + 1) % _tips.length);
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

    return OnboardingScaffold(
      progress: 0.06,
      showBack: false,
      onContinue: canContinue ? _continue : null,
      continueLabel: isReady ? 'Continuar' : 'Aguarde…',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                  CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
                ),
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: AppColors.brandCyan.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: isReady
                      ? const Icon(
                          Icons.check_circle,
                          color: AppColors.brandCyan,
                          size: 60,
                        )
                      : const Icon(
                          Icons.auto_awesome_rounded,
                          color: AppColors.brandCyan,
                          size: 52,
                        ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                isReady
                    ? 'Encontramos suas informações.'
                    : 'A IA tá lendo seu currículo…',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
              ),
              const SizedBox(height: 28),
              // Card de dica — só durante o processamento. Quando IA termina,
              // some pra dar foco ao "Tudo pronto!" + auto-navegação.
              if (!isReady) _TipCard(tip: _tips[_tipIndex]),
              if (!isReady) ...[
                const SizedBox(height: 20),
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.brandCyan,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Tip {
  final String icon;
  final String text;
  const _Tip({required this.icon, required this.text});
}

class _TipCard extends StatelessWidget {
  final _Tip tip;
  const _TipCard({required this.tip});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.1),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey(tip.text),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(tip.icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Text(
                  'Dica enquanto a IA trabalha',
                  style: TextStyle(
                    color: AppColors.brandCyan.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tip.text,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textPrimary,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
