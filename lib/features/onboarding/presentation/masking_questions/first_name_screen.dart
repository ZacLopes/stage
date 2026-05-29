// FirstNameScreen — pergunta o primeiro nome.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth/auth_session.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/profile_editor_view_model.dart';
import '../../../profile/application/extraction_status_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../../utils/onboarding_input_decoration.dart';
import '../../utils/save_with_retry.dart';
import '../onboarding_scaffold.dart';
import 'last_name_screen.dart';

class FirstNameScreen extends StatefulWidget {
  const FirstNameScreen({super.key});
  @override
  State<FirstNameScreen> createState() => _FirstNameScreenState();
}

class _FirstNameScreenState extends State<FirstNameScreen> {
  late final TextEditingController _ctrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final vm = context.read<ProfileEditorViewModel>();
    final extraction = context.read<ExtractionStatusViewModel>();
    final fromExtraction = extraction.result?.parsed['fullName']?.toString().split(' ').first ?? '';
    final initial = vm.personal?.firstName ?? fromExtraction;
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
    AnalyticsService.shared.track('onboarding_masking_question_answered',
        props: {'question': 'first_name'});

    final vm = context.read<ProfileEditorViewModel>();
    final userId = currentUserIdOrNull();
    if (userId == null) {
      // ignore: unawaited_futures
      handleSessionLost(context);
      return;
    }
    final base = vm.personal ?? PersonalInfo(userId: userId);
    setState(() => _saving = true);
    final ok = await saveWithRetry(
      context: context,
      operation: () => vm.commitPersonal(base.copyWith(firstName: value)),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LastNameScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Qual seu primeiro nome?',
      progress: 0.19,
      continueLabel: _saving ? 'Salvando…' : 'Continuar',
      onContinue: (_ctrl.text.trim().isEmpty || _saving) ? null : _continue,
      child: TextField(
        controller: _ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: onboardingInputDecoration(hintText: 'Ex: Maria'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _continue(),
      ),
    );
  }
}

