import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../core/analytics/screen_tracking.dart';

import '../../services/analytics_service.dart';
import 'auth_screen.dart';
import '../../core/theme/theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with ScreenTrackingMixin {
  @override
  String get screenName => 'onboarding_intro';

  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    Analytics.shared.onboardingStepReached(step: 1, stepId: 'onboarding_intro');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    } else {
      _navigateToAuth();
    }
  }

  void _skipOnboarding() {
    _navigateToAuth();
  }

  void _navigateToAuth() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const AuthScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceVariant,
      body: SafeArea(
        child: Stack(
          children: [
            // PageView
            PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() => _currentPage = index);
              },
              children: [
                _buildSlide1(),
                _buildSlide2(),
                _buildSlide3(),
              ],
            ),

            // Removed Top Right: Skip Button

            // Bottom Navigation
            Positioned(
              bottom: 32,
              left: 24,
              right: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Indicators
                  Row(
                    children: List.generate(
                      3,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.only(right: 8),
                        height: 8,
                        width: _currentPage == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? AppColors.brandCyan
                              : Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),

                  // Next / Start Button
                  ElevatedButton(
                    onPressed: _nextPage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _currentPage == 2 ? 'Começar' : 'Próximo',
                          style: TextStyle(fontFamily: 'Outfit', 
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_currentPage != 2) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 20),
                        ]
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Slide 1: Swipe Mechanics ---
  Widget _buildSlide1() {
    return _BaseSlide(
      index: 0,
      currentIndex: _currentPage,
      headline: 'Encontre oportunidades\ncom um swipe',
      subtitle: 'Sem formulários intermináveis. Deslize,\naplique e pronto.',
      illustration: const _SwipeMockup(),
    );
  }

  // --- Slide 2: AI Agent ---
  Widget _buildSlide2() {
    return _BaseSlide(
      index: 1,
      currentIndex: _currentPage,
      headline: 'Um agente de IA\nmonta seu currículo',
      subtitle:
          'É só conversar. Ele pergunta o essencial\ne preenche seu perfil pra você.',
      illustration: const _AgentMockup(),
    );
  }

  // --- Slide 3: Real Companies ---
  Widget _buildSlide3() {
    return _BaseSlide(
      index: 2,
      currentIndex: _currentPage,
      headline: 'Match perfeito com\no seu futuro',
      subtitle:
          'Todos os tipos de vagas\nnas melhores empresas do Brasil.',
      illustration: const _CompaniesMockup(),
    );
  }
}

// ==========================================
// Base Slide Layout
// ==========================================
class _BaseSlide extends StatefulWidget {
  final int index;
  final int currentIndex;
  final String headline;
  final String subtitle;
  final Widget illustration;

  const _BaseSlide({
    required this.index,
    required this.currentIndex,
    required this.headline,
    required this.subtitle,
    required this.illustration,
  });

  @override
  State<_BaseSlide> createState() => _BaseSlideState();
}

