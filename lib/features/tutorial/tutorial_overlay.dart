import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'tutorial_controller.dart';
import 'tutorial_step.dart';
import '../../core/theme/theme.dart';

/// Full-screen overlay that dims the app, cuts a spotlight hole around
/// the current step's target widget, and shows a tooltip card explaining
/// what the user is looking at. Listens to [TutorialController] and
/// rebuilds on every step change.
///
/// Mounted once at the root via `MaterialApp.builder`. When the
/// controller is idle (`!isRunning`), it renders nothing.
class TutorialOverlay extends StatelessWidget {
  const TutorialOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TutorialController>(
      builder: (context, controller, _) {
        if (!controller.isRunning) return const SizedBox.shrink();

        final step = controller.currentStep;
        if (step == null) return const SizedBox.shrink();

        // While the controller is mid-transition (onEnter running),
        // show a soft dimmed scrim with a centered spinner so the
        // user gets feedback that something's happening but no
        // mis-positioned spotlight flashes on screen.
        if (controller.isTransitioning) {
          return _TransitioningScrim();
        }

        return _StepOverlay(step: step, controller: controller);
      },
    );
  }
}

class _TransitioningScrim extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        color: Colors.black.withOpacity(0.55),
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepOverlay extends StatefulWidget {
  final TutorialStep step;
  final TutorialController controller;
  const _StepOverlay({required this.step, required this.controller});

  @override
  State<_StepOverlay> createState() => _StepOverlayState();
}

class _StepOverlayState extends State<_StepOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..forward();
    _fade = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Rect? _targetRect() {
    final key = widget.step.targetKey;
    if (key == null) return null;
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.attached) return null;
    final offset = ro.localToGlobal(Offset.zero);
    return offset & ro.size;
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final rawTarget = _targetRect();
    final target = rawTarget?.inflate(widget.step.padding);

    return FadeTransition(
      opacity: _fade,
      child: Stack(
        children: [
          // Dimmed scrim + spotlight hole. Eats taps so the user can't
          // interact with the UI behind it — they have to either advance
          // via "Próximo" or skip.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {}, // swallow
              child: CustomPaint(
                painter: _SpotlightPainter(
                  targetRect: target,
                  radius: widget.step.radius,
                ),
              ),
            ),
          ),
          // Soft glowing ring around the target to draw the eye.
          if (target != null)
            Positioned(
              left: target.left - 4,
              top: target.top - 4,
              width: target.width + 8,
              height: target.height + 8,
              child: IgnorePointer(
                child: _PulsingRing(radius: widget.step.radius + 2),
              ),
            ),
          // Tooltip card with title/description/actions.
          _Tooltip(
            step: widget.step,
            target: target,
            screen: screen,
            controller: widget.controller,
          ),
        ],
      ),
    );
  }
}

// ─── Spotlight cut-out ──────────────────────────────────────────────────
class _SpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  final double radius;

  _SpotlightPainter({required this.targetRect, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.72);

    if (targetRect == null) {
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }

    // even-odd fill: rect minus rounded hole = dimmed everywhere except
    // the target.
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(targetRect!, Radius.circular(radius)));
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.targetRect != targetRect || old.radius != radius;
}

// ─── Soft pulsing ring around the spotlight ─────────────────────────────
class _PulsingRing extends StatefulWidget {
  final double radius;
  const _PulsingRing({required this.radius});

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(
              color: AppColors.gold.withOpacity(0.6 + 0.4 * t),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withOpacity(0.25 + 0.25 * t),
                blurRadius: 14 + 8 * t,
                spreadRadius: 1.5,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Tooltip card ───────────────────────────────────────────────────────
class _Tooltip extends StatelessWidget {
  final TutorialStep step;
  final Rect? target;
  final Size screen;
  final TutorialController controller;

  const _Tooltip({
    required this.step,
    required this.target,
    required this.screen,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    // Decide tooltip position:
    //   - no target / anchor=center → center vertically
    //   - target in top half       → below
    //   - target in bottom half    → above
    const horizontalPadding = 20.0;
    const tooltipMaxWidth = 340.0;

    final wantsCenter =
        step.anchor == TutorialTooltipAnchor.center || target == null;

    Widget card = _TooltipCard(step: step, controller: controller);

    if (wantsCenter) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: tooltipMaxWidth),
            child: card,
          ),
        ),
      );
    }

    final t = target!;
    final placeBelow = t.center.dy < screen.height * 0.5;
    final mediaPadding = MediaQuery.of(context).padding;

    if (placeBelow) {
      final top = t.bottom + 16;
      return Positioned(
        left: horizontalPadding,
        right: horizontalPadding,
        top: top,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _ArrowUp(targetCenterX: t.center.dx),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: tooltipMaxWidth),
                child: card,
              ),
            ),
          ],
        ),
      );
    } else {
      // place above
      final bottom = screen.height - t.top + 16;
      return Positioned(
        left: horizontalPadding,
        right: horizontalPadding,
        bottom: bottom - mediaPadding.bottom,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: tooltipMaxWidth),
                child: card,
              ),
            ),
            _ArrowDown(targetCenterX: t.center.dx),
          ],
        ),
      );
    }
  }
}

