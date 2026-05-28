import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Tipografia centralizada. Outfit (headings) + Inter (body), bundled como
/// fontes nativas (não google_fonts).
///
/// Hierarquia:
/// - display  — heros, splash, números grandes de gamificação
/// - headline — títulos de tela
/// - title    — títulos de seção / card
/// - body     — texto corrido
/// - label    — botões, chips, badges
/// - caption  — metadados, microcopy
/// - overline — eyebrow text
class AppTextStyles {
  AppTextStyles._();

  static const String _headingFamily = 'Outfit';
  static const String _bodyFamily = 'Inter';

  // ─── Display ─────────────────────────────────────────────────────────
  static const TextStyle displayLg = TextStyle(
    fontFamily: _headingFamily,
    fontSize: 32,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  static const TextStyle displayMd = TextStyle(
    fontFamily: _headingFamily,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  // ─── Headline (títulos de tela) ──────────────────────────────────────
  static const TextStyle headlineLg = TextStyle(
    fontFamily: _headingFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.25,
  );

  static const TextStyle headlineMd = TextStyle(
    fontFamily: _headingFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  // ─── Title (títulos de seção / card) ─────────────────────────────────
  static const TextStyle titleLg = TextStyle(
    fontFamily: _headingFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  static const TextStyle titleMd = TextStyle(
    fontFamily: _headingFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  static const TextStyle titleSm = TextStyle(
    fontFamily: _headingFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  // ─── Body ────────────────────────────────────────────────────────────
  static const TextStyle bodyLg = TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.45,
  );

  static const TextStyle bodyMd = TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.45,
  );

  static const TextStyle bodySm = TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  // ─── Label (botões, chips, badges) ───────────────────────────────────
  static const TextStyle labelLg = TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  static const TextStyle labelMd = TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  static const TextStyle labelSm = TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  // ─── Caption ─────────────────────────────────────────────────────────
  static const TextStyle caption = TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textTertiary,
    height: 1.35,
  );

  // ─── Overline (eyebrow / pequenos rótulos all-caps) ──────────────────
  static const TextStyle overline = TextStyle(
    fontFamily: _bodyFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textTertiary,
    letterSpacing: 1.2,
    height: 1.35,
  );
}
