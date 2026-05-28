import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme.dart';
import '../../core/utils/app_notifications.dart';
import '../../data/models/models.dart';
import '../auth/user_viewmodel.dart';
import '../gamification/question_screen.dart';
import 'home_viewmodel.dart';

/// Trilha aberta única (estilo Duolingo) que substitui a navegação em dois
/// níveis (lista de mundos → tela de mundo). Renderiza TODAS as fases de
/// todos os tracks em uma única scroll-view zig-zag, separadas por divisores
/// horizontais com o nome do mundo.
///
/// Lock cascade GLOBAL: a "fase atual" é a primeira não-completa em toda a
/// lista achatada (atravessa mundos). Fases anteriores: completed. Posteriores:
/// locked.
class OpenTrailView extends StatefulWidget {
  const OpenTrailView({super.key});

  @override
  State<OpenTrailView> createState() => _OpenTrailViewState();
}

class _OpenTrailViewState extends State<OpenTrailView> {
  final ScrollController _scrollController = ScrollController();

  /// Keys de cada `_WorldSeparator` na ordem em que aparecem. Permite descobrir
  /// qual mundo está no topo do viewport via `RenderBox.localToGlobal`.
  final Map<int, GlobalKey> _separatorKeys = {};

  /// Índice do mundo "atual" — atualizado on-scroll. Inicia em null pra evitar
  /// disparar haptic no primeiro frame (sem scroll, já estamos no mundo 0).
  int? _currentWorld;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Detecta cruzamento de mundo durante scroll. Pra cada separator visível,
  /// computa o topo em coords globais e marca como "mundo atual" o último
  /// cujo topo passou da borda superior do viewport. Quando esse índice muda,
  /// dispara um haptic leve (estilo Duolingo).
  void _onScroll() {
    final scrollCtx = _scrollController.position.context.notificationContext;
    final scrollBox = scrollCtx?.findRenderObject() as RenderBox?;
    if (scrollBox == null) return;
    final viewportTop = scrollBox.localToGlobal(Offset.zero).dy;

    int? activeWorld;
    _separatorKeys.forEach((i, key) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      final separatorTop = box.localToGlobal(Offset.zero).dy;
      // Separator passou (ou está passando) a borda superior do viewport.
      // Buffer de 60px pra disparar quando ele está saindo de vista no topo.
      if (separatorTop < viewportTop + 60) {
        activeWorld = i;
      }
    });

