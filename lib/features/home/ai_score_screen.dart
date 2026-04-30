import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;

import '../../core/constants/stage_colors.dart';
import '../auth/user_viewmodel.dart';
import '../profile/profile_viewmodel.dart';
import '../../services/ai_service.dart';
import '../../data/models/models.dart';
import 'resume_improvement_chat_screen.dart';

class AIScoreScreen extends StatefulWidget {
  final String resumeText;
  final List<int>? pdfBytes;
  final VoidCallback onFinish;

  const AIScoreScreen({
    super.key, 
    required this.resumeText, 
    this.pdfBytes,
    required this.onFinish
  });

  @override
  State<AIScoreScreen> createState() => _AIScoreScreenState();
}

class _AIScoreScreenState extends State<AIScoreScreen> with TickerProviderStateMixin {
  bool _isLoading = true;
  late AnimationController _gaugeController;
  late Animation<double> _scoreAnimation;
  late AnimationController _listController;
  
  ResumeAnalysisResult? _result;

  @override
  void initState() {
    super.initState();
    _gaugeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _scoreAnimation = Tween<double>(begin: 0, end: 0).animate(CurvedAnimation(parent: _gaugeController, curve: Curves.easeOutQuart));
    
    _listController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

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
      final result = await aiService.evaluateResume(widget.resumeText);
      
      if (!mounted) return;

      setState(() {
        _result = result;
        _isLoading = false;
        _scoreAnimation = Tween<double>(begin: 0, end: result.score.toDouble()).animate(
          CurvedAnimation(parent: _gaugeController, curve: Curves.easeOutQuart)
        );
      });

      _gaugeController.forward();
      _listController.forward();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro na análise: $e'), backgroundColor: StageColors.error),
      );
      widget.onFinish();
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleFinish() async {
    if (_result?.parsedData != null) {
      // Show a confirmation dialog before applying AI suggestions
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Atualizar Perfil?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: Text('Deseja que a nossa IA atualize seu perfil profissional com as informações reconstruídas do seu currículo?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('AGORA NÃO', style: GoogleFonts.inter(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: StageColors.brandBlue),
              child: Text('SIM, ATUALIZAR', style: GoogleFonts.inter(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        if (!mounted) return;
        setState(() => _isLoading = true);
        
        try {
          final userVM = context.read<UserViewModel>();
          final currentData = Map<String, dynamic>.from(userVM.user?.gamificationData ?? {});
          
          // Map AI parsed data to gamification structure
          currentData['whoIAm'] = {
            'derived': {
              'summary': _result!.parsedData!.aboutMe,
              'skills': _result!.parsedData!.skills,
              'interests': _result!.parsedData!.interests,
            },
            'last_updated': DateTime.now().toIso8601String(),
          };

          currentData['module3'] = {
            'experiences_and_courses': {
              'experiences': _result!.parsedData!.experiences,
            },
            'last_updated': DateTime.now().toIso8601String(),
          };

          await userVM.updateProfile(gamificationData: currentData);
          
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Perfil atualizado com sucesso!', style: GoogleFonts.inter()),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao atualizar perfil: $e'), backgroundColor: StageColors.error),
          );
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }
      }
    }
    
