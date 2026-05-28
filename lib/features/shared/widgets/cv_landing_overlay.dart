import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';

/// Plays a one-shot "document flying to Profile tab" animation by inserting
/// a temporary [OverlayEntry]. Used after a CV is auto-saved (via trail
/// completion or PDF import) to guide the user to the Profile tab in the
/// bottom nav.
///
/// [profileIconKey] must be attached to the Profile bottom-nav item widget
/// — its global bounds determine the animation's landing point. If the
/// key can't resolve a position (e.g. nav not yet laid out), the future
/// resolves quickly without animating, so callers can proceed.
Future<void> playCvLandingAnimation(
  BuildContext context, {
  required GlobalKey profileIconKey,
  Duration duration = const Duration(milliseconds: 1200),
}) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  final renderObj = profileIconKey.currentContext?.findRenderObject();
  if (renderObj is! RenderBox || !renderObj.attached) return;

  final size = MediaQuery.of(context).size;
  final iconCenter =
      renderObj.localToGlobal(renderObj.size.center(Offset.zero));
  final startCenter = Offset(size.width / 2, size.height / 2);

  final entry = OverlayEntry(
    builder: (ctx) => _CvLandingAnimation(
      start: startCenter,
      end: iconCenter,
      duration: duration,
    ),
  );

  overlay.insert(entry);
  await Future.delayed(duration);
  entry.remove();
}

class _CvLandingAnimation extends StatefulWidget {
  final Offset start;
  final Offset end;
  final Duration duration;

  const _CvLandingAnimation({
    required this.start,
    required this.end,
    required this.duration,
  });

  @override
  State<_CvLandingAnimation> createState() => _CvLandingAnimationState();
}

class _CvLandingAnimationState extends State<_CvLandingAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();

    _progress = CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);

    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 1.1).chain(CurveTween(curve: Curves.easeOutBack)), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.4).chain(CurveTween(curve: Curves.easeIn)), weight: 40),
    ]).animate(_controller);

    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 15),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 25),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          final t = _progress.value;
          // Arc trajectory: lift mid-flight for a "tossing" feel.
          final dx = widget.start.dx + (widget.end.dx - widget.start.dx) * t;
          final straightY =
              widget.start.dy + (widget.end.dy - widget.start.dy) * t;
          final arcLift = -120.0 * (4 * t * (1 - t)); // peak at t=0.5
          final dy = straightY + arcLift;

          return Stack(
            children: [
              Positioned(
                left: dx - 36,
                top: dy - 36,
                child: Opacity(
                  opacity: _opacity.value,
                  child: Transform.scale(
                    scale: _scale.value,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.55),
                            blurRadius: 28,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.description_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