    if (activeWorld != _currentWorld) {
      // Só vibra se já tínhamos um mundo registrado antes (evita o haptic
      // inicial quando _currentWorld passa de null → 0 ao montar a tela).
      if (_currentWorld != null && activeWorld != null) {
        HapticFeedback.lightImpact();
      }
      _currentWorld = activeWorld;
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HomeViewModel>();
    final userVm = context.watch<UserViewModel>();

    final tracks = viewModel.tracks;
    final phasesByTrack = viewModel.phasesByTrack;

    // 1. Achatar fases em ordem global (tracks já vêm ordenados por orderIndex).
    final flat = <Phase>[];
    for (final t in tracks) {
      flat.addAll(phasesByTrack[t.id] ?? const <Phase>[]);
    }

    // 2. Index global da fase "atual" — primeira não-completa.
    final currentIndex = flat.indexWhere((p) => !viewModel.isPhaseCompleted(p.id));

    // 3. Mostrar banner M1 só se o track_1 existe E o user tem a flag ligada.
    final showM1Banner =
        userVm.showM1ResetNotice && tracks.any((t) => t.id == 'track_1');

    // Reset do mapa de keys a cada build — track list pode mudar (hot reload,
    // resync) e queremos sempre uma key estável por índice de mundo.
    _separatorKeys.clear();

    return LayoutBuilder(
      builder: (context, constraints) {
        final centerOffset = constraints.maxWidth / 2;

        // Constrói (separator + section) por track, mantendo o flatStartIndex
        // pra que cada PhaseNode saiba sua posição no cascade global.
        int flatStart = 0;
        final sections = <Widget>[];
        for (var i = 0; i < tracks.length; i++) {
          final track = tracks[i];
          final phases = phasesByTrack[track.id] ?? const <Phase>[];
          if (phases.isEmpty) continue; // pular separator órfão

          final separatorKey = GlobalKey();
          _separatorKeys[i] = separatorKey;

          sections.add(_WorldSeparator(
            key: separatorKey,
            track: track,
            worldIndex: i,
            isFirst: sections.isEmpty,
          ));
          sections.add(_WorldSection(
            track: track,
            phases: phases,
            flatStartIndex: flatStart,
            currentGlobalIndex: currentIndex,
            centerOffset: centerOffset,
          ));
          flatStart += phases.length;
        }

        return SingleChildScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              if (showM1Banner)
                _M1ResetBanner(onDismiss: userVm.clearM1ResetNotice),
              ...sections,
              const SizedBox(height: 100),
            ],
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// M1 Reset Banner — preserva o aviso âmbar que existia em GamifiedPhaseList.
// ════════════════════════════════════════════════════════════════════════════

class _M1ResetBanner extends StatelessWidget {
  final Future<void> Function() onDismiss;
  const _M1ResetBanner({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warning, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded,
              color: AppColors.warning, size: 20),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text(
              'Atualizamos algumas perguntas para deixar seu CV ainda melhor — vamos refinar juntos.',
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          GestureDetector(
            onTap: () => onDismiss(),
            child: const Icon(Icons.close_rounded,
                size: 18, color: AppColors.warning),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// _WorldSeparator — divisor entre mundos, com pílula colorida + título.
// ════════════════════════════════════════════════════════════════════════════

class _WorldSeparator extends StatelessWidget {
  final Track track;
  final int worldIndex;
  final bool isFirst;

  const _WorldSeparator({
    super.key,
    required this.track,
    required this.worldIndex,
    required this.isFirst,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(track.color);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        isFirst ? AppSpacing.base : AppSpacing.xl2,
        AppSpacing.lg,
        AppSpacing.base,
      ),
      child: Column(
        children: [
          // Linha decorativa com gradient + pílula central "MUNDO N"
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0),
                        color.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    'MUNDO ${worldIndex + 1}',
                    style: AppTextStyles.overline.copyWith(
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textOnDark,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0.55),
                        color.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Título do mundo
          Semantics(
            header: true,
            child: Text(
              track.title.toUpperCase(),
              textAlign: TextAlign.center,
              style: AppTextStyles.titleMd.copyWith(
                letterSpacing: 1.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Subtítulo
          Text(
            track.description,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// _WorldSection — Stack(path painter + Column de nodes zig-zag).
// Reinicia o zig-zag a cada seção (esquerda no localIndex 0).
// ════════════════════════════════════════════════════════════════════════════

class _WorldSection extends StatelessWidget {
  final Track track;
  final List<Phase> phases;
  final int flatStartIndex;
  final int currentGlobalIndex;
  final double centerOffset;

  static const double _itemHeight = 160.0;
  static const double _amplitude = 80.0;

  const _WorldSection({
    required this.track,
    required this.phases,
    required this.flatStartIndex,
    required this.currentGlobalIndex,
    required this.centerOffset,
  });

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HomeViewModel>();
    final color = Color(track.color);
    final completed =
        phases.map((p) => viewModel.isPhaseCompleted(p.id)).toList();

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _PhasePathPainter(
              itemCount: phases.length,
              itemHeight: _itemHeight,
              centerOffset: centerOffset,
              amplitude: _amplitude,
              completedPhases: completed,
              baseColor: color,
            ),
          ),
        ),
        Column(
          children: List.generate(phases.length, (localIndex) {
            final phase = phases[localIndex];
            final globalIndex = flatStartIndex + localIndex;
            final isCompleted = completed[localIndex];
            final isCurrent = globalIndex == currentGlobalIndex;
            final isLocked = currentGlobalIndex != -1 &&
                globalIndex > currentGlobalIndex;

            final side = (localIndex % 2 == 0) ? -1.0 : 1.0;
            final xOffset = side * _amplitude;

            return SizedBox(
              height: _itemHeight,
              child: Align(
                alignment: Alignment.center,
                child: Transform.translate(
                  offset: Offset(xOffset, 0),
                  child: _PhaseNode(
                    key: ValueKey(phase.id),
                    phase: phase,
                    color: color,
                    isLocked: isLocked,
                    isCompleted: isCompleted,
                    isCurrent: isCurrent,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// _PhaseNode — adaptado de gamified_phase_list.dart. Mudança principal: recebe
// `color` por parâmetro (em vez de derivar de index). Mantém efeito 3D,
// breathing animation no current, ícone variável por título e label embaixo.
// ════════════════════════════════════════════════════════════════════════════

class _PhaseNode extends StatefulWidget {
  final Phase phase;
  final Color color;
  final bool isLocked;
  final bool isCompleted;
  final bool isCurrent;

  const _PhaseNode({
    super.key,
    required this.phase,
    required this.color,
    required this.isLocked,
    required this.isCompleted,
    required this.isCurrent,
  });

  @override
  State<_PhaseNode> createState() => _PhaseNodeState();
}

class _PhaseNodeState extends State<_PhaseNode>
    with TickerProviderStateMixin {
  late AnimationController _breathingController;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
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
    if (widget.isCurrent) {
      if (!_breathingController.isAnimating) {
        _breathingController.repeat(reverse: true);
      }
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

  @override
  Widget build(BuildContext context) {
    const double size = 100.0;
    final bool locked = widget.isLocked;
    final Color baseColor = locked ? AppColors.border : widget.color;
    final double scale = widget.isCurrent ? _scaleAnimation.value : 1.0;

    final Color shadowColor = locked
        ? AppColors.textDisabled
        : Color.alphaBlend(
            Colors.black.withValues(alpha: 0.3),
            baseColor,
          );

    final activeDeco = BoxDecoration(
      color: baseColor,
      shape: BoxShape.circle,
      border: widget.isCurrent
          ? Border.all(color: AppColors.surface, width: 4)
          : null,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: () {
            if (locked) {
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
          child: Transform.scale(
            scale: scale,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                children: [
                  // Sombra dura — "base" do botão 3D
                  Positioned(
                    top: 4,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: shadowColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  // Face do botão — afunda ao pressionar
                  Positioned(
                    top: _isPressed ? 4 : 0,
                    left: 0,
                    right: 0,
                    bottom: _isPressed ? 0 : 4,
                    child: Container(
                      decoration: activeDeco,
                      child: Center(
                        child: widget.isCompleted
                            ? const Icon(Icons.check_rounded,
                                color: AppColors.textOnDark, size: 48)
                            : locked
                                ? const Icon(Icons.lock_rounded,
                                    color: AppColors.textDisabled, size: 32)
                                : _phaseIcon(widget.phase.title),
                      ),
                    ),
                  ),
                  // Highlight elíptico no topo (reflexo)
                  if (!locked)
                    Positioned(
                      top: _isPressed ? 8 : 4,
                      left: 20,
                      child: Container(
                        width: 24,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Label da fase
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: AppShadows.sm,
          ),
          child: Text(
            widget.phase.title,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMd.copyWith(
              fontWeight: FontWeight.bold,
              color: locked ? AppColors.textDisabled : AppColors.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _phaseIcon(String title) {
    IconData iconData = Icons.star_rounded;
    final t = title.toLowerCase();
    if (t.contains('ferramentas') ||
        t.contains('técnicas') ||
        t.contains('hard skills')) {
      iconData = Icons.build_rounded;
    } else if (t.contains('idiomas') ||
        t.contains('inglês') ||
        t.contains('espanhol')) {
      iconData = Icons.translate_rounded;
    } else if (t.contains('experiências') ||
        t.contains('trabalho') ||
        t.contains('cargo')) {
      iconData = Icons.work_rounded;
    } else if (t.contains('sobre') ||
        t.contains('quem') ||
        t.contains('perfil')) {
      iconData = Icons.person_rounded;
    } else if (t.contains('cronômetro') || t.contains('tempo')) {
      iconData = Icons.timer_rounded;
    } else if (t.contains('partida') || t.contains('início')) {
      iconData = Icons.flag_rounded;
    } else if (t.contains('educação') ||
        t.contains('curso') ||
        t.contains('faculdade')) {
      iconData = Icons.school_rounded;
    }
    return Icon(iconData, color: AppColors.textOnDark, size: 40);
  }
}

// ════════════════════════════════════════════════════════════════════════════
// _PhasePathPainter — adaptado. Curva ativa entre fases completas usa gradient
// sutil top→bottom da cor única do mundo (baseColor).
// ════════════════════════════════════════════════════════════════════════════

class _PhasePathPainter extends CustomPainter {
  final int itemCount;
  final double itemHeight;
  final double centerOffset;
  final double amplitude;
  final List<bool> completedPhases;
  final Color baseColor;

  _PhasePathPainter({
    required this.itemCount,
    required this.itemHeight,
    required this.centerOffset,
    required this.amplitude,
    required this.completedPhases,
    required this.baseColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (itemCount < 2) return; // 1 fase = sem segmento

    final borderPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24.0
      ..strokeCap = StrokeCap.round;

    final inactivePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16.0
      ..strokeCap = StrokeCap.round;

    // 1. Borda de fundo contínua
    final fullPath = Path();
    for (int i = 0; i < itemCount - 1; i++) {
      _addSegment(fullPath, i, moveToStart: i == 0);
    }
    canvas.drawPath(fullPath, borderPaint);

    // 2. Segmento por segmento — colore onde o nó inicial está completo
    for (int i = 0; i < itemCount - 1; i++) {
      final segmentPath = Path();
      _addSegment(segmentPath, i, moveToStart: true);

      if (completedPhases[i]) {
        final rect = segmentPath.getBounds();
        final activePaint = Paint()
          ..shader = LinearGradient(
            colors: [
              baseColor,
              Color.alphaBlend(
                Colors.black.withValues(alpha: 0.15),
                baseColor,
              ),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16.0
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(segmentPath, activePaint);
      } else {
        canvas.drawPath(segmentPath, inactivePaint);
      }
    }
  }

  void _addSegment(Path path, int i, {required bool moveToStart}) {
    final double sideCurrent = (i % 2 == 0) ? -1.0 : 1.0;
    final double sideNext = ((i + 1) % 2 == 0) ? -1.0 : 1.0;

    final double startX = centerOffset + sideCurrent * amplitude;
    final double startY = (i * itemHeight) + (itemHeight / 2);
    final double endX = centerOffset + sideNext * amplitude;
    final double endY = ((i + 1) * itemHeight) + (itemHeight / 2);

    if (moveToStart) path.moveTo(startX, startY);

    final double controlY1 = startY + (endY - startY) * 0.5;
    final double controlY2 = startY + (endY - startY) * 0.5;
    path.cubicTo(startX, controlY1, endX, controlY2, endX, endY);
  }

  @override
  bool shouldRepaint(covariant _PhasePathPainter oldDelegate) {
    return oldDelegate.itemCount != itemCount ||
        oldDelegate.completedPhases != completedPhases ||
        oldDelegate.baseColor != baseColor;
  }
}
