// PhoneScreen — pergunta telefone com country code.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/brazil_phone_formatter.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/profile_editor_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
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

  @override
  void initState() {
    super.initState();
    final vm = context.read<ProfileEditorViewModel>();
    final initialPhone = vm.personal?.phoneNumber ?? '';
    _code = vm.personal?.phoneCountryCode ?? '+55';
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

  void _continue() async {
    if (!_valid) return;
    AnalyticsService.shared.track('onboarding_masking_question_answered', props: {'question': 'phone'});
    final vm = context.read<ProfileEditorViewModel>();
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final base = vm.personal ?? PersonalInfo(userId: userId);
    // Sempre persiste só dígitos — máscara é puramente visual.
    final digits = _ctrl.text.replaceAll(RegExp(r'\D'), '');
    await vm.commitPersonal(base.copyWith(
      phoneCountryCode: _code,
      phoneNumber: digits,
    ));
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const GenderScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Qual seu telefone?',
      progress: 0.38,
      onContinue: _valid ? _continue : null,
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
              decoration: InputDecoration(
                hintText: _code == '+55' ? '(11) 98765-4321' : '11987654321',
                filled: true,
                fillColor: Colors.white,
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }
}