class _BaseSlideState extends State<_BaseSlide>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeIll;
  late Animation<double> _fadeHead;
  late Animation<double> _fadeSub;
  late Animation<Offset> _slideIll;
  late Animation<Offset> _slideHead;
  late Animation<Offset> _slideSub;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Staggered fades
    _fadeIll = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
        parent: _animController, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)));
    _fadeHead = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
        parent: _animController, curve: const Interval(0.2, 0.8, curve: Curves.easeOut)));
    _fadeSub = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
        parent: _animController, curve: const Interval(0.4, 1.0, curve: Curves.easeOut)));

    // Staggered slides
    _slideIll = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
        CurvedAnimation(parent: _animController, curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic)));
    _slideHead = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
        CurvedAnimation(parent: _animController, curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic)));
    _slideSub = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
        CurvedAnimation(parent: _animController, curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic)));

    if (widget.index == widget.currentIndex) {
      _animController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _BaseSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == widget.currentIndex &&
        oldWidget.currentIndex != widget.index) {
      _animController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Top ~60% for illustration
          Expanded(
            flex: 6,
            child: Center(
              child: AnimatedBuilder(
                animation: _animController,
                builder: (context, child) => Opacity(
                  opacity: _fadeIll.value,
                  child: SlideTransition(
                    position: _slideIll,
                    child: child,
                  ),
                ),
                child: widget.illustration,
              ),
            ),
          ),
          
          // Bottom ~40% for text
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                AnimatedBuilder(
                  animation: _animController,
                  builder: (context, child) => Opacity(
                    opacity: _fadeHead.value,
                    child: SlideTransition(
                      position: _slideHead,
                      child: child,
                    ),
                  ),
                  child: Text(
                    widget.headline,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Outfit', 
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AnimatedBuilder(
                  animation: _animController,
                  builder: (context, child) => Opacity(
                    opacity: _fadeSub.value,
                    child: SlideTransition(
                      position: _slideSub,
                      child: child,
                    ),
                  ),
                  child: Text(
                    widget.subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Inter', 
                      fontSize: 16,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// MOCKUPS (Flutter UI representations)
// ==========================================

class _SwipeMockup extends StatefulWidget {
  const _SwipeMockup();

  @override
  State<_SwipeMockup> createState() => _SwipeMockupState();
}

class _SwipeMockupState extends State<_SwipeMockup>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  final List<Map<String, dynamic>> _mockJobs = [
    {'color': AppColors.brandBlue, 'icon': Icons.business},
    {'color': const Color(0xFF1565C0), 'icon': Icons.rocket_launch},
    {'color': const Color(0xFF0D47A1), 'icon': Icons.account_balance},
    {'color': AppColors.brandCyan, 'icon': Icons.flash_on},
    {'color': const Color(0xFFFF9800), 'icon': Icons.work_outline},
    {'color': const Color(0xFF673AB7), 'icon': Icons.location_on_outlined},
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Shift data: Move top card to back
        if (mounted) {
          setState(() {
            var first = _mockJobs.removeAt(0);
            _mockJobs.add(first);
          });
          _animController.reset();
          // Short pause between swipes
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) _animController.forward();
          });
        }
      }
    });

    // Start
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _animController.forward();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 380,
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          final progress = Curves.easeInOutCubic.transform(_animController.value);

          return Stack(
            alignment: Alignment.center,
            children: [
              // 3. Card emerging from back (fading in + scaling up)
              _buildStackCard(2, progress),
              
              // 2. Card scaling up to front
              _buildStackCard(1, progress),
              
              // 1. Top Card swiping out
              _buildStackCard(0, progress),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStackCard(int index, double progress) {
    final job = _mockJobs[index];
    double scale = 1.0;
    double opacity = 1.0;
    double dx = 0.0;
    double dy = 0.0;
    double rotation = 0.0;

    if (index == 0) {
      // Swipe out logic
      dx = progress * 350;
      dy = -progress * 20;
      rotation = progress * 0.4;
      opacity = 1.0 - (progress * 1.5).clamp(0.0, 1.0);
    } else if (index == 1) {
      // Scale from background to foreground
      // State at 1.0 is exactly state of index 0 at 0.0
      scale = 0.9 + (progress * 0.1);
      dy = 20 - (progress * 20);
    } else if (index == 2) {
      // Fade in from deep back
      // State at 1.0 is exactly state of index 1 at 0.0
      scale = 0.8 + (progress * 0.1);
      dy = 40 - (progress * 20);
      opacity = progress; 
    }

    return Transform.translate(
      offset: Offset(dx, dy),
      child: Transform.rotate(
        angle: rotation,
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: _buildCardContent(job['color'], job['icon']),
          ),
        ),
      ),
    );
  }

  Widget _buildCardContent(Color color, IconData icon) {
    return Container(
      width: 250,
      height: 350,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 10),
          )
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const Spacer(),
          Container(height: 20, width: 140, decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 8),
          Container(height: 14, width: 80, decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 24),
          Row(
            children: [
              Container(height: 24, width: 60, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12))),
              const SizedBox(width: 8),
              Container(height: 24, width: 60, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12))),
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// Slide 2 — Agente de IA (animação)
// ==========================================
// Ecoa o assistente REAL da trilha: avatar sparkle no gradiente da marca
// (Icons.auto_awesome_rounded), bolha branca da IA + bolha azul do usuário,
// pontinhos ondulando. Um orb "vivo" (aura em anéis + sparkles) conduz uma
// micro-conversa orquestrada onde o agente PREENCHE o perfil — em loop suave.
class _AgentMockup extends StatefulWidget {
  const _AgentMockup();

