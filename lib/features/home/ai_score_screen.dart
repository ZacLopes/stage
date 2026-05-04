import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;

import '../../core/constants/stage_colors.dart';
import '../auth/user_viewmodel.dart';
import '../profile/profile_viewmodel.dart';
import '../../services/ai_service.dart';
import '../../data/models/models.dart';
import 'home_screen.dart';
import 'home_viewmodel.dart';
import 'resume_improvement_chat_screen.dart';

/// Tela de análise do CV importado pelo usuário.
///
/// Recebe o texto extraído do PDF (`resumeText`), os bytes originais
/// (`pdfBytes`) e o cargo-alvo (`targetJobTitle`). Mostra um score
/// contextualizado e oferece 3 caminhos: Aplicar / Melhorar / Trilha,
/// cada um abre uma tab específica da Home (Vagas / Currículo / Trilha).
///
/// IMPORTANTE: a navegação para a Home é feita pela própria tela usando
/// seu próprio context. Não usar callbacks definidos em telas que foram
/// removidas via `pushReplacement` (ex: CompletionScreen) — o `mounted`
/// dessas telas é false quando o callback dispara, fazendo a navegação
/// falhar silenciosamente.
class AIScoreScreen extends StatefulWidget {
  final String resumeText;
  final Uint8List? pdfBytes;
  final String? targetJobTitle;

  /// Tab da Home a abrir após "Aplicar com este currículo" (default: Vagas = 0).
  final int applyDestinationTab;

  /// Tab da Home a abrir após o chat de melhoria (default: Currículo = 2).
  final int improveDestinationTab;

  /// Tab da Home a abrir após "Construir do zero" (default: Trilha = 1).
  final int buildDestinationTab;

  const AIScoreScreen({
    super.key,
    required this.resumeText,
    this.pdfBytes,
    this.targetJobTitle,
    this.applyDestinationTab = 0,
    this.improveDestinationTab = 2,
    this.buildDestinationTab = 1,
  });

  @override
  State<AIScoreScreen> createState() => _AIScoreScreenState();
}

class _AIScoreScreenState extends State<AIScoreScreen> with TickerProviderStateMixin {
  bool _isLoading = true;
  bool _isFinalizing = false;
  String? _errorMessage;

  late AnimationController _gaugeController;
  late Animation<double> _scoreAnimation;
  late AnimationController _listController;

  ResumeAnalysisResult? _result;

