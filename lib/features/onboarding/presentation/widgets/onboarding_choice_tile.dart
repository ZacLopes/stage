import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/theme.dart';

/// Ladrilho de escolha ÚNICA do onboarding (revisão UX 28/07, achado P3-41).
///
/// O wizard tinha quatro controles diferentes para a mesma pergunta "escolha
/// uma": check que só aparecia DEPOIS de selecionar (origem, gênero), rádio
/// redondo (momento), checkbox quadrado (modelo de trabalho) e chips (áreas).
/// O check-só-quando-selecionado é o pior dos quatro — antes do toque não há
/// afordância nenhuma de que aquilo é escolhível, nem de que é uma escolha só.
///
/// Regra que ficou: **redondo = escolha uma; quadrado = escolha quantas
/// quiser** ([OnboardingMultiCheck]), sempre visível nos dois estados.
///
/// Chips continuam sendo a exceção, e a razão anotada aqui antes era falsa:
/// eu escrevi "listas longas com busca", mas a tela de áreas
/// (`desired_titles_screen.dart`) é um `Wrap` de 13 chips **sem campo de
/// busca nenhum**. O critério real é outro e é geométrico: rótulos curtos em
/// quantidade cabem três por linha num `Wrap` e viram uma lista de treze
/// linhas se forem ladrilhos. Chips seguem valendo aí — pelo motivo certo.
class OnboardingChoiceTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const OnboardingChoiceTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? AppColors.primary : AppColors.textDisabled,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
