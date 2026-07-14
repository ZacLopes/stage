// ReviewPersonalInfoScreen (Container 1 — Tela A)
//
// Após AllSetScreen, usuário revisa dados pessoais antes de seguir pro currículo.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/utils/contact_email.dart';
import '../../auth/auth_session.dart';
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
  bool _emailFieldValid = false;
  // QA Dia 6 — pra calcular `time_on_screen_ms` no review_confirmed.
  DateTime? _shownAt;

  @override
  void initState() {
    super.initState();
    _shownAt = DateTime.now();
    // ignore: unawaited_futures
    Analytics.shared.onboardingPersonalReviewShown();
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
        ContactEmail.isUsable(d.email) &&
        _emailFieldValid;
  }

  void _continue() async {
    if (!_canContinue) return;
    final userId = currentUserIdOrNull();
    if (userId == null) {
      // ignore: unawaited_futures
      handleSessionLost(context);
      return;
    }
    final timeOnScreenMs = _shownAt != null
        ? DateTime.now().difference(_shownAt!).inMilliseconds
        : 0;
    // edits_count granular não está instrumentado (precisaria escutar
    // onChanged de cada field) — passa 0. Pra qualidade de extração IA,
    // o sinal vem do `cv_adaptation_user_edited` post-adapt.
    // ignore: unawaited_futures
    Analytics.shared.onboardingPersonalReviewConfirmed(
      editsCount: 0,
      timeOnScreenMs: timeOnScreenMs,
    );
    await context.read<ProfileEditorViewModel>().commitPersonal(_draft!.copyWith(userId: userId));
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ReviewResumeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProfileEditorViewModel>();
    final initial = _draft ?? vm.personal ??
        PersonalInfo(userId: currentUserIdOrNull() ?? '');

    return OnboardingScaffold(
      title: 'Informações pessoais',
      subtitle: 'Confira e ajuste se precisar.',
      progress: 0.56,
      onContinue: _canContinue ? _continue : null,
      child: PersonalInfoForm(
        initial: initial,
        requireCriticalFields: true,
        onChanged: (d) => setState(() => _draft = d),
        onEmailValidityChanged: (valid) {
          if (_emailFieldValid != valid) {
            setState(() => _emailFieldValid = valid);
          }
        },
      ),
    );
  }
}