  @override
  void initState() {
    super.initState();
    _gaugeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));
    _scoreAnimation = Tween<double>(begin: 0, end: 0).animate(CurvedAnimation(
        parent: _gaugeController, curve: Curves.easeOutQuart));

    _listController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));

    _analyzeResume();
  }

  @override
  void dispose() {
    _gaugeController.dispose();
    _listController.dispose();
    super.dispose();
  }

  Future<void> _analyzeResume() async {
    try {
      final aiService = AIService();
      final result = await aiService.evaluateResume(
        widget.resumeText,
        targetJobTitle: widget.targetJobTitle,
      );

      if (!mounted) return;

      setState(() {
        _result = result;
        _isLoading = false;
        _errorMessage = null;
        _scoreAnimation =
            Tween<double>(begin: 0, end: result.score.toDouble()).animate(
          CurvedAnimation(parent: _gaugeController, curve: Curves.easeOutQuart),
        );
      });

      _gaugeController.forward();
      _listController.forward();
    } on ResumeEvaluationException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Falha inesperada na análise: $e';
      });
    }
  }

  /// Salva o PDF na biblioteca + propaga dados parseados pro perfil, depois
  /// navega pra Home na tab pedida.
  /// Não bloqueia em falha de persistência — usuário ainda vai pra Home (a
  /// análise local é o que importa).
  Future<void> _persistAndGo(int destinationTab) async {
    if (_isFinalizing) return;
    setState(() => _isFinalizing = true);

    try {
      if (widget.pdfBytes != null) {
        try {
          final dt = DateTime.now();
          await context.read<ProfileViewModel>().saveResume(
                'Currículo importado (${dt.day}/${dt.month})',
                widget.pdfBytes!,
              );
        } catch (e) {
          debugPrint('Falha ao salvar CV na biblioteca: $e');
        }
      }

      final parsed = _result?.parsedData;
      if (parsed != null && mounted) {
        try {
          final userVM = context.read<UserViewModel>();
          final currentData =
              Map<String, dynamic>.from(userVM.user?.gamificationData ?? {});

          currentData['imported_resume'] = {
            'sobre_mim': parsed.aboutMe,
            'skills': parsed.skills,
            'experiences': parsed.experiences,
            'interests': parsed.interests,
            'imported_at': DateTime.now().toIso8601String(),
          };

          currentData['whoIAm'] = {
            'derived': {
              'summary': parsed.aboutMe,
              'skills': parsed.skills,
              'interests': parsed.interests,
            },
            'last_updated': DateTime.now().toIso8601String(),
          };

          await userVM.updateProfile(gamificationData: currentData);
        } catch (e) {
          debugPrint('Falha ao propagar dados do CV pro perfil: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _isFinalizing = false);
    }

    if (!mounted) return;
    _goHome(destinationTab);
  }

  void _goHome(int tabIndex) {
    context.read<HomeViewModel>().requestTabChange(tabIndex);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  void _handleApplyWithCurrent() {
    _persistAndGo(widget.applyDestinationTab);
  }

  void _handleImproveWithAI() {
    if (_result == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResumeImprovementChatScreen(
          resumeText: widget.resumeText,
          pdfBytes: widget.pdfBytes?.toList(),
          analysis: _result!,
          onFinish: () => _persistAndGo(widget.improveDestinationTab),
        ),
      ),
    );
  }

  void _handleBuildFromScratch() {
    _persistAndGo(widget.buildDestinationTab);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _AnalysisLoadingView();
    }
    if (_errorMessage != null) {
      return _ErrorView(
        message: _errorMessage!,
        onRetry: () {
          setState(() {
            _isLoading = true;
            _errorMessage = null;
          });
          _analyzeResume();
        },
        onAbort: () => _goHome(widget.buildDestinationTab),
      );
    }

    final score = _result?.score ?? 0;
    final color = score >= 80
        ? const Color(0xFF10B981)
        : (score >= 60 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 360,
                pinned: true,
                backgroundColor: Colors.white,
                elevation: 0,
                automaticallyImplyLeading: false,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    color: Colors.white,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 60),
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            AnimatedBuilder(
                              animation: _scoreAnimation,
                              builder: (context, child) {
                                return CustomPaint(
                                  size: const Size(200, 200),
                                  painter: _GaugePainter(
                                    progress: _scoreAnimation.value / 100,
                                    color: color,
                                    backgroundColor: color.withOpacity(0.1),
                                  ),
                                );
                              },
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedBuilder(
                                  animation: _scoreAnimation,
                                  builder: (context, child) {
                                    return Text(
                                      '${_scoreAnimation.value.toInt()}',
                                      style: GoogleFonts.outfit(
                                          fontSize: 72,
                                          fontWeight: FontWeight.bold,
                                          color: color,
                                          height: 1),
                                    );
                                  },
                                ),
                                Text(
                                  widget.targetJobTitle != null
                                      ? 'Aderência'
                                      : 'Score IA',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: StageColors.bodyGray,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (widget.targetJobTitle != null) ...[
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              'em "${widget.targetJobTitle}"',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: StageColors.subtitleGray,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 140),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Análise Detalhada',
                        style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: StageColors.titleText),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.targetJobTitle != null
                            ? 'Comparamos seu currículo com o perfil esperado para essa vaga.'
                            : 'Identificamos pontos cruciais para alavancar seu perfil.',
                        style: GoogleFonts.inter(
                            fontSize: 16, color: StageColors.bodyGray),
                      ),
                      const SizedBox(height: 32),
                      _buildAnalysisSection(
                        title: 'Pontos Fortes',
                        items: _result?.strengths ?? [],
                        icon: Icons.check_circle_rounded,
                        color: const Color(0xFF10B981),
                        delay: 0,
                      ),
                      const SizedBox(height: 24),
                      _buildAnalysisSection(
                        title: 'A Melhorar',
                        items: _result?.weaknesses ?? [],
                        icon: Icons.error_rounded,
                        color: const Color(0xFFF59E0B),
                        delay: 0.2,
                      ),
                      const SizedBox(height: 36),
                      Text(
                        'O que você quer fazer agora?',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: StageColors.titleText,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _ChoiceActionCard(
                        title: 'Aplicar com este currículo',
                        description:
                            'Salvamos seu PDF e te levamos direto pra aba Vagas.',
                        icon: Icons.rocket_launch_rounded,
                        color: const Color(0xFF10B981),
                        onTap: _isFinalizing ? null : _handleApplyWithCurrent,
                        isPrimary: true,
                      ),
                      const SizedBox(height: 12),
                      _ChoiceActionCard(
                        title: 'Melhorar com IA antes',
                        description:
                            'Chat rápido pra reescrever os pontos fracos. Depois você decide se aplica.',
                        icon: Icons.auto_awesome_rounded,
                        color: StageColors.brandBlue,
                        onTap: _isFinalizing ? null : _handleImproveWithAI,
                      ),
                      const SizedBox(height: 12),
                      _ChoiceActionCard(
                        title: 'Construir do zero pela trilha',
                        description:
                            'Já temos seus dados — a trilha vai te guiar pra um CV mais forte.',
                        icon: Icons.map_rounded,
                        color: const Color(0xFF6366F1),
                        onTap: _isFinalizing ? null : _handleBuildFromScratch,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_isFinalizing)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(color: StageColors.brandBlue),
            ),
          ),
      ],
    );
  }

  Widget _buildAnalysisSection({
    required String title,
    required List<String> items,
    required IconData icon,
    required Color color,
    required double delay,
  }) {
    return FadeTransition(
      opacity: CurvedAnimation(
          parent: _listController,
          curve: Interval(delay, 1.0, curve: Curves.easeOut)),
      child: SlideTransition(
        position: Tween<Offset>(
                begin: const Offset(0, 0.1), end: Offset.zero)
            .animate(CurvedAnimation(
                parent: _listController,
                curve: Interval(delay, 1.0, curve: Curves.easeOut))),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey.withOpacity(0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.1), shape: BoxShape.circle),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(title,
                      style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: StageColors.titleText)),
                ],
              ),
              const SizedBox(height: 16),
              ...items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(item,
                                style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: StageColors.bodyGray,
                                    height: 1.5))),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceActionCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool isPrimary;

  const _ChoiceActionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: color.withOpacity(isPrimary ? 0.5 : 0.3),
                width: isPrimary ? 2 : 1.5),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(isPrimary ? 0.12 : 0.05),
                blurRadius: isPrimary ? 22 : 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: StageColors.titleText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: StageColors.bodyGray,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.grey[400], size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;

  _GaugePainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 16.0;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    const startAngle = 135 * (math.pi / 180);
    const sweepAngle = 270 * (math.pi / 180);

    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle,
        sweepAngle, false, bgPaint);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle,
        sweepAngle * progress, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onAbort;

  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onAbort,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline,
                    color: Color(0xFFEF4444), size: 36),
              ),
              const SizedBox(height: 20),
              Text(
                'Não conseguimos analisar seu CV',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: StageColors.titleText,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: StageColors.bodyGray,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StageColors.brandBlue,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    'Tentar de novo',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onAbort,
                child: Text(
                  'Pular análise e ir para a trilha',
                  style: GoogleFonts.inter(
                    color: StageColors.subtitleGray,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalysisLoadingView extends StatefulWidget {
  @override
  State<_AnalysisLoadingView> createState() => _AnalysisLoadingViewState();
}

class _AnalysisLoadingViewState extends State<_AnalysisLoadingView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _currentStep = 0;
  final List<String> _steps = [
    'Lendo texto do PDF...',
    'Identificando competências...',
    'Comparando com a vaga-alvo...',
    'Calculando aderência...',
    'Gerando dicas de melhoria...',
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _startSteps();
  }

  void _startSteps() async {
    for (int i = 0; i < _steps.length; i++) {
      if (!mounted) return;
      setState(() => _currentStep = i);
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: StageColors.brandBlue.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.description_outlined,
                      size: 50, color: StageColors.brandBlue),
                ),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, -40 + (80 * _controller.value)),
                      child: Container(
                        width: 100,
                        height: 3,
                        decoration: BoxDecoration(
                          color: StageColors.brandBlue,
                          boxShadow: [
                            BoxShadow(
                              color: StageColors.brandBlue.withOpacity(0.5),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 60),
            Text(
              'Raio-X em andamento...',
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: StageColors.titleText,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Column(
              children: List.generate(_steps.length, (index) {
                final isActive = index == _currentStep;
                final isDone = index < _currentStep;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: isActive || isDone ? 1.0 : 0.3,
                    child: Row(
                      children: [
                        Icon(
                          isDone
                              ? Icons.check_circle
                              : (isActive ? Icons.sync : Icons.circle_outlined),
                          size: 18,
                          color: isDone
                              ? const Color(0xFF10B981)
                              : (isActive
                                  ? StageColors.brandBlue
                                  : Colors.grey),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _steps[index],
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isActive
                                  ? StageColors.titleText
                                  : StageColors.bodyGray,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
