// WorkModeScreen — multi-select Remoto/Híbrido/Presencial.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/preferences_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../../utils/save_with_retry.dart';
import '../onboarding_scaffold.dart';
import 'job_types_screen.dart';
import '../../../../core/theme/theme.dart';
import '../widgets/onboarding_multi_check.dart';

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
  DateTime? _shownAt;
  final Set<WorkMode> _selected = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _shownAt = DateTime.now();
    // ignore: unawaited_futures
    Analytics.shared.onboardingPrefStepShown(
      step: 4,
      stepName: 'work_mode',
    );
    final current = context.read<PreferencesViewModel>().prefs?.workMode;
    if (current != null) _selected.addAll(current);
  }

  Future<void> _next() async {
    if (_saving) return;
    // ignore: unawaited_futures
    Analytics.shared.onboardingPrefStepAnswered(
      step: 4,
      stepName: 'work_mode',
      valuesCount: 1,
      timeMs: _shownAt != null
          ? DateTime.now().difference(_shownAt!).inMilliseconds
          : 0,
    );
    final vm = context.read<PreferencesViewModel>();
    setState(() => _saving = true);
    final ok = await saveWithRetry(
      context: context,
      operation: () => vm.setWorkMode(_selected.toList()),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const JobTypesScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Como prefere trabalhar?',
      subtitle: 'Pode selecionar mais de um.',
      progress: 0.81,
      continueLabel: _saving ? 'Salvando…' : 'Continuar',
      onContinue: (_selected.isEmpty || _saving) ? null : _next,
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
                  color: isSelected ? AppColors.primarySoft : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: isSelected ? AppColors.primary : AppColors.textTertiary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? AppColors.primary : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    OnboardingMultiCheck(selected: isSelected),
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