    widget.onFinish();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _AnalysisLoadingView();
    }

    final score = _result?.score ?? 0;
    final color = score >= 80 ? const Color(0xFF10B981) : (score >= 60 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 340,
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
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
                          }
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedBuilder(
                              animation: _scoreAnimation,
                              builder: (context, child) {
                                return Text(
                                  '${_scoreAnimation.value.toInt()}',
                                  style: GoogleFonts.outfit(fontSize: 72, fontWeight: FontWeight.bold, color: color, height: 1),
                                );
                              }
                            ),
                            Text(
                              'Score IA',
                              style: GoogleFonts.inter(fontSize: 14, color: StageColors.bodyGray, fontWeight: FontWeight.w600, letterSpacing: 1),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Análise Detalhada',
                    style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: StageColors.titleText),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Identificamos pontos cruciais para alavancar seu perfil.',
                    style: GoogleFonts.inter(fontSize: 16, color: StageColors.bodyGray),
                  ),
                  const SizedBox(height: 32),

                  // Strengths
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

                  const SizedBox(height: 48),
                  
                  // CHOICE A: Improve with AI
                  _ChoiceActionCard(
                    title: 'Melhorar Currículo com IA',
                    description: 'Chat interativo para destacar seus pontos fortes.',
                    icon: Icons.auto_awesome_rounded,
                    color: StageColors.brandBlue,
                    onTap: _handleImproveWithAI,
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // CHOICE B: Go to Jobs
                  _ChoiceActionCard(
                    title: 'Ir para Vagas agora',
                    description: 'Seu currículo atual já está disponível na aba Currículo.',
                    icon: Icons.work_outline_rounded,
                    color: const Color(0xFF10B981),
                    onTap: _handleGoToJobs,
                  ),
                  
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleImproveWithAI() {
    if (_result == null) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResumeImprovementChatScreen(
          resumeText: widget.resumeText,
          pdfBytes: widget.pdfBytes,
          analysis: _result!,
          onFinish: widget.onFinish,
        ),
      ),
    );
  }

  Future<void> _handleGoToJobs() async {
    setState(() => _isLoading = true);
    try {
      // 1. Save Resume to Library if pdfBytes are available
      if (widget.pdfBytes != null) {
        await context.read<ProfileViewModel>().saveResume(
          'Currículo Original (${DateTime.now().day}/${DateTime.now().month})',
          widget.pdfBytes!,
        );
      }

      // 2. Apply AI parsed data to profile if available
      if (_result?.parsedData != null) {
        final userVM = context.read<UserViewModel>();
        final currentData = Map<String, dynamic>.from(userVM.user?.gamificationData ?? {});
        
        currentData['whoIAm'] = {
          'derived': {
            'summary': _result!.parsedData!.aboutMe,
            'skills': _result!.parsedData!.skills,
            'interests': _result!.parsedData!.interests,
          },
          'last_updated': DateTime.now().toIso8601String(),
        };

        currentData['module3'] = {
          'experiences_and_courses': {
            'experiences': _result!.parsedData!.experiences,
          },
          'last_updated': DateTime.now().toIso8601String(),
        };

        await userVM.updateProfile(gamificationData: currentData);
      }

      widget.onFinish();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao finalizar: $e'), backgroundColor: StageColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildAnalysisSection({
    required String title,
    required List<String> items,
    required IconData icon,
    required Color color,
    required double delay,
  }) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _listController, curve: Interval(delay, 1.0, curve: Curves.easeOut)),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
          CurvedAnimation(parent: _listController, curve: Interval(delay, 1.0, curve: Curves.easeOut))
        ),
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
                    decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(title, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: StageColors.titleText)),
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
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(item, style: GoogleFonts.inter(fontSize: 14, color: StageColors.bodyGray, height: 1.5))),
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
  final VoidCallback onTap;

  const _ChoiceActionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.05),
              blurRadius: 15,
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
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;

  _GaugePainter({required this.progress, required this.color, required this.backgroundColor});

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
    
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, bgPaint);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle * progress, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) => oldDelegate.progress != progress;
}

class _AnalysisLoadingView extends StatefulWidget {
  @override
  State<_AnalysisLoadingView> createState() => _AnalysisLoadingViewState();
}

class _AnalysisLoadingViewState extends State<_AnalysisLoadingView> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _currentStep = 0;
  final List<String> _steps = [
    'Lendo texto extraído...',
    'Identificando competências...',
    'Analisando impacto das experiências...',
    'Calculando score de mercado...',
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
            // Scanner Animation
            Stack(
              alignment: Alignment.center,
              children: [
                // Icon Background
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: StageColors.brandBlue.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.description_outlined, size: 50, color: StageColors.brandBlue),
                ),
                // Scanning Line
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
            // Progress Steps
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
                          isDone ? Icons.check_circle : (isActive ? Icons.sync : Icons.circle_outlined),
                          size: 18,
                          color: isDone ? const Color(0xFF10B981) : (isActive ? StageColors.brandBlue : Colors.grey),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _steps[index],
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                              color: isActive ? StageColors.titleText : StageColors.bodyGray,
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
