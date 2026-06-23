// JobTypesScreen — multi-select CLT/Estágio/PJ/Meio período.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/preferences_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../../utils/save_with_retry.dart';
import '../onboarding_scaffold.dart';
import 'onboarding_complete_screen.dart';
import '../../../../core/theme/theme.dart';

// Audiência entry-level. Ordem: do mais comum (Estágio, alunos ativos) pro
// menos comum (Temporário). Taxonomia alinhada com job_preferences_screen.
const _options = <(JobType, String, String, IconData)>[
  (JobType.internship, 'Estágio', 'Pra quem ainda tá na faculdade', Icons.school_rounded),
  (JobType.trainee, 'Trainee', 'Programa pós-formação', Icons.rocket_launch_rounded),
  (JobType.juniorFullTime, 'CLT Júnior', 'Primeira vaga formal', Icons.badge_rounded),
  (JobType.temporary, 'Temporário', 'Vagas pontuais', Icons.schedule_rounded),
];

class JobTypesScreen extends StatefulWidget {
  const JobTypesScreen({super.key});
  @override
  State<JobTypesScreen> createState() => _JobTypesScreenState();
}

class _JobTypesScreenState extends State<JobTypesScreen> {
  DateTime? _shownAt;
  final Set<JobType> _selected = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _shownAt = DateTime.now();
    // ignore: unawaited_futures
    Analytics.shared.onboardingPrefStepShown(
      step: 5,
      stepName: 'job_types',
    );
    final current = context.read<PreferencesViewModel>().prefs?.jobTypes;
    if (current != null) _selected.addAll(current);
  }

  Future<void> _next() async {
    if (_saving) return;
    // ignore: unawaited_futures
    Analytics.shared.onboardingPrefStepAnswered(
      step: 5,
      stepName: 'job_types',
      valuesCount: _selected.length,
      timeMs: _shownAt != null
          ? DateTime.now().difference(_shownAt!).inMilliseconds
          : 0,
    );
    final vm = context.read<PreferencesViewModel>();
    setState(() => _saving = true);
    final ok = await saveWithRetry(
      context: context,
      operation: () => vm.setJobTypes(_selected.toList()),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    // push normal (NÃO pushReplacement) — preserva JobTypes na stack pra
    // que back-swipe do OnboardingComplete volte 1 tela só. Quando o user
    // toca "Começar" lá, o popUntil isFirst limpa tudo de qualquer jeito.
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OnboardingCompleteScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Que tipo de vaga te interessa?',
      subtitle: 'Pode selecionar mais de um.',
      progress: 0.94,
      continueLabel: _saving ? 'Salvando…' : 'Continuar',
      onContinue: (_selected.isEmpty || _saving) ? null : _next,
      child: Column(
        children: _options.map((tuple) {
          final value = tuple.$1;
          final label = tuple.$2;
          final sub = tuple.$3;
          final icon = tuple.$4;
          final isSelected = _selected.contains(value);
          return _selectableTile(label, sub, icon, isSelected, () => setState(() {
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

Widget _selectableTile(String label, String sub, IconData icon, bool isSelected, VoidCallback onTap) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandCyan.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.brandCyan : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? AppColors.brandCyan : AppColors.textTertiary, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppColors.brandCyan : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(sub, style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _Checkbox(selected: isSelected),
          ],
        ),
      ),
    ),
  );
}

class _Checkbox extends StatelessWidget {
  final bool selected;
  const _Checkbox({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22, height: 22,
      decoration: BoxDecoration(
        color: selected ? AppColors.brandCyan : Colors.white,
        border: Border.all(
          color: selected ? AppColors.brandCyan : AppColors.borderStrong,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
          : null,
    );
  }
}
