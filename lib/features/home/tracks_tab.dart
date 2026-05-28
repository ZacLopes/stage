import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../auth/user_viewmodel.dart';
import 'home_viewmodel.dart';
import 'open_trail_view.dart';
import '../gamification/gamification_viewmodel.dart';

class TracksTab extends StatelessWidget {
  /// Optional back affordance shown as an arrow in the header's top-left
  /// corner. When the tab is rendered embedded inside another screen
  /// (e.g. as a sub-page of the Currículo tab), the host passes this to
  /// let the user return to the entry-point.
  final VoidCallback? onBack;

  const TracksTab({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    final userViewModel = context.watch<UserViewModel>();

    return Column(
      children: [
        // Header
        _buildHeader(context, userViewModel),
        // Tracks List
        Expanded(
          child: Consumer<HomeViewModel>(
            builder: (context, viewModel, child) {
              if (viewModel.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              return const OpenTrailView();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, UserViewModel userViewModel) {
    return Consumer<GamificationViewModel>(
      builder: (context, gameViewModel, child) {
        final progress = gameViewModel.totalCareerProgress;
        final percentage = (progress * 100).toInt();
        
        return Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppRadius.xl)),
            boxShadow: AppShadows.sm,
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (onBack != null) ...[
                    GestureDetector(
                      onTap: onBack,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(
                    child: Text(
                      'Vamos construir seu currículo?',
                      style: AppTextStyles.titleLg,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs + 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.successSoft,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: AppColors.success, size: 16),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '$percentage% Pronto',
                          style: AppTextStyles.labelSm.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              // Career Completion Progress Bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: AppColors.border,
                      color: AppColors.success,
                      minHeight: 12,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Complete as fases para gerar seu currículo profissional.',
                    style: AppTextStyles.caption.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
