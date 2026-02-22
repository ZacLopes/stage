import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/models.dart';
import '../gamification/question_screen.dart';
import 'gamification_viewmodel.dart';
import '../../core/utils/app_notifications.dart';

class GamifiedPhaseList extends StatelessWidget {
  final List<Phase> phases;
  final Track track;

  const GamifiedPhaseList({
    super.key, 
    required this.phases,
    required this.track,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<GamificationViewModel>(
      builder: (context, viewModel, child) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Background Gradient (Fills the entire parent)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFE0F7FA), // Light Cyan
                      Color(0xFFF3E5F5), // Light Purple
                      Colors.white,
                    ],
                    stops: [0.0, 0.4, 1.0],
                  ),
                ),
              ),
            ),
            
            // Content
            LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: EdgeInsets.zero, // Remove padding to let header touch top if needed
                  child: Column(
                    children: [
                      // Custom Header
                      _WorldHeader(track: track),
                      
                      const SizedBox(height: 20),

                      // Phase Map
                      Stack(
                        children: [
                          // The Path Line - Needs explicit height or match parent?
                          // Since we are in a Column -> Stack, Positioned.fill works if Stack has size.
                          // The Column below gives the Stack its size.
                            Positioned.fill(
                            child: CustomPaint(
                              painter: _PhasePathPainter(
                                itemCount: phases.length,
                                itemHeight: 160.0, 
                                centerOffset: constraints.maxWidth / 2,
                                amplitude: 80.0,
                                completedPhases: phases.map((p) => viewModel.isPhaseCompleted(p.id)).toList(),
                              ),
                            ),
                          ),
                          // The Nodes
                          Column(
                            children: List.generate(phases.length, (index) {
                              final phase = phases[index];
                              
                              // Strict alternating logic: Left (-1), Right (1)
                              final double side = (index % 2 == 0) ? -1.0 : 1.0;
                              final double xOffset = side * 80.0;

                              final isCompleted = viewModel.isPhaseCompleted(phase.id);

                              bool isLocked = true;
                              if (index == 0) {
                                isLocked = false;
                              } else {
                                final prevPhase = phases[index - 1];
                                if (viewModel.isPhaseCompleted(prevPhase.id)) {
                                  isLocked = false;
                                }
                              }

                              bool isCurrent = !isLocked && !isCompleted; 

                              return Container(
                                height: 160.0,
                                alignment: Alignment.center,
                                child: Transform.translate(
                                  offset: Offset(xOffset, 0),
                                  child: _PhaseNode(
                                    key: ValueKey(phase.id),
                                    phase: phase, 
                                    index: index,
                                    isLocked: isLocked,
                                    isCompleted: isCompleted,
                                    isCurrent: isCurrent,
                                  ),
                                ),
                              );
                            }),
                          ),
                          
                          // Extra space at bottom
                          const SizedBox(height: 100),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      }
    );
  }
}

class _PhaseNode extends StatefulWidget {
  final Phase phase;
  final int index;
  final bool isLocked;
  final bool isCompleted;
  final bool isCurrent;

  const _PhaseNode({
    super.key,
    required this.phase, 
    required this.index,
    required this.isLocked,
    required this.isCompleted,
    required this.isCurrent,
  });

  @override
  State<_PhaseNode> createState() => _PhaseNodeState();
}

