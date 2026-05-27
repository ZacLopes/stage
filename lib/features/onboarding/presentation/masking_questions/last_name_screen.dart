// LastNameScreen — pergunta o sobrenome.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/profile_editor_view_model.dart';
import '../../../profile/application/extraction_status_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../../utils/onboarding_input_decoration.dart';
import '../../utils/save_with_retry.dart';
import '../onboarding_scaffold.dart';
import 'email_screen.dart';

class LastNameScreen extends StatefulWidget {
  const LastNameScreen({super.key});
  @override
  State<LastNameScreen> createState() => _LastNameScreenState();
}

class _LastNameScreenState extends State<LastNameScreen> {
  late final TextEditingController _ctrl;
  bool _saving = false;

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

  Future<void> _continue() async {
    if (_saving) return;
    final value = _ctrl.text.trim();
    if (value.isEmpty) return;
    AnalyticsService.shared.track('onboarding_masking_question_answered', props: {'question': 'last_name'});

    final vm = context.read<ProfileEditorViewModel>();
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final base = vm.personal ?? PersonalInfo(userId: userId);
    setState(() => _saving = true);
    final ok = await saveWithRetry(
      context: context,
      operation: () => vm.commitPersonal(base.copyWith(lastName: value)),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const EmailScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'E seu sobrenome?',
      progress: 0.25,
      continueLabel: _saving ? 'Salvando…' : 'Continuar',
      onContinue: (_ctrl.text.trim().isEmpty || _saving) ? null : _continue,
      child: TextField(
        controller: _ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: onboardingInputDecoration(hintText: 'Ex: Silva'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _continue(),
      ),
    );
  }
}
