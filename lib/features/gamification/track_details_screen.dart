import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/models.dart';
import 'gamification_viewmodel.dart';
import 'question_screen.dart';

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

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: viewModel.phases.length,
            itemBuilder: (context, index) {
              final phase = viewModel.phases[index];
              if (phase.title == 'Revisão') return const SizedBox.shrink();
              return _buildPhaseCard(context, phase, index);
            },
          );
        },
      ),
    );
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
            ],
          ),
        ),
      ),
    );
  }
}
