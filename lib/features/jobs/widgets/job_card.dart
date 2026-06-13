import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/job.dart';
import '../utils/match_band.dart';
import '../utils/match_score.dart';
import '../../../core/theme/theme.dart';

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

  /// Confiança da análise (Passo 5 do plano match-score, 2026-05-27).
  /// Função de quantas dimensões o user declarou. Default `high` mantém
  /// retrocompat — quando não passado, comporta como antes (score sempre
  /// visível). Quando `low`, ring é substituído por badge "Análise limitada"
  /// + CTA com [missingDimensions]. Quando `medium`, ring normal + ressalva.
  final MatchConfidence confidence;

  /// Labels das dimensões que o user ainda NÃO declarou (ex:
  /// `['cidade', 'salário mínimo']`). Renderizado como CTA no card quando
  /// `confidence == low`. Default lista vazia.
  final List<String> missingDimensions;

  /// FASE 2 (T2.4, holdout §5/D3): false = variante 'hidden' — o ring de
  /// match some do card PRÉ-SWIPE (banda revelada só no detalhe da vaga).
  final bool showScore;

  const JobCard({
    super.key,
    required this.job,
    this.matchScore,
    this.isPending = false,
    this.isNoResume = false,
    this.confidence = MatchConfidence.high,
    this.missingDimensions = const [],
    this.showScore = true,
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

  /// Score efetivo usado pra badge. Prioriza o passado externamente
  /// (calculado pelo MatchScoreCalculator); fallback pro field do model.
  int get _score => widget.matchScore ?? widget.job.matchScore;

  // Paleta monocromática brand — header e acentos não mudam com a faixa de
  // match. Diferenciação visual fica só no número do ring (e nos estados
  // isNoResume/isPending via conteúdo do ring, não cor).
  static const Color _accent = AppColors.brandCyan; // AppColors.brandCyan
  static const Color _accentDark = AppColors.brandBlue; // AppColors.brandBlue

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeIn,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 24,
              spreadRadius: 0,
              offset: const Offset(0, 8),
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
                // SingleChildScrollView aqui quebra o CardSwiper porque ele
                // aplica RenderTransform em cima dos cards e precisa de
                // altura determinística. ClipRect mantém o layout original
                // e só clipa o conteúdo que ultrapassa, sem introduzir
                // scrollview nem afetar transforms ancestrais.
                child: ClipRect(
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
                              color: AppColors.textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Company and Location
                          Row(
                            children: [
                              const Icon(
                                Icons.business_rounded,
                                size: 14,
                                color: AppColors.textTertiary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.job.companyName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.location_on_rounded,
                                size: 14,
                                color: AppColors.textTertiary,
                              ),
                              const SizedBox(width: 2),
                              Flexible(
                                child: Text(
                                  widget.job.location,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textTertiary,
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
                              ),
                              _buildChip(
                                icon: Icons.laptop_mac_rounded,
                                label: widget.job.workModel,
                              ),
                              _buildChip(
                                icon: Icons.work_rounded,
                                label: widget.job.jobType,
                              ),
                            ],
                          ),

                          if (widget.job.applicationMethod == 'email')
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: _buildAiApplicationCta(),
                            ),

                          // CTA discreto quando confidence != high — orienta
                          // o user a completar perfil. Variante diferente
                          // pra low (âmbar forte) vs medium (azul suave).
                          // Vide _MissingDimensionsCta.
                          if ((widget.confidence == MatchConfidence.low ||
                                  widget.confidence ==
                                      MatchConfidence.medium) &&
                              widget.missingDimensions.isNotEmpty &&
                              !widget.isPending &&
                              !widget.isNoResume)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: _MissingDimensionsCta(
                                missing: widget.missingDimensions,
                                confidence: widget.confidence,
                              ),
                            ),

                          const SizedBox(height: 14),

                          // Description section header — overline minúsculo,
                          // sem barra colorida. Hierarquia vem do tracking
                          // e da cor mais clara.
                          const Text(
                            'SOBRE A VAGA',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textTertiary,
                              letterSpacing: 1.2,
                            ),
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
                                color: AppColors.textTertiary,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Affordance discreta — chevron no canto direito sinaliza
                      // que o card é tocável, sem o peso de um pill com label.
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 22,
                            color: Color(0xFFCBD5E1),
                          ),
                        ),
                      ),
                    ],
                  ),
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
      height: 110,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_accent.withOpacity(0.92), _accentDark.withOpacity(0.95)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Glow sutil superior à esquerda — única decoração restante.
          // Cria sensação de luz incidente sem virar "bolha".
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
                    Colors.white.withOpacity(0.10),
                    Colors.white.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          // Overlay translúcido — efeito glass por cima do gradient
          Positioned.fill(
            child: Container(color: Colors.white.withOpacity(0.06)),
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
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
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

                // Match ring — 5 estados (precedência de cima pra baixo):
                //   1. holdout hidden → nada pré-swipe (T2.4 §5/D3;
                //      banda revelada no detalhe da vaga)
                //   2. noResume       → CTA "crie seu CV"
                //   3. pending        → dots animados
                //   4. confidence low → badge "Análise limitada" (Passo 5)
                //   5. score real     → ring com BANDA (T2.4: o número
                //      0-100 saiu do pré-swipe; completo só no detalhe)
                !widget.showScore
                    ? const SizedBox.shrink()
                    : widget.isNoResume
                    ? const _NoResumeBadge()
                    : widget.isPending
                    ? _MatchPendingRing()
                    : widget.confidence == MatchConfidence.low
                    ? const _LimitedAnalysisBadge()
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
                                      // T2.4 — banda em vez de número
                                      // (Alta ≥70 / Média 40-69 / Baixa <40).
                                      matchBandFor(_score).label,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
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
      color: _accent.withOpacity(0.1),
      child: Center(
        child: Text(
          widget.job.companyName.isNotEmpty
              ? widget.job.companyName[0].toUpperCase()
              : '?',
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: _accent,
          ),
        ),
      ),
    );
  }

  Widget _buildAiApplicationCta() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFDBFE), width: 1),
      ),
      child: const Row(
        children: [
          Icon(Icons.auto_awesome_rounded, size: 15, color: AppColors.primary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Essa vaga aceita aplicações automáticas por IA, dê o swipe e acompanhe o resultado pelo WhatsApp ou Email!',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                height: 1.18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textTertiary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
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
          const Icon(Icons.description_outlined, color: Colors.white, size: 22),
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

/// CTA inline no body do card quando `confidence != high` (Passo 5).
/// Tem 2 variantes:
/// - LOW (âmbar forte): "Pra match completo, declare: X, Y" — convida o
///   user a preencher múltiplas dimensões. Aparece junto com badge
///   "análise limitada" no header.
/// - MEDIUM (azul suave): "Match estimado — declare X pra refinar" —
///   ressalta que o score é confiável mas pode melhorar. Aparece junto
///   com o ring normal.
///
/// Filtra "salário mínimo" do display porque a coluna não existe no
/// relacional ainda (decisão founder 2026-05-27) — declarar não funciona,
/// então não pedir.
class _MissingDimensionsCta extends StatelessWidget {
  final List<String> missing;
  final MatchConfidence confidence;
  const _MissingDimensionsCta({
    required this.missing,
    required this.confidence,
  });

  bool get _isMedium => confidence == MatchConfidence.medium;

  @override
  Widget build(BuildContext context) {
    // Filtra dimensões não-acionáveis (salário mínimo não tem coluna no
    // relacional ainda — user não consegue declarar, então não pedir).
    final actionable = missing.where((m) => m != 'salário mínimo').toList();
    if (actionable.isEmpty) return const SizedBox.shrink();

    if (_isMedium) {
      return _buildChip(
        bg: AppColors.primarySoft, // azul muito claro
        border: const Color(0xFFBFDBFE),
        iconColor: const Color(0xFF1D4ED8), // azul médio
        textColor: AppColors.primary,
        // Pra medium menciona só a primeira dimensão (tom suave).
        text: 'Match estimado — declare ${actionable.first} pra refinar',
      );
    }

    // LOW: lista até 2 dimensões + reticências se há mais.
    final visible = actionable.take(2).join(', ');
    final overflow = actionable.length > 2 ? '…' : '';
    return _buildChip(
      bg: AppColors.warningSoft, // âmbar muito claro
      border: AppColors.warningSoft,
      iconColor: const Color(0xFFC2410C), // âmbar escuro
      textColor: const Color(0xFF9A3412),
      text: 'Pra match completo, declare: $visible$overflow',
    );
  }

  Widget _buildChip({
    required Color bg,
    required Color border,
    required Color iconColor,
    required Color textColor,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline_rounded, size: 14, color: iconColor),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge mostrado no header do card quando `confidence == low` (Passo 5 do
/// plano match-score, 2026-05-27). User tem perfil mas declarou < 3 dimensões
/// — score interno é calculado pra ordenar feed, mas a UI esconde o número
/// pra não "mentir" e mostra CTA pra completar perfil. Ocupa o mesmo slot
/// 60×60 do ring real. Detalhamento de "quais dimensões faltam" aparece no
/// JobDetailsSheet.
class _LimitedAnalysisBadge extends StatelessWidget {
  const _LimitedAnalysisBadge();

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
          const Icon(Icons.help_outline_rounded, color: Colors.white, size: 22),
          const SizedBox(height: 2),
          Text(
            'análise\nlimitada',
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
          CustomPaint(size: const Size(60, 60), painter: _PendingRingPainter()),
          // 3 dots pulsando em sequência
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final phase = (_ctrl.value + i * 0.2) % 1.0;
                  final scale =
                      0.6 + 0.4 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
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
