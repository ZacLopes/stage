import 'package:flutter/material.dart';

import '../../../../core/theme/theme.dart';

/// Quadrado de escolha MÚLTIPLA do onboarding.
///
/// Revisão UX 28/07, achado P3-41. A regra do wizard é
/// **redondo = escolha uma; quadrado = escolha quantas quiser**, sempre
/// visível nos dois estados — o par deste widget é o [OnboardingChoiceTile].
///
/// Existia duas vezes, byte a byte igual, em `work_mode_screen` e
/// `job_types_screen`. Duas cópias de um controle cuja razão de existir é
/// *ser reconhecível* são exatamente o tipo de duplicata que vira defeito:
/// basta alguém ajustar o raio ou a cor de uma para o wizard voltar a ter
/// dois quadrados diferentes para a mesma pergunta.
class OnboardingMultiCheck extends StatelessWidget {
  final bool selected;
  const OnboardingMultiCheck({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : Colors.white,
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.borderStrong,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
          : null,
    );
  }
}
