// FirstNameScreen — pergunta o primeiro nome.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/analytics_service.dart';
import '../../../profile/application/profile_editor_view_model.dart';
import '../../../profile/application/extraction_status_view_model.dart';
import '../../../profile/domain/entities/entities.dart';
import '../onboarding_scaffold.dart';
import 'last_name_screen.dart';

class FirstNameScreen extends StatefulWidget {
  const FirstNameScreen({super.key});
  @override
  State<FirstNameScreen> createState() => _FirstNameScreenState();
}

class _FirstNameScreenState extends State<FirstNameScreen> {
  late final TextEditingController _ctrl;

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

  void _continue() async {
    final value = _ctrl.text.trim();
    if (value.isEmpty) return;
    AnalyticsService.shared.track('onboarding_masking_question_answered',
        props: {'question': 'first_name'});

    final vm = context.read<ProfileEditorViewModel>();
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final base = vm.personal ?? PersonalInfo(userId: userId);
    await vm.commitPersonal(base.copyWith(firstName: value));

    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LastNameScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      title: 'Qual seu primeiro nome?',
      progress: 0.19,
      onContinue: _ctrl.text.trim().isEmpty ? null : _continue,
      child: TextField(
        controller: _ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: _decoration('Ex: Maria'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _continue(),
      ),
    );
  }
}

InputDecoration _decoration(String hint) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF00C27A), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    );
