// Decoração padrão dos TextFields do onboarding.
//
// Centraliza cores, raios, paddings e estado focado. Sem esta utility, cada
// tela tinha sua própria InputDecoration inline — uma com borda focada azul
// (#29B6D2), outra com a borda preta padrão do Flutter, padding levemente
// diferente. Pro user, era inconsistência visual entre telas do mesmo fluxo.
//
// Como usar:
//   decoration: onboardingInputDecoration(hintText: 'Ex: Maria'),
//
// Pra suffixIcon ou estados de erro custom, passa via parâmetros. Pra
// decorações muito complexas (ex: AgeRangeScreen com borda vermelha de
// validação), continua inline — esta função não tenta cobrir todo caso.

import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';

const _kBorderColor = AppColors.border;
const _kHintColor = AppColors.textDisabled;
const _kAccent = AppColors.primary;

/// Retorna a `InputDecoration` padrão das telas do onboarding.
/// Aparência consistente: fundo branco, borda cinza clara fina, borda
/// focada accent #29B6D2 com 2px, raio 12, padding generoso.
InputDecoration onboardingInputDecoration({
  String? hintText,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(color: _kHintColor),
    filled: true,
    fillColor: Colors.white,
    suffixIcon: suffixIcon,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _kBorderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _kBorderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _kAccent, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
  );
}
