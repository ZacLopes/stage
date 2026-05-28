import 'package:flutter/widgets.dart';

/// Escala de espaçamento em incrementos de 4px.
///
/// Substitui `EdgeInsets.all(11)`, `.all(14)`, `.symmetric(horizontal: 22)`
/// e outros valores ad-hoc espalhados pelo app — todos viram um dos 8 abaixo.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double base = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xl2 = 32;
  static const double xl3 = 48;

  // Atalhos pra EdgeInsets simétricos comuns
  static const EdgeInsets allXs = EdgeInsets.all(xs);
  static const EdgeInsets allSm = EdgeInsets.all(sm);
  static const EdgeInsets allMd = EdgeInsets.all(md);
  static const EdgeInsets allBase = EdgeInsets.all(base);
  static const EdgeInsets allLg = EdgeInsets.all(lg);
  static const EdgeInsets allXl = EdgeInsets.all(xl);

  static const EdgeInsets pageHorizontal =
      EdgeInsets.symmetric(horizontal: base);
  static const EdgeInsets pageVertical =
      EdgeInsets.symmetric(vertical: base);
}
