import 'package:flutter/widgets.dart';

import 'app_colors.dart';

/// Gradients centralizados. Antes cada feature inventava o seu
/// (settings tinha indigo+violet, jobs/gamification tinham suas combinações).
class AppGradients {
  AppGradients._();

  /// Gradient da marca (logo Stage) — cyan → blue. Splash, headers, CTAs.
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.brandCyan, AppColors.brandBlue],
  );

  /// Variante vertical do brand — pra backgrounds full-screen.
  static const LinearGradient brandVertical = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.brandCyan, AppColors.brandBlue],
  );

  /// Fundo claro tintado de azul. Pra hero sections e overlays suaves.
  static const LinearGradient surfaceSoft = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF5F9FF), Color(0xFFE8F4FD)],
  );

  /// Pra estados de sucesso (phase completion, milestones).
  static const LinearGradient success = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF22C55E), AppColors.success],
  );

  /// Pra elementos de XP / conquista.
  static const LinearGradient xp = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFCD34D), AppColors.xp],
  );
}
