// Átomos visuais do fio de conversa da Trilha de Coleta (PLANO-FASE-6 T6.3):
// bolha da IA (esquerda, com avatar), bolha do usuário (direita) e o indicador
// de "digitando" animado — o toque que dá calor de conversa.
//
// Motion (polimento): toda bolha entra com fade + slide curto (lateral coerente
// com o falante); o avatar "respira" enquanto a IA digita; os pontinhos ondulam
// em senoide. Tudo no design system (AppColors/AppShadows/AppGradients/AppSpacing).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart';

/// Cantos da bolha: o lado "preso" ao falante fica reto (4), os outros redondos.
const double _bubbleBig = 18;
const double _bubbleSmall = 4;
const double _maxBubbleFraction = 0.82;
const Duration _entranceDuration = Duration(milliseconds: 280);

/// Entrada padrão de um item do fio: fade + slide curto, dispara uma vez. dx<0
/// vem da esquerda (IA), dx>0 da direita (usuário). dy sempre sobe um pouco.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.child, this.dx = 0});

  final Widget child;
  final double dx;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: _entranceDuration,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset((1 - t) * dx, (1 - t) * 12),
          child: child,
        ),
      ),
    );
  }
}

/// Avatar da IA — círculo da marca com um brilho. Quando [animated] (durante o
/// "digitando"), respira: pulso suave de escala + halo brand pulsante.
class TrilhaAiAvatar extends StatefulWidget {
  const TrilhaAiAvatar({super.key, this.size = 34, this.animated = false});

  final double size;
  final bool animated;

  @override
  State<TrilhaAiAvatar> createState() => _TrilhaAiAvatarState();
}

class _TrilhaAiAvatarState extends State<TrilhaAiAvatar>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(TrilhaAiAvatar old) {
    super.didUpdateWidget(old);
    if (old.animated != widget.animated) _sync();
  }

  void _sync() {
    if (widget.animated) {
      _c ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1300),
      )..repeat(reverse: true);
    } else {
      _c?.dispose();
      _c = null;
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  Widget _disc(double scale, double glow) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          gradient: AppGradients.brand,
          shape: BoxShape.circle,
          boxShadow: glow > 0
              ? [
                  BoxShadow(
                    color: AppColors.brandCyan.withValues(alpha: glow),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.auto_awesome_rounded,
          color: AppColors.onPrimary,
          size: widget.size * 0.52,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return _disc(1.0, 0.0);
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(c.value);
        return _disc(1.0 + 0.06 * t, 0.30 * t);
      },
    );
  }
}

/// Bolha de fala da IA (esquerda).
class AiBubble extends StatelessWidget {
  const AiBubble({super.key, required this.text, this.showAvatar = true});

  final String text;

  /// Em bolhas consecutivas da IA, escondemos o avatar repetido (alinhamento
  /// mantido com um espaço da mesma largura).
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * _maxBubbleFraction;
    return _Entrance(
      dx: -16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAvatar)
            const TrilhaAiAvatar()
          else
            const SizedBox(width: 34),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: AppSpacing.base,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(_bubbleSmall),
                    topRight: Radius.circular(_bubbleBig),
                    bottomLeft: Radius.circular(_bubbleBig),
                    bottomRight: Radius.circular(_bubbleBig),
                  ),
                  boxShadow: AppShadows.brand,
                ),
                child: Text(
                  text,
                  style: AppTextStyles.bodyLg.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bolha de resposta do usuário (direita).
class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * _maxBubbleFraction;
    return _Entrance(
      dx: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: AppSpacing.base,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(_bubbleBig),
                    topRight: Radius.circular(_bubbleBig),
                    bottomLeft: Radius.circular(_bubbleBig),
                    bottomRight: Radius.circular(_bubbleSmall),
                  ),
                  boxShadow: AppShadows.sm,
                ),
                child: Text(
                  text,
                  style: AppTextStyles.bodyLg.copyWith(
                    color: AppColors.onPrimary,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Os 3 pontinhos pulsando — onda senoidal suave (escala + opacidade defasadas).
/// Reutilizável: serve no "digitando" e como spinner da marca em passos da IA.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.color = AppColors.textTertiary, this.dot = 8});

  final Color color;
  final double dot;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_c.value + i * 0.18) % 1.0;
            final wave = (math.sin(phase * 2 * math.pi) + 1) / 2;
            final scale = 0.7 + 0.3 * wave;
            final opacity = 0.4 + 0.6 * wave;
            return Padding(
              padding: EdgeInsets.only(right: i < 2 ? AppSpacing.xs : 0),
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: widget.dot,
                    height: widget.dot,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Indicador de "digitando" — avatar respirando + 3 pontinhos ondulando.
class TypingBubble extends StatelessWidget {
  const TypingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return _Entrance(
      dx: -16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TrilhaAiAvatar(animated: true),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.base,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(_bubbleSmall),
                topRight: Radius.circular(_bubbleBig),
                bottomLeft: Radius.circular(_bubbleBig),
                bottomRight: Radius.circular(_bubbleBig),
              ),
              boxShadow: AppShadows.brand,
            ),
            child: const TypingDots(),
          ),
        ],
      ),
    );
  }
}
