// LastNameScreen — pergunta o sobrenome.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/profile_editor_view_model.dart';
import '../../../profile/application/extraction_status_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../onboarding_scaffold.dart';
import 'email_screen.dart';

class LastNameScreen extends StatefulWidget {
  const LastNameScreen({super.key});
  @override
  State<LastNameScreen> createState() => _LastNameScreenState();
}

class _LastNameScreenState extends State<LastNameScreen> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final vm = context.read<ProfileEditorViewModel>();
    final extraction = context.read<ExtractionStatusViewModel>();
    final parts = extraction.result?.parsed['fullName']?.toString().split(' ') ?? [];
    final fromExtraction = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final initial = vm.personal?.lastName ?? fromExtraction;
    _ctrl = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _continue() async {
    final value = _ctrl.text.trim();
    if (value.isEmpty) return;
    AnalyticsService.shared.track('onboarding_masking_question_answered', props: {'question': 'last_name'});

    final vm = context.read<ProfileEditorViewModel>();
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final base = vm.personal ?? PersonalInfo(userId: userId);
    await vm.commitPersonal(base.copyWith(lastName: value));

    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const EmailScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'E seu sobrenome?',
      progress: 0.25,
      onContinue: _ctrl.text.trim().isEmpty ? null : _continue,
      child: TextField(
        controller: _ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          hintText: 'Ex: Silva',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _continue(),
      ),
    );
  }
}
