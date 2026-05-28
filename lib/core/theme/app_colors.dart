import 'package:flutter/material.dart';

/// Stage design tokens — paleta semântica.
///
/// Organizada por **função** (primary, success, surface…), não por matiz.
/// A identidade visual segue o gradient do logo Stage (cyan → blue);
/// verde é exclusivamente cor de sucesso.
class AppColors {
  AppColors._();

  // ─── Brand (gradient do logo) ────────────────────────────────────────
  static const Color brand = Color(0xFF1E88B8);
  static const Color brandCyan = Color(0xFF29B6D2);
  static const Color brandBlue = Color(0xFF1565A8);
  static const Color brandSoft = Color(0xFFE0F4FA);

  // ─── Primary (CTA, foco, ações principais) ───────────────────────────
  static const Color primary = brandBlue;
  static const Color primaryHover = Color(0xFF0F4A82);
  static const Color primarySoft = brandSoft;
  static const Color onPrimary = Colors.white;

  // ─── Secondary (acentos, ícones de AppBar, links) ────────────────────
  static const Color secondary = brandCyan;
  static const Color secondarySoft = Color(0xFFE0F7FA);
  static const Color onSecondary = Colors.white;

  // ─── Semânticas (1 cor cada) ─────────────────────────────────────────
  static const Color success = Color(0xFF16A34A);
  static const Color successSoft = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningSoft = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFEF4444);
  static const Color errorSoft = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF0EA5E9);
  static const Color infoSoft = Color(0xFFE0F2FE);

  // ─── Gamificação (XP, conquistas) ────────────────────────────────────
  static const Color xp = Color(0xFFF59E0B);
  static const Color gold = Color(0xFFFFD700);
  static const Color silver = Color(0xFFC0C0C0);
  static const Color bronze = Color(0xFFCD7F32);

  // ─── Trilhas (paleta rotativa, 5 cores harmoniosas) ──────────────────
  /// Usada em gamification pra colorir fases. Antes era array hardcoded
  /// dentro de gamified_phase_list.dart.
  static const List<Color> trackPalette = <Color>[
    Color(0xFF29B6D2), // cyan (brand)
    Color(0xFF7C3AED), // violet
    Color(0xFFF59E0B), // amber
    Color(0xFFEF4444), // red
    Color(0xFF16A34A), // green
  ];

  // ─── Neutros ─────────────────────────────────────────────────────────
  static const Color background = Color(0xFFF3F4F6);
  static const Color surface = Colors.white;
  static const Color surfaceVariant = Color(0xFFF9FAFB);
  static const Color surfaceMuted = Color(0xFFF0F0F0);
  static const Color overlay = Color(0x66000000);

  // ─── Texto (4 níveis + invertido) ────────────────────────────────────
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF4B5563);
  static const Color textTertiary = Color(0xFF6B7280);
  static const Color textDisabled = Color(0xFF9CA3AF);
  static const Color textOnDark = Colors.white;

  // ─── Bordas ──────────────────────────────────────────────────────────
  static const Color border = Color(0xFFE5E7EB);
  static const Color borderStrong = Color(0xFFD1D5DB);
  static const Color divider = Color(0xFFF3F4F6);
}