class _PhaseNodeState extends State<_PhaseNode> with TickerProviderStateMixin {
  late AnimationController _breathingController;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    
    // Breathing Animation
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut)
    );
    _breathingController.addListener(() {
      if (mounted) setState(() {});
    });

    _handleStateChanges();
  }

  @override
  void didUpdateWidget(_PhaseNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    _handleStateChanges();
  }

  void _handleStateChanges() {
    // Breathing
    if (widget.isCurrent) {
       if (!_breathingController.isAnimating) _breathingController.repeat(reverse: true);
    } else {
       _breathingController.stop();
       _breathingController.reset();
    }
  }

  @override
  void dispose() {
    _breathingController.dispose();
    super.dispose();
  }
  
  // ... (Color helper)
  Color _getPhaseColor(int index) {
      final colors = [
        const Color(0xFF58CC02), // Green
        const Color(0xFFCE82FF), // Purple
        const Color(0xFF1CB0F6), // Blue
        const Color(0xFFFF4B4B), // Red
        const Color(0xFFFF9600), // Orange
        const Color(0xFF00CD9C), // Teal
        const Color(0xFFEB5757), // Salmon
        const Color(0xFF2D9CDB), // Light Blue
      ];
      return colors[(index * 5 + 3) % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final double size = 100.0;
 

    // Effective states
    final bool effectiveLocked = widget.isLocked;
    final Color effectiveBaseColor = effectiveLocked ? const Color(0xFFE5E7EB) : _getPhaseColor(widget.index);
    
    // Scale Logic
    final double scale = widget.isCurrent ? _scaleAnimation.value : 1.0;
    
    // Decoration Logic
    final activeDeco = BoxDecoration(
      gradient: LinearGradient(
        colors: [effectiveBaseColor, effectiveBaseColor],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      shape: BoxShape.circle,
      border: widget.isCurrent ? Border.all(color: Colors.white, width: 4) : null,
    );

    final Color activeShadowColor = effectiveLocked 
        ? const Color(0xFF9CA3AF) 
        : Color.alphaBlend(Colors.black.withOpacity(0.3), effectiveBaseColor);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: () {
             if (effectiveLocked) {
              AppNotifications.show(
                context, 
                'Complete a etapa anterior primeiro!',
                type: NotificationType.warning,
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QuestionScreen(phase: widget.phase),
                ),
              );
            }
          },
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Transform.scale(
                scale: scale,
                child: Container(
                  width: size,
                  height: size,
                  child: Stack(
                    children: [
                      Positioned(
                        top: 4, left: 0, right: 0, bottom: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: activeShadowColor, 
                            shape: BoxShape.circle
                          ),
                        ),
                      ),
                      Positioned(
                        top: _isPressed ? 4 : 0, left: 0, right: 0, bottom: _isPressed ? 0 : 4,
                        child: Container(
                          decoration: activeDeco,
                          child: Center(
                            child: widget.isCompleted
                                ? const Icon(Icons.check_rounded, color: Colors.white, size: 48)
                                : effectiveLocked 
                                  ? Icon(Icons.lock_rounded, color: Colors.grey.shade400, size: 32)
                                  : _getPhaseIcon(widget.phase.title),
                          ),
                        ),
                      ),
                      if (!effectiveLocked)
                      Positioned(
                         top: _isPressed ? 8 : 4, left: 20,
                         child: Container(
                           width: 24, height: 12,
                           decoration: BoxDecoration(
                             color: Colors.white.withOpacity(0.2),
                             borderRadius: BorderRadius.circular(12),
                           ),
                         ),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Label
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            widget.phase.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: widget.isLocked ? const Color(0xFF9CA3AF) : const Color(0xFF4B5563),
              fontSize: 14,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _getPhaseIcon(String title) {
    IconData iconData = Icons.star_rounded; // Default
    final t = title.toLowerCase();

    if (t.contains('ferramentas') || t.contains('técnicas') || t.contains('hard skills')) {
      iconData = Icons.build_rounded;
    } else if (t.contains('idiomas') || t.contains('inglês') || t.contains('espanhol')) {
      iconData = Icons.translate_rounded;
    } else if (t.contains('experiências') || t.contains('trabalho') || t.contains('cargo')) {
      iconData = Icons.work_rounded;
    } else if (t.contains('sobre') || t.contains('quem') || t.contains('perfil')) {
      iconData = Icons.person_rounded;
    } else if (t.contains('cronômetro') || t.contains('tempo')) {
      iconData = Icons.timer_rounded;
    } else if (t.contains('partida') || t.contains('início')) {
      iconData = Icons.flag_rounded;
    } else if (t.contains('educação') || t.contains('curso') || t.contains('faculdade')) {
      iconData = Icons.school_rounded;
    }

    return Icon(
      iconData,
      color: Colors.white,
      size: 40,
    );
  }
}

// Helper for phase colors (moved to top level or static access if needed, but for now we keep here and pass to painter)
Color _getPhaseColor(int index) {
  final colors = [
    const Color(0xFF58CC02), // Green
    const Color(0xFFCE82FF), // Purple
    const Color(0xFF1CB0F6), // Blue
    const Color(0xFFFF4B4B), // Red
    const Color(0xFFFF9600), // Orange
    const Color(0xFF00CD9C), // Teal
    const Color(0xFFEB5757), // Salmon
    const Color(0xFF2D9CDB), // Light Blue
  ];
  return colors[(index * 5 + 3) % colors.length];
}

class _PhasePathPainter extends CustomPainter {
  final int itemCount;
  final double itemHeight;
  final double centerOffset;
  final double amplitude;
  final List<bool> completedPhases;

  _PhasePathPainter({
    required this.itemCount,
    required this.itemHeight,
    required this.centerOffset,
    required this.amplitude,
    required this.completedPhases,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = Colors.black.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24.0
      ..strokeCap = StrokeCap.round;

    final inactivePaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16.0
      ..strokeCap = StrokeCap.round;

    // 1. Draw continuous background/border
    final fullPath = Path();
    for (int i = 0; i < itemCount - 1; i++) {
        _addSegmentToPath(fullPath, i, moveToStart: i == 0);
    }
    canvas.drawPath(fullPath, borderPaint);

    // 2. Draw segments
    for (int i = 0; i < itemCount - 1; i++) {
      final segmentPath = Path();
      _addSegmentToPath(segmentPath, i, moveToStart: true);

      // Segment is active if the starting node is completed
      if (completedPhases[i]) {
         final startColor = _getPhaseColor(i);
         final endColor = _getPhaseColor(i + 1);

         final gradient = LinearGradient(
           colors: [startColor, endColor],
           begin: Alignment.topCenter,
           end: Alignment.bottomCenter,
         );
         
         final rect = segmentPath.getBounds();
         final activePaint = Paint()
            ..shader = gradient.createShader(rect)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 16.0
            ..strokeCap = StrokeCap.round;

         canvas.drawPath(segmentPath, activePaint);
      } else {
         canvas.drawPath(segmentPath, inactivePaint);
      }
    }
  }

  void _addSegmentToPath(Path path, int i, {required bool moveToStart}) {
      final double sideCurrent = (i % 2 == 0) ? -1.0 : 1.0;
      final double sideNext = ((i + 1) % 2 == 0) ? -1.0 : 1.0;

      final double startX = centerOffset + sideCurrent * amplitude;
      final double startY = (i * itemHeight) + (itemHeight / 2);

      final double endX = centerOffset + sideNext * amplitude;
      final double endY = ((i + 1) * itemHeight) + (itemHeight / 2);

      if (moveToStart) {
         path.moveTo(startX, startY);
      }

      final double controlPointY1 = startY + (endY - startY) * 0.5;
      final double controlPointY2 = startY + (endY - startY) * 0.5;
      
      path.cubicTo(
        startX, controlPointY1, 
        endX, controlPointY2, 
        endX, endY
      );
  }

  @override
  bool shouldRepaint(covariant _PhasePathPainter oldDelegate) {
    return oldDelegate.itemCount != itemCount ||
           oldDelegate.completedPhases != completedPhases;
  }
}


class _WorldHeader extends StatelessWidget {
  final Track track;

  const _WorldHeader({required this.track});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Color(track.color),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(track.color).withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SafeArea( // Ensure content is below status bar
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), // Reduced padding
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                    onPressed: () => Navigator.pop(context),
                  ),
                  IconButton(
                    icon: const Icon(Icons.info_outline, color: Colors.white, size: 24),
                    onPressed: () { 
                         // Generate info text based on track ID or title
                         String infoText = "";
                         String collectionText = "";
                         
                         if (track.id == 'track_1') {
                            infoText = "Neste mundo, vamos explorar quem você é para além do currículo.";
                            collectionText = "Coletaremos informações sobre seus pontos fortes, estilo de trabalho e motivações pessoais.";
                         } else if (track.id == 'track_2') {
                            infoText = "Aqui vamos construir a base sólida da sua formação.";
                            collectionText = "Coletaremos dados sobre sua escolaridade, cursos, datas importantes e conquistas acadêmicas.";
                         } else if (track.id == 'track_3') {
                            infoText = "Vamos mapear sua jornada profissional até aqui.";
                            collectionText = "Coletaremos detalhes sobre suas experiências anteriores, cargos, empresas e principais responsabilidades.";
                         } else if (track.id == 'track_4') {
                            infoText = "Hora de mostrar o que você sabe fazer na prática.";
                            collectionText = "Coletaremos suas habilidades técnicas (Hard Skills), ferramentas que domina e idiomas.";
                         } else if (track.id == 'track_5') {
                            infoText = "Os toques finais para conectar você ao mercado.";
                            collectionText = "Coletaremos seus links profissionais (LinkedIn, Portfólio) e informações de contato.";
                         } else {
                            infoText = "Informações sobre esta trilha.";
                            collectionText = "Coletaremos dados relevantes para o seu perfil.";
                         }

                         showDialog(
                           context: context,
                           builder: (context) => AlertDialog(
                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                             title: Row(
                               children: [
                                 Icon(Icons.info_outline, color: Color(track.color)),
                                 const SizedBox(width: 10),
                                 const Text("Sobre esta trilha", style: TextStyle(fontWeight: FontWeight.bold)),
                               ],
                             ),
                             content: Column(
                               mainAxisSize: MainAxisSize.min,
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 Text(infoText, style: const TextStyle(fontSize: 16)),
                                 const SizedBox(height: 16),
                                 const Text("O que vamos coletar:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                 const SizedBox(height: 4),
                                 Text(collectionText, style: TextStyle(fontSize: 14, color: Colors.grey[700])),
                               ],
                             ),
                             actions: [
                               TextButton(
                                 onPressed: () => Navigator.pop(context),
                                 child: Text("Entendi", style: TextStyle(color: Color(track.color), fontWeight: FontWeight.bold)),
                               )
                             ],
                           ),
                         );
                    },
                  ),
                ],
              ),
              // Compact Header Content
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                   Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                    ),
                    child: Icon(
                      _getTrackIcon(track.id), 
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.9),
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  )

                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getTrackIcon(String trackId) {
    switch (trackId) {
      case 'track_1': // Quem eu sou
        return Icons.person_rounded;
      case 'track_2': // Minha Base (Formação)
        return Icons.school_rounded;
      case 'track_3': // Minhas Experiências
        return Icons.work_history_rounded;
      case 'track_4': // Hard Skills
        return Icons.handyman_rounded;
      case 'track_5': // Links
        return Icons.link_rounded;
      default:
        return Icons.auto_stories_rounded;
    }
  }
}

