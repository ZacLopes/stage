import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Helpers semânticos pra mostrar SnackBars de forma consistente.
///
/// Antes cada feature montava seu próprio com cores ad-hoc. Agora:
/// `AppSnackBar.success(context, 'Salvo!')` etc.
class AppSnackBar {
  AppSnackBar._();

  static void success(BuildContext context, String message) =>
      _show(context, message, AppColors.success, Icons.check_circle_rounded);

  static void error(BuildContext context, String message) =>
      _show(context, message, AppColors.error, Icons.error_rounded);

  static void warning(BuildContext context, String message) =>
      _show(context, message, AppColors.warning, Icons.warning_rounded);

  static void info(BuildContext context, String message) =>
      _show(context, message, AppColors.info, Icons.info_rounded);

  static void _show(
    BuildContext context,
    String message,
    Color accent,
    IconData icon,
  ) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  message,
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.textOnDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
