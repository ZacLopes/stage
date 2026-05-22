// ReviewPersonalInfoScreen (Container 1 — Tela A)
//
// Após AllSetScreen, usuário revisa dados pessoais antes de seguir pro currículo.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/analytics_service.dart';
import '../../profile/application/profile_editor_view_model.dart';
import '../../profile/domain/entities/entities.dart';
import '../../profile/presentation/widgets/personal_info_form.dart';
import 'onboarding_scaffold.dart';
import 'review_resume_screen.dart';

class ReviewPersonalInfoScreen extends StatefulWidget {
  const ReviewPersonalInfoScreen({super.key});

  @override
  State<ReviewPersonalInfoScreen> createState() => _ReviewPersonalInfoScreenState();
}

class _ReviewPersonalInfoScreenState extends State<ReviewPersonalInfoScreen> {
  PersonalInfo? _draft;

  @override
  void initState() {
    super.initState();
    AnalyticsService.shared.track('onboarding_review_personal_shown');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProfileEditorViewModel>().load().then((_) {
        if (!mounted) return;
        setState(() => _draft = context.read<ProfileEditorViewModel>().personal);
      });
    });
  }

  bool get _canContinue {
    final d = _draft;
    return d != null &&
        (d.firstName?.trim().isNotEmpty ?? false) &&
        (d.lastName?.trim().isNotEmpty ?? false) &&
        (d.email?.trim().isNotEmpty ?? false);
  }

  void _continue() async {
    if (!_canContinue) return;
    AnalyticsService.shared.track('onboarding_review_personal_continued');
    await context.read<ProfileEditorViewModel>().commitPersonal(_draft!);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ReviewResumeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProfileEditorViewModel>();
    final initial = _draft ?? vm.personal ??
        PersonalInfo(userId: Supabase.instance.client.auth.currentUser?.id ?? '');

    return OnboardingScaffold(
      title: 'Informações pessoais',
      subtitle: 'Confira e ajuste se precisar.',
      progress: 0.75,
      onContinue: _canContinue ? _continue : null,
      child: PersonalInfoForm(
        initial: initial,
        requireCriticalFields: true,
        onChanged: (d) => setState(() => _draft = d),
      ),
    );
  }
}
