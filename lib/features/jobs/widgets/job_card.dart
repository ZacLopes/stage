import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/job.dart';

class JobCard extends StatefulWidget {
  final Job job;

  const JobCard({
    super.key,
    required this.job,
  });

  @override
  State<JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<JobCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _ringAnimation;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _ringAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
    );
    _fadeIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _matchColor {
    final score = widget.job.matchScore;
    if (score >= 85) return const Color(0xFF10B981);
    if (score >= 70) return const Color(0xFF3B82F6);
    return const Color(0xFFF59E0B);
  }

  List<Color> get _cardGradient {
    final score = widget.job.matchScore;
    if (score >= 85) {
      return [const Color(0xFF064E3B), const Color(0xFF065F46)];
    } else if (score >= 70) {
      return [const Color(0xFF1E3A8A), const Color(0xFF1E40AF)];
    }
    return [const Color(0xFF78350F), const Color(0xFF92400E)];
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeIn,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: _matchColor.withOpacity(0.15),
              blurRadius: 30,
              spreadRadius: 0,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─────────── Premium Header ───────────
            _buildPremiumHeader(),

            // ─────────── Body ───────────
            // Estrutura: parte de cima rola silenciosamente se o conteúdo
            // exceder; tap indicator fica pinned no fundo. Isso garante que
            // chips com texto longo (ex: "R$ 2.000 - R$ 3.000" + "Híbrido"
            // + "CLT Júnior") nunca overflowem o card.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Job Title
                            Text(
                              widget.job.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                                color: Color(0xFF0F172A),
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 6),

                            // Company and Location
                            Row(
                              children: [
                                const Icon(Icons.business_rounded, size: 14, color: Color(0xFF94A3B8)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    widget.job.companyName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF475569),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.location_on_rounded, size: 14, color: Color(0xFF94A3B8)),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    widget.job.location,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Tags / Chips
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: [
                                _buildChip(
                                  icon: Icons.payments_rounded,
                                  label: widget.job.salaryRange,
                                  gradientColors: [const Color(0xFFDCFCE7), const Color(0xFFBBF7D0)],
                                  textColor: const Color(0xFF166534),
                                  iconColor: const Color(0xFF16A34A),
                                ),
                                _buildChip(
                                  icon: Icons.laptop_mac_rounded,
                                  label: widget.job.workModel,
                                  gradientColors: [const Color(0xFFEDE9FE), const Color(0xFFDDD6FE)],
                                  textColor: const Color(0xFF5B21B6),
                                  iconColor: const Color(0xFF7C3AED),
                                ),
                                _buildChip(
                                  icon: Icons.work_rounded,
                                  label: widget.job.jobType,
                                  gradientColors: [const Color(0xFFFEF3C7), const Color(0xFFFDE68A)],
                                  textColor: const Color(0xFF92400E),
                                  iconColor: const Color(0xFFD97706),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Description section header
                            Row(
                              children: [
                                Container(
                                  width: 3,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: _matchColor,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Sobre a vaga',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF334155),
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),

                            // Description (clipped silently if too long)
                            ShaderMask(
                              shaderCallback: (Rect bounds) {
                                return const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.black, Colors.transparent],
                                  stops: [0.6, 1.0],
                                ).createShader(bounds);
                              },
                              blendMode: BlendMode.dstIn,
                              child: Text(
                                widget.job.description,
                                maxLines: 6,
                                overflow: TextOverflow.fade,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF64748B),
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Tap indicator pinned at bottom
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _matchColor.withOpacity(0.08),
                              _matchColor.withOpacity(0.05),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _matchColor.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.touch_app_rounded,
                              size: 13,
                              color: _matchColor,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Toque para detalhes',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _matchColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumHeader() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _cardGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
          ),
          Positioned(
            right: 30,
            bottom: -30,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.07),
              ),
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Logo
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: widget.job.companyLogoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.job.companyLogoUrl,
                            fit: BoxFit.cover,
                            // Falha de rede / DNS / 404 → fallback letter avatar.
                            // CachedNetworkImage não polui o console com stack
                            // traces como o Image.network nativo faz.
                            errorWidget: (_, __, ___) => _buildLogoFallback(),
                            placeholder: (_, __) => _buildLogoFallback(),
                          )
                        : _buildLogoFallback(),
                  ),
                ),
                const SizedBox(width: 14),

                // Company info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.job.jobType.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.job.companyName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.job.postedDaysAgo,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // Animated Match Ring
                AnimatedBuilder(
                  animation: _ringAnimation,
                  builder: (context, _) {
                    return SizedBox(
                      width: 60,
                      height: 60,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CustomPaint(
                            size: const Size(60, 60),
                            painter: _MatchRingPainter(
                              progress: _ringAnimation.value,
                              score: widget.job.matchScore,
                              color: Colors.white,
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(widget.job.matchScore * _ringAnimation.value).toInt()}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                'match',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoFallback() {
    return Container(
      color: _matchColor.withOpacity(0.1),
      child: Center(
        child: Text(
          widget.job.companyName.isNotEmpty
              ? widget.job.companyName[0].toUpperCase()
              : '?',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: _matchColor,
          ),
        ),
      ),
    );
  }

  Widget _buildChip({
    required IconData icon,
    required String label,
    required List<Color> gradientColors,
    required Color textColor,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradientColors),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchRingPainter extends CustomPainter {
  final double progress;
  final int score;
  final Color color;

  _MatchRingPainter({
    required this.progress,
    required this.score,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    final strokeWidth = 4.0;

    // Background track
    final trackPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * (score / 100) * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_MatchRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
