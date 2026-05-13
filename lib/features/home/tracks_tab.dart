import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
    final user = userViewModel.user;

    return Consumer<GamificationViewModel>(
      builder: (context, gameViewModel, child) {
        final progress = gameViewModel.totalCareerProgress;
        final percentage = (progress * 100).toInt();
        
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
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
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: Color(0xFF4F46E5),
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Olá, ${user?.name ?? "Estudante"}!',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF111827),
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Vamos construir seu currículo?',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF6B7280),
                              ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7), // Light green
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '$percentage% Pronto',
                          style: const TextStyle(
                            color: Color(0xFF15803D),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Career Completion Progress Bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey[200],
                      color: const Color(0xFF00C27A), // Duolingo Green
                      minHeight: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Complete as fases para gerar seu currículo profissional.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
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
