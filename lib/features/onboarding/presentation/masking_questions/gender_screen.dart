// GenderScreen — pergunta gênero.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/profile_editor_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../onboarding_scaffold.dart';
import 'age_range_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _selected = context.read<ProfileEditorViewModel>().personal?.gender;
  }

  void _continue() async {
    if (_selected == null) return;
    AnalyticsService.shared.track('onboarding_masking_question_answered', props: {'question': 'gender'});
    final vm = context.read<ProfileEditorViewModel>();
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final base = vm.personal ?? PersonalInfo(userId: userId);
    await vm.commitPersonal(base.copyWith(gender: _selected));
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AgeRangeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Qual seu gênero?',
      subtitle: 'Será usado nas suas candidaturas quando aplicável.',
      progress: 0.6,
      onContinue: _selected == null ? null : _continue,
      child: Column(
        children: _options.map((tuple) {
          final value = tuple.$1;
          final label = tuple.$2;
          final isSelected = _selected == value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => setState(() => _selected = value),
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
        }).toList(),
      ),
    );
  }
}
