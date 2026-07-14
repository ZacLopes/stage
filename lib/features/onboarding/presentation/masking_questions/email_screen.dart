// EmailScreen — pergunta email.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../auth/auth_session.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/utils/contact_email.dart';
import '../../../../services/analytics_service.dart';
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
  late final bool _loginUsesApplePrivateRelay;
  late final bool _loginUsesSyntheticEmail;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final vm = context.read<ProfileEditorViewModel>();
    final extraction = context.read<ExtractionStatusViewModel>();
    final fromExtraction = extraction.result?.parsed['email']?.toString() ?? '';
    final rawAuthEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    _loginUsesApplePrivateRelay = ContactEmail.isApplePrivateRelay(rawAuthEmail);
    _loginUsesSyntheticEmail = ContactEmail.isSyntheticAuthEmail(rawAuthEmail);
    final initial = ContactEmail.resolveInitial(
      profileEmail: vm.personal?.email,
      extractedEmail: fromExtraction,
      authEmail: rawAuthEmail,
    );
    _ctrl = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _valid => ContactEmail.isUsable(_ctrl.text);

  String? get _errorText {
    final value = _ctrl.text.trim();
    if (value.isEmpty) return null;
    if (ContactEmail.isApplePrivateRelay(value)) {
      return 'Esse endereço privado da Apple é só para login. Informe outro contato.';
    }
    if (ContactEmail.isSyntheticAuthEmail(value)) {
      return 'Esse endereço é usado apenas no login por telefone.';
    }
    if (!ContactEmail.isValid(value)) return 'Digite um e-mail válido.';
    return null;
  }

  Future<void> _continue() async {
    if (!_valid || _saving) return;
    AnalyticsService.shared.track('onboarding_masking_question_answered', props: {'question': 'email'});

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
      operation: () => vm.commitPersonal(
        base.copyWith(email: ContactEmail.normalize(_ctrl.text)),
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PhoneScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Qual e-mail vai no seu currículo?',
      progress: 0.31,
      continueLabel: _saving ? 'Salvando…' : 'Continuar',
      onContinue: (_valid && !_saving) ? _continue : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loginUsesApplePrivateRelay || _loginUsesSyntheticEmail) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline, size: 20, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _loginUsesApplePrivateRelay
                          ? 'Seu login com Apple usa um e-mail privado. Informe abaixo um contato para recrutadores; seu login não muda.'
                          : 'Seu login por telefone não possui um e-mail público. Informe abaixo um contato para recrutadores; seu login não muda.',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            decoration: onboardingInputDecoration(hintText: 'voce@email.com').copyWith(
              labelText: 'E-mail profissional',
              helperText: 'Pode ser Gmail, Outlook, iCloud ou domínio próprio.',
              helperMaxLines: 2,
              errorText: _errorText,
              errorMaxLines: 2,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _continue(),
          ),
        ],
      ),
    );
  }
}