class _CelebrationParticles extends StatefulWidget {
  final bool animate;
  const _CelebrationParticles({required this.animate});

  @override
  State<_CelebrationParticles> createState() => _CelebrationParticlesState();
}

class _CelebrationParticlesState extends State<_CelebrationParticles> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Particle> _particles;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _particles = List.generate(20, (index) => _createParticle());
  }

  _Particle _createParticle() {
    final color = [
      Colors.amber, Colors.orange, Colors.red, Colors.blue, Colors.purple, Colors.green
    ][_random.nextInt(6)];
    
    return _Particle(
      color: color,
      angle: _random.nextDouble() * 2 * pi,
      speed: 2.0 + _random.nextDouble() * 4.0,
      size: 4.0 + _random.nextDouble() * 4.0,
      offset: _random.nextDouble() * 20.0, // Random start offset
    );
  }

  @override
  void didUpdateWidget(_CelebrationParticles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !oldWidget.animate) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _ParticlePainter(
            particles: _particles,
            progress: _controller.value,
          ),
          size: const Size(300, 300),
        );
      },
    );
  }
}

class _Particle {
  final Color color;
  final double angle;
  final double speed;
  final double size;
  final double offset;

  _Particle({
    required this.color,
    required this.angle,
    required this.speed,
    required this.size,
    required this.offset,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  _ParticlePainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final center = Offset(size.width / 2, size.height / 2);

    for (var particle in particles) {
      // Ease out quint pattern for explosion
      final t = Curves.easeOutQuint.transform(progress);
      final distance = particle.offset + (t * 120.0 * particle.speed * 0.5);
      
      // Calculate position
      final x = center.dx + cos(particle.angle) * distance;
      final y = center.dy + sin(particle.angle) * distance;
      
      // Fade out and gravity
      final opacity = (1.0 - progress).clamp(0.0, 1.0);
      paint.color = particle.color.withOpacity(opacity);
      
      // Draw
      canvas.drawCircle(Offset(x, y + (progress * 50)), particle.size * (1 - progress), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}