  @override
  State<_AgentMockup> createState() => _AgentMockupState();
}

class _AgentMockupState extends State<_AgentMockup>
    with TickerProviderStateMixin {
  // Aura/respiração do orb + onda dos pontinhos + brilho dos sparkles: contínuo.
  late final AnimationController _aura;
  // Linha do tempo da conversa: bolha do user -> digitando -> resposta -> chip.
  late final AnimationController _loop;

  @override
  void initState() {
    super.initState();
    _aura = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6400),
    )..repeat();
  }

  @override
  void dispose() {
    _aura.dispose();
    _loop.dispose();
    super.dispose();
  }

  // Envelope trapezoidal: 0 antes de [a], sobe até 1 em [b], segura, cai a 0 em
  // [d] (a partir de [c]). Deixa o loop "respirar" sem snap no reinício.
  double _env(double t, double a, double b, double c, double d) {
    if (t <= a || t >= d) return 0;
    if (t < b) return Curves.easeOut.transform((t - a) / (b - a));
    if (t > c) return 1 - Curves.easeIn.transform((t - c) / (d - c));
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      height: 372,
      child: Column(
        children: [
          // -- Orb de IA vivo -------------------------------------------------
          SizedBox(
            width: 300,
            height: 150,
            child: AnimatedBuilder(
              animation: _aura,
              builder: (context, _) => _orb(_aura.value),
            ),
          ),
          const SizedBox(height: 14),
          // -- Micro-conversa -------------------------------------------------
          Expanded(
            child: AnimatedBuilder(
              animation: Listenable.merge([_loop, _aura]),
              builder: (context, _) => _conversation(_loop.value, _aura.value),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Orb ----
  Widget _orb(double a) {
    final breathe = 1.0 + 0.05 * math.sin(a * 2 * math.pi);
    final glow = 0.28 + 0.18 * ((math.sin(a * 2 * math.pi) + 1) / 2);
    return Stack(
      alignment: Alignment.center,
      children: [
        // Anéis de aura expandindo (radar suave).
        Positioned.fill(child: CustomPaint(painter: _AuraRingsPainter(a))),
        // Sparkles flutuando ao redor.
        ..._sparkles(a),
        // Disco do agente (avatar real: gradiente brand + auto_awesome).
        Transform.scale(
          scale: breathe,
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              gradient: AppGradients.brand,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandCyan.withValues(alpha: glow),
                  blurRadius: 26,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: AppColors.brandBlue.withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.onPrimary,
              size: 38,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _sparkles(double a) {
    final specs = <List<Object>>[
      [const Offset(-90, -34), 13.0, 0.0],
      [const Offset(92, -20), 11.0, 0.35],
      [const Offset(72, 40), 15.0, 0.6],
      [const Offset(-78, 42), 10.0, 0.85],
    ];
    return [
      for (final s in specs)
        _oneSparkle(a, s[0] as Offset, s[1] as double, s[2] as double),
    ];
  }

  Widget _oneSparkle(double a, Offset off, double size, double phase) {
    final tw = (math.sin((a + phase) * 2 * math.pi) + 1) / 2;
    return Transform.translate(
      offset: off,
      child: Opacity(
        opacity: (0.22 + 0.6 * tw).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.7 + 0.4 * tw,
          child: Icon(
            Icons.auto_awesome,
            size: size,
            color: phase > 0.5 ? AppColors.brandCyan : AppColors.gold,
          ),
        ),
      ),
    );
  }

  // ---- Conversa ----
  Widget _conversation(double t, double a) {
    final userIn = _env(t, 0.04, 0.16, 0.90, 0.99);
    final typingIn = _env(t, 0.22, 0.30, 0.40, 0.46);
    final replyIn = _env(t, 0.44, 0.54, 0.90, 0.99);
    final chipIn = _env(t, 0.58, 0.70, 0.90, 0.99);
    final burst = _env(t, 0.58, 0.66, 0.72, 0.82);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        // Bolha do usuário (direita).
        _fadeSlide(
          userIn,
          const Offset(22, 0),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [_userBubble('Fiz um estágio em Finanças')],
          ),
        ),
        const SizedBox(height: 10),
        // Digitando OU resposta (esquerda, com avatar mini).
        SizedBox(
          height: 62,
          child: Stack(
            children: [
              _fadeSlide(
                typingIn,
                const Offset(-18, 0),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _agentBubble(child: _dots(a)),
                ),
              ),
              _fadeSlide(
                replyIn,
                const Offset(-18, 0),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _agentBubble(
                    child: _replyText('Boa! Já adicionei ao seu perfil ✨'),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Chip preenchendo o perfil (payoff).
        _profileStrip(chipIn, burst),
      ],
    );
  }

  Widget _fadeSlide(double v, Offset from, Widget child) {
    return Opacity(
      opacity: v.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(from.dx * (1 - v), from.dy * (1 - v)),
        child: child,
      ),
    );
  }

  Widget _miniAvatar() {
    return Container(
      width: 30,
      height: 30,
      decoration: const BoxDecoration(
        gradient: AppGradients.brand,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.auto_awesome_rounded,
          color: AppColors.onPrimary, size: 16),
    );
  }

  Widget _agentBubble({required Widget child}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _miniAvatar(),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 208),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandBlue.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ],
    );
  }

  Widget _userBubble(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(6),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: AppColors.onPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _replyText(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w500,
        height: 1.3,
      ),
    );
  }

  Widget _dots(double a) {
    return SizedBox(
      height: 8,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase = (a + i * 0.18) % 1.0;
          final wave = (math.sin(phase * 2 * math.pi) + 1) / 2;
          return Padding(
            padding: EdgeInsets.only(right: i < 2 ? 5 : 0),
            child: Opacity(
              opacity: (0.4 + 0.6 * wave).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.7 + 0.3 * wave,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.textTertiary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _profileStrip(double chipIn, double burst) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              color: AppColors.successSoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.check_rounded,
                color: AppColors.success, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'SEU PERFIL',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _chip('Finanças', filled: true),
                    const SizedBox(width: 6),
                    // Chip que "entra" (payoff) com um estouro de sparkle.
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        if (burst > 0)
                          Opacity(
                            opacity: ((1 - burst) * 0.9).clamp(0.0, 1.0),
                            child: Transform.scale(
                              scale: 0.6 + burst * 1.4,
                              child: const Icon(Icons.auto_awesome,
                                  color: AppColors.brandCyan, size: 26),
                            ),
                          ),
                        Opacity(
                          opacity: chipIn.clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: 0.6 + 0.4 * chipIn,
                            child: _chip('Estágio', filled: false),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, {required bool filled}) {
    final bg = filled
        ? AppColors.primary.withValues(alpha: 0.10)
        : AppColors.brandCyan.withValues(alpha: 0.14);
    final fg = filled ? AppColors.primary : AppColors.brandBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _AuraRingsPainter extends CustomPainter {
  final double t;
  _AuraRingsPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const baseR = 37.0;
    final maxExpand = size.shortestSide / 2 - baseR + 8;
    const rings = 3;
    for (var i = 0; i < rings; i++) {
      final p = (t + i / rings) % 1.0;
      final r = baseR + p * maxExpand;
      final opacity = (1 - p) * 0.30;
      if (opacity <= 0.01) continue;
      final paint = Paint()
        ..color = AppColors.brandCyan.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * (1 - p) + 0.5;
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuraRingsPainter oldDelegate) =>
      oldDelegate.t != t;
}

class _CompaniesMockup extends StatefulWidget {
  const _CompaniesMockup();

  @override
  State<_CompaniesMockup> createState() => _CompaniesMockupState();
}

class _CompaniesMockupState extends State<_CompaniesMockup>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  final List<Map<String, dynamic>> _row1 = [
    {'label': 'Tecnologia', 'icon': Icons.computer_rounded, 'color': AppColors.brandBlue},
    {'label': 'Saúde', 'icon': Icons.medical_services_rounded, 'color': const Color(0xFFE91E63)},
    {'label': 'Jurídico', 'icon': Icons.gavel_rounded, 'color': const Color(0xFF607D8B)},
    {'label': 'Logística', 'icon': Icons.local_shipping_rounded, 'color': const Color(0xFFF57C00)},
  ];

  final List<Map<String, dynamic>> _row2 = [
    {'label': 'Design', 'icon': Icons.palette_rounded, 'color': const Color(0xFF9C27B0)},
    {'label': 'Finanças', 'icon': Icons.account_balance_rounded, 'color': AppColors.primary},
    {'label': 'Engenharia', 'icon': Icons.engineering_rounded, 'color': const Color(0xFF795548)},
    {'label': 'Vendas', 'icon': Icons.storefront_rounded, 'color': const Color(0xFF2196F3)},
  ];

  final List<Map<String, dynamic>> _row3 = [
    {'label': 'Marketing', 'icon': Icons.campaign_rounded, 'color': const Color(0xFF00BCD4)},
    {'label': 'Educação', 'icon': Icons.school_rounded, 'color': AppColors.warning},
    {'label': 'Agronegócio', 'icon': Icons.eco_rounded, 'color': const Color(0xFF4CAF50)},
    {'label': 'RH', 'icon': Icons.people_rounded, 'color': const Color(0xFF673AB7)},
  ];

  @override
  void initState() {
    super.initState();
    // 60-second duration ensures extremely smooth, slow movement
    // that won't show a loop snap during the user's brief stay on this screen.
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    return Container(
      width: 340,
      height: 280,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(), // No background, border, or shadow! 
      child: Stack(
        children: [
          // Row 1 - Moves Left
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: _buildMarqueeRow(_row1, 1.0),
          ),
          
          // Row 2 - Moves Right (faster)
          Positioned(
            top: 90,
            left: 0,
            right: 0,
            child: _buildMarqueeRow(_row2, -1.3),
          ),
          
          // Row 3 - Moves Left (slow)
          Positioned(
            top: 160,
            left: 0,
            right: 0,
            child: _buildMarqueeRow(_row3, 0.7),
          ),
          
          // Edges Mask for smooth fade-in/out matching exactly the scaffold background
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    bgColor,
                    bgColor.withOpacity(0.0),
                    bgColor.withOpacity(0.0),
                    bgColor,
                  ],
                  stops: const [0.0, 0.15, 0.85, 1.0],
                ),
              ),
            ),
          ),
          
          // The Premium Center Focus Card (Now smaller and horizontal)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(100), // Pill shape
                border: Border.all(color: AppColors.brandBlue.withOpacity(0.1), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandBlue.withOpacity(0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: AppGradients.brand,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brandCyan.withOpacity(0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ]
                    ),
                    child: const Icon(Icons.explore_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CARREIRAS EM',
                        style: TextStyle(fontFamily: 'Inter', 
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textTertiary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Todos os Setores',
                        style: TextStyle(fontFamily: 'Outfit', 
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF1D1B20),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8), // Extra right padding for balance
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMarqueeRow(List<Map<String, dynamic>> items, double speedMulti) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        // Safe middle ground for infinite-feeling 60s movement
        const double baseOffset = 4000.0; 
        final double translation = _animController.value * 2000 * speedMulti;
        
        return Transform.translate(
          offset: Offset(-baseOffset - translation, 0),
          child: SizedBox(
            height: 60,
            child: OverflowBox(
              maxWidth: double.infinity,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(80, (index) {
                  return _buildPill(items[index % items.length]);
                }),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPill(Map<String, dynamic> item) {
    final Color color = item['color'];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.only(left: 10, right: 18, top: 10, bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(100), // Perfect pill shape
        border: Border.all(color: color.withOpacity(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(item['icon'], color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            item['label'],
            style: TextStyle(fontFamily: 'Inter', 
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: const Color(0xFF333333),
            ),
          ),
        ],
      ),
    );
  }
}
