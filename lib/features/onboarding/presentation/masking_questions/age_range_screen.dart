// AgeRangeScreen — pergunta faixa etária.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/profile_editor_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../onboarding_scaffold.dart';
import '../all_set_screen.dart';
import '../review_personal_info_screen.dart';

const _options = <(AgeRange, String)>[
  (AgeRange.under18, 'Menos de 18'),
  (AgeRange.age18_24, '18 a 24'),
  (AgeRange.age25_34, '25 a 34'),
  (AgeRange.age35_44, '35 a 44'),
  (AgeRange.age45_54, '45 a 54'),
  (AgeRange.age55_64, '55 a 64'),
  (AgeRange.age65Plus, '65 ou mais'),
];

class AgeRangeScreen extends StatefulWidget {
  const AgeRangeScreen({super.key});
  @override
  State<AgeRangeScreen> createState() => _AgeRangeScreenState();
}

class _AgeRangeScreenState extends State<AgeRangeScreen> {
  AgeRange? _selected;

  @override
  void initState() {
    super.initState();
    _selected = context.read<ProfileEditorViewModel>().personal?.ageRange;
  }

  void _continue() async {
    if (_selected == null) return;
    AnalyticsService.shared.track('onboarding_masking_question_answered', props: {'question': 'age_range'});
    final vm = context.read<ProfileEditorViewModel>();
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final base = vm.personal ?? PersonalInfo(userId: userId);
    await vm.commitPersonal(base.copyWith(ageRange: _selected));
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AllSetScreen(
          viaPath: 'upload',
          onContinue: () {
            // Wire final (Semana 2 — Bloco I.2): navega pra Container 1 Tela A.
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReviewPersonalInfoScreen()),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Qual sua faixa etária?',
      subtitle: 'Algumas vagas pedem faixa etária.',
      progress: 0.65,
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
