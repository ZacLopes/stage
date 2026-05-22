// ExperienceLevelScreen — multi-select Júnior/Pleno/Sênior.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/preferences_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../onboarding_scaffold.dart';
import 'onboarding_complete_screen.dart';

const _options = <(ExperienceLevel, String, String)>[
  (ExperienceLevel.entry, 'Júnior', '0-2 anos'),
  (ExperienceLevel.mid, 'Pleno', '3-5 anos'),
  (ExperienceLevel.senior, 'Sênior', '5+ anos'),
];

class ExperienceLevelScreen extends StatefulWidget {
  const ExperienceLevelScreen({super.key});
  @override
  State<ExperienceLevelScreen> createState() => _ExperienceLevelScreenState();
}

class _ExperienceLevelScreenState extends State<ExperienceLevelScreen> {
  final Set<ExperienceLevel> _selected = {};

  @override
  void initState() {
    super.initState();
    final current = context.read<PreferencesViewModel>().prefs?.experienceLevel;
    if (current != null) _selected.addAll(current);
  }

  void _next() async {
    AnalyticsService.shared.track('onboarding_preferences_experience_level_completed');
    await context.read<PreferencesViewModel>().setExperienceLevel(_selected.toList());
    if (!mounted) return;
    // onFinish=null → usa default que chama createCampaign(isSkipped: true)
    // antes de fechar o stack. Crítico pra AuthGate destravar.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const OnboardingCompleteScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Qual seu nível?',
      subtitle: 'Pode selecionar mais de um.',
      progress: 0.95,
      onContinue: _next,
      skipButton: TextButton(onPressed: _next, child: const Text('Pular')),
      child: Column(
        children: _options.map((tuple) {
          final value = tuple.$1;
          final label = tuple.$2;
          final sub = tuple.$3;
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isSelected ? const Color(0xFF00C27A) : Colors.black87,
                            ),
                          ),
                          Text(sub, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                        ],
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
