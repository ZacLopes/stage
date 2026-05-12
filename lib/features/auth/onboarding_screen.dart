import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/stage_colors.dart';
import '../../services/analytics_service.dart';
import 'auth_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    Analytics.shared.onboardingStepReached(step: 1);
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
      backgroundColor: StageColors.offWhite,
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
                              ? StageColors.brandCyan
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
                      backgroundColor: StageColors.ctaGreen,
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
                          style: GoogleFonts.outfit(
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

  // --- Slide 2: Gamified Resume ---
  Widget _buildSlide2() {
    return _BaseSlide(
      index: 1,
      currentIndex: _currentPage,
      headline: 'Crie seu currículo\njogando',
      subtitle:
          'Responda perguntas simples e a nossa IA\nmonta um CV profissional pra você.',
      illustration: const _ResumeMockup(),
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
                    style: GoogleFonts.outfit(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: StageColors.titleText,
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
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: StageColors.bodyGray,
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
    {'color': StageColors.brandBlue, 'icon': Icons.business},
    {'color': const Color(0xFF1565C0), 'icon': Icons.rocket_launch},
    {'color': const Color(0xFF0D47A1), 'icon': Icons.account_balance},
    {'color': StageColors.brandCyan, 'icon': Icons.flash_on},
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


class _ResumeMockup extends StatelessWidget {
  const _ResumeMockup();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 340,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.grey.withOpacity(0.05), width: 1),
        boxShadow: [
          BoxShadow(
            color: StageColors.brandBlue.withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 10),
          )
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Profile header
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: StageColors.brandCyan.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_rounded, color: StageColors.brandCyan, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 10, width: 90, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(5))),
                    const SizedBox(height: 6),
                    Container(height: 6, width: 50, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(3))),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 32),
          // S-Curved Trail
          Expanded(
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                // Custom Painter for the S-Curve
                SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: CustomPaint(
                    painter: _STrailPainter(),
                  ),
                ),
                
                // Nodes positioned to follow the S-Curve
                // Top Node
                _buildPositionedNode(true, top: 0, left: 60),
                // Mid-Top Node
                _buildPositionedNode(true, top: 45, left: 110),
                // Mid-Bottom Node
                _buildPositionedNode(true, top: 90, left: 55),
                // Final Curriculum Icon
                _buildPositionedNode(false, top: 135, left: 95, isLast: true),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPositionedNode(bool completed, {required double top, required double left, bool isLast = false}) {
    return Positioned(
      top: top,
      left: left,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: completed ? StageColors.ctaGreen : (isLast ? Colors.white : Colors.grey[100]),
          shape: BoxShape.circle,
          border: isLast ? Border.all(color: Colors.grey[200]!, width: 2) : null,
          boxShadow: [
            BoxShadow(
              color: (completed ? StageColors.ctaGreen : Colors.black).withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Icon(
          isLast ? Icons.article_rounded : (completed ? Icons.check_rounded : Icons.lock_rounded),
          color: completed ? Colors.white : (isLast ? StageColors.starGold : Colors.grey[400]),
          size: isLast ? 28 : 22,
        ),
      ),
    );
  }
}

class _STrailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = StageColors.ctaGreen.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    final path = Path();
    
    // Start slightly left
    path.moveTo(size.width * 0.38, 10);
    
    // Draw S-Curve using Bezier (Shortened tops)
    // From Point 1 to 2 (Mid-Top)
    path.cubicTo(
      size.width * 0.40, 20, 
      size.width * 0.65, 30, 
      size.width * 0.60, 65, 
    );
    
    // From Point 2 to 3 (Mid-Bottom)
    path.cubicTo(
      size.width * 0.55, 80, 
      size.width * 0.25, 90, 
      size.width * 0.35, 110, 
    );

    // From Point 3 to End (Curriculum)
    path.cubicTo(
      size.width * 0.40, 130, 
      size.width * 0.55, 140, 
      size.width * 0.53, 160, 
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
    {'label': 'Tecnologia', 'icon': Icons.computer_rounded, 'color': StageColors.brandBlue},
    {'label': 'Saúde', 'icon': Icons.medical_services_rounded, 'color': const Color(0xFFE91E63)},
    {'label': 'Jurídico', 'icon': Icons.gavel_rounded, 'color': const Color(0xFF607D8B)},
    {'label': 'Logística', 'icon': Icons.local_shipping_rounded, 'color': const Color(0xFFF57C00)},
  ];

  final List<Map<String, dynamic>> _row2 = [
    {'label': 'Design', 'icon': Icons.palette_rounded, 'color': const Color(0xFF9C27B0)},
    {'label': 'Finanças', 'icon': Icons.account_balance_rounded, 'color': StageColors.ctaGreen},
    {'label': 'Engenharia', 'icon': Icons.engineering_rounded, 'color': const Color(0xFF795548)},
    {'label': 'Vendas', 'icon': Icons.storefront_rounded, 'color': const Color(0xFF2196F3)},
  ];

  final List<Map<String, dynamic>> _row3 = [
    {'label': 'Marketing', 'icon': Icons.campaign_rounded, 'color': const Color(0xFF00BCD4)},
    {'label': 'Educação', 'icon': Icons.school_rounded, 'color': const Color(0xFFFFC107)},
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
                border: Border.all(color: StageColors.brandBlue.withOpacity(0.1), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: StageColors.brandBlue.withOpacity(0.15),
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
                      gradient: StageColors.brandGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: StageColors.brandCyan.withOpacity(0.4),
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
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[500],
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Todos os Setores',
                        style: GoogleFonts.outfit(
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
            style: GoogleFonts.inter(
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


