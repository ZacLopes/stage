import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/models.dart';
import '../auth/user_viewmodel.dart';
import 'home_viewmodel.dart';
import 'gamified_track_list.dart';
import '../gamification/level_progress_screen.dart';
import '../gamification/level_system.dart';
import '../gamification/gamification_viewmodel.dart';

import '../../core/constants/tutorial_keys.dart';

class TracksTab extends StatelessWidget {
  const TracksTab({super.key});

  @override
  Widget build(BuildContext context) {
    final userViewModel = context.watch<UserViewModel>();
    final user = userViewModel.user;

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
              
              return GamifiedTrackList(tracks: viewModel.tracks);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, UserViewModel userViewModel) {
    final user = userViewModel.user;
    
    // We use GamificationViewModel for global progress
    return Consumer<GamificationViewModel>(
      builder: (context, gameViewModel, child) {
        final progress = gameViewModel.totalCareerProgress;
        final percentage = (progress * 100).toInt();
        
        return Container(
          key: TutorialKeys.xpHeaderKey,
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
