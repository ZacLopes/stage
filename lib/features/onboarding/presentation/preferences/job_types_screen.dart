// JobTypesScreen — multi-select CLT/Estágio/PJ/Meio período.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/preferences_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../onboarding_scaffold.dart';
import 'experience_level_screen.dart';

const _options = <(JobType, String)>[
  (JobType.fullTime, 'CLT / Tempo integral'),
  (JobType.internship, 'Estágio'),
  (JobType.contract, 'PJ / Contrato'),
  (JobType.partTime, 'Meio período'),
];

class JobTypesScreen extends StatefulWidget {
  const JobTypesScreen({super.key});
  @override
  State<JobTypesScreen> createState() => _JobTypesScreenState();
}

class _JobTypesScreenState extends State<JobTypesScreen> {
  final Set<JobType> _selected = {};

  @override
  void initState() {
    super.initState();
    final current = context.read<PreferencesViewModel>().prefs?.jobTypes;
    if (current != null) _selected.addAll(current);
  }

  void _next() async {
    AnalyticsService.shared.track('onboarding_preferences_job_types_completed');
    await context.read<PreferencesViewModel>().setJobTypes(_selected.toList());
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ExperienceLevelScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Tipo de contrato?',
      progress: 0.9,
      onContinue: _next,
      skipButton: TextButton(onPressed: _next, child: const Text('Pular')),
      child: Column(
        children: _options.map((tuple) {
          final value = tuple.$1;
          final label = tuple.$2;
          final isSelected = _selected.contains(value);
          return _selectableTile(label, isSelected, () => setState(() {
                if (isSelected) {
                  _selected.remove(value);
                } else {
                  _selected.add(value);
                }
              }));
        }).toList(),
      ),
    );
  }
}

Widget _selectableTile(String label, bool isSelected, VoidCallback onTap) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      onTap: onTap,
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
}
