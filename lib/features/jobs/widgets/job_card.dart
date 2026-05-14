import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/job.dart';

// ────────────────────────────────────────────────────────────
// Pendente = IA ainda calculando. Renderiza placeholder no lugar do
// score % pra evitar flash de número errado.
// ────────────────────────────────────────────────────────────
class JobCard extends StatefulWidget {
  final Job job;

  /// Score 0-100 calculado externamente via MatchScoreCalculator. Se omitido,
  /// usa `job.matchScore` (que hoje é 0 por default — placeholder).
  final int? matchScore;

  /// True quando a IA está calculando o score em background. Renderiza
  /// placeholder (dots animados) em vez do número pra evitar flash visual.
  final bool isPending;

  /// True quando o user não tem currículo no app (nem importado nem trilha).
  /// Card mostra CTA "Crie seu currículo" em vez de score — sem CV não há
  /// como calcular match honesto.
  final bool isNoResume;

  const JobCard({
    super.key,
    required this.job,
    this.matchScore,
    this.isPending = false,
    this.isNoResume = false,
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

  /// Score efetivo usado pra cor/badge. Prioriza o passado externamente
  /// (calculado pelo MatchScoreCalculator); fallback pro field do model.
  int get _score => widget.matchScore ?? widget.job.matchScore;

  /// Cor de acento — usada em shadow do card, ring de match, divisor da seção.
  /// Alinhada com o `_cardGradient` pra UI parecer coerente.
  Color get _matchColor {
    if (widget.isNoResume) return const Color(0xFF6366F1); // indigo — convida ação
    if (widget.isPending) return const Color(0xFF64748B);  // slate neutro
    if (_score >= 85) return const Color(0xFF10B981);     // esmeralda
    if (_score >= 70) return const Color(0xFF8B5CF6);     // violeta
    return const Color(0xFFF59E0B);                        // âmbar
  }

  /// Gradient do header. Antes usava cores quase pretas (verde escuro
  /// `#064E3B`, marrom morto `#78350F`) com 2 stops planos — o card parecia
  /// chapado e opaco. Agora: paletas vibrantes mas profundas, 3 stops pra
  /// criar profundidade, alinhadas com o brand (indigo→violet aparece no
  /// resto do app).
  List<Color> get _cardGradient {
    if (widget.isNoResume) {
      // Indigo→violet — comunica "ação pendente" + alinha com brand do app
      return [
        const Color(0xFF6366F1),
        const Color(0xFF8B5CF6),
        const Color(0xFF7C3AED),
      ];
    }
    if (widget.isPending) {
      // Slate elegante — não comunica score nenhum (IA ainda calculando)
      return [
        const Color(0xFF475569),
        const Color(0xFF334155),
        const Color(0xFF1E293B),
      ];
    }
    if (_score >= 85) {
      // Esmeralda vibrante → teal → cyan profundo
      return [
        const Color(0xFF10B981),
        const Color(0xFF0D9488),
        const Color(0xFF0F766E),
      ];
    }
    if (_score >= 70) {
      // Indigo → violet → purple — premium, casa com o brand do app
      return [
        const Color(0xFF6366F1),
        const Color(0xFF8B5CF6),
        const Color(0xFF7C3AED),
      ];
    }
    // Âmbar → laranja → coral — calor sem agressividade
    return [
      const Color(0xFFF59E0B),
      const Color(0xFFF97316),
      const Color(0xFFEA580C),
    ];
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
            // Estrutura: header info (title/company/chips) tem tamanho natural;
            // a descrição expande pra ocupar todo o espaço restante até o pill
            // "Toque para detalhes" no fundo. ShaderMask faz fade visual nas
            // últimas linhas pra indicar continuidade.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Bloco fixo no topo: title + meta + chips + section header
                    Column(
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
                      ],
                    ),

                    // Description — expande pra preencher TODO espaço restante
                    // até o pill. ShaderMask faz fade nas últimas ~20% do
                    // espaço pra sinalizar que tem mais conteúdo se tocar.
                    Expanded(
                      child: ShaderMask(
                        shaderCallback: (Rect bounds) {
                          return const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black, Colors.transparent],
                            stops: [0.78, 1.0],
                          ).createShader(bounds);
                        },
                        blendMode: BlendMode.dstIn,
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Text(
                            widget.job.description,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF64748B),
                              height: 1.5,
                            ),
                          ),
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
          // 3 stops criam profundidade — meio segura a cor central por
          // mais tempo, transições nas pontas são mais suaves.
          stops: _cardGradient.length == 3 ? const [0.0, 0.55, 1.0] : null,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Glow superior à esquerda — dá sensação de luz incidente
          Positioned(
            left: -30,
            top: -40,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withOpacity(0.18),
                    Colors.white.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          // Bolha decorativa direita topo
          Positioned(
            right: -25,
            top: -25,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.12),
              ),
            ),
          ),
          // Bolha menor direita base
          Positioned(
            right: 40,
            bottom: -35,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.10),
              ),
            ),
          ),
          // Acento secundário esquerda
          Positioned(
            left: 30,
            bottom: -50,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
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

                // Match ring — 3 estados: noResume (CTA criar CV) > pending (dots) > score real
                widget.isNoResume
                    ? const _NoResumeBadge()
                    : widget.isPending
                    ? _MatchPendingRing()
                    : AnimatedBuilder(
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
                                    score: _score,
                                    color: Colors.white,
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${(_score * _ringAnimation.value).toInt()}%',
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

/// Placeholder do ring de match enquanto IA calcula. Mostra 3 dots pulsando
/// no lugar do "%match", sem indicar valor ou cor — evita commit visual a um
/// número que pode mudar.
/// Badge mostrado no header do card quando o user não tem CV no app. Ocupa
/// o mesmo slot 60×60 do match ring, mas em vez de número/dots mostra ícone
/// de documento + texto "Crie seu CV". Tap no card abre detalhes da vaga,
/// mas o sinal é: pra ter match real, precisa de currículo primeiro.
class _NoResumeBadge extends StatelessWidget {
  const _NoResumeBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.18),
        border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.description_outlined,
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(height: 2),
          Text(
            'crie\nseu CV',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.95),
              fontSize: 8,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchPendingRing extends StatefulWidget {
  @override
  State<_MatchPendingRing> createState() => _MatchPendingRingState();
}

class _MatchPendingRingState extends State<_MatchPendingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Anel tracejado sutil (idle)
          CustomPaint(
            size: const Size(60, 60),
            painter: _PendingRingPainter(),
          ),
          // 3 dots pulsando em sequência
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final phase = (_ctrl.value + i * 0.2) % 1.0;
                  final scale = 0.6 + 0.4 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PendingRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
