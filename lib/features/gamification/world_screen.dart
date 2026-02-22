import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/models.dart';
import '../home/home_viewmodel.dart';
import 'gamification_viewmodel.dart';
import 'gamified_phase_list.dart';

class WorldScreen extends StatefulWidget {
  final Track world;

  const WorldScreen({super.key, required this.world});

  @override
  State<WorldScreen> createState() => _WorldScreenState();
}

class _WorldScreenState extends State<WorldScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<HomeViewModel>(
        builder: (context, viewModel, child) {
          final phases = viewModel.phasesByTrack[widget.world.id] ?? [];

          if (viewModel.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (phases.isEmpty) {
             // Show empty state, but with header if possible? 
             // Without phases, GamifiedPhaseList might look empty but show header.
             // Let's allow GamifiedPhaseList to handle empty phases or pass empty list.
             // But if empty, we might want to show a message.
             // For now, let's keep the simple text, but maybe user wants header?
             // Let's try to just return GamifiedPhaseList with empty list, or simple text.
             // The user didn't ask to fix empty state.
             if (phases.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Nenhuma etapa encontrada neste mundo.'),
                      TextButton(onPressed: () => Navigator.pop(context), child: Text("Voltar"))
                    ],
                  )
                );
             }
          }

          return GamifiedPhaseList(
            phases: phases,
            track: widget.world,
          );
        },
      ),
    );
  }
}
