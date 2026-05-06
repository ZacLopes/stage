import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/job.dart';
import '../utils/match_score.dart';

class JobDetailsSheet extends StatefulWidget {
  final Job job;

  /// Resultado do MatchScoreCalculator. Quando presente, mostra a seção
  /// "Por que esse match?" com as razões. Quando null, esconde a seção.
  final MatchResult? match;

  const JobDetailsSheet({
    super.key,
    required this.job,
    this.match,
  });

  @override
  State<JobDetailsSheet> createState() => _JobDetailsSheetState();
}

class _JobDetailsSheetState extends State<JobDetailsSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _ringAnim;
  late final Animation<double> _slideAnim;
  bool _isSaved = false;

  /// Score efetivo: prioriza o passado externamente (calculado), fallback
  /// pro field do model (que hoje é 0).
  int get _score => widget.match?.score ?? widget.job.matchScore;

  Color get _matchColor {
    final score = _score;
    if (score >= 85) return const Color(0xFF10B981);
    if (score >= 70) return const Color(0xFF3B82F6);
    return const Color(0xFFF59E0B);
  }

  List<Color> get _headerGradient {
    final score = _score;
    if (score >= 85) {
      return [const Color(0xFF065F46), const Color(0xFF047857), const Color(0xFF059669)];
    } else if (score >= 70) {
      return [const Color(0xFF1E3A8A), const Color(0xFF1E40AF), const Color(0xFF2563EB)];
    }
    return [const Color(0xFF78350F), const Color(0xFF92400E), const Color(0xFFB45309)];
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _ringAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
    );
    _slideAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.92,
        maxChildSize: 0.97,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              Expanded(
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    // ─── Sticky Header (Hero) ───
                    SliverToBoxAdapter(child: _buildHeroHeader()),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Match Score Card
                            _buildMatchCard(),
                            const SizedBox(height: 20),

                            // Quick Metrics Row
                            _buildMetricsRow(),
                            const SizedBox(height: 24),

                            // Description
                            _buildSection(
                              title: 'Sobre a vaga',
                              icon: Icons.info_outline_rounded,
                              color: const Color(0xFF4F46E5),
                              child: Text(
                                widget.job.description,
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.65,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Requirements (esconde se vazio — algumas vagas
                            // não têm seção separada e tudo vem no description)
                            if (widget.job.requirements.isNotEmpty) ...[
                              _buildSection(
                                title: 'Requisitos',
                                icon: Icons.checklist_rounded,
                                color: const Color(0xFF7C3AED),
                                child: Column(
                                  children: widget.job.requirements
                                      .asMap()
                                      .entries
                                      .map((e) => _buildRequirementItem(e.key, e.value))
                                      .toList(),
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],

                            // Benefits (esconde se vazio)
                            if (widget.job.benefits.isNotEmpty) ...[
                              _buildSection(
                                title: 'Benefícios',
                                icon: Icons.card_giftcard_rounded,
                                color: const Color(0xFF059669),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: widget.job.benefits
                                      .map((b) => _buildBenefitChip(b))
                                      .toList(),
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],

                            // About Company
                            if (widget.job.aboutCompany.isNotEmpty) ...[
                              _buildSection(
                                title: 'Sobre a ${widget.job.companyName}',
                                icon: Icons.business_rounded,
                                color: const Color(0xFF0EA5E9),
                                child: Text(
                                  widget.job.aboutCompany,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.65,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],

                            // Posted / Deadline
                            _buildFooterInfo(),

                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom CTA
              _buildBottomBar(),
            ],
          );
        },
      ),
    );
  }

  // ════════════════════════════════════════════
  //  HERO HEADER
  // ════════════════════════════════════════════
  Widget _buildHeroHeader() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _headerGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Stack(
        children: [
          // Decorative arcs
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ),
          Positioned(
            left: -20,
            bottom: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.04),
              ),
            ),
          ),

          // Close button
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Save button
          Positioned(
            top: 0,
            left: 0,
            child: StatefulBuilder(
              builder: (ctx, setSt) => IconButton(
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    _isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    key: ValueKey(_isSaved),
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() => _isSaved = !_isSaved);
                },
              ),
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Logo
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: widget.job.companyLogoUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: widget.job.companyLogoUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _logoFallback(),
                                placeholder: (_, __) => _logoFallback(),
                              )
                            : _logoFallback(),
                      ),
                    ),
                    const SizedBox(width: 14),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Job type badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
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
                          const SizedBox(height: 5),
                          Text(
                            widget.job.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.job.companyName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Animated ring
                    AnimatedBuilder(
                      animation: _ringAnim,
                      builder: (_, __) => SizedBox(
                        width: 64,
                        height: 64,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: const Size(64, 64),
                              painter: _RingPainter(
                                progress: _ringAnim.value,
                                score: _score,
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${(_score * _ringAnim.value).toInt()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  'match',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.75),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
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

  Widget _logoFallback() {
    return Container(
      color: _matchColor.withOpacity(0.12),
      child: Center(
        child: Text(
          widget.job.companyName.isNotEmpty ? widget.job.companyName[0] : '?',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: _matchColor,
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  MATCH CARD
  // ════════════════════════════════════════════
  Widget _buildMatchCard() {
    final score = _score;
    String matchLabel;
    String matchDescription;
    if (score >= 85) {
      matchLabel = 'Excelente match! 🎯';
      matchDescription = 'Seu perfil atende muito bem aos requisitos desta vaga.';
    } else if (score >= 70) {
      matchLabel = 'Bom match! ✨';
      matchDescription = 'Você tem um bom alinhamento com o perfil buscado.';
    } else {
      matchLabel = 'Match razoável';
      matchDescription = 'Há alguns pontos a desenvolver, mas vale tentar!';
    }

    return AnimatedBuilder(
      animation: _slideAnim,
      builder: (_, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.3, 0),
          end: Offset.zero,
        ).animate(_slideAnim),
        child: FadeTransition(opacity: _slideAnim, child: child),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _matchColor.withOpacity(0.08),
              _matchColor.withOpacity(0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _matchColor.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _matchColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.auto_awesome_rounded,
                      color: _matchColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        matchLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _matchColor.withOpacity(0.9),
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        matchDescription,
                        style: TextStyle(
                          color: _matchColor.withOpacity(0.7),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedBuilder(
                  animation: _ringAnim,
                  builder: (_, __) => Text(
                    '${(_score * _ringAnim.value).toInt()}%',
                    style: TextStyle(
                      color: _matchColor,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            // Razões do match (quando disponível)
            if (widget.match != null && widget.match!.reasons.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(height: 1, color: _matchColor.withOpacity(0.15)),
              const SizedBox(height: 12),
              ...widget.match!.reasons.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          r.matched
                              ? Icons.check_circle_rounded
                              : Icons.remove_circle_outline_rounded,
                          size: 16,
                          color: r.matched
                              ? const Color(0xFF10B981)
                              : Colors.grey[400],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: r.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: r.matched
                                        ? const Color(0xFF1F2937)
                                        : Colors.grey[600],
                                  ),
                                ),
                                if (r.detail != null && r.detail!.isNotEmpty)
                                  TextSpan(
                                    text: '  ${r.detail}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  METRICS ROW
  // ════════════════════════════════════════════
  Widget _buildMetricsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            icon: Icons.location_on_rounded,
            label: 'Local',
            value: widget.job.location,
            color: const Color(0xFF0EA5E9),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricCard(
            icon: Icons.payments_rounded,
            label: 'Salário',
            value: widget.job.salaryRange,
            color: const Color(0xFF10B981),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricCard(
            icon: Icons.laptop_mac_rounded,
            label: 'Modelo',
            value: widget.job.workModel,
            color: const Color(0xFF7C3AED),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  SECTION CONTAINER
  // ════════════════════════════════════════════
  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Divider
          Divider(height: 1, color: const Color(0xFFF1F5F9)),
          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  REQUIREMENT ITEM
  // ════════════════════════════════════════════
  Widget _buildRequirementItem(int index, String req) {
    final colors = [
      const Color(0xFF4F46E5),
      const Color(0xFF7C3AED),
      const Color(0xFF0EA5E9),
      const Color(0xFF059669),
      const Color(0xFFF59E0B),
    ];
    final color = colors[index % colors.length];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              req,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF475569),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  BENEFIT CHIP
  // ════════════════════════════════════════════
  Widget _buildBenefitChip(String benefit) {
    // Constrói chips compactos quando o benefício é curto (1 linha), e
    // cards full-width quando é uma string longa (texto descritivo do Gupy).
    final isLong = benefit.length > 50;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: isLong ? double.infinity : 280,
      ),
      child: Container(
        width: isLong ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)],
          ),
          borderRadius: BorderRadius.circular(isLong ? 12 : 20),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF10B981)),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                benefit,
                style: const TextStyle(
                  color: Color(0xFF166534),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  FOOTER
  // ════════════════════════════════════════════
  Widget _buildFooterInfo() {
    // Wrap permite quebrar em 2 linhas quando o texto é longo (ex: "Inscrições
    // até 31 de maio de 2026"), em vez de truncar com ellipsis.
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _footerChip(
              icon: Icons.schedule_rounded,
              iconColor: const Color(0xFF94A3B8),
              text: widget.job.postedDaysAgo,
              textColor: const Color(0xFF64748B),
            ),
            if (widget.job.deadline != null)
              _footerChip(
                icon: Icons.event_rounded,
                iconColor: const Color(0xFFF59E0B),
                text: widget.job.deadline!,
                textColor: const Color(0xFF92400E),
                bold: true,
              ),
          ],
        ),
      ),
    );
  }

  /// Item de info da pílula footer (ícone + texto). Renderiza sem largura
  /// fixa, então o Wrap pai pode quebrar em duas linhas se necessário.
  Widget _footerChip({
    required IconData icon,
    required Color iconColor,
    required String text,
    required Color textColor,
    bool bold = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: textColor,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════
  //  BOTTOM BAR
  // ════════════════════════════════════════════
  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Apply button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 10),
                        Text('Candidatura enviada para ${widget.job.companyName}! 🎉'),
                      ],
                    ),
                    backgroundColor: const Color(0xFF059669),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    duration: const Duration(seconds: 3),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: EdgeInsets.zero,
              ),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.send_rounded, size: 20, color: Colors.white),
                      SizedBox(width: 10),
                      Text(
                        'Aplicar para esta vaga',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // AI adapt button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4F46E5),
                side: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 18, color: Color(0xFF4F46E5)),
                  SizedBox(width: 8),
                  Text(
                    'Adaptar meu currículo com IA',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Ring Painter
// ─────────────────────────────────────────────
class _RingPainter extends CustomPainter {
  final double progress;
  final int score;

  _RingPainter({required this.progress, required this.score});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    const strokeWidth = 4.5;

    final trackPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, trackPaint);

    final progressPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * (score / 100) * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.progress != progress;
}
