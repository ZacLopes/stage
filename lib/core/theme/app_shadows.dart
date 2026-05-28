import 'package:flutter/widgets.dart';

/// Sombras em 3 níveis. Substituem `BoxShadow(blurRadius: 24, offset: ...)`
/// inventados por feature.
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> sm = <BoxShadow>[
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> md = <BoxShadow>[
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> lg = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  /// Sombra suave azul (brand-tinted), pra cards de destaque.
  static const List<BoxShadow> brand = <BoxShadow>[
    BoxShadow(
      color: Color(0x141565A8),
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];
}
