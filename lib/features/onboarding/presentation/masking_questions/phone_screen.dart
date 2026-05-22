// PhoneScreen — pergunta telefone com country code.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
    _ctrl = TextEditingController(text: vm.personal?.phoneNumber ?? '');
    _code = vm.personal?.phoneCountryCode ?? '+55';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _valid => _ctrl.text.trim().length >= 8;

  void _continue() async {
    if (!_valid) return;
    AnalyticsService.shared.track('onboarding_masking_question_answered', props: {'question': 'phone'});
    final vm = context.read<ProfileEditorViewModel>();
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final base = vm.personal ?? PersonalInfo(userId: userId);
    await vm.commitPersonal(base.copyWith(
      phoneCountryCode: _code,
      phoneNumber: _ctrl.text.trim(),
    ));
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const GenderScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Qual seu telefone?',
      progress: 0.45,
      onContinue: _valid ? _continue : null,
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: DropdownButtonFormField<String>(
              initialValue: _code,
              decoration: const InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 18),
              ),
              items: const [
                DropdownMenuItem(value: '+55', child: Text('🇧🇷 +55')),
                DropdownMenuItem(value: '+1', child: Text('🇺🇸 +1')),
                DropdownMenuItem(value: '+351', child: Text('🇵🇹 +351')),
                DropdownMenuItem(value: '+44', child: Text('🇬🇧 +44')),
              ],
              onChanged: (v) => setState(() => _code = v ?? '+55'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                hintText: '11987654321',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }
}
