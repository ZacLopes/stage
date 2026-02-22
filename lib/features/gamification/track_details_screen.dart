import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../data/models/models.dart';
import '../auth/user_viewmodel.dart';
import '../resume/widgets/ai_consent_modal.dart';
import 'gamification_viewmodel.dart';
import 'question_screen.dart';
import 'interview_report_screen.dart';

class TrackDetailsScreen extends StatefulWidget {
  final Track track;

  const TrackDetailsScreen({super.key, required this.track});

  @override
  State<TrackDetailsScreen> createState() => _TrackDetailsScreenState();
}

class _TrackDetailsScreenState extends State<TrackDetailsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        context.read<GamificationViewModel>().loadPhases(widget.track.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.track.title),
        backgroundColor: Color(widget.track.color),
        foregroundColor: Colors.white,
      ),
      body: Consumer<GamificationViewModel>(
        builder: (context, viewModel, child) {
          if (viewModel.isLoadingPhases) {
            return const Center(child: CircularProgressIndicator());
          }

          return Stack(
            children: [
              ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: viewModel.phases.length + 1, // +1 for extra space
                itemBuilder: (context, index) {
                  if (index == viewModel.phases.length) {
                     return const SizedBox(height: 80); // Space for FAB
                  }
                  final phase = viewModel.phases[index];
                  if (phase.title == 'Revisão') return const SizedBox.shrink(); // Failsafe UI hide
                  return _buildPhaseCard(context, phase, index);
                },
              ),
              if (widget.track.id == 'track_secret')
                 Positioned(
                   bottom: 16,
                   left: 16,
                   right: 16,
                   child: _buildSecretReportButton(context),
                 ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSecretReportButton(BuildContext context) {
    return ElevatedButton(
      onPressed: () => _generateSecretReport(context),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: const Color(0xFFFFD700),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 8,
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome),
          SizedBox(width: 8),
          Text(
            'GERAR RELATÓRIO DE ELITE',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
        ],
      ),
    );
  }

  Future<bool> _checkAndShowAIConsent(BuildContext context) async {
    final userVM = context.read<UserViewModel>();
    final user = userVM.user;
    
    if (user != null && user.aiConsent) {
      return true;
    }

    final completer = Completer<bool>();

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      pageBuilder: (context, anim1, anim2) => AIConsentModal(
        onAccept: () async {
          await userVM.updateAIConsent(true);
          if (context.mounted) Navigator.pop(context);
          completer.complete(true);
        },
        onCancel: () {
          Navigator.pop(context);
          completer.complete(false);
        },
      ),
    );

    return completer.future;
  }

  Future<void> _generateSecretReport(BuildContext context) async {
    // 1. Check AI consent BEFORE sending any data
    if (!await _checkAndShowAIConsent(context)) {
      return; // User declined consent
    }

    // 2. Show Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFD700)),
      ),
    );

    try {
      // 3. Gather answers
      final viewModel = context.read<GamificationViewModel>();
      final answers = await viewModel.getAnswersForTrack(widget.track.id);

      if (!context.mounted) return;
      
      // 4. Call AI
      final report = await context.read<GamificationViewModel>().generateInterviewReport(answers);
      
      if (!context.mounted) return;
      Navigator.pop(context); // Close loading

      // 5. Navigate to Report
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => InterviewReportScreen(report: report)),
      );

    } catch (e) {
      if (context.mounted) {
         Navigator.pop(context); // Close loading
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Erro ao gerar relatório: $e')),
         );
      }
    }
  }

  Widget _buildPhaseCard(BuildContext context, Phase phase, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => QuestionScreen(phase: phase),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Color(widget.track.color).withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: Color(widget.track.color),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      phase.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phase.description,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 16),
                  Text(
                    '${phase.xpReward} XP',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