class _TooltipCard extends StatelessWidget {
  final TutorialStep step;
  final TutorialController controller;
  const _TooltipCard({required this.step, required this.controller});

  @override
  Widget build(BuildContext context) {
    final isLast = controller.currentIndex == controller.totalSteps - 1;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E1B4B), AppColors.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.35),
              blurRadius: 28,
              spreadRadius: 1,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top: step counter + skip
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${controller.currentIndex + 1}/${controller.totalSteps}',
                    style: TextStyle(fontFamily: 'Inter', 
                      fontSize: 10.5,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: controller.skip,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Pular tutorial',
                    style: TextStyle(fontFamily: 'Inter', 
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Title
            Text(
              step.title,
              style: TextStyle(fontFamily: 'Outfit', 
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.2,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            // Description
            Text(
              step.description,
              style: TextStyle(fontFamily: 'Inter', 
                fontSize: 13,
                color: Colors.white.withOpacity(0.85),
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            // Último step com finalChoices → 2 CTAs empilhados (em vez do
            // botão "Bora começar" único). Cada um finaliza o tutorial e
            // dispara o callback (navegação + analytics) configurado no
            // step. Os progress dots somem porque o user já chegou no fim.
            if (isLast && step.finalChoices.isNotEmpty)
              _FinalChoicesActions(step: step, controller: controller)
            else
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: List.generate(controller.totalSteps, (i) {
                        final active = i == controller.currentIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          margin: const EdgeInsets.only(right: 4),
                          height: 4,
                          width: active ? 18 : 6,
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.gold
                                : Colors.white.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: controller.next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1E1B4B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isLast ? 'Bora começar' : 'Próximo',
                          style: TextStyle(fontFamily: 'Inter',
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// CTAs empilhados pro último step quando `step.finalChoices` está
/// preenchido. Cada botão finaliza o tutorial (marca seen + fecha
/// overlay) ANTES de chamar o callback do choice, então a navegação
/// acontece com a UI já limpa.
class _FinalChoicesActions extends StatelessWidget {
  final TutorialStep step;
  final TutorialController controller;
  const _FinalChoicesActions({required this.step, required this.controller});

  @override
  Widget build(BuildContext context) {
    final choices = step.finalChoices;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < choices.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                await controller.finish();
                await choices[i].onTap();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: i == 0
                    ? Colors.white
                    : Colors.white.withOpacity(0.12),
                foregroundColor: i == 0
                    ? const Color(0xFF1E1B4B)
                    : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: i == 0
                      ? BorderSide.none
                      : BorderSide(color: Colors.white.withOpacity(0.3)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                elevation: 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(choices[i].icon, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    choices[i].label,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// Small triangle pointing up (tooltip is below target).
class _ArrowUp extends StatelessWidget {
  final double targetCenterX;
  const _ArrowUp({required this.targetCenterX});
  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final align = ((targetCenterX / screenW) * 2 - 1).clamp(-0.85, 0.85);
    return Align(
      alignment: Alignment(align, 0),
      child: CustomPaint(
        size: const Size(16, 8),
        painter: _TrianglePainter(pointsUp: true),
      ),
    );
  }
}

// Small triangle pointing down (tooltip is above target).
class _ArrowDown extends StatelessWidget {
  final double targetCenterX;
  const _ArrowDown({required this.targetCenterX});
  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final align = ((targetCenterX / screenW) * 2 - 1).clamp(-0.85, 0.85);
    return Align(
      alignment: Alignment(align, 0),
      child: CustomPaint(
        size: const Size(16, 8),
        painter: _TrianglePainter(pointsUp: false),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final bool pointsUp;
  _TrianglePainter({required this.pointsUp});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF1E1B4B);
    final path = Path();
    if (pointsUp) {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(0, size.height)
        ..lineTo(size.width, size.height)
        ..close();
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.pointsUp != pointsUp;
}
