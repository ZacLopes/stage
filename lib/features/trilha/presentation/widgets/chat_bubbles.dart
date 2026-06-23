// Átomos visuais do fio de conversa da Trilha de Coleta (PLANO-FASE-6 T6.3):
// bolha da IA (esquerda, com avatar), bolha do usuário (direita) e o indicador
// de "digitando" animado — o toque que dá calor de conversa.
//
// Tudo no design system (AppColors/AppTextStyles/AppSpacing). A geometria de
// bolha de chat (canto pequeno de um lado) é um idioma de chat, definido local.

import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart';

/// Cantos da bolha: o lado "preso" ao falante fica reto (4), os outros redondos.
const double _bubbleBig = 18;
const double _bubbleSmall = 4;
const double _maxBubbleFraction = 0.78;

/// Avatar da IA — círculo da marca com um brilho. Reusado pela bolha e pelo
/// indicador de digitação.
class TrilhaAiAvatar extends StatelessWidget {
  const TrilhaAiAvatar({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: AppGradients.brand,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.auto_awesome_rounded,
        color: AppColors.onPrimary,
        size: size * 0.52,
      ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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
                  vertical: AppSpacing.md,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(_bubbleSmall),
                    topRight: Radius.circular(_bubbleBig),
                    bottomLeft: Radius.circular(_bubbleBig),
                    bottomRight: Radius.circular(_bubbleBig),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x0F000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  text,
                  style: AppTextStyles.bodyLg.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.4,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: AppSpacing.md,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(_bubbleBig),
                    topRight: Radius.circular(_bubbleBig),
                    bottomLeft: Radius.circular(_bubbleBig),
                    bottomRight: Radius.circular(_bubbleSmall),
                  ),
                ),
                child: Text(
                  text,
                  style: AppTextStyles.bodyLg.copyWith(
                    color: AppColors.onPrimary,
                    height: 1.4,
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

/// Indicador de "digitando" — 3 pontinhos pulsando dentro de uma bolha da IA.
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
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
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TrilhaAiAvatar(),
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
              boxShadow: [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    // Cada ponto pulsa defasado.
                    final t = (_c.value + i * 0.2) % 1.0;
                    final scale = 0.6 + 0.4 * (1 - (2 * t - 1).abs());
                    return Padding(
                      padding: EdgeInsets.only(right: i < 2 ? AppSpacing.xs : 0),
                      child: Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.textTertiary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
