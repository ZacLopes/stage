import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/job.dart';
import '../utils/match_score.dart';
import '../../../core/theme/theme.dart';

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

  /// Score efetivo: prioriza o passado externamente (calculado), fallback
  /// pro field do model (que hoje é 0).
  int get _score => widget.match?.score ?? widget.job.matchScore;

  /// True quando não há análise utilizável — user sem CV/perfil ou sem
  /// preferências configuradas. UI esconde score e renderiza CTA "complete
  /// seu perfil" em vez de mostrar 0%.
  bool get _hideScore =>
      (widget.match?.isNoResume ?? false) || (widget.match?.isUnknown ?? false);

  // Monocromático: sheet sempre usa brand cyan/blue, independente da faixa
  // de match. Diferenciação vem do número no ring.
  static const Color _matchColor = AppColors.brandCyan;     // brandCyan
  static const Color _matchColorDark = AppColors.brandBlue; // brandBlue

  List<Color> get _headerGradient => const [_matchColor, _matchColorDark];

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
        color: AppColors.surfaceVariant,
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
              // Drag handle agora vive DENTRO do hero header (sobreposto ao
              // gradient azul) em vez de ocupar uma faixa branca antes dele.
              // Sem essa fusão, o sheet ficava com 3 zonas visuais no topo:
              // canto arredondado branco + drag handle + gradient azul, e a
              // transição entre eles parecia bugada.
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
                              color: AppColors.textTertiary,
                              child: _buildJobHtml(
                                html: widget.job.descriptionHtml,
                                fallbackPlain: widget.job.description,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Requirements (esconde se vazio — algumas vagas
                            // não têm seção separada e tudo vem no description)
                            if (widget.job.requirements.isNotEmpty) ...[
                              _buildSection(
                                title: 'Requisitos',
                                icon: Icons.checklist_rounded,
                                color: AppColors.textTertiary,
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
                                color: AppColors.textTertiary,
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
                                color: AppColors.textTertiary,
                                child: _buildJobHtml(
                                  html: widget.job.aboutCompanyHtml,
                                  fallbackPlain: widget.job.aboutCompany,
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
          // Drag handle sobre o gradient — cor branca semi-transparente
          // pra ficar visível sem competir com o conteúdo do header.
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          // Glow sutil superior à esquerda — única decoração restante,
          // alinhada com o estilo glassmorphism do JobCard.
          Positioned(
            left: -30,
            top: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withOpacity(0.10),
                    Colors.white.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          // Overlay glass
          Positioned.fill(
            child: Container(color: Colors.white.withOpacity(0.06)),
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
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
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
                              color: Colors.white.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.25),
                                width: 0.5,
                              ),
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

                    // Animated ring (esconde quando sem perfil/prefs —
                    // mostrar 0% é enganoso porque sugere análise feita).
                    if (_hideScore)
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.15),
                        ),
                        child: const Icon(
                          Icons.person_outline_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      )
                    else
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
    // Sem perfil/prefs → renderiza CTA pra completar perfil em vez de
    // mostrar "Match razoável 0%" enganoso. User precisa entender que
    // não dá pra calcular match sem ele ter colocado dados primeiro.
    if (_hideScore) return _buildNoProfileCard();

    final score = _score;
    String matchLabel;
    String matchDescription;
    if (score >= 85) {
      matchLabel = 'Excelente match';
      matchDescription = 'Seu perfil atende muito bem aos requisitos desta vaga.';
    } else if (score >= 70) {
      matchLabel = 'Bom match';
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        matchDescription,
                        style: const TextStyle(
                          color: AppColors.textTertiary,
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
                          color: r.matched ? _matchColor : AppColors.textDisabled,
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
                                        ? AppColors.textPrimary
                                        : AppColors.textTertiary,
                                  ),
                                ),
                                if (r.detail != null && r.detail!.isNotEmpty)
                                  TextSpan(
                                    text: '  ${r.detail}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textTertiary,
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

  /// Card de "sem análise possível" — substitui o match card quando user
  /// não tem perfil/CV nem preferências. Em vez de mostrar 0% enganoso,
  /// explica o porquê + dá CTA visual claro.
  Widget _buildNoProfileCard() {
    final isUnknown = widget.match?.isUnknown ?? false;
    final title = isUnknown
        ? 'Configure suas preferências'
        : 'Crie seu currículo pra ver matches';
    final description = isUnknown
        ? 'Sem preferências de área, modelo e cidade, não dá pra calcular o quanto a vaga combina com você.'
        : 'Importe um PDF ou complete seu perfil pra IA analisar o quanto cada vaga combina com você.';

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
              AppColors.warningSoft,
              AppColors.warningSoft.withOpacity(0.4),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.xp),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Color(0xFFFBBF24),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lightbulb_outline_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.warning,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFF92400E),
                      fontSize: 13,
                      height: 1.4,
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

  // ════════════════════════════════════════════
  //  METRICS ROW
  // ════════════════════════════════════════════
  Widget _buildMetricsRow() {
    const neutral = AppColors.textTertiary;
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            icon: Icons.location_on_rounded,
            label: 'Local',
            value: widget.job.location,
            color: neutral,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricCard(
            icon: Icons.payments_rounded,
            label: 'Salário',
            value: widget.job.salaryRange,
            color: neutral,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricCard(
            icon: Icons.laptop_mac_rounded,
            label: 'Modelo',
            value: widget.job.workModel,
            color: neutral,
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
              color: AppColors.textTertiary,
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
                      color: AppColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Divider
          Divider(height: 1, color: AppColors.surfaceMuted),
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
  //  HTML CONTENT (description + aboutCompany)
  // ════════════════════════════════════════════
  /// Renderiza HTML cru de description/aboutCompany com estilo consistente
  /// ao restante da sheet (mesma fonte, mesma cor base que o antigo Text).
  /// Se [html] estiver vazio (vagas em cache antes do campo HTML existir),
  /// cai pro [fallbackPlain] num Text comum.
  /// Sanitiza HTML cru de vagas (Greenhouse, Lever, Gupy, Brazil Jobs) antes
  /// de passar pro flutter_html. ATS retornam HTML cheio de:
  /// - `<iframe>` (vídeos institucionais) → buracos verticais gigantes
  /// - `<img>`, `<table>` blockados pelo whitelist mas com margem fantasma
  /// - `style="color: #f1c40f"` em h3 (template Greenhouse) → amarelo berrante
  /// - `style="font-family: helvetica..."` em cada <li>/<span> → quebra Inter base
  /// - `<br>` em cascata → espaços inconsistentes
  /// - `class=""`, `data-teams="true"` → lixo do editor
  ///
  /// Estratégia: remover blocks pesados ANTES de qualquer renderização,
  /// strippar attrs visuais (style/class/data-*), colapsar quebras.
  static String _sanitizeJobHtml(String html) {
    if (html.isEmpty) return '';
    var s = html;

    // Remove blocks inteiros (tag + conteúdo) — ordem importa: aninhamento.
    final blockTags = ['script', 'style', 'iframe', 'video', 'audio', 'table', 'figure', 'svg'];
    for (final tag in blockTags) {
      final re = RegExp('<$tag\\b[^>]*>[\\s\\S]*?</$tag>', caseSensitive: false);
      s = s.replaceAll(re, '');
    }

    // Self-closing / void elements que viram placeholders visuais.
    s = s.replaceAll(RegExp(r'<img\b[^>]*/?>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<source\b[^>]*/?>', caseSensitive: false), '');

    // Strip de atributos visuais — style, class, data-*, on* (handlers JS).
    s = s.replaceAll(RegExp(r'''\s+style\s*=\s*"[^"]*"''', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r"""\s+style\s*=\s*'[^']*'""", caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'''\s+class\s*=\s*"[^"]*"''', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r"""\s+class\s*=\s*'[^']*'""", caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'''\s+data-[a-z\-]+\s*=\s*"[^"]*"''', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r"""\s+data-[a-z\-]+\s*=\s*'[^']*'""", caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'''\s+on[a-z]+\s*=\s*"[^"]*"''', caseSensitive: false), '');

    // 3+ <br> seguidos viram 2 (preserva separação intencional sem buraco).
    s = s.replaceAll(RegExp(r'(\s*<br\s*/?>\s*){3,}', caseSensitive: false), '<br><br>');

    // <p></p> e <span></span> vazios — colapsa.
    s = s.replaceAll(RegExp(r'<p>\s*</p>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<span>\s*</span>', caseSensitive: false), '');

    return s.trim();
  }

  Widget _buildJobHtml({required String html, required String fallbackPlain}) {
    final trimmed = _sanitizeJobHtml(html);
    if (trimmed.isEmpty) {
      return Text(
        fallbackPlain,
        style: const TextStyle(
          fontSize: 15,
          height: 1.65,
          color: AppColors.textSecondary,
        ),
      );
    }
    const baseFont = 'Inter';
    const baseColor = AppColors.textSecondary;
    const accent = AppColors.success;
    return Html(
      data: trimmed,
      onLinkTap: (url, attributes, element) async {
        if (url == null || url.isEmpty) return;
        final uri = Uri.tryParse(url);
        if (uri == null) return;
        // Browser externo (Safari/Chrome) — saída explícita do app.
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {}
      },
      style: {
        'body': Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          fontFamily: baseFont,
          fontSize: FontSize(15),
          lineHeight: const LineHeight(1.65),
          color: baseColor,
        ),
        'p': Style(
          margin: Margins.only(bottom: 10),
        ),
        'strong': Style(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        'b': Style(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        'em': Style(fontStyle: FontStyle.italic),
        'i': Style(fontStyle: FontStyle.italic),
        'h1': Style(
          fontFamily: 'Outfit',
          fontSize: FontSize(18),
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
          margin: Margins.only(top: 14, bottom: 8),
        ),
        'h2': Style(
          fontFamily: 'Outfit',
          fontSize: FontSize(17),
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
          margin: Margins.only(top: 14, bottom: 8),
        ),
        'h3': Style(
          fontFamily: 'Outfit',
          fontSize: FontSize(16),
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          margin: Margins.only(top: 12, bottom: 6),
        ),
        'h4': Style(
          fontFamily: 'Outfit',
          fontSize: FontSize(15),
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          margin: Margins.only(top: 12, bottom: 6),
        ),
        'ul': Style(
          margin: Margins.only(top: 4, bottom: 10, left: 4),
          padding: HtmlPaddings.only(left: 16),
        ),
        'ol': Style(
          margin: Margins.only(top: 4, bottom: 10, left: 4),
          padding: HtmlPaddings.only(left: 16),
        ),
        'li': Style(
          margin: Margins.only(bottom: 4),
        ),
        'a': Style(
          color: accent,
          textDecoration: TextDecoration.underline,
        ),
        // Separador horizontal — linha fina cinza com margin curto.
        // Sem isso, flutter_html renderiza barra preta grossa.
        'hr': Style(
          border: const Border(
            top: BorderSide(color: AppColors.border, width: 1),
          ),
          margin: Margins.symmetric(vertical: 12),
          height: Height(0),
        ),
        // Hardcoded reset pra tags que podem quebrar layout — flutter_html
        // ignora os blockeds via onlyRenderTheseTags abaixo, mas zerar
        // estilo defende caso a whitelist mude no futuro.
        'img': Style(display: Display.none),
        'iframe': Style(display: Display.none),
        'script': Style(display: Display.none),
        'table': Style(display: Display.none),
      },
      // Whitelist explícita — bloqueia img/iframe/script/table/video/object
      // mesmo que venham no HTML do ATS. Reduz risco de layout quebrado e
      // qualquer surpresa visual.
      onlyRenderTheseTags: const {
        'html', 'body', 'div', 'span', 'p', 'br', 'hr',
        'b', 'strong', 'i', 'em', 'u',
        'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
        'ul', 'ol', 'li',
        'a',
        'small', 'sub', 'sup',
      },
    );
  }

  // ════════════════════════════════════════════
  //  REQUIREMENT ITEM
  // ════════════════════════════════════════════
  Widget _buildRequirementItem(int index, String req) {
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
              color: _matchColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _matchColor,
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
                color: AppColors.textSecondary,
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
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(isLong ? 12 : 20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.check_rounded, size: 14, color: _matchColor),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                benefit,
                style: const TextStyle(
                  color: AppColors.textPrimary,
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
          color: AppColors.surfaceMuted,
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
              iconColor: AppColors.textTertiary,
              text: widget.job.postedDaysAgo,
              textColor: AppColors.textTertiary,
            ),
            if (widget.job.deadline != null)
              _footerChip(
                icon: Icons.event_rounded,
                iconColor: AppColors.textTertiary,
                text: widget.job.deadline!,
                textColor: AppColors.textSecondary,
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
