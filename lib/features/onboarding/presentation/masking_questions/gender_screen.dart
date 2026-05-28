// GenderScreen — pergunta gênero.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/profile_editor_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../../utils/save_with_retry.dart';
import '../onboarding_scaffold.dart';
import 'age_range_screen.dart';
import '../../../../core/theme/theme.dart';

const _options = <(Gender, String)>[
  (Gender.male, 'Masculino'),
  (Gender.female, 'Feminino'),
  (Gender.other, 'Outro'),
  (Gender.preferNotToSay, 'Prefiro não dizer'),
];

class GenderScreen extends StatefulWidget {
  const GenderScreen({super.key});
  @override
  State<GenderScreen> createState() => _GenderScreenState();
}

class _GenderScreenState extends State<GenderScreen> {
  Gender? _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = context.read<ProfileEditorViewModel>().personal?.gender;
  }

  Future<void> _continue() async {
    if (_selected == null || _saving) return;
    AnalyticsService.shared.track('onboarding_masking_question_answered', props: {'question': 'gender'});
    final vm = context.read<ProfileEditorViewModel>();
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final base = vm.personal ?? PersonalInfo(userId: userId);
    setState(() => _saving = true);
    final ok = await saveWithRetry(
      context: context,
      operation: () => vm.commitPersonal(base.copyWith(gender: _selected)),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AgeRangeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Qual seu gênero?',
      subtitle: 'Será usado nas suas candidaturas quando aplicável.',
      progress: 0.44,
      continueLabel: _saving ? 'Salvando…' : 'Continuar',
      onContinue: (_selected == null || _saving) ? null : _continue,
      child: Column(
        children: _options.map((tuple) {
          final value = tuple.$1;
          final label = tuple.$2;
          final isSelected = _selected == value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selected = value);
              },
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
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? AppColors.brandCyan : Colors.black87,
                        ),
                      ),
                    ),
                    if (isSelected) const Icon(Icons.check_circle, color: AppColors.brandCyan),
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
