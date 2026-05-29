// PhoneScreen — pergunta telefone com country code.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../auth/auth_session.dart';
import '../../../../core/utils/brazil_phone_formatter.dart';
import '../../../../services/analytics_service.dart';
import '../../../auth/phone_auth_helpers.dart';
import '../../../profile/application/profile_editor_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../../utils/onboarding_input_decoration.dart';
import '../../utils/save_with_retry.dart';
import '../onboarding_scaffold.dart';
import 'gender_screen.dart';

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});
  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  late final TextEditingController _ctrl;
  String _code = '+55';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final vm = context.read<ProfileEditorViewModel>();

    // Prioridade do pré-preenchimento:
    //  1. profile_personal (user já passou por essa tela antes)
    //  2. synthetic email do phone signup (ex: phone_5543991260202@stage.app
    //     → +55 / 43991260202). Sem isso, user que entrou com telefone
    //     teria que redigitar o número que ele acabou de fornecer.
    //  3. Vazio + default +55.
    String initialPhone = vm.personal?.phoneNumber ?? '';
    String initialCode = vm.personal?.phoneCountryCode ?? '+55';

    if (initialPhone.isEmpty) {
      final authEmail = Supabase.instance.client.auth.currentUser?.email;
      final parsed = PhoneAuthHelpers.parseSyntheticEmail(authEmail);
      if (parsed != null) {
        initialPhone = parsed.phone;
        initialCode = parsed.countryCode;
      }
    }

    _code = initialCode;
    _ctrl = TextEditingController(
      text: _code == '+55' && initialPhone.isNotEmpty
          ? BrazilPhoneFormatter.format(initialPhone)
          : initialPhone,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int get _digitsCount =>
      _ctrl.text.replaceAll(RegExp(r'\D'), '').length;

  bool get _valid => _digitsCount >= 8;

  Future<void> _continue() async {
    if (!_valid || _saving) return;
    AnalyticsService.shared.track('onboarding_masking_question_answered', props: {'question': 'phone'});
    final vm = context.read<ProfileEditorViewModel>();
    final userId = currentUserIdOrNull();
    if (userId == null) {
      // ignore: unawaited_futures
      handleSessionLost(context);
      return;
    }
    final base = vm.personal ?? PersonalInfo(userId: userId);
    // Sempre persiste só dígitos — máscara é puramente visual.
    final digits = _ctrl.text.replaceAll(RegExp(r'\D'), '');
    setState(() => _saving = true);
    final ok = await saveWithRetry(
      context: context,
      operation: () => vm.commitPersonal(base.copyWith(
        phoneCountryCode: _code,
        phoneNumber: digits,
      )),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const GenderScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Qual seu telefone?',
      progress: 0.38,
      continueLabel: _saving ? 'Salvando…' : 'Continuar',
      onContinue: (_valid && !_saving) ? _continue : null,
      child: Row(
        children: [
          SizedBox(
            width: 124,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _code,
              decoration: const InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 18),
              ),
              items: const [
                DropdownMenuItem(value: '+55', child: Text('🇧🇷 +55', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: '+1', child: Text('🇺🇸 +1', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: '+351', child: Text('🇵🇹 +351', overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: '+44', child: Text('🇬🇧 +44', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() {
                _code = v ?? '+55';
                _ctrl.clear();
              }),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: TextInputType.phone,
              inputFormatters: _code == '+55'
                  ? [BrazilPhoneFormatter()]
                  : [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(15),
                    ],
              decoration: onboardingInputDecoration(
                hintText: _code == '+55' ? '(11) 98765-4321' : '11987654321',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }
}
