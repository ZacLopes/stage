// WorkModeScreen — multi-select Remoto/Híbrido/Presencial.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/preferences_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../onboarding_scaffold.dart';
import 'job_types_screen.dart';

const _options = <(WorkMode, String, IconData)>[
  (WorkMode.remote, 'Remoto', Icons.home_outlined),
  (WorkMode.hybrid, 'Híbrido', Icons.sync_alt_outlined),
  (WorkMode.inPerson, 'Presencial', Icons.business_outlined),
];

class WorkModeScreen extends StatefulWidget {
  const WorkModeScreen({super.key});
  @override
  State<WorkModeScreen> createState() => _WorkModeScreenState();
}

class _WorkModeScreenState extends State<WorkModeScreen> {
  final Set<WorkMode> _selected = {};

  @override
  void initState() {
    super.initState();
    final current = context.read<PreferencesViewModel>().prefs?.workMode;
    if (current != null) _selected.addAll(current);
  }

  void _next() async {
    AnalyticsService.shared.track('onboarding_preferences_work_mode_completed');
    await context.read<PreferencesViewModel>().setWorkMode(_selected.toList());
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const JobTypesScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Como prefere trabalhar?',
      progress: 0.88,
      onContinue: _next,
      skipButton: TextButton(onPressed: _next, child: const Text('Pular')),
      child: Column(
        children: _options.map((tuple) {
          final value = tuple.$1;
          final label = tuple.$2;
          final icon = tuple.$3;
          final isSelected = _selected.contains(value);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => setState(() {
                if (isSelected) {
                  _selected.remove(value);
                } else {
                  _selected.add(value);
                }
              }),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF00C27A).withValues(alpha: 0.08) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF00C27A) : const Color(0xFFE5E7EB),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: isSelected ? const Color(0xFF00C27A) : const Color(0xFF6B7280)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? const Color(0xFF00C27A) : Colors.black87,
                        ),
                      ),
                    ),
                    if (isSelected) const Icon(Icons.check_circle, color: Color(0xFF00C27A)),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
