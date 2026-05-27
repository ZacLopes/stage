// EmailScreen — pergunta email.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/analytics_service.dart';
import '../../../auth/phone_auth_helpers.dart';
import '../../../profile/application/profile_editor_view_model.dart';
import '../../../profile/application/extraction_status_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../../utils/onboarding_input_decoration.dart';
import '../../utils/save_with_retry.dart';
import '../onboarding_scaffold.dart';
import 'phone_screen.dart';

class EmailScreen extends StatefulWidget {
  const EmailScreen({super.key});
  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> {
  late final TextEditingController _ctrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final vm = context.read<ProfileEditorViewModel>();
    final extraction = context.read<ExtractionStatusViewModel>();
    final fromExtraction = extraction.result?.parsed['email']?.toString() ?? '';
    final rawAuthEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    // Ignora email sintético do signup por telefone (`phone_<digits>@stage.app`).
    // Mostrar isso pré-preenchido confunde o user — ele acha que esse é o
    // email "real" da conta. Deixa vazio pra ele digitar o email de verdade.
    final authEmail = PhoneAuthHelpers.isSyntheticEmail(rawAuthEmail) ? '' : rawAuthEmail;
    final initial = vm.personal?.email ?? fromExtraction.ifEmpty(authEmail);
    _ctrl = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _valid {
    final t = _ctrl.text.trim();
    return t.contains('@') && t.contains('.');
  }

  Future<void> _continue() async {
    if (!_valid || _saving) return;
    AnalyticsService.shared.track('onboarding_masking_question_answered', props: {'question': 'email'});

    final vm = context.read<ProfileEditorViewModel>();
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final base = vm.personal ?? PersonalInfo(userId: userId);
    setState(() => _saving = true);
    final ok = await saveWithRetry(
      context: context,
      operation: () => vm.commitPersonal(base.copyWith(email: _ctrl.text.trim().toLowerCase())),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PhoneScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Melhor email pra te contatar?',
      progress: 0.31,
      continueLabel: _saving ? 'Salvando…' : 'Continuar',
      onContinue: (_valid && !_saving) ? _continue : null,
      child: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: onboardingInputDecoration(hintText: 'voce@email.com'),
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
