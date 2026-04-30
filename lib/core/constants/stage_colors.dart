import 'package:flutter/material.dart';

/// Stage brand colors extracted from the logo gradient.
class StageColors {
  StageColors._();

  // Brand gradient endpoints
  static const Color brandCyan = Color(0xFF29B6D2);
  static const Color brandBlue = Color(0xFF1565A8);

  // CTA / Action cyan (aligned with brand blue)
  static const Color ctaGreen = Color(0xFF29B6D2); // Now using brand cyan for primary actions

  // Branding specific
  static const Color brandCyanAccent = Color(0xFFE0F7FA);
  static const Color starGold = Color(0xFFFFD700);

  // Backgrounds
  static const Color offWhite = Color(0xFFF5F9FF);
  static const Color scaffoldGray = Color(0xFFF3F4F6);

  // Text
  static const Color darkText = Color(0xFF1F2937);
  static const Color titleText = Color(0xFF111827);
  static const Color subtitleGray = Color(0xFF6B7280);
  static const Color bodyGray = Color(0xFF4B5563);
  static const Color hintGray = Color(0xFF9CA3AF);

  // Chip states
  static const Color chipUnselectedBg = Color(0xFFF0F0F0);
  static const Color chipUnselectedText = Color(0xFF374151);
  static const Color chipBorder = Color(0xFFD1D5DB);

  // Error
  static const Color error = Color(0xFFEF4444);

  // Brand gradient (used for splash, headers, accents)
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandCyan, brandBlue],
  );

  // Lighter gradient for backgrounds
  static const LinearGradient lightGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [offWhite, Color(0xFFE8F4FD)],
  );
}
