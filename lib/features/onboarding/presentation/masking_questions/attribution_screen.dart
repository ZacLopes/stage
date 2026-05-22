// AttributionScreen — "Como nos conheceu?" — primeira de 7 perguntas
// mascarando a latência da extração do CV.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/profile_editor_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../onboarding_scaffold.dart';
import 'first_name_screen.dart';

const _options = [
  'Instagram',
  'TikTok',
  'Indicação de amigo',
  'LinkedIn',
  'ChatGPT',
  'YouTube',
  'X / Twitter',
  'Reddit',
  'Outro',
];

class AttributionScreen extends StatefulWidget {
  const AttributionScreen({super.key});

  @override
  State<AttributionScreen> createState() => _AttributionScreenState();
}

class _AttributionScreenState extends State<AttributionScreen> {
  String? _selected;

  void _continue() async {
    if (_selected == null) return;
    AnalyticsService.shared.track('onboarding_masking_question_answered',
        props: {'question': 'attribution', 'value': _selected!});

    final vm = context.read<ProfileEditorViewModel>();
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final base = vm.personal ?? PersonalInfo(userId: userId);
    await vm.commitPersonal(base.copyWith(attributionSource: _selected));

    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const FirstNameScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Como nos conheceu?',
      subtitle: 'Ajuda a gente entender de onde você vem.',
      progress: 0.25,
      onContinue: _selected == null ? null : _continue,
      child: Column(
        children: _options.map((opt) {
          final isSelected = _selected == opt;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => setState(() => _selected = opt),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF00C27A).withValues(alpha: 0.08)
                      : Colors.white,
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
                        opt,
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
